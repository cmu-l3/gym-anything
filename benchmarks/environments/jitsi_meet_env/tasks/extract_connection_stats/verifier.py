#!/usr/bin/env python3
"""
Verifier for extract_connection_stats task.

Criteria:
1. File exists and is non-empty (10 pts)
2. Valid JSON structure (15 pts)
3. Contains 'connectionStats' (15 pts)
4. Contains 'conferenceInfo' with correct room name (15 pts)
5. Contains 'myUserId' (10 pts)
6. Contains valid ISO 8601 timestamp (10 pts)
7. File created/modified during task execution (10 pts)
8. VLM: Meeting interface visible in trajectory (15 pts)
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utilities if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=1): return []
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_connection_stats(traj, env_info, task_info):
    """
    Verify the extraction of Jitsi connection statistics.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_room = metadata.get('target_room', 'QualityAuditRoom2024').lower()

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Task Result Metadata
    # ------------------------------------------------------------------
    task_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", task_result_file.name)
        with open(task_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(task_result_file.name):
            os.unlink(task_result_file.name)

    output_exists = task_result.get("output_exists", False)
    file_created_during_task = task_result.get("file_created_during_task", False)
    
    # 2. Verify File Existence (10 pts)
    # ------------------------------------------------------------------
    if output_exists:
        score += 10
        feedback_parts.append("Output file exists.")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file /home/ga/jitsi_connection_stats.json not found."
        }

    # 3. Retrieve and Validate File Content
    # ------------------------------------------------------------------
    content_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    stats_data = {}
    valid_json = False
    
    try:
        copy_from_env("/tmp/jitsi_stats_verification.json", content_file.name)
        with open(content_file.name, 'r') as f:
            stats_data = json.load(f)
            valid_json = True
            score += 15 # Valid JSON
            feedback_parts.append("File contains valid JSON.")
    except json.JSONDecodeError:
        feedback_parts.append("File is not valid JSON.")
    except Exception as e:
        feedback_parts.append(f"Could not read content file: {e}")
    finally:
        if os.path.exists(content_file.name):
            os.unlink(content_file.name)

    if not valid_json:
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 4. Content Structure Verification
    # ------------------------------------------------------------------
    
    # Check 'connectionStats' (15 pts)
    if 'connectionStats' in stats_data:
        score += 15
        feedback_parts.append("'connectionStats' key present.")
    else:
        feedback_parts.append("'connectionStats' key missing.")

    # Check 'conferenceInfo' and Room Name (15 pts)
    conf_info = stats_data.get('conferenceInfo', {})
    room_name = str(conf_info.get('roomName', '')).lower()
    
    if conf_info and isinstance(conf_info, dict):
        if target_room in room_name:
            score += 15
            feedback_parts.append(f"Correct room name found: {room_name}.")
        else:
            feedback_parts.append(f"Incorrect room name: found '{room_name}', expected '{target_room}'.")
    else:
        feedback_parts.append("'conferenceInfo' missing or invalid.")

    # Check 'myUserId' (10 pts)
    user_id = conf_info.get('myUserId')
    if user_id and str(user_id).strip():
        score += 10
        feedback_parts.append("User ID present.")
    else:
        feedback_parts.append("User ID missing.")

    # Check 'timestamp' (10 pts)
    timestamp_str = stats_data.get('timestamp')
    timestamp_valid = False
    if timestamp_str:
        try:
            # Flexible ISO format check
            timestamp_str = timestamp_str.replace('Z', '+00:00')
            datetime.fromisoformat(timestamp_str)
            timestamp_valid = True
            score += 10
            feedback_parts.append("Timestamp is valid.")
        except ValueError:
            feedback_parts.append("Timestamp format invalid.")
    else:
        feedback_parts.append("Timestamp missing.")

    # 5. Anti-Gaming Timestamp Check (10 pts)
    # ------------------------------------------------------------------
    if file_created_during_task:
        score += 10
        feedback_parts.append("File created during task execution.")
    else:
        feedback_parts.append("File timestamp predates task start (anti-gaming check failed).")

    # 6. VLM Verification (15 pts)
    # ------------------------------------------------------------------
    # Use trajectory frames to verify they actually entered the meeting
    frames = sample_trajectory_frames(traj, n=5)
    vlm_score = 0
    
    if frames:
        prompt = """
        You are verifying a Jitsi Meet task. Look at these screenshots.
        1. Is the Jitsi Meet interface visible?
        2. Is there an active video meeting (not just the start screen)?
        3. Is the browser developer console visible in any frame?
        
        Answer JSON: {"meeting_active": bool, "console_visible": bool}
        """
        
        result = query_vlm(images=frames, prompt=prompt)
        parsed = result.get('parsed', {})
        
        if parsed.get('meeting_active', False):
            vlm_score += 10
            feedback_parts.append("Visual evidence of active meeting.")
        
        if parsed.get('console_visible', False):
            vlm_score += 5
            feedback_parts.append("Visual evidence of developer console.")
    
    score += vlm_score

    # Final Evaluation
    # ------------------------------------------------------------------
    # Threshold: 60 points + required JSON structure
    passed = score >= 60 and valid_json and 'connectionStats' in stats_data
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }