#!/usr/bin/env python3
"""
Verifier for 555 Timer Astable Task.

Checks:
1. Result file existence and freshness (anti-gaming).
2. Correctness of calculated values (Frequency, Duty Cycle, Time High, Time Low).
3. VLM verification of app usage (trajectory analysis).
"""

import json
import re
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_555_timer_astable(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Metadata for Ground Truth
    metadata = task_info.get('metadata', {})
    expected_freq = metadata.get('expected_frequency', 1.38)
    expected_duty = metadata.get('expected_duty_cycle', 54.81)
    expected_high = metadata.get('expected_time_high_ms', 395.01)
    expected_low = metadata.get('expected_time_low_ms', 325.71)

    # 2. Check File Status (20 points)
    if not result_data.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Results file /sdcard/555_timer_results.txt not found."}
    
    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Results file was not created during the task session (anti-gaming check failed)."}
    
    score += 20
    feedback_parts.append("File created successfully (+20)")

    # 3. Parse and Verify Values (40 points)
    content = result_data.get('file_content', '')
    
    # Regex patterns to find values regardless of case or slight formatting diffs
    # Looks for "Label: Number" pattern
    patterns = {
        'freq': r'Frequency_Hz[:\s]+([\d\.]+)',
        'duty': r'Duty_Cycle_Percent[:\s]+([\d\.]+)',
        'high': r'Time_High_ms[:\s]+([\d\.]+)',
        'low': r'Time_Low_ms[:\s]+([\d\.]+)'
    }
    
    extracted = {}
    for key, pat in patterns.items():
        match = re.search(pat, content, re.IGNORECASE)
        if match:
            try:
                extracted[key] = float(match.group(1))
            except ValueError:
                extracted[key] = None
        else:
            extracted[key] = None

    # Scoring Logic for Values
    val_score = 0
    
    # Frequency (10 pts)
    if extracted['freq'] is not None and abs(extracted['freq'] - expected_freq) < 0.1:
        val_score += 10
    else:
        feedback_parts.append(f"Freq incorrect: got {extracted['freq']}, expected {expected_freq}")

    # Duty Cycle (10 pts)
    if extracted['duty'] is not None and abs(extracted['duty'] - expected_duty) < 2.0:
        val_score += 10
    else:
        feedback_parts.append(f"Duty incorrect: got {extracted['duty']}, expected {expected_duty}")

    # Time High (10 pts)
    if extracted['high'] is not None and abs(extracted['high'] - expected_high) < 20.0:
        val_score += 10
    else:
        feedback_parts.append(f"T_High incorrect: got {extracted['high']}, expected {expected_high}")
        
    # Time Low (10 pts)
    if extracted['low'] is not None and abs(extracted['low'] - expected_low) < 20.0:
        val_score += 10
    else:
        feedback_parts.append(f"T_Low incorrect: got {extracted['low']}, expected {expected_low}")

    score += val_score
    if val_score == 40:
        feedback_parts.append("All values correct (+40)")
    else:
        feedback_parts.append(f"Value check score: {val_score}/40")


    # 4. VLM Trajectory Verification (40 points)
    # Ensure the agent actually used the app and didn't just write the file
    frames = sample_trajectory_frames(traj, n=5)
    
    prompt = """
    You are verifying an agent's work on an Android app.
    The task is to use the "Electrical Engineering Calculations" app to calculate 555 Timer Astable parameters.
    
    Look at the sequence of screenshots. Answer these questions:
    1. Is the "Electrical Engineering Calculations" app visible?
    2. Did the agent navigate to a "555 Timer" or "Astable" calculation screen?
    3. Can you see input fields for R1, R2, and C being filled (Values should be 10k, 47k, 10uF)?
    
    Return JSON:
    {
        "app_visible": boolean,
        "calculator_reached": boolean,
        "inputs_visible": boolean,
        "confidence": "low|medium|high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    vlm_score = 0
    if vlm_result['success']:
        parsed = vlm_result['parsed']
        if parsed.get('app_visible'):
            vlm_score += 10
        if parsed.get('calculator_reached'):
            vlm_score += 15
        if parsed.get('inputs_visible'):
            vlm_score += 15
            
        score += vlm_score
        feedback_parts.append(f"Visual verification score: {vlm_score}/40")
    else:
        feedback_parts.append("Visual verification failed (VLM error)")

    # Final Pass Determination
    # Must have file created (20) + at least one correct value (10) + visual confirmation of app use (at least 10)
    # Total threshold > 60
    passed = (score >= 60) and result_data.get('file_created_during_task', False) and (val_score > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }