#!/usr/bin/env python3
"""
Verifier for Financial Model Audit task.

Stub verifier — primary evaluation uses VLM checklist verifier externally.
Basic checks for output file existence and key corrected values.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_financial_model_audit(traj, env_info, task_info):
    """
    Verify financial model audit task completion.

    Checks that the agent has:
    1. Saved an output file
    2. Fixed key formula errors on the Income Statement
    3. Fixed the Balance Sheet cross-reference
    4. Fixed Cash Flow Statement issues
    5. Created an Audit_Findings sheet

    Full scoring is handled by the VLM checklist verifier.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/financial_model_audit_result.json')

    # Copy the result JSON from the container
    tmp_dir = tempfile.mkdtemp()
    local_result = os.path.join(tmp_dir, 'result.json')

    try:
        copy_from_env(result_file, local_result)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result: {e}"}

    try:
        with open(local_result, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}

    score = 0
    feedback_parts = []

    # Check 1: Output file exists (10 pts)
    output_exists = result.get('output_file_exists', False)
    if output_exists:
        score += 10
        feedback_parts.append("PASS: Output file exists (+10)")
    else:
        feedback_parts.append("FAIL: No output file found")

    parsed = result.get('parsed_data', {})
    sheets = parsed.get('sheets', {})

    # Check 2: Income Statement Net Income is correct (20 pts)
    # After fixing all errors, IS Net Income (row 30, col C) should be ~22,875
    is_sheet = sheets.get('Income Statement', [])
    if len(is_sheet) >= 30:
        try:
            ni_val = is_sheet[29][2]  # row 30 (0-indexed=29), col C (0-indexed=2)
            if ni_val is not None:
                ni_float = float(ni_val)
                if abs(ni_float - 22875) / 22875 <= 0.03:
                    score += 20
                    feedback_parts.append(f"PASS: IS Net Income correct: {ni_float:.0f} (+20)")
                else:
                    feedback_parts.append(f"FAIL: IS Net Income wrong: {ni_float:.0f} (expected ~22,875)")
            else:
                feedback_parts.append("FAIL: IS Net Income cell is empty")
        except (IndexError, TypeError, ValueError) as e:
            feedback_parts.append(f"FAIL: Could not read IS Net Income: {e}")
    else:
        feedback_parts.append("FAIL: Income Statement too short")

    # Check 3: Balance Sheet balances (15 pts)
    bs_sheet = sheets.get('Balance Sheet', [])
    if len(bs_sheet) >= 26:
        try:
            balance_check = bs_sheet[25][2]  # row 26 (0-indexed=25), col C (0-indexed=2)
            if balance_check is not None and str(balance_check).upper().strip() == "OK":
                score += 15
                feedback_parts.append("PASS: Balance Sheet balances (+15)")
            else:
                feedback_parts.append(f"FAIL: Balance Check shows: {balance_check}")
        except (IndexError, TypeError) as e:
            feedback_parts.append(f"FAIL: Could not read Balance Check: {e}")
    else:
        feedback_parts.append("FAIL: Balance Sheet too short")

    # Check 4: Cash Flow Ending Cash matches BS Cash (15 pts)
    cf_sheet = sheets.get('Cash Flow Statement', [])
    if len(cf_sheet) >= 23 and len(bs_sheet) >= 4:
        try:
            cf_ending = float(cf_sheet[22][1])  # row 23, col B
            bs_cash = float(bs_sheet[3][2])      # row 4, col C
            if abs(cf_ending - bs_cash) <= 1:
                score += 15
                feedback_parts.append(f"PASS: CF Ending Cash matches BS Cash: {cf_ending:.0f} (+15)")
            else:
                feedback_parts.append(f"FAIL: CF Ending Cash ({cf_ending:.0f}) != BS Cash ({bs_cash:.0f})")
        except (IndexError, TypeError, ValueError) as e:
            feedback_parts.append(f"FAIL: Could not compare CF/BS cash: {e}")
    else:
        feedback_parts.append("FAIL: Cash Flow or Balance Sheet too short")

    # Check 5: CF Debt Repayment is negative (10 pts)
    if len(cf_sheet) >= 16:
        try:
            debt_val = float(cf_sheet[15][1])  # row 16, col B
            if debt_val < 0:
                score += 10
                feedback_parts.append(f"PASS: Debt Repayment is negative: {debt_val:.0f} (+10)")
            else:
                feedback_parts.append(f"FAIL: Debt Repayment should be negative: {debt_val:.0f}")
        except (IndexError, TypeError, ValueError) as e:
            feedback_parts.append(f"FAIL: Could not read Debt Repayment: {e}")

    # Check 6: Audit_Findings sheet exists with content (20 pts)
    audit_sheet = sheets.get('Audit_Findings', sheets.get('Audit Findings', None))
    if audit_sheet is not None:
        non_empty_rows = sum(1 for row in audit_sheet if any(cell is not None for cell in row))
        if non_empty_rows >= 5:
            score += 20
            feedback_parts.append(f"PASS: Audit_Findings sheet has {non_empty_rows} rows (+20)")
        elif non_empty_rows >= 2:
            score += 10
            feedback_parts.append(f"PARTIAL: Audit_Findings sheet has only {non_empty_rows} rows (+10)")
        else:
            feedback_parts.append("FAIL: Audit_Findings sheet is nearly empty")
    else:
        feedback_parts.append("FAIL: No Audit_Findings sheet found")

    # Check 7: NI dollar impact documented (10 pts)
    # The correct impact is $3,475 (= 22,875 - 19,400)
    if audit_sheet is not None:
        found_impact = False
        for row in audit_sheet:
            for cell in row:
                if cell is not None:
                    try:
                        val = float(cell)
                        if abs(val - 3475) / 3475 <= 0.10:
                            found_impact = True
                            break
                    except (ValueError, TypeError):
                        pass
            if found_impact:
                break
        if found_impact:
            score += 10
            feedback_parts.append("PASS: NI dollar impact documented (~$3,475) (+10)")
        else:
            feedback_parts.append("FAIL: NI dollar impact not found on Audit_Findings sheet")

    passed = score >= metadata.get('pass_threshold', 55)
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "output_exists": output_exists,
            "sheets_found": list(sheets.keys()),
            "total_score": score,
        }
    }
