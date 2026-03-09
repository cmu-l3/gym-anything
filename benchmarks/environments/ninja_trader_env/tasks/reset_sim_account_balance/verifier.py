#!/usr/bin/env python3
"""
Verifier for reset_sim_account_balance task.

Verification Strategy:
1. File-based: Check if 'current_accounts.csv' was created/modified during task.
2. Content-based: Parse CSV to ensure Sim101 has $50,000 balance.
3. VLM-based: Verify final screenshot shows 50,000 in the Accounts grid.

Scoring:
- CSV Created & Recent: 30 pts
- Sim101 Data Present: 20 pts
- Balance Correct in CSV: 30 pts
- VLM Visual Confirmation: 20 pts
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reset_sim_account_balance(traj, env_info, task_info):
    """
    Verify that the Sim101 account balance was reset to $50,000.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100
    
    # 1. Retrieve JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Path corresponds to what export_result.ps1 writes (converted to Linux path format by docker cp usually works, 
        # but here we use the exact path string the agent environment uses for copy_from_env)
        # Windows path in container: C:\temp\task_result.json
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate File-based Criteria
    csv_exists = result.get("csv_exists", False)
    created_during = result.get("file_created_during_task", False)
    sim_found = result.get("sim101_found", False)
    balance_match = result.get("balance_correct_in_csv", False)

    if csv_exists:
        if created_during:
            score += 30
            feedback_parts.append("Export file created successfully (+30)")
        else:
            score += 10
            feedback_parts.append("Export file exists but timestamp is old (+10)")
    else:
        feedback_parts.append("Export file 'current_accounts.csv' not found (0)")

    if sim_found:
        score += 20
        feedback_parts.append("Sim101 account found in export (+20)")
    elif csv_exists:
        feedback_parts.append("Sim101 account missing from export (0)")

    if balance_match:
        score += 30
        feedback_parts.append("CSV confirms balance is 50,000 (+30)")
    elif sim_found:
        feedback_parts.append(f"CSV shows incorrect balance: {result.get('detected_balance_info')} (0)")

    # 3. VLM Verification (Visual Check)
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = (
            "You are verifying a NinjaTrader task. Look at the screenshot.\n"
            "1. Is the 'Accounts' tab or grid visible?\n"
            "2. Can you see a row for 'Sim101'?\n"
            "3. Does the 'Cash' or 'Net Liquidation' column for Sim101 show '$50,000.00' or '50,000'?\n"
            "Respond in JSON: {\"accounts_visible\": bool, \"sim101_visible\": bool, \"balance_50k\": bool}"
        )
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("accounts_visible"):
                    vlm_score += 5
                if parsed.get("sim101_visible"):
                    vlm_score += 5
                if parsed.get("balance_50k"):
                    vlm_score += 10
                    feedback_parts.append("Visual verification passed: $50k visible (+20)")
                else:
                    feedback_parts.append("Visual verification: $50k NOT visible")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if CSV was perfect, give partial VLM points
            if balance_match: 
                vlm_score += 10
                feedback_parts.append("VLM failed, awarded partial points based on CSV")

    score += vlm_score

    # Final Pass/Fail Determination
    # Must have CSV with correct balance to pass
    passed = (balance_match and score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }