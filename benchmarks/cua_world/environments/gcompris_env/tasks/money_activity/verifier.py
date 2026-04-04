#!/usr/bin/env python3
"""
Verifier for GCompris Money Activity Task.

Scoring Criteria:
1. Evidence Structure (25 pts): Directory and files exist.
2. Anti-Gaming (15 pts): Files created during task, valid timestamps.
3. Visual Verification (60 pts): VLM analysis of the 3 user-generated screenshots.
   - activity_opened.png: Shows Money activity (20 pts)
   - rounds_completed.png: Shows progress (20 pts)
   - main_menu_return.png: Shows Main Menu (20 pts)
"""

import json
import os
import tempfile
import logging
import sys

# Import VLM utilities from the gym_anything framework
# (Adjust path if necessary based on environment structure, but standard is typically available)
try:
    from gym_anything.vlm import query_vlm
except ImportError:
    # Mock for testing if environment not set up
    def query_vlm(prompt, image):
        return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_money_activity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 1. Directory and File Existence
    if result.get("evidence_dir_exists"):
        score += 5
        feedback_parts.append("Evidence directory created.")
    else:
        feedback_parts.append("Evidence directory missing.")

    files_info = result.get("files", {})
    required_files = ["activity_opened.png", "rounds_completed.png", "main_menu_return.png"]
    
    files_exist = 0
    for fname in required_files:
        if files_info.get(fname, {}).get("exists"):
            files_exist += 1
            score += 5  # 5 pts per file existence (Total 15)
    
    feedback_parts.append(f"{files_exist}/3 evidence files found.")

    # 2. Timestamp / Anti-Gaming
    timestamps_valid = True
    timestamps = []
    
    for fname in required_files:
        f_data = files_info.get(fname, {})
        if f_data.get("exists"):
            if not f_data.get("created_during_task"):
                timestamps_valid = False
            timestamps.append((fname, f_data.get("mtime", 0)))
            
            # Check for non-empty files
            if f_data.get("size", 0) < 1000: # < 1KB is suspicious for a screenshot
                score -= 5
                feedback_parts.append(f"{fname} is suspiciously small.")

    # Check order: opened < rounds < menu
    ordered = False
    if len(timestamps) == 3:
        # sort by time
        t_open = files_info["activity_opened.png"]["mtime"]
        t_rounds = files_info["rounds_completed.png"]["mtime"]
        t_menu = files_info["main_menu_return.png"]["mtime"]
        
        if t_open <= t_rounds <= t_menu:
            ordered = True
            score += 10
            feedback_parts.append("Screenshots taken in correct chronological order.")
        else:
            feedback_parts.append("Screenshots NOT in correct order.")
            
    if timestamps_valid and files_exist > 0:
        score += 5
        feedback_parts.append("Files created during task window.")

    # 3. App State
    if result.get("app_was_running"):
        score += 10
        feedback_parts.append("GCompris is running.")
    else:
        feedback_parts.append("GCompris is NOT running.")

    # 4. VLM Verification of User Screenshots
    # We need to pull the actual images from the environment to analyze them
    evidence_path = task_info.get("metadata", {}).get("evidence_dir", "/home/ga/Documents/money_evidence")
    
    vlm_score = 0
    vlm_feedback = []

    # Prompt templates
    prompts = {
        "activity_opened.png": "Is this a screenshot of a money/currency counting activity in GCompris? It should show coins, bills, or a price tag. Return JSON: {'is_money_activity': bool}",
        "rounds_completed.png": "Does this screenshot show a money activity in progress or completed? Are there coins/bills moved into a payment area or a 'Correct' message? Return JSON: {'progress_visible': bool}",
        "main_menu_return.png": "Is this the GCompris main menu showing category icons (like a sheep, cat, penguin, etc.)? Return JSON: {'is_main_menu': bool}"
    }

    for fname in required_files:
        if files_info.get(fname, {}).get("exists"):
            # Copy image to temp
            local_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            remote_path = f"{evidence_path}/{fname}"
            try:
                copy_from_env(remote_path, local_img.name)
                
                # Query VLM
                vlm_resp = query_vlm(prompt=prompts[fname], image=local_img.name)
                
                if vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    
                    if fname == "activity_opened.png" and parsed.get("is_money_activity"):
                        vlm_score += 20
                        vlm_feedback.append("Activity opened verified.")
                    elif fname == "rounds_completed.png" and parsed.get("progress_visible"):
                        vlm_score += 20
                        vlm_feedback.append("Rounds completion verified.")
                    elif fname == "main_menu_return.png" and parsed.get("is_main_menu"):
                        vlm_score += 20  # Adjusted to meet total 100 logic (Total score calc below)
                        vlm_feedback.append("Return to menu verified.")
                    else:
                        vlm_feedback.append(f"VLM rejected {fname}.")
                else:
                    vlm_feedback.append(f"VLM failed for {fname}.")

            except Exception as e:
                logger.error(f"Error processing {fname}: {e}")
                vlm_feedback.append(f"Error checking {fname}.")
            finally:
                if os.path.exists(local_img.name):
                    os.unlink(local_img.name)

    score += vlm_score
    
    # Cap score at 100
    score = min(score, 100)
    
    # Pass threshold
    passed = score >= 60 and result.get("files", {}).get("activity_opened.png", {}).get("exists")

    full_feedback = " ".join(feedback_parts) + " | VLM: " + " ".join(vlm_feedback)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": full_feedback
    }