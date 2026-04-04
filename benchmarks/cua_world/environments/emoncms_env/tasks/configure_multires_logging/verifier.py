#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_multires_logging(traj, env_info, task_info):
    """
    Verifies that the agent configured the input processing chain correctly.
    
    Criteria:
    1. Input 'rack_power_main' has valid processes.
    2. Chain contains at least two 'Log to feed' actions.
    3. Feed 'rack_power_live' exists with interval 10s.
    4. Feed 'rack_power_archive' exists with interval 1800s.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
        
    metadata = task_info.get('metadata', {})
    expected_live_name = metadata.get('feed_live_name', 'rack_power_live')
    expected_live_int = metadata.get('feed_live_interval', 10)
    expected_arch_name = metadata.get('feed_archive_name', 'rack_power_archive')
    expected_arch_int = metadata.get('feed_archive_interval', 1800)

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 3. Analyze Data
    feeds_found = result.get('feeds_found', [])
    process_list = result.get('process_list_string', '')
    
    score = 0
    feedback = []
    
    # Check 1: Input Process Chain Exists (20 pts)
    # A valid process list for logging usually looks like "1:123,1:124"
    if process_list and len(process_list) > 2:
        score += 20
        feedback.append("Input processing chain configured.")
    else:
        feedback.append("Input processing chain is empty or invalid.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Check 2: Dual Logging Configured (20 pts)
    # Check if we found at least 2 feeds linked in the chain
    if len(feeds_found) >= 2:
        score += 20
        feedback.append(f"Found {len(feeds_found)} linked feeds.")
    else:
        feedback.append(f"Expected at least 2 linked feeds, found {len(feeds_found)}.")
        
    # Check 3: Live Feed Configuration (25 pts)
    live_feed = next((f for f in feeds_found if f['name'] == expected_live_name), None)
    if live_feed:
        if live_feed['interval'] == expected_live_int:
            score += 25
            feedback.append(f"Feed '{expected_live_name}' correctly set to {expected_live_int}s.")
        else:
            feedback.append(f"Feed '{expected_live_name}' found but interval is {live_feed['interval']}s (expected {expected_live_int}s).")
    else:
        feedback.append(f"Feed '{expected_live_name}' not found in processing chain.")

    # Check 4: Archive Feed Configuration (25 pts)
    arch_feed = next((f for f in feeds_found if f['name'] == expected_arch_name), None)
    if arch_feed:
        if arch_feed['interval'] == expected_arch_int:
            score += 25
            feedback.append(f"Feed '{expected_arch_name}' correctly set to {expected_arch_int}s.")
        else:
            feedback.append(f"Feed '{expected_arch_name}' found but interval is {arch_feed['interval']}s (expected {expected_arch_int}s).")
    else:
        feedback.append(f"Feed '{expected_arch_name}' not found in processing chain.")

    # Check 5: Feed Naming (10 pts)
    # Implicitly checked above by searching by name, but we give points for perfect matches
    if live_feed and arch_feed:
        score += 10
        feedback.append("Feed naming convention followed exactly.")

    # 4. Final Verdict
    # Threshold 85 means they need to get intervals correct
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }