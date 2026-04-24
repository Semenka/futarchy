// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title FutarchyAMM
/// @notice Constant-product AMM (Uniswap V2 math, no fee) pairing collateral
///         with a LONG outcome token. One instance per branch per proposal.
///         Price accumulator enables TWAP reads to harden decide() against
///         end-of-window manipulation.
///
///         LONG price in collateral = reserveCollateral / reserveLong.
///         The spot price is the market-implied E[KPI_normalized] in [0, 1].
contract FutarchyAMM is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 private constant Q112 = 2 ** 112;

    IERC20 public immutable collateral;
    IERC20 public immutable longToken;

    uint112 private reserveCollateral_;
    uint112 private reserveLong_;
    uint32 private blockTimestampLast_;

    uint256 public priceLongCumulativeLast; // UQ112.112 cumulative price of long-in-collateral

    event Mint(address indexed sender, uint256 collateralIn, uint256 longIn, uint256 shares);
    event Burn(address indexed sender, address indexed to, uint256 shares, uint256 collateralOut, uint256 longOut);
    event Swap(
        address indexed sender,
        address indexed to,
        uint256 collateralIn,
        uint256 longIn,
        uint256 collateralOut,
        uint256 longOut
    );
    event Sync(uint112 reserveCollateral, uint112 reserveLong);

    constructor(IERC20 _collateral, IERC20 _longToken, string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {
        collateral = _collateral;
        longToken = _longToken;
    }

    function getReserves() public view returns (uint112 rColl, uint112 rLong, uint32 ts) {
        return (reserveCollateral_, reserveLong_, blockTimestampLast_);
    }

    /// @notice Spot long price in collateral, scaled by 1e18.
    function getLongPrice() external view returns (uint256) {
        uint112 rColl = reserveCollateral_;
        uint112 rLong = reserveLong_;
        if (rLong == 0) return 0;
        return (uint256(rColl) * 1e18) / uint256(rLong);
    }

    /// @notice TWAP of long price over [now - window, now], scaled by 1e18.
    ///         Caller provides the cumulative snapshot taken `window` seconds ago.
    function consultTWAP(uint256 cumulativeAtStart, uint32 tsAtStart) external view returns (uint256 twap) {
        (uint112 rColl, uint112 rLong, uint32 tsLast) = getReserves();
        uint32 nowTs = uint32(block.timestamp);

        uint256 cumulativeNow = priceLongCumulativeLast;
        if (tsLast != nowTs && rLong > 0) {
            uint256 priceQ112 = (uint256(rColl) * Q112) / uint256(rLong);
            cumulativeNow += priceQ112 * (nowTs - tsLast);
        }
        uint32 elapsed = nowTs - tsAtStart;
        require(elapsed > 0, "AMM: window=0");
        // average UQ112.112 price → scale to 1e18
        twap = ((cumulativeNow - cumulativeAtStart) * 1e18) / (uint256(elapsed) * Q112);
    }

    function _update(uint256 balColl, uint256 balLong, uint112 rColl, uint112 rLong) private {
        require(balColl <= type(uint112).max && balLong <= type(uint112).max, "AMM: overflow");
        uint32 nowTs = uint32(block.timestamp);
        uint32 elapsed = nowTs - blockTimestampLast_;
        if (elapsed > 0 && rColl > 0 && rLong > 0) {
            uint256 priceQ112 = (uint256(rColl) * Q112) / uint256(rLong);
            priceLongCumulativeLast += priceQ112 * elapsed;
        }
        reserveCollateral_ = uint112(balColl);
        reserveLong_ = uint112(balLong);
        blockTimestampLast_ = nowTs;
        emit Sync(uint112(balColl), uint112(balLong));
    }

    /// @notice Deposit `collateralIn` + `longIn` in proportion to reserves; mint LP shares.
    function addLiquidity(uint256 collateralIn, uint256 longIn, address to)
        external
        nonReentrant
        returns (uint256 shares)
    {
        (uint112 rColl, uint112 rLong,) = getReserves();

        collateral.safeTransferFrom(msg.sender, address(this), collateralIn);
        longToken.safeTransferFrom(msg.sender, address(this), longIn);

        uint256 balColl = collateral.balanceOf(address(this));
        uint256 balLong = longToken.balanceOf(address(this));
        uint256 amountColl = balColl - rColl;
        uint256 amountLong = balLong - rLong;

        uint256 supply = totalSupply();
        if (supply == 0) {
            shares = Math.sqrt(amountColl * amountLong) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY); // lock forever
        } else {
            shares = Math.min((amountColl * supply) / rColl, (amountLong * supply) / rLong);
        }
        require(shares > 0, "AMM: zero shares");
        _mint(to, shares);

        _update(balColl, balLong, rColl, rLong);
        emit Mint(msg.sender, amountColl, amountLong, shares);
    }

    /// @notice Burn `shares`; receive proportional collateral + long.
    function removeLiquidity(uint256 shares, address to)
        external
        nonReentrant
        returns (uint256 amountColl, uint256 amountLong)
    {
        (uint112 rColl, uint112 rLong,) = getReserves();
        uint256 balColl = collateral.balanceOf(address(this));
        uint256 balLong = longToken.balanceOf(address(this));
        uint256 supply = totalSupply();

        amountColl = (shares * balColl) / supply;
        amountLong = (shares * balLong) / supply;
        require(amountColl > 0 && amountLong > 0, "AMM: zero out");

        _burn(msg.sender, shares);
        collateral.safeTransfer(to, amountColl);
        longToken.safeTransfer(to, amountLong);

        balColl = collateral.balanceOf(address(this));
        balLong = longToken.balanceOf(address(this));
        _update(balColl, balLong, rColl, rLong);
        emit Burn(msg.sender, to, shares, amountColl, amountLong);
    }

    /// @notice Swap `collateralIn` for long; slippage-protected.
    function swapCollateralForLong(uint256 collateralIn, uint256 minLongOut, address to)
        external
        nonReentrant
        returns (uint256 longOut)
    {
        (uint112 rColl, uint112 rLong,) = getReserves();
        require(rColl > 0 && rLong > 0, "AMM: uninit");

        collateral.safeTransferFrom(msg.sender, address(this), collateralIn);
        // x*y=k, no fee: longOut = rLong - k / (rColl + dx)
        uint256 newColl = uint256(rColl) + collateralIn;
        uint256 newLong = (uint256(rColl) * uint256(rLong)) / newColl;
        if (newLong * newColl < uint256(rColl) * uint256(rLong)) newLong += 1; // round up to preserve k
        longOut = uint256(rLong) - newLong;
        require(longOut >= minLongOut, "AMM: slippage");

        longToken.safeTransfer(to, longOut);
        _update(newColl, newLong, rColl, rLong);
        emit Swap(msg.sender, to, collateralIn, 0, 0, longOut);
    }

    /// @notice Swap `longIn` for collateral; slippage-protected.
    function swapLongForCollateral(uint256 longIn, uint256 minCollateralOut, address to)
        external
        nonReentrant
        returns (uint256 collateralOut)
    {
        (uint112 rColl, uint112 rLong,) = getReserves();
        require(rColl > 0 && rLong > 0, "AMM: uninit");

        longToken.safeTransferFrom(msg.sender, address(this), longIn);
        uint256 newLong = uint256(rLong) + longIn;
        uint256 newColl = (uint256(rColl) * uint256(rLong)) / newLong;
        if (newColl * newLong < uint256(rColl) * uint256(rLong)) newColl += 1;
        collateralOut = uint256(rColl) - newColl;
        require(collateralOut >= minCollateralOut, "AMM: slippage");

        collateral.safeTransfer(to, collateralOut);
        _update(newColl, newLong, rColl, rLong);
        emit Swap(msg.sender, to, 0, longIn, collateralOut, 0);
    }
}
