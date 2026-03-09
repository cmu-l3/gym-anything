#!/usr/bin/env python3
"""
Verifier for check_respiratory_meds_safety_lorlatinib task.

Verification Strategy:
1. Programmatic: Check if /sdcard/respiratory_check.txt exists and parses correctly.
2. Programmatic: Verify the reported colors are valid traffic light colors.
3. VLM: Verify the agent actually looked up the drugs in the app using trajectory frames.
"""

import json
import base64
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_respiratory_safety(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # =========================================================
    # CRITERION 1: File Existence & Format (40 points)
    # =========================================================
    output_exists = result.get("output_exists", False)
    content_b64 = result.get("output_content_base64", "")
    
    parsed_drugs = {}
    
    if output_exists and content_b64:
        score += 10
        feedback_parts.append("Report file created.")
        
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            
            # Check Header
            if "Lorlatinib" in content:
                score += 5
                feedback_parts.append("Report context correct.")
            
            # Parse Lines
            lines = content.split('\n')
            valid_colors = ["red", "orange", "yellow", "green", "grey", "gray"]
            
            for line in lines:
                line_lower = line.lower()
                # Simple regex to find "Drug: Color"
                match = re.search(r'(salbutamol|albuterol|theophylline|montelukast)\s*[:=-]\s*([a-z]+)', line_lower)
                if match:
                    drug = match.group(1)
                    if drug == 'albuterol': drug = 'salbutamol'
                    color = match.group(2)
                    
                    if color in valid_colors:
                        parsed_drugs[drug] = color
            
            # Check if all 3 drugs are present
            drugs_found = len(parsed_drugs)
            if drugs_found == 3:
                score += 25
                feedback_parts.append("All 3 drugs reported with valid colors.")
            elif drugs_found > 0:
                score += (drugs_found * 8)
                feedback_parts.append(f"Found {drugs_found}/3 drugs.")
            else:
                feedback_parts.append("Format error: Could not parse drug colors.")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing file: {e}")
    else:
        feedback_parts.append("Report file NOT found.")

    # =========================================================
    # CRITERION 2: VLM Trajectory Verification (60 points)
    # =========================================================
    # We need to verify the agent actually did the work using VLM
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's work in the 'Liverpool Cancer iChart' app.
    The task was to check interactions for 'Lorlatinib' with 'Salbutamol', 'Theophylline', and 'Montelukast'.
    
    Review the screenshots and answer:
    1. Did the agent select 'Lorlatinib' as the cancer drug?
    2. Did the agent navigate to the 'Respiratory' category or search for these drugs?
    3. Are interaction result colors visible for any of these drugs?
    
    Return JSON:
    {
        "lorlatinib_selected": boolean,
        "respiratory_drugs_checked": boolean,
        "colors_visible": boolean,
        "explanation": string
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("lorlatinib_selected"):
            vlm_score += 20
            feedback_parts.append("VLM confirmed Lorlatinib selection.")
        
        if parsed.get("respiratory_drugs_checked"):
            vlm_score += 20
            feedback_parts.append("VLM confirmed respiratory drugs checked.")
            
        if parsed.get("colors_visible"):
            vlm_score += 20
            feedback_parts.append("VLM confirmed interaction results visible.")
    else:
        # Fallback if VLM fails but file is perfect
        if len(parsed_drugs) == 3:
            vlm_score = 30 # Give partial credit if file is good but VLM failed
            feedback_parts.append("VLM verification skipped/failed, partial credit based on file.")

    score += vlm_score

    # Consistency Check (Bonus/Sanity)
    # If the file reports colors, but VLM says no drugs were checked, that's suspicious (hallucination)
    if len(parsed_drugs) == 3 and vlm_score < 20:
        score = min(score, 40) # Cap score if evidence contradicts file
        feedback_parts.append("WARNING: File content found but no visual evidence of work. Potential hallucination.")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }