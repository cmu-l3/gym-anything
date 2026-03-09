#!/usr/bin/env python3
"""
Verifier for Manage Drug Recall Action task.
Verifies that the agent identified the patient on Atenolol and created a high-priority tickler.
"""

import json
import os
import logging
import tempfile
import time
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_drug_recall_action(traj, env_info, task_info):
    """
    Verify the drug recall task.
    
    Scoring Criteria:
    1. Tickler Created (30 pts): A new tickler exists for Maria Santos.
    2. Content Accuracy (30 pts): Message contains "Recall" and "Stop".
    3. Priority High (20 pts): Tickler priority is High.
    4. Workflow Verification (20 pts): VLM confirms search tool usage or correct form.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_part1 = metadata.get('required_message_part1', 'recall').lower()
    required_part2 = metadata.get('required_message_part2', 'stop').lower()

    # 1. Load result JSON from container
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
    feedback = []
    
    # Extract data
    initial_count = int(result.get("initial_tickler_count", 0))
    current_count = int(result.get("current_tickler_count", 0))
    latest_tickler = result.get("latest_tickler")
    
    # ------------------------------------------------------------------
    # DATABASE CHECKS
    # ------------------------------------------------------------------
    
    # Criterion 1: Tickler Created (30 pts)
    # Check count increase and existence of latest tickler
    tickler_created = False
    if current_count > initial_count and latest_tickler:
        score += 30
        tickler_created = True
        feedback.append("New tickler record created for patient.")
    else:
        feedback.append("No new tickler record found.")
        
    # Criterion 2: Content Accuracy (30 pts)
    if tickler_created:
        message = latest_tickler.get("message", "").lower()
        if required_part1 in message and required_part2 in message:
            score += 30
            feedback.append(f"Message content correct ('{message}').")
        elif required_part1 in message:
            score += 15
            feedback.append("Message mentions 'recall' but missing 'stop'.")
        else:
            feedback.append(f"Message content incorrect (got '{message}').")
    
    # Criterion 3: Priority High (20 pts)
    if tickler_created:
        priority = str(latest_tickler.get("priority", "")).lower()
        # OSCAR priorities: 'High', '1', or sometimes just the string 'High'
        if "high" in priority or priority == "1":
            score += 20
            feedback.append("Priority correctly set to High.")
        else:
            feedback.append(f"Priority not High (got '{priority}').")

    # ------------------------------------------------------------------
    # VLM VERIFICATION (20 pts)
    # ------------------------------------------------------------------
    # Use VLM to verify they didn't just stumble there but followed workflow
    vlm_score = 0
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + [final_frame] if final_frame else frames
    
    if all_images:
        prompt = """
        You are verifying an agent performing a drug recall task in an EMR.
        The agent should:
        1. Search for a drug (Atenolol) or run a report.
        2. Open a patient chart.
        3. Fill out a "Tickler" (reminder) form with a high priority message.
        
        Look at these screenshots of the workflow.
        Do you see evidence of:
        - A search screen or drug report?
        - A "Tickler" or "Add Task" popup/form?
        - The words "Recall" or "Atenolol" typed?
        
        Respond with JSON: {"evidence_found": true/false, "confidence": 0-1, "reason": "..."}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=all_images)
            if vlm_res and vlm_res.get("parsed", {}).get("evidence_found"):
                vlm_score = 20
                feedback.append("VLM verified workflow evidence.")
            else:
                # Fallback: if they got the database part perfect, give partial workflow points
                if score >= 60:
                    vlm_score = 10
                    feedback.append("VLM inconclusive, partial credit based on result.")
                else:
                    feedback.append("VLM did not observe correct workflow.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            if score >= 60: vlm_score = 10 # Graceful degradation
            
    score += vlm_score
    
    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }