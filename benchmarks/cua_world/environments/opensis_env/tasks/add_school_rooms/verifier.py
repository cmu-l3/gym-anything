#!/usr/bin/env python3
"""
Verifier for add_school_rooms task.

Verifies:
1. Room SCI-201 created with capacity 30 (30 pts)
2. Room COMP-305 created with capacity 25 (30 pts)
3. Room count increased by at least 2 (Anti-gaming) (20 pts)
4. VLM Trajectory shows correct navigation (20 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_school_rooms(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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
    feedback = []
    
    # 2. Verify Room 1 (SCI-201, Cap 30) - 30 pts
    r1 = result.get('room1', {})
    if r1.get('exists'):
        try:
            cap = int(float(r1.get('capacity', 0)))
            if cap == 30:
                score += 30
                feedback.append("Room SCI-201 created correctly (30/30)")
            else:
                score += 15
                feedback.append(f"Room SCI-201 created but wrong capacity: {cap} vs 30 (15/30)")
        except:
            score += 15
            feedback.append("Room SCI-201 created but invalid capacity format (15/30)")
    else:
        feedback.append("Room SCI-201 NOT found (0/30)")

    # 3. Verify Room 2 (COMP-305, Cap 25) - 30 pts
    r2 = result.get('room2', {})
    if r2.get('exists'):
        try:
            cap = int(float(r2.get('capacity', 0)))
            if cap == 25:
                score += 30
                feedback.append("Room COMP-305 created correctly (30/30)")
            else:
                score += 15
                feedback.append(f"Room COMP-305 created but wrong capacity: {cap} vs 25 (15/30)")
        except:
            score += 15
            feedback.append("Room COMP-305 created but invalid capacity format (15/30)")
    else:
        feedback.append("Room COMP-305 NOT found (0/30)")

    # 4. Anti-Gaming: Count Check - 20 pts
    # Ensures agent actually added records, didn't just modify existing (though we cleaned up)
    counts = result.get('counts', {})
    initial = counts.get('initial', 0)
    final = counts.get('final', 0)
    diff = final - initial
    
    if diff >= 2:
        score += 20
        feedback.append(f"Room count increased by {diff} (>=2) (20/20)")
    elif diff >= 1:
        score += 10
        feedback.append(f"Room count increased by {diff} (only 1) (10/20)")
    else:
        feedback.append(f"Room count did not increase correctly (Diff: {diff}) (0/20)")

    # 5. VLM Trajectory Verification - 20 pts
    # Check if agent navigated to "School Setup" or "Rooms"
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    Analyze these screenshots of a user interacting with OpenSIS.
    The user should be navigating to 'School Setup' and then 'Rooms' to add new rooms.
    
    Look for:
    1. The OpenSIS side menu or top menu.
    2. Headers saying "School Setup" or "Rooms".
    3. A form for adding a room (fields like Title, Capacity).
    4. A list of rooms.
    
    Did the user access the Rooms management interface?
    Answer YES or NO, and explain briefly.
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    if vlm_result and vlm_result.get('success'):
        vlm_resp = vlm_result.get('parsed', {}).get('response', '').lower()
        if 'yes' in vlm_resp:
            score += 20
            feedback.append("VLM confirmed navigation to Rooms interface (20/20)")
        else:
            feedback.append("VLM did not confirm navigation to Rooms interface (0/20)")
    else:
        # Fallback if VLM fails: give points if database check passed perfectly (assume they must have used UI)
        if score >= 80:
            score += 20
            feedback.append("VLM skipped/failed, but DB check perfect -> Assumed valid UI use (20/20)")
        else:
            feedback.append("VLM verification failed (0/20)")

    # Final Result
    passed = score >= 60 and r1.get('exists') and r2.get('exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }