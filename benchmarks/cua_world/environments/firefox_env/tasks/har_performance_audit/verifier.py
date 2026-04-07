#!/usr/bin/env python3
"""
Verifier for har_performance_audit task.

Checks:
1. Valid HAR file exists and was created during the task.
2. HAR file contains > 50 entries (sufficient trace depth).
3. HAR file contains requests targeting the expected Wikipedia page.
4. HAR file headers confirm "Disable Cache" was active.
5. Text file exists and is populated.
6. The URL in the text file matches one of the top 3 slowest assets in the actual HAR.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_har_performance_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_har_path = metadata.get('expected_har_path', '/home/ga/Documents/jwst_network.har')
    expected_txt_path = metadata.get('expected_txt_path', '/home/ga/Documents/slowest_asset.txt')
    target_keyword = metadata.get('target_url_keyword', 'James_Webb_Space_Telescope')
    min_entries = metadata.get('min_entries', 50)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Copy metadata result
    # ---------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result metadata: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Validate file presence and timestamps
    if not result_data.get('har_exists', False):
        return {"passed": False, "score": 0, "feedback": "HAR file was not created"}
    if not result_data.get('txt_exists', False):
        feedback_parts.append("Text file was not created")
        
    if not result_data.get('har_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "HAR file pre-dates task execution (anti-gaming)"}

    # ---------------------------------------------------------
    # Parse HAR file
    # ---------------------------------------------------------
    temp_har = tempfile.NamedTemporaryFile(delete=False, suffix='.har')
    har_data = None
    try:
        copy_from_env(expected_har_path, temp_har.name)
        with open(temp_har.name, 'r', encoding='utf-8') as f:
            har_data = json.load(f)
        score += 20
        feedback_parts.append("HAR file exists and is valid JSON")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse HAR file: {e}"}
    finally:
        if os.path.exists(temp_har.name):
            os.unlink(temp_har.name)

    entries = har_data.get('log', {}).get('entries', [])
    
    # Check trace depth
    if len(entries) >= min_entries:
        score += 10
        feedback_parts.append(f"Trace depth sufficient ({len(entries)} entries)")
    else:
        feedback_parts.append(f"Trace depth insufficient ({len(entries)} entries, expected >={min_entries})")

    # Check correct page profiled
    targeted_correct_page = False
    for entry in entries:
        url = entry.get('request', {}).get('url', '')
        if target_keyword in url:
            targeted_correct_page = True
            break
            
    if targeted_correct_page:
        score += 20
        feedback_parts.append("Correct Wikipedia page profiled")
    else:
        feedback_parts.append("Did not find requests to the expected Wikipedia page")

    # Check "Disable Cache" headers
    cache_disabled = False
    for entry in entries[:20]: # Check first few entries for cache-control directives
        headers = entry.get('request', {}).get('headers', [])
        for header in headers:
            name = header.get('name', '').lower()
            val = header.get('value', '').lower()
            if (name == 'cache-control' and 'no-cache' in val) or (name == 'pragma' and 'no-cache' in val):
                cache_disabled = True
                break
        if cache_disabled:
            break

    if cache_disabled:
        score += 10
        feedback_parts.append("Cache disabled verified via request headers")
    else:
        feedback_parts.append("Could not verify cache was disabled (no-cache headers missing)")

    # ---------------------------------------------------------
    # Parse Slowest Asset Text File and Compare
    # ---------------------------------------------------------
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    reported_url = ""
    try:
        if result_data.get('txt_exists', False):
            copy_from_env(expected_txt_path, temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8') as f:
                reported_url = f.read().strip()
            if reported_url.startswith("http"):
                score += 10
                feedback_parts.append("Text file formatted correctly")
            else:
                feedback_parts.append("Text file does not contain a valid URL string")
    except Exception as e:
        feedback_parts.append(f"Failed to read text file: {e}")
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    # ---------------------------------------------------------
    # Compute ground truth from HAR and evaluate
    # ---------------------------------------------------------
    if entries and reported_url:
        # Extract all URLs and their total time
        assets = []
        for entry in entries:
            req_url = entry.get('request', {}).get('url', '')
            time_ms = entry.get('time', 0)
            if req_url and time_ms > 0:
                assets.append({"url": req_url, "time": time_ms})
                
        # Sort by time descending
        assets.sort(key=lambda x: x["time"], reverse=True)
        
        # Take top 3 as acceptable answers (accounting for minor DevTools timing variations/ties)
        top_urls = [a["url"] for a in assets[:3]]
        
        if reported_url in top_urls:
            score += 30
            feedback_parts.append(f"Accurate bottleneck found: {reported_url[:50]}...")
        else:
            feedback_parts.append("Reported URL does not match the slowest assets in the generated HAR")

    # Final Evaluation
    key_criteria_met = (
        result_data.get('har_exists', False) and 
        targeted_correct_page and 
        (reported_url in [a["url"] for a in assets[:3]] if 'assets' in locals() else False)
    )
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }