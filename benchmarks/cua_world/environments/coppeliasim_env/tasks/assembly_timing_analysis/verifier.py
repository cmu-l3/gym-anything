#!/usr/bin/env python3
"""
Verifier for assembly_timing_analysis task.

Scoring (100 points):
  - Criterion 1 (20 pts): cycle_timing.csv exists and was created after task start
  - Criterion 2 (25 pts): CSV has >= 10 cycle rows
  - Criterion 3 (25 pts): Timing data is valid — cycles with positive duration >= 8,
                          avg duration > 0 and <= 300 s (physically plausible)
  - Criterion 4 (30 pts): timing_report.json exists, is new, has required fields
                          with total_cycles >= 10 and avg_cycle_time_s in (0, 300]

Pass threshold: 70
Anti-gaming checks:
  - Do-nothing score: 0 (no files)
  - Empty CSV + JSON: max 50 pts (20+30) if JSON has correct fields but CSV empty → fails
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/assembly_timing_analysis_result.json"


def verify_assembly_timing_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # Criterion 1: CSV exists and is new (20 pts)
    if result.get("csv_exists") and result.get("csv_is_new"):
        score += 20
        feedback.append("Cycle timing CSV created after task start (+20)")
    elif result.get("csv_exists"):
        feedback.append("CSV exists but predates task start")
    else:
        feedback.append("cycle_timing.csv not found")

    # Criterion 2: >= 10 cycle rows (25 pts)
    row_count = int(result.get("csv_row_count", 0))
    if row_count >= 10:
        score += 25
        feedback.append(f"CSV has {row_count} cycle records (>= 10 required) (+25)")
    elif row_count >= 5:
        score += 10
        feedback.append(f"CSV has {row_count} cycles (partial: 10/25, need >= 10)")
    else:
        feedback.append(f"CSV has {row_count} cycle records (need >= 10)")

    # Criterion 3: Timing data is physically valid (25 pts)
    analysis = result.get("csv_analysis", {})
    if isinstance(analysis, dict):
        has_timing = analysis.get("has_timing", False)
        positive_cycles = int(analysis.get("cycles_with_positive_duration", 0))
        avg_dur = float(analysis.get("avg_duration", 0.0))
        max_dur = float(analysis.get("max_duration", 0.0))
        # Valid: positive cycles >= 8, avg in (0, 300]
        if has_timing and positive_cycles >= 8 and 0 < avg_dur <= 300:
            score += 25
            feedback.append(
                f"Timing valid: {positive_cycles} cycles with positive duration, "
                f"avg={avg_dur:.2f}s (+25)"
            )
        elif has_timing and positive_cycles >= 4:
            score += 10
            feedback.append(
                f"Partial timing: {positive_cycles} valid cycles, avg={avg_dur:.2f}s (partial: 10/25)"
            )
        elif not has_timing:
            feedback.append("CSV lacks cycle_duration_s column or timing data")
        else:
            feedback.append(
                f"Timing data invalid: {positive_cycles} valid cycles, avg={avg_dur:.2f}s"
            )
    else:
        feedback.append("Could not parse timing CSV analysis")

    # Criterion 4: JSON report with required fields and valid totals (30 pts)
    json_fields = result.get("json_fields", {})
    if isinstance(json_fields, dict):
        has_fields = json_fields.get("has_fields", False)
        total_cycles = int(json_fields.get("total_cycles", 0))
        avg_cycle = float(json_fields.get("avg_cycle_time_s", 0.0))
    else:
        has_fields = False
        total_cycles = 0
        avg_cycle = 0.0

    if (result.get("json_exists") and result.get("json_is_new")
            and has_fields and total_cycles >= 10 and 0 < avg_cycle <= 300):
        score += 30
        feedback.append(
            f"Timing report valid: {total_cycles} cycles, avg={avg_cycle:.2f}s (+30)"
        )
    elif result.get("json_exists") and result.get("json_is_new") and has_fields:
        score += 15
        feedback.append(
            f"Timing report exists with fields but total_cycles={total_cycles} "
            f"or avg={avg_cycle:.2f}s invalid (partial: 15/30)"
        )
    elif result.get("json_exists") and result.get("json_is_new"):
        score += 5
        feedback.append("Timing report JSON exists but missing required fields (partial: 5/30)")
    else:
        feedback.append("timing_report.json not found or not new")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }
