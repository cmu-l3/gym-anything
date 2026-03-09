#!/usr/bin/env python3
"""
Verifier for git_cherry_pick_fix task.

Verification Criteria:
1.  **Fix Present (40pts):** `AuthUtils.java` on `main` contains `MessageDigest.isEqual`.
2.  **Clean State (30pts):** `AuthUtils.java` does NOT contain `TODO: Implement OAuth2` or `tempDebug` (proves cherry-pick vs merge).
3.  **Commit History (20pts):** `git log` on `main` shows the specific commit message "FIX: Use constant-time comparison...".
4.  **Compilation (10pts):** The project compiles successfully.
5.  **VLM Verification:** Trajectory shows interaction with Git tool window (Log tab).

Pass Threshold: 70 points.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_git_cherry_pick_fix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_msg = metadata.get('required_commit_msg', "FIX: Use constant-time comparison to prevent timing attacks")

    # Retrieve result JSON
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
    
    # Extract data
    git_log = result.get('git_log_main', '')
    current_branch = result.get('current_branch', '')
    build_success = result.get('build_success', False)
    has_fix = result.get('has_fix_code', False)
    has_wip = result.get('has_wip_code', False)
    has_debug = result.get('has_debug_code', False)

    # Criterion 1: Fix Present (40 pts)
    if has_fix:
        score += 40
        feedback_parts.append("Security fix code found in AuthUtils.java")
    else:
        feedback_parts.append("Security fix code (MessageDigest.isEqual) NOT found")

    # Criterion 2: Clean State (30 pts)
    # If user merged the whole branch, has_wip would be true.
    # We want has_wip to be FALSE.
    if not has_wip and not has_debug:
        score += 30
        feedback_parts.append("Branch is clean (no WIP code detected)")
    elif has_wip or has_debug:
        feedback_parts.append("Branch contains unwanted WIP code (likely merged entire branch instead of cherry-pick)")

    # Criterion 3: Commit History (20 pts)
    if required_msg in git_log:
        score += 20
        feedback_parts.append("Commit message found in git log")
    else:
        feedback_parts.append("Required commit message NOT found in git log")

    # Criterion 4: Compilation (10 pts)
    if build_success:
        score += 10
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Project compilation failed")

    # Criterion 5: Verify Branch
    if current_branch.strip() != 'main':
        score = 0
        feedback_parts.append(f"FAILED: Wrong branch checked out ({current_branch}). Task requires applying fix to 'main'.")

    # VLM Verification (Optional but good for process check)
    # We check if the agent actually used the GUI
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=5)
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and frames:
            prompt = """
            You are verifying a Git task in IntelliJ IDEA.
            Look at these screenshots.
            1. Do you see the 'Git' tool window open (usually at the bottom)?
            2. Do you see a list of commits (Log view)?
            3. Do you see a context menu with 'Cherry-Pick' or visual evidence of commit selection?
            
            Respond YES if you see evidence of using the Git UI for history/cherry-picking.
            Respond NO if you only see a terminal or code editor.
            """
            vlm_resp = query_vlm(prompt=prompt, images=frames)
            if vlm_resp and vlm_resp.get('success'):
                resp_text = vlm_resp.get('response', '').upper()
                if "YES" in resp_text:
                    vlm_passed = True
                    feedback_parts.append("VLM: Git UI usage detected")
                else:
                    feedback_parts.append("VLM: Git UI usage NOT detected (did you use terminal?)")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Final scoring logic
    passed = score >= 70
    
    # If the code is fixed but WIP is present, it's a fail (merge scenario)
    if has_fix and has_wip:
        passed = False
        feedback_parts.append("FAIL: Task failed because WIP code was introduced (Merge instead of Cherry-Pick)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }