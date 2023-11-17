// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import {IAdapter} from "../interfaces/IAdapter.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IPendle} from "../interfaces/IPendle.sol";
import {IPendleSYToken} from "../interfaces/IPendleSYToken.sol";
import {IPendleToken}   from "../interfaces/IPendleToken.sol";
import {IMarketPlace} from "../interfaces/IMarketPlace.sol";
import {ILender} from "../interfaces/ILender.sol";

import {Exception} from "../errors/Exception.sol";

import {Pendle} from "../lib/Pendle.sol";
import {Safe} from "../lib/Safe.sol";

contract PendleAdapter  { 
    constructor() {}

    address public lender; 

    address public marketplace;

    address public redeemer;

    event TestEvent(address, address, uint256, uint256, string);

    error TestException(address, address, uint256, uint256, string);

    // @notice returns the address of the underlying token for the PT
    // @param pt The address of the PT
    function underlying(address pt) public view returns (address) {
        (, address underlying_, ) = IPendleSYToken(IPendleToken(pt).SY()).assetInfo();
        return (underlying_);
    }

    // @notice returns the maturity of the underlying token for the PT
    // @param pt The address of the PT
    function maturity(address pt) public view returns (uint256) {
        return IPendleToken(pt).expiry();
    }

    // @notice lendABI "returns" the arguments required in the bytes `d` for the lend function
    // @returns underlying_ The address of the underlying token
    // @returns maturity The maturity of the underlying token
    // @returns minimum The minimum amount of the PTs to receive when spending (amount - fee)
    // @returns pool The address of the pool to lend to (buy PTs from)
    function lendABI(
    ) public pure returns (
        uint256 minimum,
        address market,
        Pendle.ApproxParams memory approxParams,
        Pendle.TokenInput memory tokenInput) {
    }

    // @notice redeemABI "returns" the arguments required in the bytes `d` for the redeem function
    // @returns underlying_ The address of the underlying token
    // @returns maturity The maturity of the underlying token
    function redeemABI(
    ) public pure returns (
        Pendle.TokenOutput memory tokenOutput) {
    }
    
    // @notice verifies that the provided underlying and maturity align with the provided PT address, enabling minting
    // @param underlying_ The address of the underlying token
    // @param maturity_ The maturity of the iPT 
    // @param pt The address of the PT being deposited
    // @returns bool returns true when the PT can be used for minting to the provided underlying and maturity pairing
    function verify(address underlying_, uint256 maturity_, address pt) public view returns (bool) {
        if (underlying(pt) != underlying_ || maturity(pt) > maturity_) {
            revert Exception(
                8,
                maturity(pt),
                maturity_,
                underlying(pt),
                underlying_
            );
        }
        // Confirm that the principal token has not matured yet
        if (block.timestamp > maturity_ || maturity_ == 0) {
            revert Exception(
                7,
                maturity_,
                block.timestamp,
                address(0),
                address(0)
            );
        }
        return (true);
    }
    // @notice lends `amount` to pendle protocol
    // @param underlying_ The address of the underlying token
    // @param maturity_ The maturity of the underlying token
    // @param amount The amount of the underlying token to lend (amount[0] is used for this adapter)
    // @param internalBalance Whether or not to use the internal balance or if a transfer is necessary
    // @param d The calldata for the lend function -- described above in lendABI
    // @returns received The amount of the PTs received from the lend
    // @returns spent The amount of the underlying token spent on the lend
    // @returns fee The amount of the underlying token spent on the fee
    function lend(
        address underlying_,
        uint256 maturity_,
        uint256[] calldata amount,
        bool internalBalance,
        bytes calldata d
    ) external returns (uint256, uint256, uint256) {

        // Parse the calldata
        (
            uint256 minimum,
            address market,
            Pendle.ApproxParams memory approxParams,
            Pendle.TokenInput memory tokenInput
        ) = abi.decode(d, (uint256, address, Pendle.ApproxParams, Pendle.TokenInput));
        
        if (internalBalance == false){
            // Receive underlying funds, extract fees
            Safe.transferFrom(
                IERC20(underlying_),
                msg.sender,
                address(this),
                amount[0]
            );
        }

        (uint256 returned, ) = IPendle(ILender(lender).protocolRouters(1)).swapExactTokenForPt(
            address(this),
            market,
            minimum,
            approxParams,
            tokenInput
        );

        return (returned, amount[0], amount[0] / ILender(lender).feenominator());
    }

    // @notice After maturity, redeem `amount` of the underlying token from the yield protocol
    // @param amount The amount of the PTs to redeem
    // @param internalBalance Whether or not to use the internal balance or if a transfer is necessary
    // @param d The calldata for the redeem function -- described above in redeemABI
    function redeem(
        address underlying_,
        uint256 maturity_,
        uint256 amount,
        bool internalBalance,
        bytes calldata d
    ) external returns (uint256, uint256) {

        // Parse the calldata
        (
            Pendle.TokenOutput memory tokenOutput
        ) = abi.decode(d, (Pendle.TokenOutput));

        address pt = IMarketPlace(marketplace).markets(underlying_, maturity_).tokens[0];

        if (internalBalance == false){
            // Receive underlying funds, extract fees
            Safe.transferFrom(
                IERC20(pt),
                lender,
                address(this),
                amount
            );
        }

        uint256 starting = IERC20(underlying_).balanceOf(address(this));

        IPendle(ILender(lender).protocolRouters(1)).redeemPyToToken(address(this), IPendleToken(pt).YT(), amount, tokenOutput);

        uint256 received = IERC20(underlying_).balanceOf(address(this)) - starting;

        return (received, amount);
    }
}
