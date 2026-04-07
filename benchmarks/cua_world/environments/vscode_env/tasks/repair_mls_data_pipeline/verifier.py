#!/usr/bin/env python3
"""
Verifier for the repair_mls_data_pipeline task.

Evaluation Strategy:
1. Hidden test execution results (5 tests x 16 points = 80 points)
2. File modification check - ensures anti-gaming (5 points)
3. VLM Trajectory check - ensures visual workflow progression (15 points)

Pass threshold: 60/100
"""

import os
import json
import logging
import tempfile

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are auditing a computer agent's work in a VS Code environment.
The agent was asked to debug and fix Python code for a data engineering pipeline.

Look at these trajectory frames (screenshots taken during the task).
Determine if the agent actively engaged in coding:
1. Is VS Code open?
2. Are Python files visible in the editor (e.g., client.py, spatial.py, price_stats.py)?
3. Did the agent navigate through different files or type/edit code?
4. Is there evidence of running a terminal command like `pytest`?

Return a JSON with your assessment:
{
    "engaged_in_coding": true/false,
    "terminal_used": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def verify_mls_pipeline(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Check 1: File Modifications (5 points) ---
    modified_count = result.get("modified_files_count", 0)
    if modified_count > 0:
        score += 5
        feedback.append(f"[+] Anti-gaming: {modified_count} files were modified during the task (5/5).")
    else:
        feedback.append("[-] Anti-gaming: No files were modified. Agent did nothing (0/5).")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # --- Check 2: Hidden Test Results (80 points total, 16 each) ---
    hidden_tests = result.get("hidden_test_results", {})
    
    if hidden_tests.get("bug1_pagination"):
        score += 16
        feedback.append("[+] Pagination (api/client.py): Successfully followed @odata.nextLink (16/16).")
    else:
        err = hidden_tests.get("errors", {}).get("bug1", "")
        feedback.append(f"[-] Pagination (api/client.py): Failed hidden test. {err} (0/16).")
        
    if hidden_tests.get("bug2_timezone"):
        score += 16
        feedback.append("[+] Timezone (datetime_utils.py): Naive/Aware collision resolved (16/16).")
    else:
        err = hidden_tests.get("errors", {}).get("bug2", "")
        feedback.append(f"[-] Timezone (datetime_utils.py): Failed hidden test. {err} (0/16).")

    if hidden_tests.get("bug3_enum"):
        score += 16
        feedback.append("[+] Property Enum (property_mapper.py): Mapped Condo / Townhouse safely (16/16).")
    else:
        err = hidden_tests.get("errors", {}).get("bug3", "")
        feedback.append(f"[-] Property Enum (property_mapper.py): Failed hidden test. {err} (0/16).")

    if hidden_tests.get("bug4_spatial"):
        score += 16
        feedback.append("[+] Spatial WKT (spatial.py): Negative coordinates parsed correctly (16/16).")
    else:
        err = hidden_tests.get("errors", {}).get("bug4", "")
        feedback.append(f"[-] Spatial WKT (spatial.py): Failed hidden test. {err} (0/16).")

    if hidden_tests.get("bug5_zerodiv"):
        score += 16
        feedback.append("[+] Price Stats (price_stats.py): Zero division & missing keys handled (16/16).")
    else:
        err = hidden_tests.get("errors", {}).get("bug5", "")
        feedback.append(f"[-] Price Stats (price_stats.py): Failed hidden test. {err} (0/16).")

    # --- Check 3: VLM Trajectory (15 points) ---
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if frames:
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("engaged_in_coding", False):
                    vlm_score += 10
                    feedback.append("[+] VLM confirmed agent engaged with VS Code editor (10/10).")
                else:
                    feedback.append("[-] VLM determined agent did not engage with code editor (0/10).")
                    
                if parsed.get("terminal_used", False):
                    vlm_score += 5
                    feedback.append("[+] VLM confirmed terminal usage (5/5).")
                else:
                    feedback.append("[-] VLM did not observe terminal testing (0/5).")
            else:
                logger.warning("VLM query failed.")
                feedback.append("[-] VLM check failed to execute. Awarding default 0/15.")
    else:
        logger.warning("No VLM query function available.")
        feedback.append("[-] VLM not configured. Skipping visual check (0/15).")
        
    score += vlm_score

    # Determine Pass/Fail (Threshold = 60)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }