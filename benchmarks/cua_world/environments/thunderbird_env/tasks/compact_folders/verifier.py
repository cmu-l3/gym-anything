#!/usr/bin/env python3
"""
Verifier for compact_folders task.

Verifies that mail folders were compacted by checking file sizes, ensuring
active emails were not deleted, verifying timestamps (anti-gaming), and 
checking VLM trajectory frames to ensure the agent used the GUI correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compact_folders(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Required ratio for compaction (70% of original, meaning at least 30% was reclaimed)
    target_ratio = task_info.get("metadata", {}).get("required_size_reduction_ratio", 0.7)

    # --- Criterion 1: Inbox Size Reduction (20 pts) ---
    inbox_init_size = result.get('inbox_initial_size', 0)
    inbox_final_size = result.get('inbox_final_size', 0)
    inbox_reduced = (inbox_init_size > 0) and (inbox_final_size < inbox_init_size * target_ratio)
    
    if inbox_reduced:
        score += 20
        reduction_pct = 100 * (1 - (inbox_final_size / inbox_init_size))
        feedback_parts.append(f"Inbox size reduced by {reduction_pct:.1f}%")
    else:
        feedback_parts.append("Inbox size was not properly reduced")

    # --- Criterion 2: Junk Size Reduction (15 pts) ---
    junk_init_size = result.get('junk_initial_size', 0)
    junk_final_size = result.get('junk_final_size', 0)
    junk_reduced = (junk_init_size > 0) and (junk_final_size < junk_init_size * target_ratio)
    
    if junk_reduced:
        score += 15
        reduction_pct = 100 * (1 - (junk_final_size / junk_init_size))
        feedback_parts.append(f"Junk size reduced by {reduction_pct:.1f}%")
    else:
        feedback_parts.append("Junk size was not properly reduced")

    # --- Criterion 3: Emails Intact Check (Anti-gaming/Destruction Check) ---
    # The final message count (From lines) should match the initial ACTIVE count 
    # (before bloat injection). We allow a variance of ±2 just for parse safety.
    inbox_init_active = result.get('inbox_initial_active', 0)
    inbox_final_active = result.get('inbox_final_active', 0)
    inbox_intact = (inbox_final_size > 0) and (abs(inbox_final_active - inbox_init_active) <= 2)
    
    if inbox_intact:
        score += 15
        feedback_parts.append(f"Inbox active emails intact ({inbox_final_active})")
    else:
        feedback_parts.append(f"Inbox active emails missing/corrupt (Expected ~{inbox_init_active}, found {inbox_final_active})")

    junk_init_active = result.get('junk_initial_active', 0)
    junk_final_active = result.get('junk_final_active', 0)
    junk_intact = (junk_final_size > 0) and (abs(junk_final_active - junk_init_active) <= 2)
    
    if junk_intact:
        score += 10
        feedback_parts.append(f"Junk active emails intact ({junk_final_active})")
    else:
        feedback_parts.append(f"Junk active emails missing/corrupt (Expected ~{junk_init_active}, found {junk_final_active})")

    # --- Criterion 4: Modified during task (Anti-gaming Do-Nothing check) ---
    inbox_modified = result.get('inbox_modified_during_task', False)
    junk_modified = result.get('junk_modified_during_task', False)
    if inbox_modified and junk_modified:
        score += 10
        feedback_parts.append("Files modified during active session")
    elif inbox_modified or junk_modified:
        score += 5
        feedback_parts.append("Only one file modified during active session")
    else:
        feedback_parts.append("No modification timestamps detected during task session")

    # --- Criterion 5: VLM Trajectory Process Verification (30 pts) ---
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = """Analyze these screenshots from a Thunderbird session.
Did the agent perform the action of "Compacting" folders?
Look for a context menu (right-click menu) with the option "Compact" or "Compact Folder" selected or visible.
Respond strictly in JSON format:
{
    "compact_menu_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is seen in the frames"
}"""
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("compact_menu_visible", False):
                    vlm_score = 30
                    feedback_parts.append("VLM verified 'Compact' GUI menu usage")
                else:
                    feedback_parts.append("VLM did not observe 'Compact' GUI usage")
            else:
                feedback_parts.append("VLM query execution failed")
        else:
            feedback_parts.append("No trajectory frames available for VLM")
    except ImportError:
        logger.warning("VLM utilities not found, skipping VLM check.")
        feedback_parts.append("VLM skipped (utilities unavailable)")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM error: {str(e)[:50]}")

    score += vlm_score

    # Passing Requirements: Need at least 60 points, the Inbox MUST be reduced successfully,
    # and the Inbox emails MUST be intact (prevents deleting the file from passing).
    key_criteria_met = inbox_reduced and inbox_intact and inbox_modified
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }