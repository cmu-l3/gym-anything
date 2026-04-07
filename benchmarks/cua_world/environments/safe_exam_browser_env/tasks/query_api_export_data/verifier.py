#!/usr/bin/env python3
"""
Verifier for query_api_export_data task.

Verification Strategy:
1. Verify `~/api_export/` directory exists (5 pts)
2. Verify each of the 3 JSON files exists and parses correctly (15 pts each)
3. Verify each JSON file contains actual array data corresponding to DB counts (10 pts each)
4. Anti-gaming: Ensure files were created during the task run, not before (10 pts)
5. VLM Trajectory: Look for terminal usage and/or DevTools network extraction (10 pts)

Pass Threshold: 60 points with at least 2 valid data files.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_query_api_export_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    valid_data_files = 0

    # 1. Directory exists
    if result.get("dir_exists"):
        score += 5
        feedback_parts.append("Export directory created")
    else:
        feedback_parts.append("Export directory missing")

    keys = ["institutions", "users", "configurations"]
    all_created_after_start = True

    # 2 & 3. File existence, validity, and content evaluation
    for key in keys:
        exists = result.get("files_exist", {}).get(key, False)
        valid_json = result.get("files_valid_json", {}).get(key, False)
        data_count = result.get("data_counts", {}).get(key, 0)
        db_count = result.get("db_counts", {}).get(key, 0)
        created_after = result.get("files_created_after_start", {}).get(key, False)
        
        if not created_after and exists:
            all_created_after_start = False

        if exists and valid_json:
            score += 15
            feedback_parts.append(f"{key}.json valid")
            
            # Check if it has realistic data corresponding to the DB
            # We accept any count > 0 as long as DB also has > 0, to account for pagination
            if data_count > 0 and db_count > 0:
                score += 10
                valid_data_files += 1
                feedback_parts.append(f"{key} data matches DB expectations")
            else:
                feedback_parts.append(f"{key} data count anomalous ({data_count} vs DB {db_count})")
        else:
            feedback_parts.append(f"{key}.json missing or invalid")

    # 4. Anti-gaming check
    if any(result.get("files_exist", {}).values()):
        if all_created_after_start:
            score += 10
            feedback_parts.append("Files created during task run (Timestamp OK)")
        else:
            feedback_parts.append("WARNING: Some files pre-date task start (Potential gaming)")

    # 5. VLM Verification (Terminal and curl usage / DevTools network extraction)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """You are verifying an agent's terminal and browser usage.
The agent was asked to query a REST API via curl OR use Firefox Developer Tools to extract an API token.
Look at these trajectory frames and determine:
1. Is there evidence of a terminal emulator being used?
2. Is there evidence of 'curl' commands being typed or executed?
3. If they used a browser fallback, did they open Developer Tools (Network tab)?

Respond strictly in JSON format:
{
    "terminal_used": true/false,
    "curl_used": true/false,
    "devtools_used": true/false
}"""
        vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
        parsed = vlm_resp.get("parsed", {})
        
        terminal = parsed.get("terminal_used", False)
        curl = parsed.get("curl_used", False)
        devtools = parsed.get("devtools_used", False)
        
        if (terminal and curl) or devtools:
            score += 10
            feedback_parts.append("VLM confirmed API tooling usage")
        else:
            feedback_parts.append("VLM did not detect terminal/curl or DevTools usage")
            
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Give benefit of the doubt if VLM fails but files are perfect
        if valid_data_files == 3:
            score += 10
            feedback_parts.append("VLM skipped; awarded points for perfect data")

    # Final criteria evaluation
    passed = score >= 60 and valid_data_files >= 2

    if not passed:
        feedback_parts.insert(0, f"FAILED: Missing core requirement. Valid data files: {valid_data_files}/3.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "valid_data_files": valid_data_files,
            "raw_result": result
        }
    }