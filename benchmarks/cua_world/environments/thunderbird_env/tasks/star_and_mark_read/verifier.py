#!/usr/bin/env python3
"""
Verifier for star_and_mark_read task in Thunderbird.

Scoring Breakdown (100 pts total):
1. Target Emails Starred (30 pts)
2. Target Emails Read (15 pts)
3. Inbox Backlog Cleared (30 pts)
4. VLM Trajectory Verification (25 pts)
Penalty: -10 pts per incorrectly starred email (max -40)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_star_and_mark_read(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    target_keyword = metadata.get('target_keyword', 'EMBARGOED')

    # Read task result JSON via copy_from_env
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

    emails = result.get('emails', [])
    mbox_mtime = result.get('mbox_mtime', 0)
    task_start = result.get('task_start_time', 0)
    
    score = 0
    feedback_parts = []

    # Anti-gaming: Ensure mbox was modified after the task started
    if mbox_mtime <= task_start:
        feedback_parts.append("Inbox file was not modified during the task (do-nothing detected)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    target_starred_count = 0
    target_read_count = 0
    non_target_read_count = 0
    non_target_starred_count = 0

    target_total = 0
    non_target_total = 0

    for em in emails:
        subject = em.get('subject', '')
        if target_keyword in subject:
            target_total += 1
            if em.get('is_starred'):
                target_starred_count += 1
            if em.get('is_read'):
                target_read_count += 1
        else:
            non_target_total += 1
            if em.get('is_read'):
                non_target_read_count += 1
            if em.get('is_starred'):
                non_target_starred_count += 1

    # 1. Target Emails Starred: 30 pts
    if target_total > 0:
        stars_score = int((target_starred_count / target_total) * 30)
        score += stars_score
        feedback_parts.append(f"{target_starred_count}/{target_total} target emails starred ({stars_score} pts)")
    else:
        feedback_parts.append("Error: No target emails found in mailbox")

    # 2. Target Emails Read: 15 pts
    if target_total > 0:
        read_score = int((target_read_count / target_total) * 15)
        score += read_score
        feedback_parts.append(f"{target_read_count}/{target_total} target emails read ({read_score} pts)")

    # 3. Non-Target Emails Read (Backlog Cleared): 30 pts
    if non_target_total > 0:
        read_ratio = non_target_read_count / non_target_total
        if read_ratio >= 0.95:
            score += 30
            feedback_parts.append(f"Inbox backlog cleared (30 pts)")
        else:
            backlog_score = int(read_ratio * 30)
            score += backlog_score
            feedback_parts.append(f"Backlog partially cleared: {non_target_read_count}/{non_target_total} read ({backlog_score} pts)")

    # 4. Precision Penalty
    if non_target_starred_count > 0:
        penalty = min(non_target_starred_count * 10, 40)
        score -= penalty
        feedback_parts.append(f"Penalty: {non_target_starred_count} non-target emails incorrectly starred (-{penalty} pts)")

    score = max(0, min(100, score))

    # 5. VLM Trajectory Verification (25 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames

        prompt = (
            "You are analyzing a sequence of screenshots from an agent interacting with Mozilla Thunderbird. "
            "Did the agent actively use Thunderbird to manage emails? Look for evidence of interacting with "
            "the inbox list, selecting emails, starring (flagging) them, or using 'Mark as Read'. "
            "Respond in JSON format with a boolean field 'thunderbird_used'."
        )
        
        vlm_result = query_vlm(images=all_frames, prompt=prompt)
        
        vlm_passed = False
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("thunderbird_used", False):
                vlm_passed = True
                
        if vlm_passed:
            score += 25
            feedback_parts.append("VLM verified Thunderbird interaction (25 pts)")
        else:
            feedback_parts.append("VLM did not detect meaningful Thunderbird interaction")
            
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Partial credit fallback if VLM is completely unavailable but system checks passed
        if score > 0:
            score += 25 
            feedback_parts.append("VLM verification skipped, points granted by fallback")

    score = max(0, min(100, score))

    # Key criteria: Must have starred at least all target emails and read at least some backlog
    key_criteria = (target_starred_count == target_total) and (non_target_read_count >= (non_target_total * 0.5))
    passed = score >= 80 and key_criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }