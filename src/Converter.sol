// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import "./lib/Safe.sol";
import "./errors/Exception.sol";

import "./interfaces/IConverter.sol";
import "./interfaces/IAaveAToken.sol";
import "./interfaces/IAaveLendingPool.sol";
import "./interfaces/ICompoundToken.sol";
import "./interfaces/ILido.sol";
import "./interfaces/IERC20.sol";

contract Converter is IConverter {
    /// @notice converts the compounding asset to the underlying asset for msg.sender
    /// @dev currently supports Compound, Aave and Lido conversions
    /// @param c address of the compounding token
    /// @param u address of the underlying token
    /// @param a amount of tokens to convert
    function convert(address c, address u, uint256 a) external {
        // First receive the tokens from msg.sender
        Safe.transferFrom(IERC20(c), msg.sender, address(this), a);

        // Get Aave pool
        try IAaveAToken(c).POOL() returns (address pool) {
            // Withdraw from Aave
            IAaveLendingPool(pool).withdraw(u, a, msg.sender);
        } catch {
            // Attempt to redeem compound tokens to the underlying asset
            try ICompoundToken(c).redeem(a) returns (uint256 err) {
                // Error if `redeem` returns non-zero value
                if (err != 0) {
                    revert Exception(28, err, 0, address(0), address(0));
                }

                // Get the balance of underlying assets redeemed
                uint256 balance = IERC20(u).balanceOf(address(this));

                // Transfer the underlying back to the user
                Safe.transfer(IERC20(u), msg.sender, balance);
            } catch {
                // Get the current balance of wstETH
                uint256 balance = IERC20(c).balanceOf(address(this));

                // Unwrap wrapped staked eth
                uint256 unwrapped = ILido(c).unwrap(balance);

                // Send the unwrapped staked ETH to the caller
                Safe.transfer(IERC20(u), msg.sender, unwrapped);
            }
        }
    }
}
