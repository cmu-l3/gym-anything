#!/usr/bin/env python3
"""
Verifier for garch_financial_risk task.

Task: GARCH(1,1) volatility modeling and Value-at-Risk estimation for SPY ETF.
Occupation: Financial Quantitative Analyst

Scoring (100 points total):
  Subtask 1 - VaR estimates CSV (35 pts):
    - CSV exists and is new (10 pts)
    - Has required columns (Date, volatility, VaR_95, VaR_99) (10 pts)
    - VaR_99 is more negative than VaR_95 (correct ordering) (10 pts)
    - Conditional volatility in realistic range (5 pts)
    - Row count > 200 (5 pts)

  Subtask 2 - Backtest CSV (20 pts):
    - CSV exists and is new (10 pts)
    - Contains Kupiec/exceedance test results (10 pts)

  Subtask 3 - 3-panel figure (25 pts):
    - PNG exists and is new (10 pts)
    - File size > 50KB (substantial multi-panel figure) (10 pts)
    - Valid PNG header (5 pts)

  Subtask 4 - R script quality (20 pts):
    - Script was modified during task (5 pts)
    - Script contains rugarch/GARCH function calls (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/garch_financial_risk_result.json"


def verify_garch_financial_risk(traj, env_info, task_info):
    """Verify GARCH volatility modeling and VaR estimation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0,
                    "feedback": "Result file not found — export script may not have run"}
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # ----------------------------------------------------------------
    # Subtask 1: VaR estimates CSV (35 pts)
    # ----------------------------------------------------------------
    if result.get('var_csv_exists') and result.get('var_csv_is_new'):
        score += 10
        feedback.append("VaR CSV created (10/10)")
    elif result.get('var_csv_exists'):
        score += 3
        feedback.append("VaR CSV exists but not created during task (3/10)")
    else:
        feedback.append("VaR CSV missing (0/10)")

    if result.get('var_has_correct_cols'):
        score += 10
        feedback.append("VaR CSV has required columns: date, volatility, VaR_95, VaR_99 (10/10)")
    else:
        feedback.append("VaR CSV missing required columns (0/10)")

    if result.get('var99_more_negative_than_var95'):
        score += 10
        feedback.append("VaR ordering correct: VaR_99 < VaR_95 < 0 (10/10)")
    else:
        feedback.append("VaR ordering incorrect: VaR_99 should be more negative than VaR_95 (0/10)")

    if result.get('conditional_vol_in_range'):
        score += 5
        feedback.append("Conditional volatility in realistic range (5/5)")
    else:
        feedback.append("Conditional volatility out of expected range (0/5)")

    row_count = result.get('var_csv_row_count', 0)
    if row_count >= 200:
        score += 5
        feedback.append(f"VaR CSV has sufficient rows: {row_count} (5/5)")
    elif row_count > 50:
        score += 2
        feedback.append(f"VaR CSV has some rows: {row_count} (2/5)")
    else:
        feedback.append(f"VaR CSV has too few rows: {row_count} (0/5)")

    # ----------------------------------------------------------------
    # Subtask 2: Backtest CSV (20 pts)
    # ----------------------------------------------------------------
    if result.get('backtest_csv_exists') and result.get('backtest_csv_is_new'):
        score += 10
        feedback.append("Backtest CSV created (10/10)")
    elif result.get('backtest_csv_exists'):
        score += 3
        feedback.append("Backtest CSV exists but not new (3/10)")
    else:
        feedback.append("Backtest CSV missing (0/10)")

    if result.get('backtest_has_kupiec'):
        score += 10
        feedback.append("Backtest CSV contains Kupiec/exceedance test results (10/10)")
    else:
        feedback.append("Backtest CSV missing Kupiec statistics (0/10)")

    # ----------------------------------------------------------------
    # Subtask 3: 3-panel figure (25 pts)
    # ----------------------------------------------------------------
    plot_size_kb = result.get('plot_size_kb', 0)

    if result.get('plot_exists') and result.get('plot_is_new'):
        score += 10
        feedback.append("GARCH report figure created (10/10)")
    elif result.get('plot_exists'):
        score += 3
        feedback.append("Figure exists but not new (3/10)")
    else:
        feedback.append("GARCH report figure missing (0/10)")

    if plot_size_kb >= 50:
        score += 10
        feedback.append(f"Figure is substantial: {plot_size_kb}KB (10/10)")
    elif plot_size_kb >= 20:
        score += 5
        feedback.append(f"Figure present but small: {plot_size_kb}KB (5/10)")
    else:
        feedback.append(f"Figure too small: {plot_size_kb}KB (0/10)")

    png_valid = False
    png_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    png_tmp.close()
    try:
        copy_from_env("/home/ga/RProjects/output/spy_garch_report.png", png_tmp.name)
        with open(png_tmp.name, 'rb') as f:
            header = f.read(8)
            if header[:8] == b'\x89PNG\r\n\x1a\n':
                png_valid = True
    except Exception:
        pass
    finally:
        try:
            os.unlink(png_tmp.name)
        except Exception:
            pass

    if png_valid:
        score += 5
        feedback.append("Valid PNG header confirmed (5/5)")
    else:
        feedback.append("PNG invalid or missing (0/5)")

    # ----------------------------------------------------------------
    # Subtask 4: R script quality (20 pts)
    # ----------------------------------------------------------------
    if result.get('script_is_new'):
        score += 5
        feedback.append("R script modified during task (5/5)")
    else:
        feedback.append("R script not modified during task (0/5)")

    if result.get('script_has_garch_fit'):
        score += 15
        feedback.append("GARCH specification/fit functions found in script (15/15)")
    elif result.get('script_has_rugarch'):
        score += 8
        feedback.append("rugarch/GARCH references found in script (8/15)")
    else:
        feedback.append("No rugarch/GARCH function calls in script (0/15)")

    # ----------------------------------------------------------------
    # VLM verification
    # ----------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    get_final = env_info.get('get_final_screenshot')
    final_frame = get_final(traj) if get_final else None

    if query_vlm and final_frame and score < 95:
        vlm_prompt = """You are reviewing a RStudio screenshot after a GARCH financial risk analysis task.
The agent was asked to fit a GARCH volatility model to S&P 500 data and compute VaR estimates.

Assess whether there is evidence of meaningful financial analysis:
- Is there R code with financial/statistical modeling functions (ugarchfit, GARCH, VaR, etc.)?
- Is there numerical output visible (model coefficients, statistics)?
- Is there a multi-panel financial chart visible?

Respond in JSON: {"financial_analysis_visible": true/false, "model_output_visible": true/false, "chart_visible": true/false}"""
        try:
            vlm_result = query_vlm(prompt=vlm_prompt, image=final_frame)
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('financial_analysis_visible') and parsed.get('chart_visible'):
                    bonus = min(10, 100 - score)
                    score += bonus
                    feedback.append(f"VLM: Financial analysis workflow confirmed (+{bonus} pts)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # ----------------------------------------------------------------
    # Score cap gates (Lesson 25): prevent partial deliverable set from passing
    # Without gate: VaR(35) + Figure(25) + Script(20) = 80 → passes without backtest
    # ----------------------------------------------------------------
    PASS_THRESHOLD = 60
    backtest_present = result.get('backtest_csv_exists') and result.get('backtest_csv_is_new')
    if not backtest_present and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback.append(f"Score capped at {PASS_THRESHOLD - 1}: spy_backtest.csv is a required deliverable")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "var_csv_created": result.get('var_csv_is_new', False),
            "var_ordering_correct": result.get('var99_more_negative_than_var95', False),
            "vol_in_range": result.get('conditional_vol_in_range', False),
            "backtest_created": result.get('backtest_csv_is_new', False),
            "plot_created": result.get('plot_is_new', False),
            "script_has_garch": result.get('script_has_garch_fit', False),
        }
    }
