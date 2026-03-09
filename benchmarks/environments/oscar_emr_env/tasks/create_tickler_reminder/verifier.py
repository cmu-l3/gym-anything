#!/usr/bin/env python3
"""
Verifier for create_tickler_reminder task.

Checks:
1. Tickler record exists for patient (20 pts)
2. Message contains expected keywords (15 pts)
3. Priority is High (15 pts)
4. Service date is correct (15 pts)
5. Assigned to correct provider (10 pts)
6. Anti-gaming: Created during task (10 pts)
7. VLM: Visual confirmation of workflow (15 pts)
"""

import json
import os
import tempfile
import logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_tickler_reminder(traj, env_info, task_info):
    """
    Verify the tickler creation task using database export and VLM.
    """
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

    # 2. Setup Variables
    score = 0
    max_score = 100
    feedback = []
    
    tickler = result.get("tickler", {})
    task_start_ts = result.get("task_start_ts", 0)
    
    # Metadata targets
    meta = task_info.get("metadata", {})
    target_msg_keyword = meta.get("target_message_content", "HbA1c").lower()
    target_priority = meta.get("target_priority", "High").lower()
    target_assignee = meta.get("target_assignee", "oscardoc") # or 999998
    target_offset = meta.get("target_offset_days", 14)

    # ========================================================
    # Criterion 1: Tickler Exists (20 pts)
    # ========================================================
    if tickler.get("found"):
        score += 20
        feedback.append("Tickler record created")
    else:
        feedback.append("No tickler record found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # ========================================================
    # Criterion 2: Content (15 pts)
    # ========================================================
    msg = tickler.get("message", "").lower()
    if target_msg_keyword in msg:
        score += 15
        feedback.append(f"Message correct ('{target_msg_keyword}' found)")
    else:
        feedback.append(f"Message missing keyword '{target_msg_keyword}'")

    # ========================================================
    # Criterion 3: Priority (15 pts)
    # ========================================================
    prio = tickler.get("priority", "").lower()
    if prio == target_priority or prio == "h":
        score += 15
        feedback.append("Priority correct (High)")
    else:
        score += 5 # Partial credit if set but wrong
        feedback.append(f"Priority mismatch: expected {target_priority}, got {prio}")

    # ========================================================
    # Criterion 4: Service Date (15 pts)
    # ========================================================
    svc_date_str = tickler.get("service_date", "")
    try:
        svc_date = datetime.strptime(svc_date_str.split()[0], "%Y-%m-%d").date()
        today = datetime.now().date() # Note: Host time vs Container time might differ slightly, but logic holds relative to expectation
        # We calculate expectation based on 'today'
        # To be robust, we check if it is approximately 14 days from task_start_ts
        start_date = datetime.fromtimestamp(task_start_ts).date()
        expected_date = start_date + timedelta(days=target_offset)
        
        diff = abs((svc_date - expected_date).days)
        
        if diff <= 1:
            score += 15
            feedback.append("Service date correct")
        elif diff <= 3:
            score += 10
            feedback.append(f"Service date close ({diff} days off)")
        else:
            feedback.append(f"Service date incorrect (expected ~{expected_date}, got {svc_date})")
    except Exception as e:
        feedback.append(f"Could not parse date: {svc_date_str}")

    # ========================================================
    # Criterion 5: Assignee (10 pts)
    # ========================================================
    assigned = tickler.get("assigned_to", "").lower()
    # Provider 999998 is oscardoc
    if assigned == "999998" or target_assignee in assigned:
        score += 10
        feedback.append("Assigned to correct provider")
    else:
        feedback.append(f"Wrong assignee: {assigned}")

    # ========================================================
    # Criterion 6: Anti-Gaming (10 pts)
    # ========================================================
    update_ts = tickler.get("update_ts", 0)
    if update_ts >= task_start_ts:
        score += 10
        feedback.append("Created during task session")
    else:
        feedback.append("Tickler predates task start (stale data)")
        # Penalize score heavily if it looks like stale data was found
        score = max(0, score - 20)

    # ========================================================
    # Criterion 7: VLM Workflow Verification (15 pts)
    # ========================================================
    # We use VLM to verify the agent actually interacted with the UI
    # and didn't just hack the DB (unlikely but good practice)
    # or to confirm UI state if DB is ambiguous.
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Analyze these screenshots of a user using Oscar EMR.
        Goal: Create a Tickler (reminder) for a patient.
        
        Look for:
        1. A patient chart or search screen.
        2. A "Tickler" or "Add Tickler" popup/screen.
        3. Form fields being filled (Message, Date, Priority).
        
        Does the user appear to be performing these steps?
        Answer JSON: {"workflow_valid": true/false, "reason": "..."}
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res and vlm_res.get("parsed", {}).get("workflow_valid"):
            score += 15
            feedback.append("VLM verified workflow")
        else:
            # Fallback if VLM fails or is negative, check basic screenshots existence
            if len(frames) > 0:
                score += 5
                feedback.append("Screenshots exist (VLM inconclusive)")
    else:
        feedback.append("No trajectory frames available for VLM")

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }