#!/usr/bin/env python3
"""
Verifier for select_safe_implant_length task.

Criteria:
1. Safety Compliance (CRITICAL): Reported safety gap >= 2.0mm.
2. Evidence Existence: Screenshot and text file created.
3. VLM Verification: Screenshot shows implant, nerve canal, and measurement.
4. Optimization: Implant length is reasonable for available bone (not excessively short).
"""

import json
import logging
import os
import tempfile
from pathlib import Path

# Gym Anything utilities
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_safe_implant_length(traj, env_info, task_info):
    """
    Verify the implant placement task.
    """
    # 1. Setup and Retrieve Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_gap = metadata.get('min_safety_gap_mm', 2.0)
    
    # Retrieve JSON result from Windows VM
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Extract values
    parsed = result.get('parsed_data', {})
    safety_gap = parsed.get('safety_gap', 0.0)
    available_height = parsed.get('available_height', 0.0)
    implant_length = parsed.get('implant_length', 0.0)
    screenshot_exists = result.get('screenshot_exists', False)
    
    score = 0
    feedback_parts = []
    
    # 2. Programmatic Verification (Data File)
    
    # Check 1: Data file existence (10 pts)
    if result.get('data_file_exists'):
        score += 10
        feedback_parts.append("Data file created.")
    else:
        feedback_parts.append("Data file missing.")

    # Check 2: Safety Compliance (40 pts) - CRITICAL
    # If gap is reported as < 2.0, immediate fail on this criterion
    if safety_gap >= min_gap:
        score += 40
        feedback_parts.append(f"Safety gap compliant ({safety_gap}mm >= {min_gap}mm).")
    else:
        feedback_parts.append(f"SAFETY VIOLATION: Gap {safety_gap}mm is less than {min_gap}mm.")

    # Check 3: Optimization/Reasonableness (10 pts)
    # Check if calculation holds: Length + Gap ~= Available (+/- tolerance)
    # And check if they picked a reasonable length (e.g., didn't pick 6mm when 12mm was available)
    calc_height = implant_length + safety_gap
    if abs(calc_height - available_height) < 1.5:
        # Math checks out
        # Check if they wasted too much bone (e.g., gap > 4mm implies they could have used a longer implant)
        if safety_gap <= 4.0:
            score += 10
            feedback_parts.append("Implant length optimized.")
        else:
            feedback_parts.append("Implant potentially too short (excessive safety gap).")
    else:
        feedback_parts.append("Measurement inconsistency: Height != Length + Gap.")

    # 3. VLM Verification (Visual Evidence)
    
    # Retrieve the specific evidence screenshot created by the agent
    # We use copy_from_env for the file the agent saved
    evidence_path = result.get('screenshot_path')
    vlm_score = 0
    
    if screenshot_exists and evidence_path:
        local_evidence = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            copy_from_env(evidence_path, local_evidence)
            
            # VLM Prompt
            prompt = """
            Verify this dental implant planning screenshot.
            1. Is there a dental implant visible (looks like a screw/fixture)?
            2. Is there a nerve canal traced or marked (usually a red or colored tube/line in the bone)?
            3. Is there a measurement line drawn between the bottom of the implant and the nerve?
            
            Return JSON:
            {
                "implant_visible": true/false,
                "nerve_visible": true/false,
                "measurement_visible": true/false
            }
            """
            
            vlm_res = query_vlm(image=local_evidence, prompt=prompt)
            if vlm_res.get('success'):
                vlm_data = vlm_res.get('parsed', {})
                if vlm_data.get('implant_visible'): vlm_score += 15
                if vlm_data.get('nerve_visible'): vlm_score += 15
                if vlm_data.get('measurement_visible'): vlm_score += 10
                feedback_parts.append("Visual evidence verified.")
            else:
                feedback_parts.append("VLM analysis failed.")
                
        except Exception as e:
            feedback_parts.append(f"Failed to copy evidence screenshot: {e}")
        finally:
            if os.path.exists(local_evidence):
                os.unlink(local_evidence)
    else:
        feedback_parts.append("Evidence screenshot missing.")

    score += vlm_score

    # Final Pass Logic
    # Must pass safety check AND get at least 70 points
    passed = (safety_gap >= min_gap) and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }