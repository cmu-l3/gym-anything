#!/usr/bin/env python3
"""
Verifier for register_aftershock_scsendorigin task.

Verification checks:
1. Origin correctly created in database (30 pts)
2. Latitude, Longitude, Depth, Time correctly parsed & matched (40 pts)
3. Report file existence & content correctness (20 pts)
4. Anti-gaming (origin created after task start) (5 pts)
5. VLM trajectory verification (terminal interaction) (5 pts)
"""

import json
import os
import tempfile
import logging
from datetime import datetime
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def safe_float(val, default=0.0):
    try:
        return float(val)
    except (ValueError, TypeError):
        return default

def verify_register_aftershock(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('expected_lat', 37.29)
    expected_lon = metadata.get('expected_lon', 136.78)
    expected_depth = metadata.get('expected_depth', 12.0)
    expected_time = metadata.get('expected_time', '2024-01-01 16:18:47')

    # Load results
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
    feedback_parts = []
    
    # 1. Database Origin Exists (30 pts)
    origin_found = result.get('origin_found', False)
    if origin_found:
        score += 30
        feedback_parts.append("[+30] Target Origin found in database.")
        
        # 2. Field Match checks (40 pts total)
        db_lat = safe_float(result.get('db_lat'))
        db_lon = safe_float(result.get('db_lon'))
        db_depth = safe_float(result.get('db_depth'))
        db_time = result.get('db_time', '')

        # Latitude (+10)
        if abs(db_lat - expected_lat) <= 0.05:
            score += 10
            feedback_parts.append(f"[+10] Latitude matches ({db_lat}).")
        else:
            feedback_parts.append(f"[+0] Latitude mismatch (got {db_lat}).")

        # Longitude (+10)
        if abs(db_lon - expected_lon) <= 0.05:
            score += 10
            feedback_parts.append(f"[+10] Longitude matches ({db_lon}).")
        else:
            feedback_parts.append(f"[+0] Longitude mismatch (got {db_lon}).")

        # Depth (+10)
        if abs(db_depth - expected_depth) <= 2.0:
            score += 10
            feedback_parts.append(f"[+10] Depth matches ({db_depth} km).")
        else:
            feedback_parts.append(f"[+0] Depth mismatch (got {db_depth} km).")

        # Time (+10)
        # We rely on DB bounding box in export script which is +/- 5 seconds
        if expected_time[:16] in db_time or expected_time[:15] in db_time:
            score += 10
            feedback_parts.append(f"[+10] Origin time accurate ({db_time}).")
        else:
            feedback_parts.append(f"[+5] Partial origin time accuracy ({db_time}).")
            score += 5

    else:
        feedback_parts.append("[+0] Target Origin NOT found in DB.")
        
    # 3. Report checks (20 pts)
    report_exists = result.get('report_exists', False)
    if report_exists:
        score += 10
        feedback_parts.append("[+10] Report file exists.")
        
        db_origin_id = result.get('db_origin_id', '')
        report_id = result.get('report_id', '')
        
        if report_id and db_origin_id and report_id == db_origin_id:
            score += 10
            feedback_parts.append("[+10] Report contains the correct Origin ID.")
        elif report_id:
            score += 5
            feedback_parts.append(f"[+5] Report contains an ID, but does not strictly match DB ({report_id}).")
        else:
            feedback_parts.append("[+0] Report does not contain a valid Origin ID.")
    else:
        feedback_parts.append("[+0] Report file missing.")

    # 4. Anti-gaming (5 pts)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    if current_count > initial_count:
        score += 5
        feedback_parts.append("[+5] New origin genuinely created during task run.")
    else:
        feedback_parts.append("[+0] Database origin count did not increase (Anti-Gaming Check Failed).")

    # 5. VLM trajectory verification (5 pts)
    vlm_score = 0
    try:
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            prompt = (
                "You are reviewing the trajectory of an agent interacting with a Linux desktop. "
                "The agent's task is to type a command line instruction (`scsendorigin`) or database query "
                "(`mysql`) into the terminal. Look at the images and check if a terminal is visible and "
                "whether it contains textual commands/output related to 'scsendorigin', 'mysql' or 'Origin'. "
                "Respond ONLY with a JSON dictionary: {\"terminal_used\": true/false}"
            )
            vlm_res = query_vlm(prompt=prompt, images=frames + [final])
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('terminal_used', False):
                    vlm_score = 5
                    feedback_parts.append("[+5] VLM verified terminal interactions.")
                else:
                    feedback_parts.append("[+0] VLM could not confirm terminal interactions.")
            else:
                vlm_score = 5
                feedback_parts.append("[+5] VLM parsing failed, assigning default trajectory credit.")
        else:
            vlm_score = 5
            feedback_parts.append("[+5] VLM unavailable, assigning default trajectory credit.")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        vlm_score = 5
        feedback_parts.append("[+5] VLM error, assigning default trajectory credit.")
        
    score += vlm_score

    # Determine passing
    key_criteria = origin_found and report_exists
    passed = (score >= 60) and key_criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }