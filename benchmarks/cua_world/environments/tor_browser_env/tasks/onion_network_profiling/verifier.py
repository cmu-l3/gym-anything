#!/usr/bin/env python3
"""
Verifier for onion_network_profiling task.
Validates the contents of exported HAR files from Tor Browser Developer Tools.
"""

import os
import json
import logging
import tempfile
from datetime import datetime
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_har_time(time_str: str) -> float:
    """Safely parse HAR ISO8601 timestamp string to Unix timestamp."""
    if not time_str:
        return 0.0
    # Python's fromisoformat is sometimes picky about 'Z' vs '+00:00'
    time_str = time_str.replace('Z', '+00:00')
    try:
        return datetime.fromisoformat(time_str).timestamp()
    except Exception as e:
        logger.error(f"Failed to parse time {time_str}: {e}")
        return 0.0

def verify_har_content(har_path: str, expected_domain: str, task_start_ts: float) -> dict:
    """
    Parses a HAR file and validates:
    1. Is valid JSON and matches HAR spec (log.entries).
    2. Contains a request to the expected domain.
    3. Traffic occurred AFTER the task start time.
    4. Primary requests were not served from cache (status 200, not 304 or _fromCache).
    """
    result = {
        "valid_json": False,
        "valid_har": False,
        "contains_domain": False,
        "after_task_start": False,
        "cache_disabled": False,
        "feedback": []
    }
    
    if not os.path.exists(har_path):
        result["feedback"].append(f"File not found: {os.path.basename(har_path)}")
        return result

    try:
        with open(har_path, 'r', encoding='utf-8') as f:
            har_data = json.load(f)
            result["valid_json"] = True
    except Exception as e:
        result["feedback"].append(f"Invalid JSON: {e}")
        return result

    log = har_data.get('log', {})
    entries = log.get('entries', [])
    if not entries:
        result["feedback"].append("HAR is empty or missing 'log.entries'")
        return result
        
    result["valid_har"] = True
    
    # Analyze entries
    matching_entries = []
    earliest_ts = float('inf')
    
    for entry in entries:
        req = entry.get('request', {})
        res = entry.get('response', {})
        url = req.get('url', '')
        
        # Check timestamp
        started_dt = entry.get('startedDateTime', '')
        ts = parse_har_time(started_dt)
        if ts > 0 and ts < earliest_ts:
            earliest_ts = ts
            
        if expected_domain in url:
            matching_entries.append((req, res, ts))
            result["contains_domain"] = True

    if not result["contains_domain"]:
        result["feedback"].append(f"No requests found for domain: {expected_domain}")
    else:
        result["feedback"].append(f"Requests found for {expected_domain}")

    # Check anti-gaming (Timestamps)
    if earliest_ts < float('inf') and earliest_ts > task_start_ts:
        result["after_task_start"] = True
        result["feedback"].append("Timestamps verify traffic occurred during task")
    else:
        result["feedback"].append("Traffic timestamp is BEFORE task start (Possible cheating/old file)")

    # Check Cache status (look at main request for the domain)
    cache_disabled_found = False
    if matching_entries:
        # Check first matching entry
        req, res, _ = matching_entries[0]
        status = res.get('status', 0)
        from_cache = res.get('_fromCache', '')
        # 200 OK without fromCache flag is good. 304 Not Modified means cache was used.
        if status == 200 and not from_cache:
            cache_disabled_found = True
        
    if cache_disabled_found:
        result["cache_disabled"] = True
        result["feedback"].append("Cache was correctly disabled (HTTP 200 responses)")
    elif matching_entries:
        result["feedback"].append("Cache might have been active (Found HTTP 304 or cached responses)")
        
    return result

def verify_onion_network_profiling(traj, env_info, task_info):
    """
    Scoring (100 points):
    - VLM DevTools opened check: 10 pts
    - Clearnet HAR file exists and valid: 15 pts
    - Clearnet HAR contains expected domain: 15 pts
    - Onion HAR file exists and valid: 20 pts [REQUIRED GATE]
    - Onion HAR contains expected domain: 20 pts
    - Timestamps after task start: 10 pts
    - Cache disabled (checked in Onion HAR): 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    clearnet_domain = metadata.get('clearnet_url', 'check.torproject.org')
    onion_domain = metadata.get('onion_url', 'duckduckgo')

    tmp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Fetch main result JSON
        result_json_path = os.path.join(tmp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

        task_start_ts = result_data.get('task_start_timestamp', 0)

        # 2. VLM Check for DevTools usage
        frames = sample_trajectory_frames(traj, n=5)
        vlm_prompt = "Look at these sequential screenshots of Tor Browser. Did the user open the Web Developer Tools (specifically the Network tab or Network Monitor)? Reply ONLY with 'YES' or 'NO'."
        try:
            vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
            if "YES" in vlm_response.upper():
                score += 10
                feedback_parts.append("VLM verified DevTools Network tab opened (10/10)")
            else:
                feedback_parts.append("VLM did not clearly see DevTools Network tab (0/10)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM check skipped/failed")

        # 3. Analyze Clearnet HAR
        clearnet_har_path = os.path.join(tmp_dir, "check_clearnet.har")
        try:
            copy_from_env("/tmp/check_clearnet.har", clearnet_har_path)
        except:
            pass # File might not exist
            
        cn_res = verify_har_content(clearnet_har_path, clearnet_domain, task_start_ts)
        
        if cn_res["valid_har"]:
            score += 15
            feedback_parts.append("Clearnet HAR valid (15/15)")
        else:
            feedback_parts.append("Clearnet HAR invalid/missing (0/15)")
            
        if cn_res["contains_domain"]:
            score += 15
            feedback_parts.append("Clearnet HAR contains target domain (15/15)")
        else:
            feedback_parts.append("Clearnet HAR missing target domain (0/15)")

        # 4. Analyze Onion HAR
        onion_har_path = os.path.join(tmp_dir, "ddg_onion.har")
        try:
            copy_from_env("/tmp/ddg_onion.har", onion_har_path)
        except:
            pass # File might not exist
            
        on_res = verify_har_content(onion_har_path, onion_domain, task_start_ts)
        
        if on_res["valid_har"]:
            score += 20
            feedback_parts.append("Onion HAR valid (20/20)")
        else:
            feedback_parts.append("Onion HAR invalid/missing (0/20)")
            
        if on_res["contains_domain"]:
            score += 20
            feedback_parts.append("Onion HAR contains target domain (20/20)")
        else:
            feedback_parts.append("Onion HAR missing target domain (0/20)")

        # Timestamps & Cache checks (Combining results from both if available)
        if cn_res["after_task_start"] or on_res["after_task_start"]:
            score += 10
            feedback_parts.append("HAR timestamps are valid (10/10)")
        else:
            feedback_parts.append("HAR timestamps invalid or missing (0/10)")

        if cn_res["cache_disabled"] or on_res["cache_disabled"]:
            score += 10
            feedback_parts.append("Cache successfully disabled (10/10)")
        else:
            feedback_parts.append("Cache not disabled or missing data (0/10)")

        # Final Evaluation
        # Gate: The onion HAR must exist and be valid
        passed = score >= 60 and on_res["valid_har"]

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        # Cleanup
        for f in os.listdir(tmp_dir):
            os.unlink(os.path.join(tmp_dir, f))
        os.rmdir(tmp_dir)