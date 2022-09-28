// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import 'forge-std/Test.sol';

import 'src/Lender.sol';
import 'src/mocks/MarketPlace.sol' as mock_mp;
import 'src/mocks/ERC20.sol' as mock_erc20;
import 'src/mocks/IlluminatePrincipalToken.sol' as mock_ipt;

import 'src/mocks/Swivel.sol' as mock_sw;
import 'src/mocks/Yield.sol' as mock_y;
import 'src/mocks/YieldToken.sol' as mock_yt;
import 'src/mocks/ElementVault.sol' as mock_ev;
import 'src/mocks/ElementToken.sol' as mock_et;
import 'src/mocks/Pendle.sol' as mock_p;
import 'src/mocks/PendleToken.sol' as mock_pt;
import 'src/mocks/Tempus.sol' as mock_t;
import 'src/mocks/TempusPool.sol' as mock_tp;
import 'src/mocks/TempusToken.sol' as mock_tt;
import 'src/mocks/SenseAdapter.sol' as mock_sa;
import 'src/mocks/SenseDivider.sol' as mock_sd;
import 'src/mocks/SensePeriphery.sol' as mock_sp;
import 'src/mocks/APWineAMMPool.sol' as mock_apwammpool;
import 'src/mocks/APWineController.sol' as mock_apwc;
import 'src/mocks/APWineFutureVault.sol' as mock_apwfv;
import 'src/mocks/APWineRouter.sol' as mock_apwr;
import 'src/mocks/APWineToken.sol' as mock_apwt;
import 'src/mocks/Notional.sol' as mock_n;

import 'src/interfaces/IERC20Metadata.sol';

import 'src/errors/Exception.sol';

contract LenderTest is Test {
    Lender l;

    // helper attributes
    address underlying;
    uint256 maturity = 2664550000;
    uint256 amount = 100000;
    uint256 feenominator = 1000;
    uint256 expectedFee = amount / feenominator;
    // swivel specific
    Swivel.Order[] private orders;
    Swivel.Components[] private components;
    uint256[] private amounts;

    // mocked internal contracts
    mock_mp.MarketPlace mp;
    mock_ipt.IlluminatePrincipalToken ipt;

    // mocked external contracts
    mock_sw.Swivel sw; // Swivel smart contract
    mock_erc20.ERC20 zct; // Zero coupon token
    mock_y.Yield swy; // Swivel yield pool
    mock_y.Yield y; // Yield's yield pool
    mock_yt.YieldToken yt; // Yield's principal token
    mock_ev.ElementVault ev; // Element's vault
    mock_et.ElementToken et; // Element's principal token
    mock_p.Pendle p; // Pendle's contract (Sushiswap router)
    mock_pt.PendleToken pt; // Pendle's principal token
    mock_t.Tempus t; // Tempus router
    mock_tp.TempusPool tp; // Tempus pool
    mock_tt.TempusToken tt; // Tempus principal token
    mock_sa.SenseAdapter sa; // Sense Adapter
    mock_sd.SenseDivider sd; // Sense Divider
    mock_sp.SensePeriphery sp; // Sense Periphery
    mock_erc20.ERC20 st; // Sense Principal Token
    mock_apwammpool.APWineAMMPool apwp; // APWine AMM pool
    mock_apwc.APWineController apwc; // APWine Controller
    mock_apwfv.APWineFutureVault apwfv; // APWine Future Vault
    mock_apwr.APWineRouter apwr; // APWine router
    mock_apwt.APWineToken apwt; // APWine principal Token
    mock_n.Notional n; // Notional's token

    function setUp() public {
        // Deploy mocked external contracts
        deployInterfaceMocks();
        // Deploy lender
        l = new Lender(address(sw), address(p), address(t));
        // Deploy marketplace
        mp = new mock_mp.MarketPlace();
        mp.iptReturns(address(ipt));
        // Set the lender in the marketplace
        l.setMarketPlace(address(mp));
    }

    function deployInterfaceMocks() internal {
        underlying = address(new mock_erc20.ERC20());
        ipt = new mock_ipt.IlluminatePrincipalToken();
        // swivel setup
        sw = new mock_sw.Swivel(underlying);
        zct = new mock_erc20.ERC20();
        swy = new mock_y.Yield(address(zct));
        // yield setup
        yt = new mock_yt.YieldToken();
        y = new mock_y.Yield(address(yt));
        // element setup
        et = new mock_et.ElementToken();
        ev = new mock_ev.ElementVault(address(et));
        // pendle setup
        pt = new mock_pt.PendleToken();
        p = new mock_p.Pendle();
        // tempus setup
        tp = new mock_tp.TempusPool();
        tt = new mock_tt.TempusToken();
        t = new mock_t.Tempus(address(tt));
        // sense setup
        sa = new mock_sa.SenseAdapter();
        sd = new mock_sd.SenseDivider(underlying);
        st = new mock_erc20.ERC20();
        sp = new mock_sp.SensePeriphery(address(st));
        // apwine setup
        apwp = new mock_apwammpool.APWineAMMPool();
        apwc = new mock_apwc.APWineController();
        apwfv = new mock_apwfv.APWineFutureVault();
        apwt = new mock_apwt.APWineToken();
        apwr = new mock_apwr.APWineRouter(address(apwt));
        // notional setup
        n = new mock_n.Notional();
    }

    function testSwivelLend() public {
        // create the order/component/amounts
        Swivel.Order memory ORDER_1 = Swivel.Order(
            bytes32('asjfdk'),
            1,
            address(yt),
            underlying,
            false,
            false,
            10,
            20,
            30,
            40
        );
        orders.push(ORDER_1);
        Swivel.Order memory ORDER_2 = Swivel.Order(
            bytes32('qwerty'),
            1,
            address(yt),
            underlying,
            true,
            true,
            101,
            202,
            303,
            404
        );
        orders.push(ORDER_2);

        Swivel.Components memory COMPONENT_1 = Swivel.Components(
            1,
            bytes32('hello'),
            bytes32('world')
        );
        components.push(COMPONENT_1);
        Swivel.Components memory COMPONENT_2 = Swivel.Components(
            1,
            bytes32('fixed'),
            bytes32('rates')
        );
        components.push(COMPONENT_2);
        amounts.push(50000);
        amounts.push(40000);
        uint256 total = amounts[0] + amounts[1];
        uint256 fee = total / feenominator;

        require(orders.length == amounts.length);
        require(orders.length == components.length);

        // mock the calls
        mock_erc20.ERC20(underlying).transferFromReturns(true);
        sw.initiateReturns(true);
        // todo: lend returned premium methods (requires modifiable balanceOf)
        ipt.mintReturns(true);
        mp.tokenReturns(address(zct));

        // execute the lend
        l.lend(
            1,
            underlying,
            maturity,
            amounts,
            address(swy),
            orders,
            components,
            fee,
            false,
            0
        );

        // transfer
        uint256 collected = l.fees(underlying);
        (address transferFromTo, uint256 transferFromAmount) = mock_erc20
            .ERC20(underlying)
            .transferFromCalled(address(this));
        assertEq(address(l), transferFromTo);
        assertEq(fee + total, transferFromAmount);
        // fee
        assertEq(fee, collected);
        // initiate
        assertEq(amounts[1], sw.initiateCalledAmount(address(yt)));
        assertEq(components[1].v, sw.initiateCalledSignature(address(yt)));
        // mint
        assertEq(total, ipt.mintCalled(address(this)));
    }

    function testYieldLend() public {
        uint256 starting = 14040;
        uint256 baseSold = amount + 15;
        mp.tokenReturns(address(yt));
        mock_erc20.ERC20(underlying).transferFromReturns(true);
        y.fyTokenReturns(address(yt));
        yt.balanceOfReturns(starting);
        y.sellBasePreviewReturns(uint128(baseSold));
        mock_erc20.ERC20(underlying).transferReturns(true);
        y.sellBaseReturns(uint128(baseSold));
        ipt.mintReturns(true);

        l.lend(2, underlying, maturity, amount, address(y), 0);

        // markets check
        (uint256 calledMaturity, uint256 calledPrincipal) = mp.tokenCalled(
            underlying
        );
        assertEq(maturity, calledMaturity);
        assertEq(2, calledPrincipal);
        // transfer check
        (address transferFromTo, uint256 transferFromAmount) = mock_erc20
            .ERC20(underlying)
            .transferFromCalled(address(this));
        assertEq(address(l), transferFromTo);
        assertEq(amount, transferFromAmount);
        // fee check
        uint256 collected = l.fees(underlying);
        assertEq(collected, expectedFee);
        // sellBase -> sellBasePreview check
        uint256 amountTransferred = mock_erc20.ERC20(underlying).transferCalled(
            address(y)
        );
        assertEq(amount - expectedFee, amountTransferred);
        uint256 amountReceived = y.sellBaseCalled(address(l));
        assertEq(baseSold, amountReceived);

        // mint check
        assertEq(baseSold, ipt.mintCalled(address(this)));
    }

    function testElementLend() public {
        // variables
        uint256 minReturned = amount / 2;
        uint256 starting = 140;
        uint256 deadline = block.timestamp + 10;
        address pool = address(ev);
        bytes32 id = bytes32('asdf');
        uint256 purchased = amount + 50;

        mp.tokenReturns(address(et));
        mock_erc20.ERC20(underlying).transferFromReturns(true);
        et.balanceOfReturns(starting);
        ev.swapReturns(purchased);
        ipt.mintReturns(true);

        l.lend(
            3,
            underlying,
            maturity,
            amount,
            minReturned,
            deadline,
            pool,
            id
        );
        // markets check
        (uint256 calledMaturity, uint256 calledPrincipal) = mp.tokenCalled(
            underlying
        );
        assertEq(maturity, calledMaturity);
        assertEq(3, calledPrincipal);

        {
            // transfer check
            (address transferFromTo, uint256 transferFromAmount) = mock_erc20
                .ERC20(underlying)
                .transferFromCalled(address(this));
            assertEq(address(l), transferFromTo);
            assertEq(amount, transferFromAmount);
        }

        // fee check
        uint256 collected = l.fees(underlying);
        assertEq(collected, expectedFee);

        // element vault check
        (
            address recipient,
            uint256 swapAmount,
            uint256 limit,
            uint256 swapDeadline
        ) = ev.swapCalled(address(l));
        assertEq(recipient, address(l));
        assertEq(swapAmount, amount - collected);
        assertEq(limit, minReturned);
        assertEq(swapDeadline, deadline);

        // mint check
        assertEq(purchased, ipt.mintCalled(address(this)));
    }

    function testPendleLend() public {
        uint256 purchased = amount + 50;
        uint256[] memory output = new uint256[](2);
        output[0] = 0;
        output[1] = purchased;
        uint256 minReturn = amount - 200;
        uint256 deadline = block.timestamp + 10;
        mp.tokenReturns(address(pt));
        mock_erc20.ERC20(underlying).transferFromReturns(true);
        p.swapExactTokensForTokensReturns(output);
        ipt.mintReturns(true);

        l.lend(4, underlying, maturity, amount, minReturn, deadline);

        // markets check
        (uint256 calledMaturity, uint256 calledPrincipal) = mp.tokenCalled(
            underlying
        );
        assertEq(maturity, calledMaturity);
        assertEq(4, calledPrincipal);

        // transfer check
        (address transferFromTo, uint256 transferFromAmount) = mock_erc20
            .ERC20(underlying)
            .transferFromCalled(address(this));
        assertEq(address(l), transferFromTo);
        assertEq(amount, transferFromAmount);

        // fee check
        uint256 collected = l.fees(underlying);
        assertEq(collected, expectedFee);

        // swap check
        // todo why isn't path also returned?
        (uint256 swapAmount, uint256 minimumBought, uint256 swapDeadline) = p
            .swapExactTokensForTokensCalled(address(l));
        assertEq(swapAmount, amount - collected);
        assertEq(minimumBought, minReturn);
        assertEq(swapDeadline, deadline);

        // mint check
        assertEq(purchased, ipt.mintCalled(address(this)));
    }

    function testTempusLend() public {
        uint256 minReturn = 100;
        uint256 deadline = block.timestamp + 10;
        // mocks
        mp.tokenReturns(address(tt));
        mock_erc20.ERC20(underlying).transferFromReturns(true);
        ipt.mintReturns(true);

        // execute
        l.lend(
            5,
            underlying,
            maturity,
            amount,
            minReturn,
            deadline,
            address(tp)
        );

        // markets check
        (uint256 calledMaturity, uint256 calledPrincipal) = mp.tokenCalled(
            underlying
        );
        assertEq(maturity, calledMaturity);
        assertEq(5, calledPrincipal);

        // transfer check
        (address transferFromTo, uint256 transferFromAmount) = mock_erc20
            .ERC20(underlying)
            .transferFromCalled(address(this));
        assertEq(address(l), transferFromTo);
        assertEq(amount, transferFromAmount);

        // fee check
        uint256 collected = l.fees(underlying);
        assertEq(collected, expectedFee);

        // deposit check
        (
            address amm,
            bool bt,
            uint256 minimumReturned,
            uint256 swapDeadline
        ) = t.depositAndFixCalled(amount - collected);
        assertEq(amm, address(tp));
        assertEq(bt, true);
        assertEq(minimumReturned, minReturn);
        assertEq(swapDeadline, deadline);

        // mint check
        assertEq(amount - collected, ipt.mintCalled(address(this)));
    }

    function testSenseLend() public {
        uint256 minReturn = amount / 2;
        uint256 senseMaturity = maturity - 20;
        uint256 returned = amount + 25;
        uint256 starting = 1124;

        mp.tokenReturns(address(st));
        st.balanceOfReturns(starting);
        sp.swapUnderlyingForPTsReturns(returned);
        mock_erc20.ERC20(underlying).transferFromReturns(true);
        ipt.mintReturns(true);

        l.lend(
            6,
            underlying,
            maturity,
            uint128(amount),
            minReturn,
            address(sp),
            senseMaturity,
            address(sa)
        );

        // markets check
        (uint256 calledMaturity, uint256 calledPrincipal) = mp.tokenCalled(
            underlying
        );
        assertEq(maturity, calledMaturity);
        assertEq(6, calledPrincipal);

        // transfer check
        (address transferFromTo, uint256 transferFromAmount) = mock_erc20
            .ERC20(underlying)
            .transferFromCalled(address(this));
        assertEq(address(l), transferFromTo);
        assertEq(amount, transferFromAmount);

        // fee check
        uint256 collected = l.fees(underlying);
        assertEq(collected, expectedFee);

        // deposit check
        (uint256 passedMaturity, uint256 lentAmount, uint256 minimum) = sp
            .swapUnderlyingForPTsCalled(address(sa));

        assertEq(passedMaturity, senseMaturity);
        assertEq(lentAmount, amount - collected);
        assertEq(minimum, minReturn);

        // mint check
        assertEq(returned, ipt.mintCalled(address(this)));
    }

    function testAPWineLend() public {
        uint256 minReturn = amount / 2;
        uint256 deadline = block.timestamp + 10;
        uint256 returned = amount + 50;
        mp.tokenReturns(address(apwp));
        apwp.getPTAddressReturns(address(apwt));
        mock_erc20.ERC20(underlying).transferFromReturns(true);
        apwr.swapExactAmountInReturns(returned);
        ipt.mintReturns(true);

        l.lend(
            7,
            underlying,
            maturity,
            amount,
            minReturn,
            deadline,
            address(apwr)
        );

        // markets check
        (uint256 calledMaturity, uint256 calledPrincipal) = mp.tokenCalled(
            underlying
        );
        assertEq(maturity, calledMaturity);
        assertEq(7, calledPrincipal);

        // transfer check
        (address transferFromTo, uint256 transferFromAmount) = mock_erc20
            .ERC20(underlying)
            .transferFromCalled(address(this));
        assertEq(address(l), transferFromTo);
        assertEq(amount, transferFromAmount);

        // fee check
        uint256 collected = l.fees(underlying);
        assertEq(collected, expectedFee);

        // deposit check
        (
            address principalToken,
            uint256 lent,
            uint256 minimum,
            uint256 swapDeadline,
            address refCode
        ) = apwr.swapExactAmountInCalled(address(l));
        assertEq(principalToken, address(apwp));
        assertEq(lent, amount - collected);
        assertEq(minimum, minReturn);
        assertEq(swapDeadline, deadline);
        assertEq(refCode, address(0));

        // mint check
        assertEq(returned, ipt.mintCalled(address(this)));
    }

    function testNotionalLend() public {
        uint256 deposited = amount - expectedFee;
        uint256 received = (deposited * 105) / 100;
        uint256 minReceived = 5;
        mp.tokenReturns(address(n));
        n.depositReturns(received);
        mock_erc20.ERC20(underlying).transferFromReturns(true);
        ipt.mintReturns(true);

        l.lend(8, underlying, maturity, amount, minReceived);

        // markets check
        (uint256 calledMaturity, uint256 calledPrincipal) = mp.tokenCalled(
            underlying
        );
        assertEq(maturity, calledMaturity);
        assertEq(8, calledPrincipal);

        // transfer check
        (address transferFromTo, uint256 transferFromAmount) = mock_erc20
            .ERC20(underlying)
            .transferFromCalled(address(this));
        assertEq(address(l), transferFromTo);
        assertEq(amount, transferFromAmount);

        // fee check
        uint256 collected = l.fees(underlying);
        assertEq(collected, expectedFee);

        // deposit check
        assertEq(deposited, n.depositCalled(address(l)));

        // mint check
        assertEq(received, ipt.mintCalled(address(this)));
    }

    function testNotionalSlippageCheck() public {
        uint256 received = 4;
        uint256 minReceived = 5;
        mp.tokenReturns(address(n));
        n.depositReturns(received);
        mock_erc20.ERC20(underlying).transferFromReturns(true);
        ipt.mintReturns(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                Exception.selector,
                16,
                received,
                minReceived,
                address(0),
                address(0)
            )
        );
        //abi.encodeWithSelector(MyContract.CustomError.selector, 1, 2)

        l.lend(8, underlying, maturity, amount, minReceived);
    }
}
