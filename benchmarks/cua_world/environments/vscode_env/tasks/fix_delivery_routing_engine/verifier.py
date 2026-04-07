#!/usr/bin/env python3
"""
Verifier for the fix_delivery_routing_engine task.

Uses AST/Regex analysis on the agent's Python code to detect the 5 required algorithmic fixes,
along with trajectory-based VLM validation to prevent gaming.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_routing_engine(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    code = result.get('engine_code', '')
    run_success = result.get('run_success') == 'true'
    
    if not code:
        return {"passed": False, "score": 0, "feedback": "routing_engine.py is missing or empty."}

    score = 0
    feedback_parts = []
    
    # 1. Float Precision Fix (20 pts)
    # Check if they multiplied the distance by 100 before casting to int
    if re.search(r'\*\s*100\)?', code) or re.search(r'\*\s*1000\)?', code):
        score += 20
        feedback_parts.append("[+] Distance float precision properly scaled")
    else:
        feedback_parts.append("[-] Distance still truncated (missing * 100)")

    # 2. Demand Index Fix (20 pts)
    # Check if they used IndexToNode in the demand callback
    demand_callback_match = re.search(r'def demand_callback.*?return', code, re.DOTALL)
    if demand_callback_match and 'IndexToNode' in demand_callback_match.group(0):
        score += 20
        feedback_parts.append("[+] Demand callback uses node index instead of routing index")
    else:
        feedback_parts.append("[-] Demand callback still uses raw routing index")

    # 3. Slack Time Fix (20 pts)
    # Check if AddDimension has a slack_max > 0
    # Original: routing.AddDimension(time_callback_index, 0, 1000, False, 'Time')
    slack_match = re.search(r'AddDimension\s*\(\s*[^,]+,\s*(1000|10000|[1-9]\d{2,})\s*,', code)
    slack_kwarg = re.search(r'slack_max\s*=\s*(1000|[1-9]\d{2,})', code)
    if slack_match or slack_kwarg:
        score += 20
        feedback_parts.append("[+] Time dimension slack increased to allow waiting")
    else:
        feedback_parts.append("[-] Time dimension still does not allow waiting (slack_max = 0)")

    # 4. Disjunction Penalty Fix (20 pts)
    # Original: penalty = 50. Expected: >= 100000
    penalty_match = re.search(r'penalty\s*=\s*([0-9_]+)', code)
    if penalty_match:
        penalty_val = int(penalty_match.group(1).replace('_', ''))
        if penalty_val >= 100000:
            score += 20
            feedback_parts.append("[+] Disjunction penalty properly increased")
        else:
            feedback_parts.append(f"[-] Disjunction penalty is still too low ({penalty_val})")
    else:
        # Check if they hardcoded the number in AddDisjunction
        if re.search(r'AddDisjunction\s*\([^,]+,\s*(100000|[1-9]\d{5,})\s*\)', code):
            score += 20
            feedback_parts.append("[+] Disjunction penalty properly increased inline")
        else:
            feedback_parts.append("[-] Disjunction penalty not fixed")

    # 5. Depot Return Constraint Fix (20 pts)
    # Must apply SetMax or SetRange to CumulVar(routing.End(v))
    depot_fix_match = re.search(r'routing\.End\s*\(\s*v\s*\)', code) and \
                      re.search(r'Set(?:Max|Range)', code)
    if depot_fix_match:
        score += 20
        feedback_parts.append("[+] Depot return time window constraint added")
    else:
        feedback_parts.append("[-] Vehicles are still not constrained to return before depot closes")

    # Syntax/Run Check
    if not run_success:
        feedback_parts.append("[!] Code failed to execute successfully (syntax or runtime error).")
        # Apply a small penalty if it doesn't run, but preserve credit for logical fixes
        score = max(0, score - 10)

    # VLM Trajectory Verification (Anti-Gaming)
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=3)
        vlm_prompt = "Did the user edit Python code within VS Code during this trajectory? Reply with exactly YES or NO."
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_resp and vlm_resp.get("parsed", "").strip().upper() != "YES":
            feedback_parts.append("[!] VLM could not confirm VS Code usage - possible gaming.")
            score = 0

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }