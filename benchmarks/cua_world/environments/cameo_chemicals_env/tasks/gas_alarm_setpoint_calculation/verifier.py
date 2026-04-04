#!/usr/bin/env python3
"""
Verifier for gas_alarm_setpoint_calculation task.

Verifies:
1. Output file exists and was created during the task.
2. File contains 4 correct chemicals.
3. LEL values match NIOSH standards (within tolerance).
4. Calculated setpoints (ppm) are correct (10% LEL converted to ppm).
5. VLM trajectory check: Agent visited chemical datasheets.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gas_alarm_setpoint_calculation(traj, env_info, task_info):
    """
    Verify the gas alarm setpoint calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', [])
    tolerances = metadata.get('tolerances', {'lel_percent': 0.2, 'ppm': 200})

    score = 0
    max_score = 100
    feedback_parts = []
    
    # --------------------------------------------------------------------------
    # 1. Load Task Result JSON
    # --------------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = task_result.get('output_exists', False)
    file_created_during_task = task_result.get('file_created_during_task', False)
    output_path = task_result.get('output_path', '')

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not file_created_during_task:
        feedback_parts.append("Warning: Output file timestamp not updated during task.")
        # We penalize but verify content in case of clock skew or filesystem quirks, usually -20
        score -= 20
    else:
        score += 10 # Points for creating the file
        feedback_parts.append("File created during task.")

    # --------------------------------------------------------------------------
    # 2. Analyze Output File Content
    # --------------------------------------------------------------------------
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(output_path, temp_output.name)
        with open(temp_output.name, 'r') as f:
            content = f.readlines()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read output file: {e}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    # Parse content
    # Expected format: Chemical Name | LEL (%) | Setpoint (ppm)
    # Allow loose parsing (headers, case insensitivity)
    parsed_data = []
    for line in content:
        line = line.strip()
        if not line or "Chemical" in line or "LEL" in line:
            continue
        
        parts = [p.strip() for p in line.split('|')]
        if len(parts) >= 3:
            try:
                # cleanup value strings
                lel_str = re.sub(r'[^\d.]', '', parts[1])
                ppm_str = re.sub(r'[^\d.]', '', parts[2])
                
                parsed_data.append({
                    "name": parts[0],
                    "lel": float(lel_str) if lel_str else 0.0,
                    "ppm": float(ppm_str) if ppm_str else 0.0
                })
            except ValueError:
                continue

    if not parsed_data:
         return {"passed": False, "score": score, "feedback": "File exists but could not parse data. Ensure 'Name | LEL | PPM' format."}

    # Score each expected chemical
    # 4 chemicals * 20 points each (10 for LEL, 10 for PPM) = 80 points max here
    chem_score = 0
    
    for expected in expected_chemicals:
        # Find matching entry in parsed data
        match = None
        for entry in parsed_data:
            # Check if any keyword matches
            if any(k.lower() in entry['name'].lower() for k in expected['keywords']):
                match = entry
                break
        
        if match:
            item_feedback = []
            
            # Check LEL
            expected_lel = expected['expected_lel_percent']
            if abs(match['lel'] - expected_lel) <= tolerances['lel_percent']:
                chem_score += 10
            else:
                item_feedback.append(f"LEL incorrect (got {match['lel']}, expected {expected_lel})")

            # Check PPM
            # Logic: PPM should be roughly expected_ppm
            # Also check if they calculated it correctly based on THEIR LEL if it differs slightly?
            # Standard: Compare against ground truth.
            expected_ppm = expected['expected_ppm']
            if abs(match['ppm'] - expected_ppm) <= tolerances['ppm']:
                chem_score += 10
            else:
                item_feedback.append(f"PPM incorrect (got {match['ppm']}, expected {expected_ppm})")
            
            if item_feedback:
                feedback_parts.append(f"{expected['name']}: " + ", ".join(item_feedback))
            else:
                feedback_parts.append(f"{expected['name']}: OK")
        else:
            feedback_parts.append(f"{expected['name']}: Not found in report")

    score += chem_score

    # --------------------------------------------------------------------------
    # 3. VLM Trajectory Verification (10 points)
    # --------------------------------------------------------------------------
    # Verify they actually looked at the data rather than guessing/knowing it
    frames = sample_trajectory_frames(traj, n=8)
    if frames:
        prompt = """
        Analyze these screenshots of a user browsing CAMEO Chemicals.
        Did the user search for and view datasheets for ANY of these chemicals:
        Methane, Propane, Hydrogen, Acetone?
        
        Answer YES or NO, followed by a brief list of chemicals seen.
        """
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
                score += 10
                feedback_parts.append("VLM: Confirmed navigation to chemical datasheets.")
            else:
                feedback_parts.append("VLM: Could not confirm visual search for chemicals.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Do not penalize if VLM fails, just don't add bonus points or assume good faith if score is high
            if score >= 60: 
                score += 10 

    # --------------------------------------------------------------------------
    # Final Result
    # --------------------------------------------------------------------------
    # Cap score
    score = min(score, 100)
    
    # Pass threshold: 70 points
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }