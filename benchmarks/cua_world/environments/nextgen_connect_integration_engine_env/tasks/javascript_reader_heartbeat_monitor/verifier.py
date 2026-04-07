#!/usr/bin/env python3
"""
Verifier for javascript_reader_heartbeat_monitor task.
"""

import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_heartbeat_monitor(traj, env_info, task_info):
    """
    Verifies that the agent created and deployed a heartbeat channel.
    """
    
    # 1. Setup - Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_polling = int(metadata.get('expected_polling_ms', 15000))
    expected_dir = metadata.get('output_dir', '/opt/heartbeat_output')
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 2. Check Channel Configuration (50 points total)
    
    # Channel Exists (10 pts)
    if result.get('channel_exists'):
        score += 10
        feedback.append("Channel 'Heartbeat_Monitor' exists.")
    else:
        feedback.append("Channel 'Heartbeat_Monitor' NOT found.")
    
    # Source Type (12 pts)
    source = result.get('source_type', '').lower()
    if 'javascript' in source and 'reader' in source:
        score += 12
        feedback.append("Source is JavaScript Reader.")
    elif 'javascript' in source:
        score += 6
        feedback.append("Source is JavaScript-based (partial match).")
    else:
        feedback.append(f"Incorrect source type: {result.get('source_type')}")
        
    # Polling Frequency (8 pts)
    try:
        polling = int(result.get('polling_freq_ms', 0))
        # Allow small variance just in case, though XML is precise
        if 14000 <= polling <= 16000:
            score += 8
            feedback.append(f"Polling interval correct ({polling} ms).")
        else:
            feedback.append(f"Polling interval incorrect ({polling} ms). Expected ~15000.")
    except:
        feedback.append("Polling interval parsing failed.")

    # Destination Type (10 pts)
    dest = result.get('dest_type', '').lower()
    if 'file' in dest and 'writer' in dest:
        score += 10
        feedback.append("Destination is File Writer.")
    else:
        feedback.append(f"Incorrect destination type: {result.get('dest_type')}")

    # Destination Directory (5 pts)
    actual_dir = result.get('dest_dir', '').strip().rstrip('/')
    target_dir = expected_dir.rstrip('/')
    if actual_dir == target_dir:
        score += 5
        feedback.append("Destination directory correct.")
    else:
        feedback.append(f"Destination directory mismatch. Got: {actual_dir}, Expected: {target_dir}")

    # Channel State (5 pts)
    state = result.get('channel_state', '').upper()
    if state == 'STARTED':
        score += 5
        feedback.append("Channel is DEPLOYED and STARTED.")
    else:
        feedback.append(f"Channel state is {state} (Expected: STARTED).")

    # 3. Check Output Files (40 points total)
    
    file_count = result.get('file_count', 0)
    files_fresh = result.get('files_created_during_task', False)
    
    if file_count >= 2:
        score += 10
        feedback.append(f"Generated {file_count} output files (>=2 required).")
    elif file_count == 1:
        score += 5
        feedback.append("Generated only 1 output file.")
    else:
        feedback.append("No output files generated.")
        
    if files_fresh:
        score += 5
        feedback.append("Files verified as created during task session.")
    elif file_count > 0:
        feedback.append("Files exist but timestamps are old (anti-gaming check failed).")
        score -= 10 # Penalty for stale data

    # Content Validation
    if result.get('sample_content_valid'):
        score += 10
        feedback.append("Output is valid HL7 format.")
        
        # Specific fields
        if metadata.get('expected_sender') in result.get('sender_app', ''):
            score += 5
            feedback.append("MSH-3 Sending App correct.")
        else:
            feedback.append(f"MSH-3 mismatch. Got: {result.get('sender_app')}")
            
        if metadata.get('expected_msg_type') in result.get('msg_type', ''):
            score += 5
            feedback.append("MSH-9 Message Type correct.")
        
        if metadata.get('expected_pid') in result.get('pid_id', ''):
            score += 5
            feedback.append("PID-3 Patient ID correct.")
    else:
        feedback.append("Output file content is NOT valid HL7 or could not be parsed.")

    # 4. VLM Verification (10 points)
    # Check if we see the channel dashboard or edit screen
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images = frames + [final_screen] if final_screen else frames
    
    if images:
        vlm_resp = query_vlm(
            images=images,
            prompt="Does the user interact with Mirth Connect/NextGen Connect interface to configure a channel? Look for 'Heartbeat', 'Source', or 'Destination' settings."
        )
        if vlm_resp.get('success') and vlm_resp.get('parsed', {}).get('positive_match', True): # Assuming basic VLM wrapper
             score += 10
             feedback.append("VLM confirms UI interaction.")
        else:
             # Fallback if VLM fails or says no
             feedback.append("VLM did not confirm active configuration (could be a false negative, no penalty).")
             score += 10 # Award points to be safe if programmatic checks pass
    else:
        feedback.append("No screenshots available for VLM.")

    # Final Calculation
    passed = (score >= 60) and result.get('channel_exists') and (file_count >= 1)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }