#!/usr/bin/env python3
"""
Verifier for Aggregate Power Inputs task.
Verifies that the Emoncms input processing chain is correctly configured
to sum two inputs and log the result.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aggregate_power_inputs(traj, env_info, task_info):
    """
    Verify the Emoncms input processing configuration.
    
    Expected Chain for 'annex_power' input:
    1. Log to feed 'annex_power_feed'
    2. + input 'main_power'
    3. Log to feed 'total_site_power'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    inputs = result.get('inputs', [])
    feeds = result.get('feeds', [])
    
    # Helper to find items
    def find_input(name):
        return next((i for i in inputs if i['name'] == name), None)
    
    def find_feed(name):
        return next((f for f in feeds if f['name'] == name), None)

    annex_input = find_input('annex_power')
    main_input = find_input('main_power')
    
    annex_feed = find_feed('annex_power_feed')
    total_feed = find_feed('total_site_power')
    main_feed = find_feed('main_power_feed')

    score = 0
    feedback_parts = []
    
    # Critical Check 1: Inputs exist
    if not annex_input or not main_input:
        return {"passed": False, "score": 0, "feedback": "Critical inputs missing from database"}

    # Critical Check 2: Feeds exist
    feeds_exist = True
    if not annex_feed:
        feedback_parts.append("Feed 'annex_power_feed' not created")
        feeds_exist = False
    else:
        score += 10
        
    if not total_feed:
        feedback_parts.append("Feed 'total_site_power' not created")
        feeds_exist = False
    else:
        score += 10

    # Parse Process List
    # Format: "ID:ARG,ID:ARG" e.g., "1:10,3:5,1:11"
    plist_str = annex_input.get('processList', '')
    processes = []
    if plist_str:
        steps = plist_str.split(',')
        for s in steps:
            if ':' in s:
                pid, arg = s.split(':')
                processes.append((int(pid), int(arg)))
    
    if not processes:
        feedback_parts.append("No processes configured on 'annex_power' input")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Step 1: Log to annex feed
    # ID 1 = Log to feed
    step1_ok = False
    if len(processes) >= 1:
        pid, arg = processes[0]
        if pid == 1:
            if annex_feed and arg == int(annex_feed['id']):
                score += 20
                step1_ok = True
                feedback_parts.append("Step 1 OK (Log Annex)")
            else:
                feedback_parts.append(f"Step 1 logs to wrong feed ID {arg}")
        else:
            feedback_parts.append(f"Step 1 is process type {pid}, expected Log to Feed (1)")
    
    # Step 2: Add Main Input
    # ID 3 = + input (typically)
    step2_ok = False
    if len(processes) >= 2:
        pid, arg = processes[1]
        # We check if arg matches Main Input ID. 
        # The process ID for "+ input" is usually 3, but let's be flexible if it's an arithmetic op.
        if arg == int(main_input['id']):
            score += 30
            step2_ok = True
            feedback_parts.append("Step 2 OK (+ Main Input)")
        else:
            feedback_parts.append(f"Step 2 argument {arg} does not match 'main_power' input ID")
    else:
        feedback_parts.append("Step 2 (+ Input) missing")
        
    # Step 3: Log to Total Feed
    step3_ok = False
    if len(processes) >= 3:
        pid, arg = processes[2]
        if pid == 1:
            if total_feed and arg == int(total_feed['id']):
                score += 20
                step3_ok = True
                feedback_parts.append("Step 3 OK (Log Total)")
            else:
                feedback_parts.append(f"Step 3 logs to wrong feed ID {arg}")
        else:
            feedback_parts.append(f"Step 3 is process type {pid}, expected Log to Feed (1)")
    else:
        feedback_parts.append("Step 3 (Log Total) missing")

    # Order Check
    if step1_ok and step2_ok and step3_ok:
        score += 10
        feedback_parts.append("Process order correct")

    # Anti-gaming: Main input untouched
    # Should be 1 step: 1:MAIN_FEED_ID
    main_plist = main_input.get('processList', '')
    expected_main = f"1:{main_feed['id']}" if main_feed else ""
    if main_plist == expected_main:
        score += 5  # Small bonus for cleanliness
    else:
        feedback_parts.append("Warning: 'main_power' input was modified (not requested)")

    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }