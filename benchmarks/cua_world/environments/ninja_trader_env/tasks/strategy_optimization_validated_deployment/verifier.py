#!/usr/bin/env python3
"""Verifier for strategy_optimization_validated_deployment task.

This is a stub verifier. Primary verification is done externally via
VLM checklist evaluators which inspect agent trajectory screenshots.

The programmatic checks below provide basic sanity validation of
file artifacts when available.

Scoring (100 points):
- Subtask 1 (20 pts): qualification_report.txt exists with valid format
- Subtask 2 (20 pts): qualified_trades.csv exists with trade data
- Subtask 3 (15 pts): Workspace saved as StrategyQualification
- Subtask 4 (15 pts): Strategy Analyzer configured with SampleMACrossOver on SPY
- Subtask 5 (15 pts): Chart has two SMA indicators
- Subtask 6 (15 pts): Cross-reference: SMA periods on chart match report values

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/strategy_optimization_validated_deployment_result.json"


def verify_strategy_optimization_validated_deployment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    fast_range = metadata.get('fast_range', {})
    slow_range = metadata.get('slow_range', {})

    # Load result JSON from VM
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env(RESULT_PATH, temp_path)
            with open(temp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}

    score = 0
    feedback_parts = []

    # ---- Subtask 1 (20 pts): qualification_report.txt ----
    try:
        if result.get('report_exists') or result.get('alt_report_found'):
            if result.get('report_format_valid'):
                # Validate Fast/Slow are within optimization ranges
                fast_val = int(result.get('report_fast_value', 0))
                slow_val = int(result.get('report_slow_value', 0))
                fast_min = fast_range.get('min', 5)
                fast_max = fast_range.get('max', 25)
                slow_min = slow_range.get('min', 30)
                slow_max = slow_range.get('max', 60)

                if fast_min <= fast_val <= fast_max and slow_min <= slow_val <= slow_max:
                    score += 20
                    feedback_parts.append(
                        f"Report valid: Fast={fast_val}, Slow={slow_val} in range (+20)")
                else:
                    score += 10
                    feedback_parts.append(
                        f"Report exists but Fast={fast_val}/Slow={slow_val} outside optimization range (+10)")
            else:
                score += 8
                feedback_parts.append("Report file exists but format incomplete (+8)")
        else:
            feedback_parts.append("qualification_report.txt not found (0)")
    except Exception as e:
        feedback_parts.append(f"Report check error: {e}")

    # ---- Subtask 2 (20 pts): qualified_trades.csv ----
    try:
        if result.get('csv_exists') or result.get('alt_csv_found'):
            csv_lines = result.get('csv_line_count', 0)
            csv_size = result.get('csv_file_size', 0)

            if csv_lines >= 3 and csv_size >= 100:
                score += 15
                feedback_parts.append(
                    f"CSV valid: {csv_lines} lines, {csv_size} bytes (+15)")

                # Bonus for SPY data and trade entries
                if result.get('csv_has_spy') or result.get('csv_has_date_range'):
                    score += 5
                    feedback_parts.append("CSV contains SPY/date data (+5)")
            elif csv_lines >= 1 and csv_size > 0:
                score += 8
                feedback_parts.append(f"CSV exists but small: {csv_lines} lines (+8)")
            else:
                score += 3
                feedback_parts.append("CSV file exists but empty (+3)")
        else:
            feedback_parts.append("qualified_trades.csv not found (0)")
    except Exception as e:
        feedback_parts.append(f"CSV check error: {e}")

    # ---- Subtask 3 (15 pts): Workspace saved ----
    try:
        if result.get('workspace_exists'):
            score += 15
            feedback_parts.append("Workspace 'StrategyQualification' saved (+15)")
        else:
            feedback_parts.append("Workspace not found (0)")
    except Exception as e:
        feedback_parts.append(f"Workspace check error: {e}")

    # ---- Subtask 4 (15 pts): Strategy Analyzer config ----
    try:
        sa_score = 0
        if result.get('ws_has_strategy_analyzer'):
            sa_score += 5
        if result.get('ws_has_sample_ma_cross'):
            sa_score += 5
        if result.get('ws_has_spy'):
            sa_score += 5
        score += sa_score
        if sa_score > 0:
            feedback_parts.append(
                f"Strategy Analyzer config: SA={'Y' if result.get('ws_has_strategy_analyzer') else 'N'}, "
                f"MAC={'Y' if result.get('ws_has_sample_ma_cross') else 'N'}, "
                f"SPY={'Y' if result.get('ws_has_spy') else 'N'} (+{sa_score})")
        else:
            feedback_parts.append("No Strategy Analyzer config detected (0)")
    except Exception as e:
        feedback_parts.append(f"SA config check error: {e}")

    # ---- Subtask 5 (15 pts): Chart has two SMA indicators ----
    try:
        sma_periods_str = result.get('ws_sma_periods', '')
        sma_periods = [p.strip() for p in sma_periods_str.split(',') if p.strip()] if sma_periods_str else []

        if len(sma_periods) >= 2:
            score += 15
            feedback_parts.append(f"Chart has SMA periods: {sma_periods} (+15)")
        elif len(sma_periods) == 1:
            score += 7
            feedback_parts.append(f"Chart has 1 SMA period: {sma_periods} (+7)")
        else:
            feedback_parts.append("No SMA indicators on chart (0)")
    except Exception as e:
        feedback_parts.append(f"SMA check error: {e}")

    # ---- Subtask 6 (15 pts): Cross-reference SMA periods match report ----
    try:
        report_fast = result.get('report_fast_value', '')
        report_slow = result.get('report_slow_value', '')

        if report_fast and report_slow and sma_periods:
            if report_fast in sma_periods and report_slow in sma_periods:
                score += 15
                feedback_parts.append(
                    f"Cross-ref match: report Fast={report_fast}/Slow={report_slow} "
                    f"found in chart SMAs {sma_periods} (+15)")
            elif report_fast in sma_periods or report_slow in sma_periods:
                score += 7
                feedback_parts.append(
                    f"Partial cross-ref: one of Fast={report_fast}/Slow={report_slow} "
                    f"matches chart SMAs {sma_periods} (+7)")
            else:
                feedback_parts.append(
                    f"Cross-ref mismatch: report Fast={report_fast}/Slow={report_slow} "
                    f"vs chart SMAs {sma_periods} (0)")
        else:
            feedback_parts.append("Cross-ref skipped: missing report values or SMA data (0)")
    except Exception as e:
        feedback_parts.append(f"Cross-ref check error: {e}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
