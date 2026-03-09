#!/usr/bin/env python3
import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_address_pr_feedback(traj, env_info, task_info):
    """
    Verifies that the agent addressed PR feedback correctly.
    
    Criteria:
    1. style.css updated with correct hex code (25 pts)
    2. contact.js updated to remove console.log (25 pts)
    3. All 3 comment threads are marked Resolved/Fixed (30 pts)
    4. Reply posted to the general thread (20 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    expected_hex = metadata.get("expected_hex", "#f5f5f5")
    forbidden_js = metadata.get("forbidden_js", "console.log")
    reply_keyword = metadata.get("reply_keyword", "backlog")

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        # Note: Path matches the one in export_result.ps1
        # In Windows envs, we might need to handle path separators carefully
        copy_from_env("C:/Users/Docker/task_results/address_pr_feedback_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Verify File Content (Code Changes)
    file_checks = result_data.get("file_checks", {})
    
    # Check CSS
    css_content = file_checks.get("css_content", "")
    if expected_hex in css_content:
        score += 25
        feedback.append("SUCCESS: style.css updated with correct background color.")
    else:
        feedback.append(f"FAIL: style.css does not contain {expected_hex}.")

    # Check JS
    js_content = file_checks.get("js_content", "")
    if forbidden_js not in js_content and "function initContactForm" in js_content:
        score += 25
        feedback.append("SUCCESS: console.log removed from contact.js.")
    elif forbidden_js in js_content:
        feedback.append("FAIL: contact.js still contains console.log.")
    else:
        feedback.append("FAIL: contact.js content missing or corrupted.")

    # 3. Verify Thread Status and Replies
    threads = result_data.get("thread_checks", {}).get("threads", [])
    
    # ADO Status: 1=Active, 2=Fixed, 4=Closed. We accept Fixed(2) or Closed(4).
    resolved_count = 0
    reply_found = False
    
    total_threads = len(threads)
    if total_threads == 0:
        feedback.append("FAIL: No PR threads found to verify.")
    
    for thread in threads:
        # Check Status
        status = thread.get("status")
        if status in [2, 4]: # Fixed or Closed
            resolved_count += 1
        
        # Check for reply (specifically looking for the general thread which usually doesn't have a filePath)
        # or checking all threads for the specific keyword
        last_reply = thread.get("last_reply_content", "")
        if reply_keyword.lower() in last_reply.lower() and thread.get("has_reply"):
            reply_found = True

    # Score Threads (30 pts)
    # 10 pts per resolved thread? Or all-or-nothing?
    # Let's do proportional
    if total_threads > 0:
        thread_score = (resolved_count / total_threads) * 30
        score += int(thread_score)
        feedback.append(f"Threads resolved: {resolved_count}/{total_threads} (+{int(thread_score)} pts).")
    
    # Score Reply (20 pts)
    if reply_found:
        score += 20
        feedback.append("SUCCESS: Reply added to discussion.")
    else:
        feedback.append("FAIL: No reply found containing keyword 'backlog'.")

    # 4. VLM Trajectory Verification
    # Ensure they actually used the UI
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    vlm_score = 0
    # Simple check: Did we see the Pull Request UI?
    if frames:
        vlm_res = query_vlm(
            images=frames,
            prompt="Does this sequence show a user interacting with Azure DevOps Pull Requests code or comments?"
        )
        if vlm_res.get("parsed", {}).get("answer", False):
            # We don't add points here, just confirm valid attempt? 
            # Or use it to validate if API check fails?
            # For now, we stick to API scoring as it is robust.
            pass

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }