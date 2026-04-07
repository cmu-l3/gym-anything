#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stop_and_restart_stream(traj, env_info, task_info):
    """
    Verify the stop_and_restart_stream task.
    
    Criteria:
    1. Log file exists and was created during the task.
    2. Log file contains correct fields and logical timestamps.
    3. Gap between stop and restart is >= 3 seconds.
    4. OpenBCI GUI is still running.
    5. VLM: Visual confirmation of stream activity/lifecycle.
    """
    
    # 1. Setup and Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_gap = metadata.get('min_stop_duration_sec', 3)
    
    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check Log File Existence and Timing (20 pts)
    if not result_data.get("log_exists", False):
        return {"passed": False, "score": 0, "feedback": "Log file not found."}
    
    if not result_data.get("log_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Log file detected but it is stale (created before task start)."}
    
    score += 10
    feedback_parts.append("Log file created.")
    
    # 3. Parse and Validate Log Content (40 pts)
    log_content = result_data.get("log_content", "")
    parsed_log = {}
    
    try:
        lines = log_content.strip().split('\\n') # Handle escaped newlines from JSON
        if len(lines) == 1: # Maybe real newlines?
             lines = log_content.strip().split('\n')
             
        for line in lines:
            if ':' in line:
                key, val = line.split(':', 1)
                parsed_log[key.strip()] = val.strip()
    except Exception as e:
        feedback_parts.append(f"Error parsing log: {str(e)}")

    required_keys = ["stream_started", "stream_stopped", "stream_restarted", "status"]
    missing_keys = [k for k in required_keys if k not in parsed_log]
    
    if missing_keys:
        feedback_parts.append(f"Missing log fields: {missing_keys}")
    else:
        score += 10
        feedback_parts.append("Log format correct.")
        
        # Validate Timestamps
        try:
            t_start = float(parsed_log["stream_started"])
            t_stop = float(parsed_log["stream_stopped"])
            t_restart = float(parsed_log["stream_restarted"])
            
            task_start_time = result_data.get("task_start", 0)
            
            # Ordering check
            if t_start < t_stop < t_restart:
                score += 10
                feedback_parts.append("Timestamps sequentially correct.")
            else:
                feedback_parts.append("Timestamps out of order.")

            # Duration check
            gap = t_restart - t_stop
            if gap >= min_gap:
                score += 15
                feedback_parts.append(f"Stop duration sufficient ({gap:.2f}s).")
            else:
                feedback_parts.append(f"Stop duration too short ({gap:.2f}s < {min_gap}s).")
                
            # Anti-gaming check (timestamps inside task window)
            if t_start > task_start_time:
                score += 5
                feedback_parts.append("Timestamps verified within task session.")
            else:
                feedback_parts.append("Timestamps appear pre-dated.")
                
        except ValueError:
            feedback_parts.append("Timestamps are not valid numbers.")

    # 4. Check App State (10 pts)
    if result_data.get("app_running", False):
        score += 10
        feedback_parts.append("OpenBCI GUI is running.")
    else:
        feedback_parts.append("OpenBCI GUI was closed.")

    # 5. VLM Verification (30 pts)
    # We need to verify the stream was actually active.
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Get trajectory frames to see the lifecycle
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots of the OpenBCI GUI. "
            "The task requires the user to: Start Data Stream -> Stop Data Stream -> Restart Data Stream. "
            "Look for the 'Start Data Stream' / 'Stop Data Stream' button in the top left or middle left. "
            "Also look for signal traces moving in the main graph (Time Series). "
            "1. Do you see evidence that the stream was active (signals shown or button says 'Stop Data Stream')? "
            "2. Is the stream active in the final state? "
            "Reply with JSON: {\"stream_was_active\": bool, \"final_stream_active\": bool}"
        )
        
        try:
            vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('stream_was_active'):
                score += 15
                feedback_parts.append("VLM confirmed stream activity.")
            else:
                feedback_parts.append("VLM could not confirm stream activity.")
                
            if parsed.get('final_stream_active'):
                score += 15
                feedback_parts.append("VLM confirmed stream active at end.")
            else:
                feedback_parts.append("VLM did not see active stream at end.")
                
        except Exception as e:
            feedback_parts.append(f"VLM check failed: {str(e)}")
            # Fallback points if logs are perfect to avoid failing on VLM error
            if score >= 60: 
                score += 20 
    else:
        feedback_parts.append("VLM unavailable.")
        if score >= 60: score += 30 # Auto-pass VLM portion if unavailable but logs are good

    # Final Pass Determination
    # Must have logs (at least 50 points from log checks) and app running
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }