#!/usr/bin/env python3
"""
Verifier for visual_forensic_bookmarking task.

Task: Find a "CRITICAL ALERT" visual event (red screen) in a 60s video loop
      and create a bookmark named "Jam Event" at that specific time.

Verification Logic:
1. Load bookmarks from API export.
2. Find bookmark matching "Jam" or "Event".
3. Calculate the bookmark's timestamp modulo 60s.
4. Compare with the ground truth start time (randomized per setup).
5. Verify bookmark is on the correct camera.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_visual_forensic_bookmarking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ==========================================================================
    # 1. Load Result JSON
    # ==========================================================================
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

    # ==========================================================================
    # 2. Parse Data
    # ==========================================================================
    bookmarks = result.get('bookmarks', [])
    devices = result.get('devices', [])
    gt_start = int(result.get('ground_truth_start_sec', 0))
    gt_duration = int(result.get('ground_truth_duration_sec', 0))
    
    if not isinstance(bookmarks, list):
        bookmarks = []

    # Map device IDs to names
    device_map = {d.get('id'): d.get('name', 'Unknown') for d in devices}

    score = 0
    feedback_parts = []
    
    # ==========================================================================
    # 3. Verification Criteria
    # ==========================================================================
    
    # Find relevant bookmark
    # Prioritize bookmark with correct name, fallback to any bookmark created recently
    target_bookmark = None
    
    for b in bookmarks:
        name = b.get('name', '').lower()
        if 'jam' in name or 'event' in name:
            target_bookmark = b
            break
            
    # If no specific named bookmark, take the last one created (if any exist)
    if not target_bookmark and bookmarks:
        target_bookmark = bookmarks[-1]
        feedback_parts.append("Warning: Bookmark name does not match 'Jam Event'.")
    
    if not target_bookmark:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No bookmarks found. Agent failed to create any bookmark."
        }

    # Criterion A: Bookmark Exists (20 pts)
    score += 20
    feedback_parts.append("Bookmark created.")

    # Criterion B: Correct Name (10 pts)
    bm_name = target_bookmark.get('name', '')
    if 'jam' in bm_name.lower() or 'event' in bm_name.lower():
        score += 10
        feedback_parts.append(f"Correct title '{bm_name}'.")
    else:
        feedback_parts.append(f"Incorrect title '{bm_name}'.")

    # Criterion C: Correct Camera (20 pts)
    dev_id = target_bookmark.get('deviceId', '')
    cam_name = device_map.get(dev_id, "Unknown Camera")
    
    if "Conveyor" in cam_name:
        score += 20
        feedback_parts.append(f"Correct camera '{cam_name}'.")
    else:
        feedback_parts.append(f"Wrong camera '{cam_name}'.")

    # Criterion D: Visual Timing Accuracy (50 pts)
    # The video is a 60s loop. The bookmark startTimeMs is absolute epoch time.
    # We need to see where it falls in the loop.
    start_ms = float(target_bookmark.get('startTimeMs', 0))
    
    # Calculate position in the loop (0-59s)
    # We assume the video plays continuously. 
    # The simplest check is modulo 60 of the epoch seconds.
    # This works because testcamera loops the file seamlessly.
    start_sec_epoch = start_ms / 1000.0
    bookmark_loop_pos = start_sec_epoch % 60
    
    # Calculate error (handling circular wrap-around)
    diff = abs(bookmark_loop_pos - gt_start)
    if diff > 30: # Shortest path around circle
        diff = 60 - diff
        
    feedback_parts.append(f"Visual Event at {gt_start}s, Bookmark at {bookmark_loop_pos:.1f}s (Diff: {diff:.1f}s).")

    timing_pass = False
    if diff <= 5.0:  # 5 second tolerance
        score += 50
        timing_pass = True
        feedback_parts.append("Timing is ACCURATE.")
    elif diff <= 10.0: # Partial credit for being close
        score += 25
        feedback_parts.append("Timing is approximate (within 10s).")
    else:
        feedback_parts.append("Timing is INCORRECT (missed the event).")

    # ==========================================================================
    # 4. Final Result
    # ==========================================================================
    passed = (score >= 70) and timing_pass
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }