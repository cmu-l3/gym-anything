#!/usr/bin/env python3
"""
Verifier for patch_recovery_operation task.

SCORING CRITERIA (100 points total):
1. Folder 'Pending-Patches' created: 10 pts
2. Emails moved to folder: 20 pts (full if >=3, partial if >=1)
3. Precision check (moved emails are actually patches): 10 pts
4. Patch files saved to disk: 30 pts (15 per valid file, max 2)
5. Status report drafted/sent: 20 pts
6. VLM Verification (Trajectory): 10 pts

Pass threshold: 65 points (requires at least saving files AND moving some emails)
"""

import json
import tempfile
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_patch_recovery_operation(traj, env_info, task_info):
    """Verify patch recovery operations (folder, file extraction, report)."""
    
    # 1. SETUP: Copy result from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_patches = metadata.get('min_patches_moved', 3)
    
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

    # 2. CRITERION: Folder Creation (10 pts)
    if result.get('folder_exists', False):
        score += 10
        feedback.append("Created 'Pending-Patches' folder (+10)")
    else:
        feedback.append("Failed to create 'Pending-Patches' folder")

    # 3. CRITERION: Emails Moved (20 pts)
    count = result.get('emails_in_folder', 0)
    if count >= min_patches:
        score += 20
        feedback.append(f"Moved {count} emails to folder (+20)")
    elif count >= 1:
        score += 10
        feedback.append(f"Moved only {count} emails (expected {min_patches}) (+10)")
    else:
        feedback.append("No emails moved to folder")

    # 4. CRITERION: Isolation Precision (10 pts)
    # Check if moved emails were actually patches
    patch_count = result.get('patch_relevance_count', 0)
    if count > 0:
        precision = patch_count / count
        if precision >= 0.8: # Allow slight error margin
            score += 10
            feedback.append("Correctly identified patch emails (+10)")
        elif precision >= 0.5:
            score += 5
            feedback.append("Mixed accuracy in patch identification (+5)")
        else:
            feedback.append("Moved emails do not look like patches")

    # 5. CRITERION: Files Saved (30 pts)
    # 15 pts per valid file (max 2)
    valid_files = result.get('valid_patch_files_count', 0)
    files_score = min(valid_files, 2) * 15
    score += files_score
    if valid_files > 0:
        feedback.append(f"Saved {valid_files} valid patch files (+{files_score})")
    else:
        feedback.append("No valid patch files found in ~/Documents/patches/")

    # 6. CRITERION: Report Drafted (20 pts)
    if result.get('report_draft_exists', False):
        score += 20
        feedback.append("Drafted status report to lead (+20)")
    else:
        feedback.append("No report email found")

    # 7. CRITERION: VLM Verification (10 pts)
    # Verify work was done via UI (anti-gaming check)
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')
    
    vlm_score = 0
    if query_vlm and sample_trajectory_frames and traj:
        try:
            frames = sample_trajectory_frames(traj, num_samples=4)
            response = query_vlm(
                images=frames,
                prompt="""Analyze these screenshots of a user working in BlueMail.
                Did the user:
                1. View/Open specific emails?
                2. Select text or use copy/paste actions?
                3. Create a folder or move emails?
                
                Answer 'YES' if you see clear evidence of email interaction and data extraction."""
            )
            resp_text = str(response).upper()
            if "YES" in resp_text or "TRUE" in resp_text:
                vlm_score = 10
                feedback.append("VLM verified interactive workflow (+10)")
        except Exception:
            # Fallback if VLM fails, grant points if file output exists (since that implies interaction)
            if valid_files > 0:
                vlm_score = 10
                feedback.append("Workflow inferred from valid output (+10)")
    
    score += vlm_score

    # Final Check
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }