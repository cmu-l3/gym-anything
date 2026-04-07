#!/usr/bin/env python3
"""Verifier for model_bess_degradation_and_warranty task.

Checks the degradation curve physics, simulation length, and threshold logic.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_bess_degradation_and_warranty(traj, env_info, task_info):
    """Verify the battery degradation simulation was completed successfully.

    Scoring (100 points total, Pass Threshold: 75):
    - File Existence & Format: 10 points
    - Time Validity (Created during task): 10 points
    - Artifact Evidence (SAM or PySAM used): 15 points
    - Simulation Length (20 years extracted): 15 points
    - Degradation Physics (Monotonically decreasing from >90%): 25 points
    - Threshold Logic (Correct year < 80%): 25 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_years = metadata.get('expected_years', 20)
    threshold_pct = metadata.get('threshold_pct', 80.0)

    score = 0
    feedback_parts = []

    # 1. Read export wrapper results
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export wrapper result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # Validate file existence & time validity
    file_exists = export_result.get('file_exists')
    if file_exists:
        score += 10
        feedback_parts.append("Report JSON exists")
    else:
        feedback_parts.append("Report JSON NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    if export_result.get('file_modified'):
        score += 10
        feedback_parts.append("File created/modified during task")
    else:
        feedback_parts.append("File was NOT modified during task (possible bypass)")

    if export_result.get('artifacts_exist'):
        score += 15
        feedback_parts.append("Evidence of Python/SAM usage found")
    else:
        feedback_parts.append("No clear evidence of Python/SAM usage")

    # 2. Copy the actual agent output JSON to perform physics and array validation
    agent_output_path = "/home/ga/Documents/SAM_Projects/battery_degradation_report.json"
    temp_output_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env(agent_output_path, temp_output_file.name)
        with open(temp_output_file.name, 'r') as f:
            agent_data = json.load(f)
    except json.JSONDecodeError:
        feedback_parts.append("Failed to parse report JSON (invalid format)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    except Exception as e:
        feedback_parts.append(f"Failed to read report JSON: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_output_file.name):
            os.unlink(temp_output_file.name)

    # Extract target array and threshold year
    soh_array = agent_data.get('yearly_state_of_health_pct', [])
    reported_year = agent_data.get('year_crossing_80_pct')

    # Simulation Length Check
    if not isinstance(soh_array, list):
        feedback_parts.append("yearly_state_of_health_pct is not a list")
    elif len(soh_array) == expected_years:
        score += 15
        feedback_parts.append("Array has exactly 20 elements")
    else:
        feedback_parts.append(f"Array has {len(soh_array)} elements (expected {expected_years})")

    # Degradation Physics Check
    if isinstance(soh_array, list) and len(soh_array) > 0:
        try:
            # Ensure all values are numeric floats
            soh_array = [float(v) for v in soh_array]
            
            # Start high, end low check
            start_val = soh_array[0]
            end_val = soh_array[-1]
            
            # Decreasing trend check (allow very slight numerical jitter up to 0.1%)
            is_decreasing = all(soh_array[i] <= soh_array[i-1] + 0.1 for i in range(1, len(soh_array)))
            
            if start_val > 90.0 and end_val < start_val and is_decreasing:
                score += 25
                feedback_parts.append(f"Physically plausible degradation (Start: {start_val:.1f}%, End: {end_val:.1f}%)")
            else:
                feedback_parts.append(f"Degradation physics failed: starts={start_val}, ends={end_val}, decreasing={is_decreasing}")
                
        except (ValueError, TypeError):
            feedback_parts.append("Non-numeric values found in State of Health array")
            
    # Threshold Logic Check
    if isinstance(soh_array, list) and len(soh_array) > 0:
        try:
            expected_crossing = None
            for i, val in enumerate(soh_array):
                if float(val) < threshold_pct:
                    expected_crossing = i + 1 # 1-based year
                    break
                    
            if expected_crossing == reported_year:
                score += 25
                feedback_parts.append(f"Threshold year correctly identified as {reported_year}")
            else:
                feedback_parts.append(f"Threshold mismatch: expected {expected_crossing}, agent reported {reported_year}")
        except (ValueError, TypeError):
            feedback_parts.append("Could not calculate threshold due to bad array values")

    # Evaluate Pass/Fail
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }