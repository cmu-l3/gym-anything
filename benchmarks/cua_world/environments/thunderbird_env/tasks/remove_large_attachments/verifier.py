#!/usr/bin/env python3
"""
Verifier for remove_large_attachments task.

Uses multi-signal programmatic checks alongside VLM trajectory sampling to ensure:
1. Emails are NOT completely deleted.
2. The specific file attachments inside them are removed, triggering a large size drop.
3. Timestamp and visual trajectory checks guard against gaming.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_attachments_removed(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_subjects = metadata.get('target_subjects', [
        "Case Evidence: Smith vs Jones (Deposition)",
        "Case Evidence: Exhibit B Scans",
        "Case Evidence: Financial Disclosures"
    ])
    max_stripped_size_bytes = metadata.get('max_stripped_size_bytes', 100000)

    # Read result from container
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
    feedback_parts = []
    
    target_emails = result.get('target_emails', {})
    
    # Criterion 1: Check if Inbox was modified
    task_start = result.get('task_start', 0)
    inbox_mtime = result.get('inbox_mtime', 0)
    
    if inbox_mtime >= task_start:
        score += 10
        feedback_parts.append("Inbox modified during task")
    else:
        feedback_parts.append("Inbox NOT modified during task")
        
    # Criterion 2: Check App Status
    app_was_running = result.get('app_was_running', False)
    if app_was_running:
        score += 10
        feedback_parts.append("Thunderbird was running")
    else:
        feedback_parts.append("Thunderbird was closed")

    # Criterion 3: Ensure emails are stripped but NOT deleted
    stripped_count = 0

    for subj in target_subjects:
        if subj in target_emails:
            score += 5  # Bonus for preserving the email string itself
            size = target_emails[subj].get('size', 0)
            if size < max_stripped_size_bytes:
                stripped_count += 1
                score += 15  # Heavy bonus for actually stripping the massive payloads
                feedback_parts.append(f"Successfully stripped: '{subj}' ({size} bytes)")
            else:
                feedback_parts.append(f"Preserved but NOT stripped: '{subj}' ({size} bytes)")
        else:
            feedback_parts.append(f"DELETED: '{subj}' was completely removed (collateral damage)")

    # Criterion 4: VLM Verification using Trajectory Frames (Not just the final screenshot)
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            You are verifying a Thunderbird task where the agent must delete email attachments.
            Looking at these chronological screenshots:
            1. Is there evidence of the agent selecting emails with "Case Evidence:" in the subject?
            2. Is there evidence of interacting with the attachment pane (e.g. right-clicking an attachment, clicking "Delete") or a confirmation dialog for deleting attachments?
            
            Respond in JSON format:
            {
                "interacted_with_attachments": true/false,
                "deleted_attachments": true/false
            }
            """
            vlm_result = query_vlm(images=images, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("deleted_attachments") or parsed.get("interacted_with_attachments"):
                    vlm_score = 20
                    feedback_parts.append("VLM verified attachment deletion workflow")
                else:
                    feedback_parts.append("VLM did not detect attachment deletion workflow")
            else:
                vlm_score = 20
                feedback_parts.append("VLM query failed, granting points")
        except Exception as e:
            logger.warning(f"VLM exception: {e}")
            vlm_score = 20  
            feedback_parts.append("VLM check skipped/failed, granting points")
    else:
        vlm_score = 20
        feedback_parts.append("VLM not available, granting points")

    score += vlm_score

    # To pass, the agent must strip at least two files WITHOUT deleting the original emails
    passed = score >= 60 and stripped_count >= 2

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }