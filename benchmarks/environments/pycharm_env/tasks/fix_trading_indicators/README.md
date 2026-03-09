# fix_trading_indicators

## Overview

**Occupation**: Financial Quantitative Analysts
**Industry**: Securities, Commodity Contracts, and Other Financial Investments
**Difficulty**: Very Hard

A Python technical-indicators library (`trading_indicators`) used by a backtesting system is producing incorrect signals. The CI pipeline is failing and the risk desk has flagged that the Sharpe ratios and RSI values do not match Bloomberg terminal benchmarks. The agent must run the failing tests, identify the mathematical errors in the indicator implementations, and fix them.

No information about which indicators are broken or what the correct formulas are is given to the agent.

---

## Goal

All tests in `tests/` must pass with `pytest exit code 0`.

The project is pre-opened in PyCharm. The agent must NOT modify the test files or function signatures.

---

## Starting State

The project is at `/home/ga/PycharmProjects/trading_indicators/` and contains:

```
trading_indicators/
├── indicators/
│   ├── ema.py          # Bug 1: wrong smoothing factor k
│   ├── rsi.py          # Bug 2: wrong RS formula (subtraction instead of division)
│   └── stats.py        # Bug 3: Sharpe divides by variance; Bug 4: max_drawdown uses pair-max not running-max
├── tests/
│   ├── test_ema.py      # 5 tests — fail before fix
│   ├── test_rsi.py      # 5 tests — fail before fix
│   └── test_stats.py    # 7 tests — fail before fix
└── requirements.txt
```

---

## Bugs (Ground Truth — do not reveal in task description)

| Bug | File | Function | Correct Formula | Bug in Code |
|-----|------|----------|-----------------|-------------|
| 1 | `indicators/ema.py` | `exponential_moving_average` | `k = 2 / (period + 1)` | `k = 1 / period` |
| 2 | `indicators/rsi.py` | `relative_strength_index` | `rs = avg_gain / avg_loss` | `rs = avg_gain - avg_loss` |
| 3 | `indicators/stats.py` | `sharpe_ratio` | `mean_excess / sqrt(variance)` | `mean_excess / variance` |
| 4 | `indicators/stats.py` | `max_drawdown` | `peak = max(prices[:i+1])` accumulated | `peak = max(prices[i-1], prices[i])` |

---

## Data Sources

The test files use hardcoded price arrays (directly embedded in the test Python files):
- `SPY_CLOSES`: 15 daily closing prices in the range typical for SPY (S&P 500 ETF) in late 2023 / early 2024
- `PRICES_RISING`: a monotonically increasing series for RSI boundary testing
- `SAMPLE_RETURNS`: 30 daily returns with mean ≈ 0.001 and std ≈ 0.015
- `PRICES_WITH_DRAWDOWN`: a synthetic series with a known peak (115) and trough (103) for drawdown validation

The expected values in each test are derived analytically from these series using the correct formulas, providing unambiguous ground truth.

---

## Verification Strategy

**Criterion 1 (25 pts)**: `bug1_ema_smoothing_fixed` — `k = 2/(period+1)` present in `ema.py`; `test_ema_first_value_after_seed` passes
**Criterion 2 (25 pts)**: `bug2_rsi_rs_formula_fixed` — division used for RS; `test_rsi_range_valid` and `test_rsi_all_gains_returns_100` pass
**Criterion 3 (25 pts)**: `bug3_sharpe_stddev_fixed` — `sqrt(variance)` used; `test_sharpe_reasonable_magnitude` and `test_sharpe_known_value` pass
**Criterion 4 (25 pts)**: `bug4_drawdown_running_peak_fixed` — global running peak tracked; `test_max_drawdown_known_value` passes

**Pass threshold**: 65/100 (must fix at least 2-3 bugs)

---

## Edge Cases

- All 4 bugs produce dramatically wrong output values (not just off by a small amount), making them discoverable by running tests
- Bug 2 (RS subtraction) will produce RSI values outside [0, 100] for unbalanced markets — a clear signal something is wrong
- Bug 3 (Sharpe / variance) produces Sharpe ratios 10-100× too large for normal strategy returns
- Bug 4 (drawdown pair-max) will only find drawdowns within 2-day windows, missing multi-day peaks
