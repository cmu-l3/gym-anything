#!/usr/bin/env python3
"""
Verifier for audit_chemo_regimen_interaction_ritonavir task.

Verification Strategy:
1. File Verification (40 pts):
   - Report file exists and was created during task.
   - Contains all 3 chemotherapy drugs.
   - Contains valid traffic light colors.
   - Vincristine + Ritonavir MUST be RED (well-known severe interaction).

2. VLM Trajectory Verification (60 pts):
   - Confirms the agent actually navigated to all three cancer drugs.
   - Confirms the agent viewed the Ritonavir interaction for each.
   - Prevents guessing colors without doing the work.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_chemo_regimen(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup score and feedback
    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. File Content Verification
    # ------------------------------------------------------------------
    report_content = ""
    try:
        # Get result JSON
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/sdcard/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(result_file.name)
        
        # Get actual report text
        if task_result.get("file_exists") and task_result.get("created_during_task"):
            report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env("/sdcard/ritonavir_chemo_audit.txt", report_file.name)
            with open(report_file.name, 'r') as f:
                report_content = f.read()
            os.unlink(report_file.name)
            
            score += 10
            feedback_parts.append("Report file created successfully.")
        else:
            feedback_parts.append("Report file not found or not created during task.")
            
    except Exception as e:
        feedback_parts.append(f"Error reading task files: {str(e)}")

    # Analyze Content
    drugs_found = []
    colors_valid = True
    vincristine_red = False
    
    valid_colors = ["red", "orange", "yellow", "green", "grey", "gray"]
    
    if report_content:
        lower_content = report_content.lower()
        
        # Check for drugs
        for drug in ["cyclophosphamide", "doxorubicin", "vincristine"]:
            if drug in lower_content:
                drugs_found.append(drug)
        
        if len(drugs_found) == 3:
            score += 10
            feedback_parts.append("All 3 drugs found in report.")
        else:
            feedback_parts.append(f"Missing drugs in report. Found: {drugs_found}")
            
        # Parse lines for format "Drug: Color"
        lines = report_content.split('\n')
        parsed_entries = {}
        for line in lines:
            if ':' in line:
                parts = line.split(':')
                key = parts[0].strip().lower()
                val = parts[1].strip().lower()
                parsed_entries[key] = val
        
        # Validate Colors
        for drug in drugs_found:
            color = parsed_entries.get(drug, "")
            if color not in valid_colors:
                colors_valid = False
                feedback_parts.append(f"Invalid color '{color}' for {drug}")
            
            # Specific Check: Vincristine + Ritonavir is a severe interaction (RED)
            if drug == "vincristine" and "red" in color:
                vincristine_red = True

        if colors_valid and len(drugs_found) == 3:
            score += 10
            feedback_parts.append("Valid color formats used.")
            
        if vincristine_red:
            score += 10
            feedback_parts.append("Correctly identified Vincristine interaction as RED.")
        else:
            feedback_parts.append("Failed to identify Vincristine interaction as RED.")

    # ------------------------------------------------------------------
    # 2. VLM Trajectory Verification
    # ------------------------------------------------------------------
    # We need to verify the agent actually navigated to these pages.
    # Sampling frames to see if they visited the drug pages.
    
    frames = sample_trajectory_frames(traj, n=8)
    
    prompt = """
    You are auditing an agent's interaction with the 'Liverpool Cancer iChart' app.
    The agent was supposed to check interactions for 3 drugs: Cyclophosphamide, Doxorubicin, and Vincristine against Ritonavir.
    
    Look at the sequence of screenshots.
    1. Do you see the 'Cancer Drugs' list being used?
    2. Do you see the details or co-medication selection for 'Cyclophosphamide'?
    3. Do you see the details or co-medication selection for 'Doxorubicin'?
    4. Do you see the details or co-medication selection for 'Vincristine'?
    5. Do you see a result screen showing 'Ritonavir' or 'HIV' medications?
    
    Output JSON:
    {
      "visited_cyclophosphamide": true/false,
      "visited_doxorubicin": true/false,
      "visited_vincristine": true/false,
      "checked_ritonavir": true/false,
      "reasoning": "Brief description of what is seen"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("visited_cyclophosphamide"): vlm_score += 15
        if parsed.get("visited_doxorubicin"): vlm_score += 15
        if parsed.get("visited_vincristine"): vlm_score += 15
        if parsed.get("checked_ritonavir"): vlm_score += 15
        
        feedback_parts.append(f"VLM Analysis: {parsed.get('reasoning')}")
    else:
        feedback_parts.append("VLM verification failed (technical error).")
    
    score += vlm_score
    feedback_parts.append(f"VLM Trajectory Score: {vlm_score}/60")

    # Final tally
    passed = score >= 85  # Strict threshold: needs almost perfect execution
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }