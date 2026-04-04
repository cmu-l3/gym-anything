#!/usr/bin/env python3
"""
Verifier for Tag Strategic Accounts task.
Checks if specific customers were tagged correctly based on opportunity revenue.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tag_strategic_accounts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"System Error: {result['error']}"}

    partners = result.get("partners", {})
    task_start_time = result.get("task_start_time", 0)

    score = 0
    feedback_parts = []
    
    # 2. Verify Logistics Pro Inc (Target: TAGGED)
    p1 = partners.get("Logistics Pro Inc", {})
    if p1.get("has_tag"):
        # Check timestamp for anti-gaming
        w_date_str = p1.get("write_date", "")
        # Odoo write_date is UTC string "YYYY-MM-DD HH:MM:SS"
        try:
            w_date_ts = datetime.strptime(w_date_str.split(".")[0], "%Y-%m-%d %H:%M:%S").timestamp()
            if w_date_ts >= task_start_time:
                score += 40
                feedback_parts.append("✅ Logistics Pro Inc tagged correctly")
            else:
                score += 10 # Partial credit if state is correct but timestamp looks stale (unlikely given setup clears it)
                feedback_parts.append("⚠️ Logistics Pro Inc has tag but record wasn't modified during task")
        except:
            # Fallback if parsing fails
            score += 40
            feedback_parts.append("✅ Logistics Pro Inc tagged")
    else:
        feedback_parts.append("❌ Logistics Pro Inc NOT tagged (Expected: Tagged due to $150k opp)")

    # 3. Verify NorthWest Retail (Target: TAGGED)
    p2 = partners.get("NorthWest Retail", {})
    if p2.get("has_tag"):
        try:
            w_date_str = p2.get("write_date", "")
            w_date_ts = datetime.strptime(w_date_str.split(".")[0], "%Y-%m-%d %H:%M:%S").timestamp()
            if w_date_ts >= task_start_time:
                score += 40
                feedback_parts.append("✅ NorthWest Retail tagged correctly")
            else:
                score += 10
                feedback_parts.append("⚠️ NorthWest Retail has tag but record wasn't modified")
        except:
            score += 40
            feedback_parts.append("✅ NorthWest Retail tagged")
    else:
        feedback_parts.append("❌ NorthWest Retail NOT tagged (Expected: Tagged due to $95k opp)")

    # 4. Verify SmallTime LLC (Target: NOT TAGGED)
    p3 = partners.get("SmallTime LLC", {})
    if not p3.get("has_tag"):
        score += 20
        feedback_parts.append("✅ SmallTime LLC correctly ignored")
    else:
        feedback_parts.append("❌ SmallTime LLC was incorrectly tagged (Revenue < $90k)")

    # 5. Final Score Calculation
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }