import json
import os
import tempfile


def verify_fix_trading_indicators(traj, env_info, task_info):
    """
    Verify that the agent fixed all 4 mathematical bugs in the trading indicators library:
      Bug 1 (25 pts): EMA smoothing factor uses k=2/(period+1) not k=1/period
      Bug 2 (25 pts): RSI uses RS = avg_gain / avg_loss (not subtraction)
      Bug 3 (25 pts): Sharpe ratio divides by std dev (not variance)
      Bug 4 (25 pts): Max drawdown tracks global running peak (not adjacent pair max)
    Pass threshold: 65 (must fix at least 2-3 bugs)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available",
        }

    task_name = "fix_trading_indicators"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result JSON malformed: {e}",
        }

    score = 0
    parts = []
    issues = []

    # Bug 1: EMA smoothing factor
    if result.get("bug1_ema_smoothing_fixed", False):
        score += 25
        parts.append("Bug 1 fixed: EMA smoothing factor k = 2/(period+1) (25/25)")
    else:
        issues.append(
            "Bug 1 NOT fixed: EMA uses k = 1/period — "
            "correct formula is k = 2/(period+1). "
            "test_ema_first_value_after_seed and test_ema_converges_toward_prices are failing."
        )

    # Bug 2: RSI RS formula
    if result.get("bug2_rsi_rs_formula_fixed", False):
        score += 25
        parts.append("Bug 2 fixed: RSI uses RS = avg_gain / avg_loss (25/25)")
    else:
        issues.append(
            "Bug 2 NOT fixed: RSI uses RS = avg_gain - avg_loss (subtraction) — "
            "must be avg_gain / avg_loss (division). "
            "RSI values will be out of [0,100] range with the bug."
        )

    # Bug 3: Sharpe ratio
    if result.get("bug3_sharpe_stddev_fixed", False):
        score += 25
        parts.append("Bug 3 fixed: Sharpe ratio divides by std dev, not variance (25/25)")
    else:
        issues.append(
            "Bug 3 NOT fixed: sharpe_ratio divides by variance — "
            "must divide by math.sqrt(variance) (std dev). "
            "This produces unrealistically large Sharpe values."
        )

    # Bug 4: Max drawdown
    if result.get("bug4_drawdown_running_peak_fixed", False):
        score += 25
        parts.append("Bug 4 fixed: max_drawdown tracks global running peak (25/25)")
    else:
        issues.append(
            "Bug 4 NOT fixed: max_drawdown computes peak as max(prices[i-1], prices[i]) — "
            "must track the global maximum from prices[0] up to current index."
        )

    score = min(score, 100)
    passed = score >= 65

    tests_passed = result.get("tests_passed", 0)
    tests_failed = result.get("tests_failed", 0)
    summary = f"Score: {score}/100 | Tests: {tests_passed} passing, {tests_failed} failing"

    all_feedback = parts + issues
    return {
        "passed": passed,
        "score": score,
        "feedback": f"{summary} | " + " | ".join(all_feedback) if all_feedback else summary,
    }
