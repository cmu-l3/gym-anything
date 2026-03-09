#!/usr/bin/env python3
"""
Verifier for git_init_and_commit task.

Criteria:
1. .git directory exists and created during task (15 pts)
2. .gitignore exists and contains correct patterns (15 pts)
3. At least one commit exists (15 pts)
4. Commit message matches exactly (15 pts)
5. Java source files are tracked (10 pts)
6. 'target' directory is NOT tracked (10 pts)
7. VLM: Verification of GUI workflow (Team > Share, Git Staging view) (20 pts)
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_git_init_and_commit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import verification utils
    try:
        from utils.eclipse_verification_utils import vlm_verify_eclipse_task
    except ImportError:
        vlm_verify_eclipse_task = None
        logger.warning("VLM utility not found")

    metadata = task_info.get('metadata', {})
    expected_msg = metadata.get('expected_commit_message', "Initial commit: Import Apache Commons CLI library")
    
    score = 0
    feedback_parts = []
    
    # --- Load Result JSON ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # --- Load Start Time (Anti-Gaming) ---
    task_start_time = 0
    try:
        temp_time = tempfile.NamedTemporaryFile(delete=False)
        copy_from_env("/tmp/task_start_time.txt", temp_time.name)
        with open(temp_time.name, 'r') as f:
            task_start_time = int(f.read().strip())
        os.unlink(temp_time.name)
    except Exception:
        logger.warning("Could not read task start time")

    # --- Criterion 1: .git directory exists (15 pts) ---
    git_exists = result.get('git_exists', False)
    git_timestamp = result.get('git_dir_timestamp', 0)
    
    if git_exists:
        if git_timestamp >= task_start_time:
            score += 15
            feedback_parts.append("Git repository initialized")
        else:
            feedback_parts.append("Git repository exists but predates task (Anti-Gaming fail)")
    else:
        feedback_parts.append("No Git repository found")

    # --- Criterion 2: .gitignore (15 pts) ---
    gitignore_exists = result.get('gitignore_exists', False)
    gitignore_content = result.get('gitignore_content', "")
    
    if gitignore_exists:
        gi_score = 5
        missing_patterns = []
        
        # Check patterns
        if "target/" in gitignore_content or "target" in gitignore_content:
            gi_score += 5
        else:
            missing_patterns.append("target/")
            
        if ".class" in gitignore_content:
            gi_score += 5
        else:
            missing_patterns.append("*.class")
            
        score += gi_score
        if missing_patterns:
            feedback_parts.append(f".gitignore exists but missing patterns: {', '.join(missing_patterns)}")
        else:
            feedback_parts.append(".gitignore correct")
    else:
        feedback_parts.append(".gitignore missing")

    # --- Criterion 3 & 4: Commit Check (30 pts) ---
    commit_count = result.get('commit_count', 0)
    commit_msg = result.get('commit_message', "").strip()
    
    if commit_count > 0:
        score += 15
        feedback_parts.append("Commit created")
        
        if commit_msg == expected_msg:
            score += 15
            feedback_parts.append("Commit message matches exactly")
        elif expected_msg.lower() in commit_msg.lower():
            score += 10
            feedback_parts.append(f"Commit message matches loosely (Expected: '{expected_msg}')")
        else:
            feedback_parts.append(f"Commit message mismatch: '{commit_msg}'")
    else:
        feedback_parts.append("No commits found")

    # --- Criterion 5 & 6: File Tracking (20 pts) ---
    has_java = result.get('has_tracked_java_files', False)
    has_target = result.get('has_tracked_target_files', False)
    
    if has_java:
        score += 10
        feedback_parts.append("Java files tracked")
    else:
        feedback_parts.append("Java source files NOT tracked")
        
    if not has_target and result.get('ignored_check') == 'target_ignored':
        score += 10
        feedback_parts.append("Build artifacts ignored")
    elif has_target:
        feedback_parts.append("FAIL: 'target/' directory was committed (should be ignored)")
    else:
        feedback_parts.append("Build artifacts not committed (good)")

    # --- Criterion 7: VLM Verification (20 pts) ---
    # We verify that they actually used the GUI (Eclipse Team menu / Staging View)
    # rather than just running 'git init' in the terminal.
    if vlm_verify_eclipse_task:
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Initialize Git repo, create .gitignore, and commit using Eclipse GUI",
            checklist_items=[
                "Eclipse IDE window is visible",
                "User accessed 'Team' menu or 'Share Project' dialog",
                "'Git Staging' view or 'Commit' dialog is visible",
                "Commit message was entered in a GUI text area",
                "Files were added/staged using the GUI"
            ]
        )
        if vlm_result:
            vlm_score = vlm_result.get('vlm_score', 0)
            # Normalize 0-100 score to 0-20 points
            points = int(vlm_score * 0.2)
            score = min(score + points, 100)
            feedback_parts.append(f"VLM Analysis ({points}/20): {vlm_result.get('vlm_feedback', '')}")
    else:
        feedback_parts.append("VLM verification skipped")

    # Final logic
    # Must have created repo and committed to pass
    passed = (git_exists and commit_count > 0 and score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }