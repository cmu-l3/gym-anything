#!/usr/bin/env python3
"""
Verifier for holiday_shutdown_work_order_rescheduling.

Criteria:
1. Non-Criticals (WO-SHUT-002, 004, 005) -> Date should be 2026-04-13.
2. Criticals (WO-SHUT-001, 003) -> Date should be ORIGINAL. Note should contain approval text.
3. Completed Trap (WO-SHUT-006) -> Date should be ORIGINAL.
4. Outside Range Trap (WO-SHUT-007, 008) -> Date should be ORIGINAL.
"""

import json
import logging
import os
import tempfile
import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_holiday_shutdown_rescheduling(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}
    
    # Get result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Define Expectations
    RESUMPTION_DATE = "2026-04-13"
    APPROVAL_TEXT = "[SHUTDOWN ACCESS APPROVED]"
    
    # Expected original dates for criticals/traps
    ORIGINALS = {
        "WO-SHUT-001": "2026-04-07",
        "WO-SHUT-003": "2026-04-08",
        "WO-SHUT-006": "2026-04-08",
        "WO-SHUT-007": "2026-04-01",
        "WO-SHUT-008": "2026-04-15"
    }

    score = 0
    feedback = []
    
    # 1. Check Non-Criticals (Rescheduling) - 30 pts (10 each)
    non_criticals = ["WO-SHUT-002", "WO-SHUT-004", "WO-SHUT-005"]
    for code in non_criticals:
        rec = data.get(code)
        if not rec:
            feedback.append(f"{code}: Missing record.")
            continue
        
        date_val = str(rec.get("date", ""))
        if RESUMPTION_DATE in date_val:
            score += 10
            feedback.append(f"{code}: Correctly rescheduled.")
        else:
            feedback.append(f"{code}: Incorrect date '{date_val}' (Expected {RESUMPTION_DATE}).")

    # 2. Check Criticals (Preserve + Note) - 30 pts (15 each)
    criticals = ["WO-SHUT-001", "WO-SHUT-003"]
    for code in criticals:
        rec = data.get(code)
        if not rec: continue
        
        date_val = str(rec.get("date", ""))
        text_content = rec.get("all_text", "")
        
        # Check Date (should match original)
        date_ok = ORIGINALS[code] in date_val
        # Check Note
        note_ok = APPROVAL_TEXT in text_content
        
        if date_ok and note_ok:
            score += 15
            feedback.append(f"{code}: Date preserved and note added.")
        elif not date_ok:
            score -= 10 # Penalty for moving critical job
            feedback.append(f"{code}: WRONG ACTION - Critical job rescheduled! Safety risk.")
        elif not note_ok:
            score += 5 # Partial credit for keeping date
            feedback.append(f"{code}: Date preserved but approval note missing.")

    # 3. Check Traps - 40 pts (Completed: 20, Outside: 10 each)
    
    # Completed Trap
    rec6 = data.get("WO-SHUT-006")
    if rec6 and ORIGINALS["WO-SHUT-006"] in str(rec6.get("date", "")):
        score += 20
        feedback.append("WO-SHUT-006 (Completed): Correctly ignored.")
    else:
        feedback.append("WO-SHUT-006 (Completed): Was wrongly modified.")

    # Outside Range Traps
    for code in ["WO-SHUT-007", "WO-SHUT-008"]:
        rec = data.get(code)
        if rec and ORIGINALS[code] in str(rec.get("date", "")):
            score += 10
            feedback.append(f"{code} (Outside range): Correctly ignored.")
        else:
            feedback.append(f"{code} (Outside range): Was wrongly modified.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": max(0, score), # No negative scores
        "feedback": " | ".join(feedback)
    }