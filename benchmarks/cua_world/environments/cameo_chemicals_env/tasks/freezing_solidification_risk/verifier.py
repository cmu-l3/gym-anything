#!/usr/bin/env python3
"""
Verifier for Freezing/Solidification Risk Assessment Task.

Scoring Criteria:
1. File Existence & Validity (15 pts): File exists and created during task.
2. Data Extraction Accuracy (50 pts): 10 pts per chemical for correct Melting Point.
3. Logical Application (15 pts): Correct YES/NO classification based on threshold.
4. Summary Accuracy (10 pts): Correct total count and priority list.
5. VLM Verification (10 pts): Trajectory shows CAMEO Chemicals interaction.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

# Import VLM utils (assumed available in environment)
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_freezing_solidification_risk(traj, env_info, task_info):
    """
    Verify the freezing risk report content and agent behavior.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    chemicals_data = metadata.get('chemicals', {})
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence (15 pts) ---
    report_exists = result.get('report_exists', False)
    created_during = result.get('created_during_task', False)
    content = result.get('report_content_json_string', "")  # This is the actual text content

    if report_exists and created_during:
        score += 15
        feedback_parts.append("Report file created successfully")
    elif report_exists:
        score += 5
        feedback_parts.append("Report exists but timestamp suggests pre-existence")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found"}

    if not content:
        return {"passed": False, "score": score, "feedback": "Report file is empty"}

    # --- Parse Report Content ---
    lines = content.split('\n')
    parsed_data = {}
    total_at_risk_reported = None
    priority_list_reported = []

    for line in lines:
        line = line.strip()
        # Parse chemical lines
        if line.startswith("CHEMICAL:"):
            # Format: CHEMICAL: Name | MELTING_POINT_C: Value | SOLIDIFIES_AT_MINUS15: YES/NO
            try:
                parts = line.split('|')
                name_part = parts[0].split(':')[1].strip()
                
                # Extract value
                mp_str = parts[1].split(':')[1].strip()
                # Handle potential ranges or text in value (agent might write "-95 to -98")
                # Regex to find the first float/int
                mp_match = re.search(r'[-]?\d+\.?\d*', mp_str)
                mp_val = float(mp_match.group()) if mp_match else None
                
                solid_part = parts[2].split(':')[1].strip().upper()
                
                # Normalize name for matching
                clean_name = None
                for known_name in chemicals_data.keys():
                    if known_name.lower() in name_part.lower():
                        clean_name = known_name
                        break
                
                if clean_name:
                    parsed_data[clean_name] = {
                        "mp": mp_val,
                        "solid": solid_part
                    }
            except Exception:
                continue
                
        # Parse summary lines
        elif line.startswith("TOTAL_AT_RISK:"):
            try:
                total_at_risk_reported = int(re.search(r'\d+', line).group())
            except:
                pass
        elif line.startswith("PRIORITY_MOVE_LIST:"):
            list_part = line.split(':', 1)[1]
            priority_list_reported = [x.strip().lower() for x in list_part.split(',')]

    # --- Criterion 2: Data Accuracy (50 pts - 10 per chemical) ---
    mp_score = 0
    valid_chems = ["Acetic acid, glacial", "Acetone", "Nitrobenzene", "Toluene", "Phenol"]
    
    for chem in valid_chems:
        if chem in parsed_data:
            data = parsed_data[chem]
            expected = chemicals_data[chem]
            val = data.get("mp")
            
            if val is not None:
                # Check range (allow strict or slight looseness)
                if expected["mp_min"] - 2 <= val <= expected["mp_max"] + 2:
                    mp_score += 10
                else:
                    feedback_parts.append(f"{chem} MP incorrect ({val}, expected ~{expected['mp_min']})")
            else:
                feedback_parts.append(f"{chem} MP unreadable")
        else:
            feedback_parts.append(f"{chem} missing from report")
            
    score += mp_score
    feedback_parts.append(f"Data accuracy: {mp_score}/50 pts")

    # --- Criterion 3: Logical Application (15 pts) ---
    logic_score = 0
    correct_calls = 0
    for chem in valid_chems:
        if chem in parsed_data:
            data = parsed_data[chem]
            expected_solid = "YES" if chemicals_data[chem]["solidifies"] else "NO"
            if data.get("solid") == expected_solid:
                correct_calls += 1
            elif data.get("solid") in ["YES", "NO"]:
                 # Check if agent was internally consistent even if MP was wrong?
                 # Strict checking against ground truth is better for this task
                 pass

    if correct_calls == 5:
        logic_score = 15
    else:
        logic_score = int((correct_calls / 5) * 15)
        
    score += logic_score
    feedback_parts.append(f"Logic checks: {correct_calls}/5 correct")

    # --- Criterion 4: Summary Accuracy (10 pts) ---
    summary_score = 0
    expected_total = metadata.get("expected_total_risk", 3)
    
    if total_at_risk_reported == expected_total:
        summary_score += 5
    
    # Check priority list
    # Expected: Acetic acid, Nitrobenzene, Phenol
    expected_priority = ["acetic", "nitrobenzene", "phenol"]
    list_correct = True
    
    # Check if all expected are in reported
    for item in expected_priority:
        found = False
        for rep in priority_list_reported:
            if item in rep:
                found = True
                break
        if not found:
            list_correct = False
    
    # Check if no extras (like Acetone)
    for rep in priority_list_reported:
        if "acetone" in rep or "toluene" in rep:
            list_correct = False
            
    if list_correct and len(priority_list_reported) >= 3:
        summary_score += 5
        
    score += summary_score

    # --- Criterion 5: VLM Verification (10 pts) ---
    # Verify agent actually browsed the site
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=5)
        prompt = (
            "Does the user appear to be searching for chemicals or viewing chemical datasheets "
            "on the CAMEO Chemicals website? Look for search results or 'Physical Properties' tables."
            "Answer YES or NO."
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if "YES" in vlm_res.get("response", "").upper():
                vlm_score = 10
            else:
                feedback_parts.append("VLM did not verify CAMEO usage")
        except Exception:
            # Fallback if VLM fails: give points if file content was perfect
            if mp_score >= 40: 
                vlm_score = 10
    else:
        # Fallback if VLM not installed
        vlm_score = 10 if mp_score > 0 else 0
        
    score += vlm_score
    
    # --- Final Result ---
    # Pass if score >= 60 AND file was created AND logic was decent
    passed = (score >= 60) and report_exists and (correct_calls >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }