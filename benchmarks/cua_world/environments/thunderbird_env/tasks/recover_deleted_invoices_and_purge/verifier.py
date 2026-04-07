#!/usr/bin/env python3
"""
Verifier for Recover Deleted Invoices and Purge task.

Verification Strategy:
1. Parse exported Inbox and Trash mbox files.
2. Check if the 3 target emails are in the Inbox (30 points).
3. Check if the 3 target emails are marked Unread (15 points).
4. Check if the Trash is completely empty (15 points).
5. Check if the Inbox does NOT contain decoy emails (anti-gaming, 25 points).
6. Evaluate trajectory frames via VLM to confirm the agent actually interacted with Thunderbird (15 points).
"""

import os
import sys
import json
import mailbox
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_unread(msg):
    """
    Check if a Thunderbird mbox message is unread.
    X-Mozilla-Status hex value ending in even digit (Bit 0 = 0) is Unread.
    """
    status = msg.get('X-Mozilla-Status', '0000')
    try:
        status_int = int(status, 16)
        # 1 (0x0001) is the MSG_FLAG_READ flag
        return (status_int & 1) == 0
    except ValueError:
        return True  # If missing or malformed, default to unread

def verify_recovery_and_purge(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_subjects = metadata.get('target_subjects', [])
    decoy_subjects = metadata.get('decoy_subjects', [])

    score = 0
    feedback_parts = []
    
    # Create temporary paths for the files
    tmp_inbox = tempfile.NamedTemporaryFile(delete=False)
    tmp_trash = tempfile.NamedTemporaryFile(delete=False)
    tmp_result = tempfile.NamedTemporaryFile(delete=False)
    
    try:
        # Copy files from environment
        copy_from_env("/tmp/verify_files/Inbox", tmp_inbox.name)
        copy_from_env("/tmp/verify_files/Trash", tmp_trash.name)
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        
        with open(tmp_result.name, 'r') as f:
            result_json = json.load(f)
            
        inbox_mbox = mailbox.mbox(tmp_inbox.name)
        trash_mbox = mailbox.mbox(tmp_trash.name)
        
        inbox_subjects = [msg.get('Subject', '') for msg in inbox_mbox]
        trash_subjects = [msg.get('Subject', '') for msg in trash_mbox]
        
        # -------------------------------------------------------------
        # CRITERION 1: Target Invoices Recovered (30 points, 10 each)
        # -------------------------------------------------------------
        targets_found = 0
        inbox_target_msgs = []
        for target in target_subjects:
            found_msg = None
            for msg in inbox_mbox:
                if msg.get('Subject', '') == target:
                    found_msg = msg
                    break
            
            if found_msg:
                targets_found += 1
                inbox_target_msgs.append(found_msg)
                
        if targets_found == len(target_subjects):
            score += 30
            feedback_parts.append(f"All {len(target_subjects)} target invoices recovered")
        else:
            score += targets_found * 10
            feedback_parts.append(f"Recovered {targets_found}/{len(target_subjects)} target invoices")

        # -------------------------------------------------------------
        # CRITERION 2: Target Invoices Marked Unread (15 points)
        # -------------------------------------------------------------
        unread_targets = 0
        for msg in inbox_target_msgs:
            if is_unread(msg):
                unread_targets += 1
                
        if len(target_subjects) > 0 and unread_targets == len(target_subjects):
            score += 15
            feedback_parts.append("All recovered invoices marked as Unread")
        elif unread_targets > 0:
            score += (15 // len(target_subjects)) * unread_targets
            feedback_parts.append(f"{unread_targets} recovered invoices marked Unread")
        else:
            feedback_parts.append("No recovered invoices were marked Unread")

        # -------------------------------------------------------------
        # CRITERION 3: Trash is Empty (15 points)
        # -------------------------------------------------------------
        trash_count = len(trash_mbox)
        if trash_count == 0:
            score += 15
            feedback_parts.append("Trash successfully emptied")
        else:
            feedback_parts.append(f"Trash is not empty (contains {trash_count} emails)")

        # -------------------------------------------------------------
        # CRITERION 4: Selective Move / Anti-Gaming (25 points)
        # -------------------------------------------------------------
        decoys_in_inbox = 0
        for decoy in decoy_subjects:
            if decoy in inbox_subjects:
                decoys_in_inbox += 1
                
        if decoys_in_inbox == 0:
            score += 25
            feedback_parts.append("Selective recovery successful (no decoys in Inbox)")
        else:
            feedback_parts.append(f"Failed selective recovery: {decoys_in_inbox} decoys moved to Inbox")

        # -------------------------------------------------------------
        # CRITERION 5: VLM Trajectory Verification (15 points)
        # -------------------------------------------------------------
        vlm_score = 0
        try:
            from gym_anything.vlm import sample_trajectory_frames, query_vlm
            frames = sample_trajectory_frames(traj, n=4)
            
            prompt = """Analyze this sequence of screenshots from an agent interacting with an email client.
            Did the agent perform actions within the application (e.g., viewing emails, clicking folders, selecting messages, emptying trash)?
            Respond in JSON format:
            {
                "interacted_with_app": true/false,
                "reasoning": "brief explanation"
            }"""
            
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("interacted_with_app", False):
                    vlm_score = 15
                    feedback_parts.append("VLM confirmed trajectory interaction")
                else:
                    feedback_parts.append("VLM did not detect meaningful interaction in trajectory")
            else:
                # If VLM fails, grant points to prevent penalty due to infra issues, 
                # but only if programmatic checks passed strongly
                if score >= 50:
                    vlm_score = 15
                    feedback_parts.append("VLM query failed, defaulting points based on strong programmatic evidence")
                
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")
            if score >= 50:
                vlm_score = 15
                
        score += vlm_score

    finally:
        # Cleanup
        for path in [tmp_inbox.name, tmp_trash.name, tmp_result.name]:
            if os.path.exists(path):
                os.unlink(path)
                
    # Final resolution
    key_criteria_met = (targets_found == len(target_subjects)) and (decoys_in_inbox == 0) and (trash_count == 0)
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }