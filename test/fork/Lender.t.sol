// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import 'forge-std/Test.sol';
import 'test/fork/Contracts.sol';
import 'test/lib/Hash.sol';

import 'src/Lender.sol';
import 'src/Redeemer.sol';
import 'src/Converter.sol';

contract LenderTest is Test {
    Lender l;
    Redeemer r;
    MarketPlace mp;
    Converter c;

    uint256 user1_sk =
        0x8882c68b373b93e91b80cef3ffced6b17a6fdabb210f09209bf5a76c9c8343cf;
    address user1_pk = 0x87FAB749498eCaE02db60079bfe51F012B71E96A;

    uint256 fork;

    uint256 FEENOMINATOR = 1000;

    uint256 maturity = 2664550000;
    uint256 startingBalance = 1000000;
    uint256 amount = 100000;
    uint256 deadline = 2**256 - 1;
    uint256 minReturn = 0;

    function setUp() public {
        // Fetch RPC URL and block number from environment
        string memory rpc = vm.envString('RPC_URL');
        uint256 blockNumber = vm.envUint('BLOCK_NUMBER');
        // Create and select fork
        fork = vm.createSelectFork(rpc, blockNumber);
        // Deploy converter
        c = new Converter();
        // Deploy lender
        l = new Lender(Contracts.SWIVEL, Contracts.PENDLE, Contracts.TEMPUS);
        // Deploy redeemer
        r = new Redeemer(
            address(l),
            Contracts.SWIVEL, // swivel
            Contracts.PENDLE_ROUTER, // pendle
            Contracts.TEMPUS, // tempus
            Contracts.APWINE_CONTROLLER // apwine
        ); // Deploy marketplace
        mp = new MarketPlace(address(r), address(l));
        // Set the redeemer's converter
        r.setConverter(address(c));

        // Given msg.sender some USDC to work with
        deal(Contracts.USDC, msg.sender, startingBalance);
    }

    function deployMarket(address u) internal {
        l.setMarketPlace(address(mp));
        // Create a market
        address[8] memory contracts;
        contracts[0] = Contracts.SWIVEL_TOKEN; // Swivel
        contracts[1] = Contracts.YIELD_TOKEN; // Yield
        contracts[2] = Contracts.ELEMENT_TOKEN; // Element
        contracts[3] = Contracts.PENDLE_TOKEN; // Pendle
        contracts[4] = Contracts.TEMPUS_TOKEN; // Tempus
        contracts[5] = Contracts.SENSE_TOKEN; // Sense
        contracts[6] = Contracts.APWINE_AMM_POOL; // APWine
        contracts[7] = Contracts.NOTIONAL_TOKEN; // Notional

        mp.createMarket(
            u,
            maturity,
            contracts,
            'TEST-TOKEN',
            'TEST',
            18,
            Contracts.ELEMENT_VAULT,
            Contracts.APWINE_ROUTER
        );
    }

    function runCheatcodes(address u) internal {
        // Give msg.sender some USDC to work with
        deal(u, msg.sender, startingBalance);
        assertEq(startingBalance, IERC20(u).balanceOf(msg.sender));

        vm.startPrank(msg.sender);

        // Approve lender to spend the underlying
        IERC20(u).approve(address(l), 2**256 - 1);
    }

    function testYieldLend() public {
        // Set up the market
        deployMarket(Contracts.USDC);

        // Runs cheats/approvals
        runCheatcodes(Contracts.USDC);

        // Execute the lend
        l.lend(
            uint8(2),
            Contracts.USDC,
            maturity,
            amount,
            Contracts.YIELD_POOL_USDC,
            amount + 1
        );

        // Get the amount that should be transferred (sellBasePreview)
        uint256 returned = IYield(Contracts.YIELD_POOL_USDC).sellBasePreview(
            Cast.u128(amount - amount / FEENOMINATOR)
        );

        // Make sure the principal tokens were transferred to the lender
        assertEq(returned, IERC20(Contracts.YIELD_TOKEN).balanceOf(address(l)));

        // Make sure the user got the iPTs
        address ipt = mp.markets(Contracts.USDC, maturity, 0);
        assertEq(returned, IERC20(ipt).balanceOf(msg.sender));
    }

    function testTempusLend() public {
        // Set up the market
        deployMarket(Contracts.USDC);

        // We need the lender contract to approve spending TEMPUS
        vm.startPrank(address(l));
        IERC20(Contracts.USDC).approve(Contracts.TEMPUS, 2**256 - 1);
        vm.stopPrank();

        // Approve the sender's activities and call lend from the sender
        runCheatcodes(Contracts.USDC);

        // Execute the lend
        uint256 expected = l.lend(
            uint8(5),
            Contracts.USDC,
            maturity,
            amount,
            minReturn,
            deadline,
            Contracts.TEMPUS_AMM
        );

        // Make sure the principal tokens were transferred to the lender
        assertEq(
            expected,
            ITempusToken(Contracts.TEMPUS_TOKEN).balanceOf(address(l))
        );

        // Make sure the same amount of iPTs were minted to the user
        address ipt = mp.markets(Contracts.USDC, maturity, 0);
        assertEq(expected, IERC20(ipt).balanceOf(msg.sender));
    }

    // TODO: Stuck on missing deployments
    function testPendleLend() public {
        // Set up the market
        deployMarket(Contracts.USDC);

        // We need the lender contract to approve spending TEMPUS
        vm.startPrank(address(l));
        IERC20(Contracts.USDC).approve(Contracts.PENDLE, 2**256 - 1);
        vm.stopPrank();

        // Approve the sender's activities and call lend from the sender
        runCheatcodes(Contracts.USDC);

        uint256 returned = l.lend(
            uint8(4),
            Contracts.USDC,
            maturity,
            amount,
            minReturn,
            deadline
        );

        // Make sure the principal tokens were transferred to the lender
        assertEq(
            returned,
            IERC20(Contracts.PENDLE_TOKEN).balanceOf(address(l))
        );

        // Make sure the same amount of iPTs were minted to the user
        address ipt = mp.markets(Contracts.USDC, maturity, 0);
        assertEq(returned, IERC20(ipt).balanceOf(msg.sender));
    }

    function testSwivelLendSkip() public {
        vm.startPrank(address(l));
        IERC20(Contracts.DAI).approve(Contracts.SWIVEL, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user1_pk);
        IERC20(Contracts.DAI).approve(Contracts.SWIVEL, type(uint256).max);
        vm.stopPrank();

        deployMarket(Contracts.DAI);

        runCheatcodes(Contracts.DAI);

        startingBalance = 500000e18;
        deal(Contracts.DAI, address(l), startingBalance);
        deal(Contracts.DAI, user1_pk, startingBalance);

        Swivel.Order[] memory orders = new Swivel.Order[](1);
        Swivel.Components[] memory signatures = new Swivel.Components[](1);
        uint256[] memory amounts = new uint256[](1);

        bytes32 key;
        orders[0] = Swivel.Order(
            key, // key
            1, // protocol
            user1_pk, // maker
            Contracts.DAI, // underlying
            true, // vault
            false, // exit
            1000, // principal
            1040, // premium
            1664550000, // maturity
            1664550000 // expiry
        );

        Hash.Order memory ord = Hash.Order(
            orders[0].key,
            orders[0].protocol,
            orders[0].maker,
            orders[0].underlying,
            orders[0].vault,
            orders[0].exit,
            orders[0].principal,
            orders[0].premium,
            orders[0].maturity,
            orders[0].expiry
        );

        bytes32 messageDigest = Hash.message(
            Hash.DOMAIN_TYPEHASH,
            Hash.order(ord)
        );

        {
            (uint8 v, bytes32 r1, bytes32 s) = vm.sign(user1_sk, messageDigest);
            signatures[0] = Swivel.Components(v, r1, s);
        }
        amounts[0] = 1000;

        //uint256 returned = l.lend(
        l.lend(
            uint8(MarketPlace.Principals.Swivel),
            Contracts.DAI,
            maturity,
            amounts,
            Contracts.YIELD_POOL_DAI,
            orders,
            signatures,
            101,
            true,
            0
        );

        // todo uncomment these
        // // Make sure the principal tokens were transferred to the lender
        // assertEq(
        //     returned,
        //     IERC20(Contracts.SWIVEL_TOKEN).balanceOf(address(l))
        // );

        // // Make sure the same amount of iPTs were minted to the user
        // address ipt = mp.markets(Contracts.DAI, maturity, 0);
        // assertEq(returned, IERC20(ipt).balanceOf(msg.sender));
    }

    function testNotionalLend() public {
        deployMarket(Contracts.DAI);

        startingBalance = 500000e18;
        runCheatcodes(Contracts.DAI);

        uint256 returned = l.lend(
            uint8(8),
            Contracts.DAI,
            maturity,
            500000e18,
            5
        );

        // Make sure the principal tokens were transferred to the lender
        assertEq(
            returned,
            IERC20(Contracts.NOTIONAL_TOKEN).balanceOf(address(l))
        );

        // Make sure the same amount of iPTs were minted to the user
        address ipt = mp.markets(Contracts.DAI, maturity, 0);
        assertEq(returned, IERC20(ipt).balanceOf(msg.sender));
    }

    function testAPWineLend() public {
        deployMarket(Contracts.USDC);

        // Run cheats/approvals
        runCheatcodes(Contracts.USDC);

        // Execute the lend
        uint256 returned = l.lend(
            uint8(7),
            Contracts.USDC,
            maturity,
            amount,
            minReturn,
            deadline,
            Contracts.APWINE_ROUTER
        );

        // Make sure the principal tokens were transferred to the lender
        address pt = IAPWineAMMPool(Contracts.APWINE_AMM_POOL).getPTAddress();
        assertEq(returned, IERC20(pt).balanceOf(address(l)));

        // Make sure the same amount of iPTs were minted to the user
        address ipt = mp.markets(Contracts.USDC, maturity, 0);
        assertEq(returned, IERC20(ipt).balanceOf(msg.sender));
    }

    function testElementLend() public {
        deployMarket(Contracts.USDC);

        // Run cheats/approvals
        runCheatcodes(Contracts.USDC);

        // Execute the lend
        uint256 returned = l.lend(
            uint8(3),
            Contracts.USDC,
            maturity,
            amount,
            minReturn,
            deadline,
            Contracts.ELEMENT_VAULT,
            Contracts.ELEMENT_POOL_ID
        );

        // Make sure the principal tokens were transferred to the lender
        assertEq(
            returned,
            IERC20(Contracts.ELEMENT_TOKEN).balanceOf(address(l))
        );

        // Make sure the same amount of iPTs were minted to the user
        address ipt = mp.markets(Contracts.USDC, maturity, 0);
        assertEq(returned, IERC20(ipt).balanceOf(msg.sender));
    }

    function testSenseLend() public {
        deployMarket(Contracts.WETH);

        vm.startPrank(address(l));
        IERC20(Contracts.WETH).approve(Contracts.SENSE_PERIPHERY, 2**256 - 1);
        vm.stopPrank();

        // Run cheats/approvals
        runCheatcodes(Contracts.WETH);

        // Execute the lend
        uint256 returned = l.lend(
            uint8(6),
            Contracts.WETH,
            maturity,
            uint128(amount),
            minReturn,
            Contracts.SENSE_PERIPHERY,
            Contracts.SENSE_MATURITY,
            Contracts.SENSE_ADAPTER
        );

        // Make sure the principal tokens were transferred to the lender
        assertEq(returned, IERC20(Contracts.SENSE_TOKEN).balanceOf(address(l)));

        // Make sure the same amount of iPTs were minted to the user
        address ipt = mp.markets(Contracts.WETH, maturity, 0);
        assertEq(returned, IERC20(ipt).balanceOf(msg.sender));
    }

    // This test is here for gas measurement purposes only
    function testSwivelLendWithSwappedPremiumGasSkip() public {
        vm.startPrank(address(l));
        IERC20(Contracts.DAI).approve(Contracts.SWIVEL, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user1_pk);
        IERC20(Contracts.DAI).approve(Contracts.SWIVEL, type(uint256).max);
        vm.stopPrank();

        deployMarket(Contracts.DAI);

        runCheatcodes(Contracts.DAI);

        startingBalance = 500000e18;
        deal(Contracts.DAI, address(l), startingBalance);
        deal(Contracts.DAI, user1_pk, startingBalance);

        Swivel.Order[] memory orders = new Swivel.Order[](1);
        Swivel.Components[] memory signatures = new Swivel.Components[](1);
        uint256[] memory amounts = new uint256[](1);

        bytes32 key;
        orders[0] = Swivel.Order(
            key, // key
            1, // protocol
            user1_pk, // maker
            Contracts.DAI, // underlying
            true, // vault
            false, // exit
            1000, // principal
            1040, // premium
            1664550000, // maturity
            1664550000 // expiry
        );

        Hash.Order memory ord = Hash.Order(
            orders[0].key,
            orders[0].protocol,
            orders[0].maker,
            orders[0].underlying,
            orders[0].vault,
            orders[0].exit,
            orders[0].principal,
            orders[0].premium,
            orders[0].maturity,
            orders[0].expiry
        );

        bytes32 messageDigest = Hash.message(
            Hash.DOMAIN_TYPEHASH,
            Hash.order(ord)
        );

        (uint8 v, bytes32 r1, bytes32 s) = vm.sign(user1_sk, messageDigest);
        signatures[0] = Swivel.Components(v, r1, s);
        amounts[0] = 1000;

        l.lend(
            uint8(1),
            Contracts.DAI,
            maturity,
            amounts,
            Contracts.YIELD_POOL_DAI,
            orders,
            signatures,
            101,
            false,
            0
        );
    }
}
