#!/usr/bin/env python3
"""
Verifier for quarter_end_close task.

Reads the JSON exported by export_result.sh via copy_from_env.

Scoring (100 points, pass >= 65):
  15 pts  City Services payment reclassified to Professional Services
  12 pts  Bank charge payment recorded ($35 to Bank Charges)
  20 pts  Adjusting journal entry (depreciation $450 + insurance $600)
  15 pts  Alfreds Futterkiste credit limit set to $1,000
  10 pts  Lock Date set to 2025-03-31
  18 pts  P&L file with correct Net Profit figure
  10 pts  Anti-gaming (new transactions created during task)
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_quarter_end_close(traj, env_info, task_info):
    """Verify quarter-end close task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/quarter_end_close_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found - export_result.sh may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    if result.get("error"):
        return {"passed": False, "score": 0,
                "feedback": f"Export error: {result['error']}"}

    metadata = task_info.get("metadata", {})
    expected_net_profit = metadata.get("expected_net_profit", 5115.0)
    expected_lock_date = metadata.get("lock_date", "2025-03-31")

    score = 0
    criteria = {}

    # -------------------------------------------------------------------
    # Criterion 1: City Services payment reclassified (15 pts)
    # -------------------------------------------------------------------
    c1 = bool(result.get("city_payment_reclassified", False))
    if c1:
        score += 15
    criteria["payment_reclassified"] = {
        "passed": c1, "points": 15 if c1 else 0, "max_points": 15,
        "details": {
            "city_payment_found": result.get("city_payment_found"),
            "reclassified": result.get("city_payment_reclassified"),
        }
    }

    # -------------------------------------------------------------------
    # Criterion 2: Bank charge payment recorded (12 pts)
    # -------------------------------------------------------------------
    new_payments = result.get("new_payment_count", 0)
    c2 = bool(result.get("has_bank_charge_35", False)) and new_payments > 0
    if c2:
        score += 12
    criteria["bank_charge_recorded"] = {
        "passed": c2, "points": 12 if c2 else 0, "max_points": 12,
        "details": {
            "has_bank_charge_35": result.get("has_bank_charge_35"),
            "new_payment_count": new_payments,
        }
    }

    # -------------------------------------------------------------------
    # Criterion 3: Adjusting journal entry (20 pts: 10 depreciation + 10 insurance)
    # -------------------------------------------------------------------
    new_je = result.get("new_je_count", 0)
    dep_ok = bool(result.get("has_je_depreciation", False)) and new_je > 0
    ins_ok = bool(result.get("has_je_insurance", False)) and new_je > 0
    c3_pts = 0
    if dep_ok:
        c3_pts += 10
    if ins_ok:
        c3_pts += 10
    score += c3_pts
    criteria["adjusting_journal_entry"] = {
        "passed": dep_ok and ins_ok, "points": c3_pts, "max_points": 20,
        "details": {
            "depreciation_ok": dep_ok,
            "insurance_ok": ins_ok,
            "narration_match": result.get("je_narration_match"),
            "new_je_count": new_je,
        }
    }

    # -------------------------------------------------------------------
    # Criterion 4: Alfreds credit limit = $1,000 (15 pts)
    # -------------------------------------------------------------------
    alfreds_limit = result.get("alfreds_credit_limit")
    c4 = False
    if alfreds_limit is not None:
        try:
            c4 = abs(float(alfreds_limit) - 1000.0) < 1.0
        except (ValueError, TypeError):
            c4 = False
    if c4:
        score += 15
    criteria["credit_limit_set"] = {
        "passed": c4, "points": 15 if c4 else 0, "max_points": 15,
        "details": {"alfreds_credit_limit": alfreds_limit}
    }

    # -------------------------------------------------------------------
    # Criterion 5: Lock Date = 2025-03-31 (10 pts)
    # -------------------------------------------------------------------
    actual_lock = result.get("lock_date_value", "").strip()
    c5 = actual_lock == expected_lock_date
    if c5:
        score += 10
    criteria["lock_date_set"] = {
        "passed": c5, "points": 10 if c5 else 0, "max_points": 10,
        "details": {"actual": actual_lock, "expected": expected_lock_date}
    }

    # -------------------------------------------------------------------
    # Criterion 6: P&L file with correct Net Profit (18 pts)
    # -------------------------------------------------------------------
    pnl_content = result.get("pnl_file_content", "")
    pnl_exists = result.get("pnl_file_exists", False)
    pnl_during_task = result.get("pnl_file_created_during_task", False)
    c6_pts = 0
    pnl_value = None

    if pnl_exists and pnl_during_task:
        c6_pts += 4  # File exists and was created during task

        # Extract numeric value from file content
        numbers = re.findall(r'[\d,]+\.?\d*', pnl_content)
        for num_str in numbers:
            try:
                val = float(num_str.replace(',', ''))
                if val > 100:  # Plausible P&L figure
                    pnl_value = val
                    break
            except ValueError:
                continue

        if pnl_value is not None:
            if abs(pnl_value - expected_net_profit) <= 5.0:
                c6_pts += 14  # Exact match (within $5 tolerance)
            elif abs(pnl_value - expected_net_profit) <= 100.0:
                c6_pts += 7   # Close but not exact
    elif pnl_exists:
        c6_pts += 2  # File exists but timestamp check failed

    score += c6_pts
    criteria["pnl_file"] = {
        "passed": c6_pts >= 14, "points": c6_pts, "max_points": 18,
        "details": {
            "file_exists": pnl_exists,
            "created_during_task": pnl_during_task,
            "content_preview": pnl_content[:200] if pnl_content else "",
            "extracted_value": pnl_value,
            "expected_value": expected_net_profit,
        }
    }

    # -------------------------------------------------------------------
    # Criterion 7: Anti-gaming (10 pts)
    # -------------------------------------------------------------------
    c7 = new_payments > 0 and new_je > 0
    if c7:
        score += 10
    criteria["anti_gaming"] = {
        "passed": c7, "points": 10 if c7 else 0, "max_points": 10,
        "details": {
            "new_payments": new_payments,
            "new_journal_entries": new_je,
        }
    }

    # -------------------------------------------------------------------
    # Final result
    # -------------------------------------------------------------------
    passed = score >= 65
    feedback_parts = [f"Score: {score}/100"]
    for name, c in criteria.items():
        status = "PASS" if c["passed"] else "FAIL"
        feedback_parts.append(
            f"  [{status}] {name}: {c['points']}/{c['max_points']} pts"
        )

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "criteria": criteria,
    }
