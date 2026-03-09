#!/bin/bash
echo "=== Setting up fix_trading_indicators ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_trading_indicators"
PROJECT_DIR="/home/ga/PycharmProjects/trading_indicators"

rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json

mkdir -p "$PROJECT_DIR/indicators"
mkdir -p "$PROJECT_DIR/tests"

# requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'REQUIREMENTS'
pytest>=7.0
numpy>=1.24.0
REQUIREMENTS

# --- indicators/__init__.py ---
touch "$PROJECT_DIR/indicators/__init__.py"

# --- indicators/ema.py ---
# BUG 1: smoothing factor uses wrong formula
# Correct EMA smoothing: k = 2 / (period + 1)
# Bug: uses k = 1 / period  (off-by-one in denominator, missing the factor of 2)
cat > "$PROJECT_DIR/indicators/ema.py" << 'PYEOF'
"""Exponential Moving Average (EMA) implementation."""
from typing import List


def exponential_moving_average(prices: List[float], period: int) -> List[float]:
    """
    Compute EMA for a price series.

    EMA_t = price_t * k + EMA_{t-1} * (1 - k)
    where k = 2 / (period + 1)  [standard smoothing factor]

    Returns a list of the same length as prices.
    Values before the first full period are seeded with the simple average.
    """
    if period <= 0 or len(prices) < period:
        return []

    # BUG: smoothing factor is wrong — should be 2/(period+1), not 1/period
    k = 1 / period

    # Seed with simple mean of first `period` prices
    ema = [sum(prices[:period]) / period]

    for price in prices[period:]:
        ema.append(price * k + ema[-1] * (1 - k))

    # Pad beginning with NaN to match input length
    result = [float("nan")] * (period - 1) + ema
    return result
PYEOF

# --- indicators/rsi.py ---
# BUG 2: RSI uses wrong formula for RS — uses (avg_gain - avg_loss) instead of (avg_gain / avg_loss)
cat > "$PROJECT_DIR/indicators/rsi.py" << 'PYEOF'
"""Relative Strength Index (RSI) implementation."""
from typing import List


def relative_strength_index(prices: List[float], period: int = 14) -> List[float]:
    """
    Compute RSI using Wilder's smoothing method.

    RS = avg_gain / avg_loss  (over `period` periods)
    RSI = 100 - (100 / (1 + RS))

    Returns list of same length as prices; first `period` values are NaN.
    """
    if len(prices) < period + 1:
        return [float("nan")] * len(prices)

    changes = [prices[i] - prices[i - 1] for i in range(1, len(prices))]
    gains = [max(c, 0.0) for c in changes]
    losses = [abs(min(c, 0.0)) for c in changes]

    result = [float("nan")] * period

    avg_gain = sum(gains[:period]) / period
    avg_loss = sum(losses[:period]) / period

    def _rsi_from_rs(ag, al):
        if al == 0:
            return 100.0
        # BUG: RS should be ag / al (division), not ag - al (subtraction)
        rs = ag - al
        return 100 - (100 / (1 + rs))

    result.append(_rsi_from_rs(avg_gain, avg_loss))

    for i in range(period, len(changes)):
        avg_gain = (avg_gain * (period - 1) + gains[i]) / period
        avg_loss = (avg_loss * (period - 1) + losses[i]) / period
        result.append(_rsi_from_rs(avg_gain, avg_loss))

    return result
PYEOF

# --- indicators/stats.py ---
# BUG 3: sharpe_ratio divides by variance instead of std dev
# BUG 4: max_drawdown computes drawdown from rolling window max instead of global running max
cat > "$PROJECT_DIR/indicators/stats.py" << 'PYEOF'
"""Portfolio statistics: Sharpe ratio and max drawdown."""
import math
from typing import List


def sharpe_ratio(returns: List[float], risk_free_rate: float = 0.0) -> float:
    """
    Compute annualised Sharpe ratio for daily returns.

    Sharpe = (mean_excess_return / std_dev_return) * sqrt(252)

    Args:
        returns: list of daily returns (e.g. [0.001, -0.002, ...])
        risk_free_rate: daily risk-free rate (default 0)
    Returns:
        Annualised Sharpe ratio (float)
    """
    n = len(returns)
    if n < 2:
        return float("nan")

    excess = [r - risk_free_rate for r in returns]
    mean_excess = sum(excess) / n
    variance = sum((r - mean_excess) ** 2 for r in excess) / (n - 1)

    if variance == 0:
        return float("nan")

    # BUG: divides by variance instead of std dev (should be math.sqrt(variance))
    sharpe = mean_excess / variance * math.sqrt(252)
    return sharpe


def max_drawdown(prices: List[float]) -> float:
    """
    Compute maximum drawdown as a fraction (negative value).

    Max drawdown = min over all t of (price[t] - running_max_up_to_t) / running_max_up_to_t

    Args:
        prices: list of asset prices (not returns)
    Returns:
        Maximum drawdown as a negative fraction (e.g. -0.12 for -12%)
    """
    if len(prices) < 2:
        return 0.0

    max_dd = 0.0
    # BUG: should track the global running peak from the start,
    # but here `peak` resets every iteration instead of accumulating
    for i in range(1, len(prices)):
        # BUG: peak is recalculated as the max of just the previous price
        # instead of the max of all prices seen so far (prices[0..i])
        peak = max(prices[i - 1], prices[i])  # wrong: should be max(prices[:i+1]) accumulated
        if prices[i] < peak:
            dd = (prices[i] - peak) / peak
            max_dd = min(max_dd, dd)

    return max_dd
PYEOF

# --- tests/__init__.py ---
touch "$PROJECT_DIR/tests/__init__.py"

# --- tests/test_ema.py ---
cat > "$PROJECT_DIR/tests/test_ema.py" << 'PYEOF'
"""Tests for EMA implementation against known reference values."""
import math
import pytest
from indicators.ema import exponential_moving_average


# Test price series for EMA verification, period=5.
# Values chosen so that analytical verification is straightforward:
#   seed = mean(first 5) = (471.52+475.31+467.92+472.83+473.72)/5 = 472.26
#   correct EMA[5] = 475.78*(2/6) + 472.26*(4/6) = 473.43  (using k=2/(5+1))
#   buggy  EMA[5]  = 475.78*(1/5) + 472.26*(4/5) = 473.16  (using k=1/5 — wrong)
# Price range (465-480) is representative of large-cap ETF price series.
PRICE_SERIES = [
    471.52, 475.31, 467.92, 472.83, 473.72, 475.78, 476.36, 475.62,
    473.54, 472.03, 468.31, 467.89, 467.95, 473.31, 472.76
]
PERIOD = 5


def test_ema_output_length():
    result = exponential_moving_average(PRICE_SERIES, PERIOD)
    assert len(result) == len(PRICE_SERIES), \
        f"EMA output length {len(result)} != input length {len(PRICE_SERIES)}"


def test_ema_prefix_is_nan():
    result = exponential_moving_average(PRICE_SERIES, PERIOD)
    for i in range(PERIOD - 1):
        assert math.isnan(result[i]), f"result[{i}] should be NaN, got {result[i]}"


def test_ema_seed_is_simple_average():
    result = exponential_moving_average(PRICE_SERIES, PERIOD)
    seed = sum(PRICE_SERIES[:PERIOD]) / PERIOD
    assert abs(result[PERIOD - 1] - seed) < 0.01, \
        f"EMA seed {result[PERIOD - 1]:.4f} != simple average {seed:.4f}"


def test_ema_first_value_after_seed():
    """Day 6 EMA with k=2/(5+1)=1/3: 475.78*(1/3) + 472.26*(2/3) = 473.43"""
    result = exponential_moving_average(PRICE_SERIES, PERIOD)
    seed = sum(PRICE_SERIES[:PERIOD]) / PERIOD
    k = 2 / (PERIOD + 1)  # correct k
    expected = PRICE_SERIES[PERIOD] * k + seed * (1 - k)
    actual = result[PERIOD]
    assert abs(actual - expected) < 0.02, \
        f"First post-seed EMA {actual:.4f} != expected {expected:.4f}. " \
        f"Check that smoothing factor k = 2/(period+1), not 1/period."


def test_ema_converges_toward_prices():
    """EMA should be between previous EMA and current price (bounded)."""
    result = exponential_moving_average(PRICE_SERIES, PERIOD)
    for i in range(PERIOD, len(PRICE_SERIES)):
        prev_ema = result[i - 1]
        curr_price = PRICE_SERIES[i]
        curr_ema = result[i]
        lo = min(prev_ema, curr_price) - 0.01
        hi = max(prev_ema, curr_price) + 0.01
        assert lo <= curr_ema <= hi, \
            f"EMA[{i}]={curr_ema:.4f} is outside [{lo:.4f}, {hi:.4f}]"
PYEOF

# --- tests/test_rsi.py ---
cat > "$PROJECT_DIR/tests/test_rsi.py" << 'PYEOF'
"""Tests for RSI implementation."""
import math
import pytest
from indicators.rsi import relative_strength_index


# 20 closing prices: a simple rising then falling sequence
# RSI should be well above 50 on the rising part
PRICES_RISING = [100.0, 101.5, 103.2, 102.8, 104.1, 105.6, 107.2, 106.5,
                 108.0, 109.3, 110.7, 109.8, 111.2, 112.5, 113.8]
PRICES_FLAT = [100.0] * 16  # all same → RSI undefined


def test_rsi_output_length():
    result = relative_strength_index(PRICES_RISING, 14)
    assert len(result) == len(PRICES_RISING)


def test_rsi_prefix_is_nan():
    result = relative_strength_index(PRICES_RISING, 14)
    for i in range(14):
        assert math.isnan(result[i]), f"result[{i}] should be NaN"


def test_rsi_range_valid():
    """RSI must always be in [0, 100]."""
    result = relative_strength_index(PRICES_RISING, 14)
    for i in range(14, len(result)):
        assert 0 <= result[i] <= 100, \
            f"RSI[{i}]={result[i]:.2f} is outside [0, 100]. " \
            f"Check RS formula: use avg_gain / avg_loss, not avg_gain - avg_loss."


def test_rsi_rising_market_above_50():
    """In a predominantly rising market, RSI should be > 50."""
    result = relative_strength_index(PRICES_RISING, 14)
    last_rsi = result[-1]
    assert last_rsi > 50, \
        f"RSI={last_rsi:.2f} should be > 50 for rising prices. " \
        f"RS = avg_gain / avg_loss (division, not subtraction)"


def test_rsi_all_gains_returns_100():
    """When all price changes are positive, RSI = 100."""
    strictly_rising = [100.0 + i for i in range(16)]
    result = relative_strength_index(strictly_rising, 14)
    assert abs(result[-1] - 100.0) < 0.01, \
        f"All-gains RSI should be 100.0, got {result[-1]:.4f}"


def test_rsi_all_losses_returns_0():
    """When all price changes are negative, RSI = 0."""
    strictly_falling = [100.0 - i * 0.5 for i in range(16)]
    result = relative_strength_index(strictly_falling, 14)
    assert abs(result[-1] - 0.0) < 0.01, \
        f"All-losses RSI should be 0.0, got {result[-1]:.4f}"
PYEOF

# --- tests/test_stats.py ---
cat > "$PROJECT_DIR/tests/test_stats.py" << 'PYEOF'
"""Tests for Sharpe ratio and max drawdown."""
import math
import pytest
from indicators.stats import sharpe_ratio, max_drawdown


# Sample daily returns for a hypothetical strategy
# mean ≈ 0.001, std ≈ 0.015 → Sharpe ≈ 0.001/0.015 * sqrt(252) ≈ 1.06
SAMPLE_RETURNS = [
    0.012, -0.008, 0.015, 0.003, -0.011, 0.018, -0.005, 0.009,
    0.001, -0.014, 0.022, -0.003, 0.007, 0.016, -0.009, 0.004,
    0.011, -0.006, 0.013, -0.002, 0.008, 0.019, -0.007, 0.005,
    0.014, -0.010, 0.017, 0.002, -0.013, 0.020
]

# Prices: steady rise then drop → drawdown should be significant
PRICES_WITH_DRAWDOWN = [
    100, 102, 105, 108, 106, 110, 115, 112, 108, 103, 105, 108, 111
]


class TestSharpeRatio:
    def test_sharpe_positive_for_positive_returns(self):
        """Strategy with positive mean return should have positive Sharpe."""
        result = sharpe_ratio(SAMPLE_RETURNS)
        assert result > 0, f"Sharpe={result:.4f} should be > 0 for positive-mean returns"

    def test_sharpe_reasonable_magnitude(self):
        """Annualised Sharpe for typical strategy should be in plausible range."""
        result = sharpe_ratio(SAMPLE_RETURNS)
        # A Sharpe > 5 or < -5 would be unrealistic for these returns
        # and indicates dividing by variance instead of std dev
        assert 0 < result < 5, \
            f"Sharpe={result:.4f} is outside plausible range (0, 5). " \
            f"Check: should divide by std_dev (sqrt(variance)), not variance."

    def test_sharpe_zero_risk_free_vs_nonzero(self):
        """Higher risk-free rate should reduce Sharpe."""
        sharpe_0 = sharpe_ratio(SAMPLE_RETURNS, risk_free_rate=0.0)
        sharpe_high_rf = sharpe_ratio(SAMPLE_RETURNS, risk_free_rate=0.0005)
        assert sharpe_0 > sharpe_high_rf, \
            "Higher risk-free rate should produce lower Sharpe"

    def test_sharpe_known_value(self):
        """Verify against manually computed value."""
        # Simple returns: all exactly 0.01 (1%)
        # mean=0.01, std=0 → Sharpe=inf (skip), use near-constant instead
        returns = [0.01 + (i % 3 - 1) * 0.001 for i in range(30)]
        result = sharpe_ratio(returns)
        # mean ≈ 0.01, std ≈ 0.001 → Sharpe ≈ 0.01/0.001 * sqrt(252) ≈ 158.7
        # If bug: divide by variance (0.000001) → Sharpe ≈ 158740 (wildly wrong)
        assert result < 500, \
            f"Sharpe={result:.2f} is unreasonably large — dividing by variance not std_dev"


class TestMaxDrawdown:
    def test_max_drawdown_negative(self):
        """Max drawdown should always be <= 0."""
        result = max_drawdown(PRICES_WITH_DRAWDOWN)
        assert result <= 0, f"Max drawdown {result:.4f} should be <= 0"

    def test_max_drawdown_known_value(self):
        """115 → 103: drawdown = (103 - 115) / 115 = -0.1043"""
        result = max_drawdown(PRICES_WITH_DRAWDOWN)
        expected = (103 - 115) / 115  # ≈ -0.1043
        assert abs(result - expected) < 0.005, \
            f"Max drawdown {result:.4f} != expected {expected:.4f}. " \
            f"peak should be global running max (115), not local pair max."

    def test_max_drawdown_monotone_rising(self):
        """No drawdown in purely rising prices."""
        rising = [100 + i for i in range(20)]
        result = max_drawdown(rising)
        assert result == 0.0, \
            f"No drawdown expected for rising prices, got {result:.4f}"

    def test_max_drawdown_immediate_drop(self):
        """Single drop at start: [100, 50, 60] → drawdown = (50-100)/100 = -0.50"""
        result = max_drawdown([100.0, 50.0, 60.0])
        assert abs(result - (-0.50)) < 0.001, \
            f"Expected max drawdown -0.50, got {result:.4f}"
PYEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Install dependencies
echo "Installing Python dependencies..."
su - ga -c "pip3 install --quiet numpy pandas pytest 2>&1 | tail -3" || true

# PyCharm .idea project files
mkdir -p "$PROJECT_DIR/.idea"
cat > "$PROJECT_DIR/.idea/misc.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectRootManager" version="2" project-jdk-name="Python 3.11" project-jdk-type="Python SDK" />
</project>
XML

cat > "$PROJECT_DIR/.idea/modules.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://$PROJECT_DIR$/trading_indicators.iml" filepath="$PROJECT_DIR$/trading_indicators.iml" />
    </modules>
  </component>
</project>
XML

cat > "$PROJECT_DIR/.idea/trading_indicators.iml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<module type="PYTHON_MODULE" version="4">
  <component name="NewModuleRootManager">
    <content url="file://$MODULE_DIR$" />
    <orderEntry type="inheritedJdk" />
    <orderEntry type="sourceFolder" forTests="false" />
  </component>
</module>
XML

chown -R ga:ga "$PROJECT_DIR/.idea"

# Record start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts

# Open in PyCharm
echo "Opening project in PyCharm..."
if type setup_pycharm_project &>/dev/null; then
    setup_pycharm_project "$PROJECT_DIR"
else
    su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' >> /home/ga/pycharm.log 2>&1 &"
    sleep 15
fi

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
