#!/usr/bin/env python3
"""
Verifier for create_release_discussion task.

Verifies:
1. Discussion room exists with correct name (30 pts)
2. Linked to correct parent channel #release-updates (20 pts)
3. Contains correct initial message (15 pts)
4. Created after task start (10 pts)
5. VLM: Workflow progression (navigation -> menu -> modal) (25 pts)
"""

import json
import os
import tempfile
import logging
from datetime import datetime
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_release_discussion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: Discussion Exists (30 pts) ---
    discussion_found = result.get("discussion_found", False)
    if discussion_found:
        score += 30
        feedback_parts.append("Discussion room found")
    else:
        feedback_parts.append("Discussion room NOT found")
        # Fail early if basic object missing? No, check VLM still.
    
    # --- CRITERION 2: Parent Linkage (20 pts) ---
    actual_parent = result.get("actual_parent_id", "")
    expected_parent = result.get("expected_parent_id", "unknown")
    
    if discussion_found and actual_parent and actual_parent == expected_parent:
        score += 20
        feedback_parts.append("Correct parent channel linkage")
    elif discussion_found:
        feedback_parts.append(f"Incorrect parent channel (expected {expected_parent}, got {actual_parent})")

    # --- CRITERION 3: Content (15 pts) ---
    msg_text = result.get("initial_message_text", "") or ""
    expected_fragment = "discuss whether we should upgrade"
    
    if discussion_found and expected_fragment.lower() in msg_text.lower():
        score += 15
        feedback_parts.append("Initial message content verified")
    elif discussion_found:
        feedback_parts.append("Initial message content mismatch/missing")

    # --- CRITERION 4: Timestamp/Anti-Gaming (10 pts) ---
    task_start = result.get("task_start_time", 0)
    ts_str = result.get("discussion_ts", "")
    
    valid_time = False
    if discussion_found and ts_str and task_start > 0:
        try:
            # Timestamp usually ISO8601 from API
            # Simple check: if we can parse it and it's > task_start
            # Often comes as "2026-02-16T..."
            # Python 3.7+ fromisoformat handles most, but let's be robust
            import dateutil.parser
            dt = dateutil.parser.parse(ts_str)
            if dt.timestamp() > task_start:
                valid_time = True
        except:
            pass
            
    if valid_time:
        score += 10
        feedback_parts.append("Created during task session")
    elif discussion_found:
        feedback_parts.append("Creation time verification failed (possibly pre-existing)")

    # --- CRITERION 5: VLM Workflow Verification (25 pts) ---
    # We look for the sequence: Channel View -> Message Action Menu -> Create Discussion Modal
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    Analyze these screenshots of a user using Rocket.Chat.
    I am looking for evidence of a specific workflow: "Creating a Discussion from a Message".
    
    Look for these specific steps:
    1. Viewing a channel list or chat timeline.
    2. A message action menu (dropdown/popover) being open on a specific message.
    3. A modal dialog titled "Create Discussion" or "Start a Discussion".
    4. Text being entered into fields like "Discussion Name" or "Parent Channel".
    
    Did the user perform this workflow?
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {}) # VLM usually returns unstructured text unless forced, assuming wrapper handles it
        # For this template, we assume boolean/score extraction or simple heuristic on the text if parsed is unavailable
        # But gym_anything.vlm usually returns 'parsed' if JSON schema provided, or we parse text.
        # Let's rely on the text response containing confirmation keywords if structured parsing isn't guaranteed by the wrapper here.
        
        response_text = str(vlm_result.get("response", "")).lower()
        if "yes" in response_text and ("modal" in response_text or "discussion" in response_text):
            vlm_score = 25
            feedback_parts.append("VLM verified workflow")
        else:
             feedback_parts.append("VLM could not clearly verify workflow steps")
    else:
        feedback_parts.append("VLM analysis failed")
        
    score += vlm_score

    # Threshold
    passed = (score >= 60) and discussion_found

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }