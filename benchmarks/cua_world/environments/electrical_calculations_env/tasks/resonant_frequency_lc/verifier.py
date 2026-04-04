#!/usr/bin/env python3
"""
Verifier for Resonant Frequency LC Circuit Calculation task.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resonant_frequency(traj, env_info, task_info):
    """
    Verifies the resonant frequency calculation task.
    
    Score breakdown (100 pts total):
    1. Result file exists and is valid (10 pts)
    2. Result value accuracy (25 pts loose, +15 pts tight)
    3. Anti-gaming: File created during task (5 pts)
    4. VLM: Navigation to correct calculator (15 pts)
    5. VLM: Correct inputs entered (10 pts)
    6. VLM: Result displayed on screen (10 pts)
    7. App running at end (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_freq = metadata.get('expected_frequency_hz', 5032.9)
    tolerance_loose = metadata.get('tolerance_loose_percent', 5.0)  # +/- 5%
    tolerance_tight = metadata.get('tolerance_tight_percent', 2.0)  # +/- 2%

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Programmatic Verification (File & App State)
    # ------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Fetch result JSON
        copy_from_env("/sdcard/tasks/resonant_frequency_lc/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    file_exists = result_data.get('file_exists', False)
    file_fresh = result_data.get('file_fresh', False)
    file_content = result_data.get('file_content', "").strip()
    app_running = result_data.get('app_running', False)

    # Check 1: App running (10 pts)
    if app_running:
        score += 10
        feedback_parts.append("App was running at end")

    # Check 2: File timestamp (5 pts)
    if file_fresh:
        score += 5
        feedback_parts.append("Result file created during task")
    elif file_exists:
        feedback_parts.append("WARNING: Result file timestamp predates task start")

    # Check 3: File existence and Content parsing (10 pts)
    val_hz = None
    if file_exists and file_content:
        score += 10
        feedback_parts.append("Result file exists")
        
        # Parse content
        # Remove non-numeric chars except . and spaces, handle units manually if needed
        # Expected formats: "5032.9", "5033 Hz", "5.033 kHz"
        
        try:
            # Simple regex to find the first number
            match = re.search(r'([\d\.]+)', file_content)
            if match:
                raw_val = float(match.group(1))
                
                # Check for units in the string to convert
                lower_content = file_content.lower()
                if 'khz' in lower_content:
                    val_hz = raw_val * 1000
                elif 'mhz' in lower_content:
                    val_hz = raw_val * 1000000
                else:
                    # Assume Hz if no prefix, but handle small numbers that might be kHz implies
                    # If user wrote "5.033" without unit, it's ambiguous. 
                    # If it's close to 5.033, assume they meant kHz?
                    # Or strict: if < 100 and expected is 5000, verify logic.
                    # Given the prompt asks for Hz, we assume raw number is Hz.
                    # However, to be generous, if they wrote 5.033 and meant kHz, we can check that.
                    
                    if raw_val < 100 and expected_freq > 1000:
                        # Likely kHz provided as bare number? Let's give benefit of doubt if it matches scaled
                        if abs(raw_val * 1000 - expected_freq) / expected_freq < 0.1:
                            val_hz = raw_val * 1000
                            feedback_parts.append("(Interpreted small value as kHz)")
                        else:
                            val_hz = raw_val
                    else:
                        val_hz = raw_val
            else:
                feedback_parts.append("Could not parse number from file")
        except ValueError:
            feedback_parts.append("Error parsing numeric value")

    # Check 4: Accuracy (40 pts max)
    if val_hz is not None:
        error_pct = abs(val_hz - expected_freq) / expected_freq * 100
        
        if error_pct <= tolerance_tight:
            score += 40
            feedback_parts.append(f"Value {val_hz:.1f} Hz is accurate (within {tolerance_tight}%)")
        elif error_pct <= tolerance_loose:
            score += 25
            feedback_parts.append(f"Value {val_hz:.1f} Hz is acceptable (within {tolerance_loose}%)")
        else:
            feedback_parts.append(f"Value {val_hz:.1f} Hz is incorrect (Expected ~{expected_freq} Hz)")

    # ------------------------------------------------------------------
    # 2. VLM Verification (Trajectory)
    # ------------------------------------------------------------------
    # 35 points allocated to VLM
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    # Prompt for VLM
    # We want to check:
    # 1. Did they navigate to Resonant Frequency calculator? (15)
    # 2. Did they enter 10 mH and 100 nF? (10)
    # 3. Is the result visible on screen? (10)
    
    vlm_prompt = """
    You are verifying an agent performing an electrical calculation task on an Android app.
    The goal is to calculate Resonant Frequency with L=10mH and C=100nF.
    
    Analyze the screenshots provided.
    
    1. NAVIGATION: Did the agent navigate to a screen titled "Resonant Frequency" or similar LC circuit calculator?
    2. INPUTS: Can you see the inputs "10" (with mH unit) and "100" (with nF unit) entered in the fields?
    3. RESULT: Is a result displayed on the screen? (Expected result is around 5033 Hz or 5.03 kHz).
    
    Respond in JSON format:
    {
        "navigated_to_calculator": true/false,
        "inputs_visible_and_correct": true/false,
        "result_visible": true/false,
        "confidence": "high/medium/low",
        "reasoning": "..."
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('navigated_to_calculator'):
            score += 15
            feedback_parts.append("VLM: Navigated to calculator")
            
        if parsed.get('inputs_visible_and_correct'):
            score += 10
            feedback_parts.append("VLM: Inputs verified")
            
        if parsed.get('result_visible'):
            score += 10
            feedback_parts.append("VLM: Result visible on screen")
    else:
        feedback_parts.append("VLM verification failed or inconclusive")

    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    passed = score >= 60 and val_hz is not None and abs(val_hz - expected_freq) / expected_freq <= tolerance_loose
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }