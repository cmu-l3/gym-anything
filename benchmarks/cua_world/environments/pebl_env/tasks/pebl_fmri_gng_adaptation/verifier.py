#!/usr/bin/env python3
"""
Verifier for pebl_fmri_gng_adaptation task.

Verification Strategy:
1. Programmatic Check (File integrity & Modification check)
2. Programmatic Syntax Check (Parsed without fatal errors)
3. AST/Regex Source Code Analysis for the 5 targeted adaptations:
   - Stimulus Duration (500)
   - ISI Duration (2500)
   - Go Key ("1")
   - Visuals (Dark mode: MakeWindow/MakeColor = "black", fg = "white")
   - Output File ("gng_fmri_log.csv")
4. VLM Trajectory Verification to ensure the agent physically edited the file
   (prevents pure API/CLI spoofing if evaluating UI workflows).
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pebl_fmri_adaptation(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Retrieve metadata exports
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.pbl')
    
    try:
        # Load task_result.json
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # Load the modified script
        script_path = "/home/ga/pebl/experiments/fmri_gng/gng_task.pbl"
        copy_from_env(script_path, temp_script.name)
        with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed to read files: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    # 1. FILE INTEGRITY & SYNTAX (20 pts)
    # -----------------------------------
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Target script gng_task.pbl was deleted or not found."}
        
    if not result.get('file_modified'):
        feedback_parts.append("File was not modified.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    if result.get('file_size_bytes', 0) < 200:
        feedback_parts.append("File size too small (likely destroyed).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if result.get('syntax_error'):
        feedback_parts.append("[0/20] Script has PEBL syntax errors and won't run.")
        # Cap score at 40 if syntax is broken
        max_score = 40
    else:
        score += 20
        feedback_parts.append("[20/20] Script modified and maintains valid PEBL syntax.")

    # 2. TIMING (20 pts)
    # -----------------------------------
    timing_score = 0
    if re.search(r'(?i)gStimDur\s*<-\s*500\b', script_content):
        timing_score += 10
    if re.search(r'(?i)gISIDur\s*<-\s*2500\b', script_content):
        timing_score += 10
        
    score += timing_score
    if timing_score == 20:
        feedback_parts.append("[20/20] TR-locked timings (500ms / 2500ms) correctly set.")
    else:
        feedback_parts.append(f"[{timing_score}/20] Timings incorrect or missing.")

    # 3. MRI BUTTON BOX KEY (20 pts)
    # -----------------------------------
    if re.search(r'(?i)gGoKey\s*<-\s*"1"', script_content):
        score += 20
        feedback_parts.append("[20/20] Go key successfully mapped to '1'.")
    else:
        feedback_parts.append("[0/20] Go key mapping incorrect (expected '1').")

    # 4. DARK MODE VISUALS (30 pts)
    # -----------------------------------
    visuals_score = 0
    if re.search(r'(?i)MakeWindow\s*\(\s*"black"\s*\)', script_content):
        visuals_score += 10
    if re.search(r'(?i)gBGColor\s*<-\s*MakeColor\s*\(\s*"black"\s*\)', script_content):
        visuals_score += 10
    if re.search(r'(?i)gFGColor\s*<-\s*MakeColor\s*\(\s*"white"\s*\)', script_content):
        visuals_score += 10
        
    score += visuals_score
    if visuals_score == 30:
        feedback_parts.append("[30/30] Dark mode visuals correctly configured.")
    else:
        feedback_parts.append(f"[{visuals_score}/30] Dark mode visuals incomplete.")

    # 5. OUTPUT LOG NAME (10 pts)
    # -----------------------------------
    if re.search(r'(?i)gOutFile\s*<-\s*"gng_fmri_log\.csv"', script_content):
        score += 10
        feedback_parts.append("[10/10] Output log file correctly renamed.")
    else:
        feedback_parts.append("[0/10] Output log file renaming incorrect.")

    # VLM Trajectory Check (Anti-gaming verify agent used UI or editor)
    # -----------------------------------
    vlm_feedback = ""
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = """Look at these screenshots of a computer desktop taken over time.
Did the agent open a text editor (like gedit, nano, vim) and modify a script file containing PEBL code?
Answer TRUE if you see a text editor being used to modify code, FALSE otherwise.
Return JSON exactly like: {"edited_code": true/false}"""
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if not parsed.get('edited_code', False):
                    vlm_feedback = " (VLM Warning: Trajectory does not clearly show text editing)"
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Enforce syntax error cap
    if score > max_score:
        score = max_score
        feedback_parts.append("Score capped due to PEBL Syntax Error.")

    # Determine Pass/Fail
    passed = (score >= 70) and not result.get('syntax_error')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + vlm_feedback
    }