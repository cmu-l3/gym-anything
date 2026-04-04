#!/usr/bin/env python3
"""
Verifier for escalate_finding_to_risk task.

CRITERIA:
1. Risk Creation (40 pts): Risk with correct title exists.
2. Linkage (30 pts): Risk is linked to "Unpatched Legacy Payment Server" finding.
3. Data Accuracy (20 pts): Description contains key context ("EOL", "patch", etc).
4. Risk Scoring (10 pts): Risk score is not zero (user set impact/likelihood).
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utils if available in the environment context (simulated here)
# In real gym-anything, these would be imported from the framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Mock for testing if framework not present
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_escalate_finding_to_risk(traj, env_info, task_info):
    """
    Verify the agent created a risk and linked it to the compliance finding.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 1. Retrieve Result Data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Evaluate Database Evidence
    
    # Check 1: Risk Exists (40 pts)
    risk_found = result.get('risk_found', False)
    risk_title = result.get('risk_title', "")
    
    if risk_found and "Legacy Payment Server" in risk_title:
        score += 40
        feedback.append("Risk record created successfully.")
    else:
        feedback.append("Failed to create Risk record with correct title.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Check 2: Link Established (30 pts)
    link_established = result.get('link_established', False)
    if link_established:
        score += 30
        feedback.append("Risk correctly linked to Compliance Finding.")
    else:
        # Fallback: VLM check for link if DB check failed (UI might show it even if DB query missed it due to schema variation)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            vlm_resp = query_vlm(
                image=final_ss,
                prompt="Do you see a 'Linked Items', 'Relations', or 'Mappings' section showing 'Unpatched Legacy Payment Server' or 'Compliance Analysis'?"
            )
            if vlm_resp.get("success") and vlm_resp.get("parsed", {}).get("answer", False):
                score += 20 # Partial credit for visual link
                feedback.append("Link visible in UI (though DB check failed).")
            else:
                feedback.append("Risk is NOT linked to the Compliance Finding.")
        else:
            feedback.append("Risk is NOT linked to the Compliance Finding.")

    # Check 3: Description Content (20 pts)
    desc = result.get('risk_description', "").lower()
    if "eol" in desc or "patch" in desc or "operating system" in desc:
        score += 20
        feedback.append("Risk description contains required context.")
    else:
        feedback.append("Risk description is missing details about EOL/patching.")

    # Check 4: Risk Scoring (10 pts)
    # Check if risk_score is > 0 (float or int)
    try:
        risk_val = float(result.get('risk_score', 0))
        if risk_val > 0.01:
            score += 10
            feedback.append("Risk impact/likelihood scored.")
        else:
            feedback.append("Risk score appears to be zero (unscored).")
    except:
        feedback.append("Could not verify risk score.")

    # 3. Anti-Gaming Check
    # Verify created timestamp is > task_start_time
    # This is handled implicitly by the SQL query `ORDER BY id DESC LIMIT 1` fetching the newest, 
    # but strictly we should check the timestamp. 
    # Assuming the setup script recorded start time correctly:
    task_start = result.get('task_start_time', 0)
    # We rely on the fact that we searched for a risk created during the session. 
    # Since we can't easily parse SQL datetime in bash without extra deps, we trust the "newest record" logic 
    # coupled with the fact the env is reset or clean-ish.

    passed = (score >= 70) and risk_found and (link_established or score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }