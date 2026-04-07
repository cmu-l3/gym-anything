#!/usr/bin/env python3
"""
Verifier for patch_contribution_harvesting task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_patch_contribution_harvesting(traj, env_info, task_info):
    """
    Verifies:
    1. 'Patch-Review' folder created (20 pts)
    2. Folder contains at least 3 emails (20 pts)
    3. Emails in folder are ACTUALLY patches (Anti-gaming) (30 pts)
    4. Report email drafted/sent to correct recipient (20 pts)
    5. Report content relevance (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # 1. Folder Existence (20 pts)
    if result.get('folder_exists', False):
        score += 20
        feedback.append("Folder 'Patch-Review' created.")
    else:
        feedback.append("Folder 'Patch-Review' NOT found.")

    # 2. Quantity (20 pts)
    count = result.get('folder_email_count', 0)
    if count >= 3:
        score += 20
        feedback.append(f"Folder contains {count} emails (Target: 3+).")
    elif count > 0:
        score += 10
        feedback.append(f"Folder contains {count} emails (Partial credit).")
    else:
        feedback.append("Folder is empty.")

    # 3. Content Precision / Anti-Gaming (30 pts)
    # The export script greps for diff markers. 
    # If the folder has emails but none are patches, score 0 here.
    valid_patches = result.get('valid_patch_count', 0)
    
    if count > 0:
        patch_ratio = valid_patches / count
        if patch_ratio >= 0.6: # At least 60% are real patches
            score += 30
            feedback.append(f"Content verified: {valid_patches} valid patches found.")
        elif valid_patches > 0:
            score += 15
            feedback.append(f"Content mixed: {valid_patches} valid patches, but some non-patches.")
        else:
            feedback.append("Anti-gaming: Moved emails do not appear to contain patches/diffs.")
    
    # 4. Report Draft (20 pts)
    report = result.get('report_email', {})
    if report.get('found', False):
        score += 20
        feedback.append("Report email found to lead-dev@project.org.")
        
        # 5. Report Content (10 pts)
        subj = report.get('subject', '').lower()
        if 'patch' in subj and any(char.isdigit() for char in subj):
            score += 10 # Ideal: Mentions "patch" and a number
            feedback.append("Report subject is descriptive.")
        elif 'patch' in subj:
            score += 5
            feedback.append("Report subject mentions patches.")
    else:
        feedback.append("No report email found to lead-dev@project.org.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }