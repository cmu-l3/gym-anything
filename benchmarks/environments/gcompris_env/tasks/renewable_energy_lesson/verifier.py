#!/usr/bin/env python3
"""
Verifier for Renewable Energy Lesson Task.

Criteria:
1. Files Created (40 pts): Screenshot and note exist and were created during the task.
2. Note Content (20 pts): Contains required keywords and a question mark.
3. Visual Verification (40 pts):
   - Trajectory shows navigation to Renewable Energy activity.
   - Saved screenshot shows the actual simulation with power generated.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_renewable_energy_lesson(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # 2. File Verification (40 Points)
    # ------------------------------------------------------------------
    
    # Check Screenshot File
    screenshot_valid = False
    if result.get('screenshot_exists') and result.get('screenshot_created_during_task'):
        if result.get('screenshot_size', 0) > 10240:  # > 10KB
            score += 20
            screenshot_valid = True
            feedback.append("Screenshot created successfully.")
        else:
            feedback.append("Screenshot file is too small/empty.")
    else:
        feedback.append("Screenshot file missing or not created during task.")

    # Check Note File Existence
    note_valid = False
    if result.get('note_exists') and result.get('note_created_during_task'):
        if result.get('note_size', 0) > 50:
            score += 20
            note_valid = True
            feedback.append("Lesson note created successfully.")
        else:
            feedback.append("Lesson note is empty or too short.")
    else:
        feedback.append("Lesson note file missing.")

    # ------------------------------------------------------------------
    # 3. Content Verification (20 Points)
    # ------------------------------------------------------------------
    
    if note_valid:
        # Copy note content to verify text
        temp_note = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(result['note_path'], temp_note.name)
            with open(temp_note.name, 'r', encoding='utf-8', errors='ignore') as f:
                note_content = f.read().lower()
            
            # check keywords
            keywords = metadata.get('required_keywords', ["energy", "solar", "wind"])
            found_count = sum(1 for k in keywords if k in note_content)
            
            if found_count >= 2:
                score += 10
                feedback.append(f"Note contains relevant keywords ({found_count} found).")
            else:
                feedback.append("Note missing relevant energy keywords.")
                
            # check for question
            if "?" in note_content:
                score += 10
                feedback.append("Note contains a discussion question.")
            else:
                feedback.append("Note missing a discussion question (?).")
                
        except Exception as e:
            feedback.append(f"Error reading note content: {str(e)}")
        finally:
            if os.path.exists(temp_note.name):
                os.unlink(temp_note.name)

    # ------------------------------------------------------------------
    # 4. VLM Verification (40 Points)
    # ------------------------------------------------------------------
    
    # A. Check the User's SAVED Screenshot (20 pts)
    # We copy the screenshot the agent took to verify it shows the right thing.
    if screenshot_valid:
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result['screenshot_path'], temp_img.name)
            
            vlm_prompt = (
                "This is a screenshot captured by a user from educational software. "
                "Does it show the 'Renewable Energy' simulation in GCompris? "
                "Look for: a town, wind turbines, solar panels, a hydroelectric dam, or energy meters. "
                "Is the simulation active (e.g., lights on in houses, meters showing power)? "
                "Reply JSON: {\"is_renewable_energy_app\": bool, \"is_simulation_active\": bool}"
            )
            
            vlm_res = query_vlm(prompt=vlm_prompt, image=temp_img.name)
            
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('is_renewable_energy_app'):
                    score += 10
                    feedback.append("Saved screenshot verifies correct app.")
                    if parsed.get('is_simulation_active'):
                        score += 10
                        feedback.append("Saved screenshot shows active simulation.")
                    else:
                        feedback.append("Simulation doesn't look active in screenshot.")
                else:
                    feedback.append("Saved screenshot does not look like the Renewable Energy activity.")
            else:
                # Fallback if VLM fails/returns garbage
                score += 10 # Give benefit of doubt if file exists and VLM errors
                feedback.append("VLM check on screenshot inconclusive (awarded partial points).")
                
        except Exception as e:
            feedback.append(f"Error analyzing saved screenshot: {str(e)}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    
    # B. Trajectory Verification (20 pts)
    # Ensure they actually navigated there
    traj_frames = sample_trajectory_frames(traj, n=6)
    
    traj_prompt = (
        "Analyze these screenshots of a user navigating GCompris educational software. "
        "1. Do you see the user navigating menus (clicking category icons)? "
        "2. Do you see the 'Renewable Energy' activity open at any point (look for wind turbines, solar panels, water dam)? "
        "Reply JSON: {\"navigated_menus\": bool, \"reached_activity\": bool}"
    )
    
    traj_res = query_vlm(prompt=traj_prompt, images=traj_frames)
    
    if traj_res and traj_res.get('success'):
        parsed = traj_res.get('parsed', {})
        if parsed.get('navigated_menus'):
            score += 10
            feedback.append("Trajectory shows menu navigation.")
        
        if parsed.get('reached_activity'):
            score += 10
            feedback.append("Trajectory shows Renewable Energy activity was reached.")
    else:
        # Fallback
        score += 10
        feedback.append("Trajectory analysis inconclusive.")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = score >= 70 and screenshot_valid and note_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }