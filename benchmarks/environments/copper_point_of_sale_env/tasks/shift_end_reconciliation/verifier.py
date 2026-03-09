#!/usr/bin/env python3
"""
Verifier for shift_end_reconciliation task.

The agent must:
1. Import 6 shift items from shift_items.csv
2. Process 5 transactions (4 completed, 1 voided)
   - T1: Ocean Blue Shirt x2 + Classic Varsity Top x1, Cash ($160)
   - T2: Yellow Wool Jumper x1 with 15% discount, Cash ($68)
   - T3: Classic Leather Jacket x1, Credit Card ($80)
   - T4: Soft Winter Jacket x2 — VOID (cashier error)
   - T5: Floral White Top x1, Cash ($75)
3. Export Sales Report to C:\\Users\\Docker\\Desktop\\shift_report.csv

Scoring (100 points total):
  - Report file exists and is new (20 pts)
  - Report has multiple data rows >= 3 (15 pts)
  - Evidence of discount applied in report (15 pts)
  - Evidence of void/cancel in report (15 pts)
  - Total amount within expected range $350-$450 (20 pts)
  - Sufficient transaction count >= 3 (15 pts)

Pass threshold: >= 55 points AND report file exists and is new
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\shift_end_result.json"

EXPECTED_TOTAL_MIN = 350.0
EXPECTED_TOTAL_MAX = 450.0


def verify_shift_end_reconciliation(traj, env_info, task_info):
    """
    Verify shift end reconciliation task.

    Reads result JSON produced by export_result.ps1, which contains:
      - report_file_exists: bool
      - report_file_new: bool
      - row_count: int
      - transaction_count: int
      - has_discount_line: bool
      - has_void_line: bool
      - total_found: float or null
      - numeric_amounts: list of floats
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # ----------------------------------------------------------------
    # Load result JSON from container
    # ----------------------------------------------------------------
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        logger.info(f"Result loaded: {result}")
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file. Export may have failed: {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    # ----------------------------------------------------------------
    # Scoring
    # ----------------------------------------------------------------
    score = 0
    feedback_parts = []

    report_exists = result.get('report_file_exists', False)
    report_new = result.get('report_file_new', False)

    # Criterion 1: Report file exists and is new (20 pts)
    if report_exists and report_new:
        score += 20
        feedback_parts.append("shift_report.csv created and is current.")
    elif report_exists and not report_new:
        feedback_parts.append("shift_report.csv exists but predates task start (stale file).")
        return {"passed": False, "score": 0,
                "feedback": "shift_report.csv exists but was not created during this task."}
    else:
        feedback_parts.append("shift_report.csv not found on Desktop.")
        return {"passed": False, "score": 0,
                "feedback": "No report file found. Agent must generate and export Sales Report to C:\\Users\\Docker\\Desktop\\shift_report.csv."}

    # Criterion 2: Report has multiple data rows (15 pts)
    row_count = result.get('row_count', 0)
    transaction_count = result.get('transaction_count', 0)
    rows = max(row_count, transaction_count)
    if rows >= 3:
        score += 15
        feedback_parts.append(f"Report has {rows} data rows.")
    elif rows >= 1:
        score += 7
        feedback_parts.append(f"Report has only {rows} rows (expected >= 3).")
    else:
        feedback_parts.append("Report appears empty or unreadable.")

    # Criterion 3: Evidence of discount applied (15 pts)
    has_discount = result.get('has_discount_line', False)
    if has_discount:
        score += 15
        feedback_parts.append("Discount evidence found in report (15% loyalty discount applied).")
    else:
        feedback_parts.append("No discount evidence in report. T2 should have 15% discount applied.")

    # Criterion 4: Evidence of void/cancel (15 pts)
    has_void = result.get('has_void_line', False)
    if has_void:
        score += 15
        feedback_parts.append("Void/cancel evidence found in report (T4 voided correctly).")
    else:
        feedback_parts.append("No void evidence in report. T4 (Soft Winter Jacket x2) should be voided.")

    # Criterion 5: Total within expected range $350-$450 (20 pts)
    total_found = result.get('total_found')
    if total_found is not None:
        try:
            total_val = float(total_found)
            if EXPECTED_TOTAL_MIN <= total_val <= EXPECTED_TOTAL_MAX:
                score += 20
                feedback_parts.append(f"Total ${total_val:.2f} is within expected range (${EXPECTED_TOTAL_MIN:.0f}-${EXPECTED_TOTAL_MAX:.0f}).")
            elif EXPECTED_TOTAL_MIN * 0.85 <= total_val <= EXPECTED_TOTAL_MAX * 1.15:
                score += 10
                feedback_parts.append(f"Total ${total_val:.2f} is close to expected range but outside bounds.")
            else:
                feedback_parts.append(f"Total ${total_val:.2f} is outside expected range (${EXPECTED_TOTAL_MIN:.0f}-${EXPECTED_TOTAL_MAX:.0f}).")
        except (TypeError, ValueError):
            feedback_parts.append("Could not parse total amount from report.")
    else:
        feedback_parts.append("No total amount found in report.")

    # Criterion 6: Sufficient transaction count (15 pts)
    if rows >= 4:
        score += 15
        feedback_parts.append(f"Report has {rows} transactions (expected 4 completed + void = 5 processed).")
    elif rows >= 3:
        score += 8
        feedback_parts.append(f"Report has {rows} transactions (expected >= 4).")
    else:
        feedback_parts.append(f"Only {rows} transactions in report; expected at least 4 completed transactions.")

    score = min(score, 100)
    passed = score >= 55

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
