#!/usr/bin/env python3
"""
Verifier for create_latent_print_logger task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. File Structure: Both .py and .talon files exist in `fingerprint_logger` directory (15 pts)
2. Talon Commands: .talon file correctly maps all 6 required "tag" voice commands (15 pts)
3. Action Executable: Action executes successfully without raising exceptions during programmatic test (10 pts)
4. CSV Header: Action writes `Timestamp,X,Y,Feature` header correctly (10 pts)
5. Correct Feature Logged: CSV contains the programmatic feature string passed to the action (10 pts)
6. Dynamic Coords Logged: CSV successfully logs the exact dynamically captured X,Y coordinates where the mouse was moved (30 pts)
7. VLM Verification: Agent trajectory shows writing code in a text editor (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_latent_print_logger(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check Talon process status
    if not result.get('talon_running', False):
        feedback_parts.append("⚠️ Talon process was not running at the end of the task")
    
    # ================================================================
    # CRITERION 1: File Structure (15 points)
    # ================================================================
    py_exists = result.get('py_exists', False)
    talon_exists = result.get('talon_exists', False)
    
    if py_exists and talon_exists:
        score += 15
        feedback_parts.append("✅ Correct file structure created")
    else:
        feedback_parts.append("❌ Missing required .py or .talon files")
        
    # ================================================================
    # CRITERION 2: Talon Commands Mapped (15 points)
    # ================================================================
    talon_content = result.get('talon_content', '').lower()
    metadata = task_info.get('metadata', {})
    expected_commands = metadata.get('expected_commands', [])
    
    commands_found = 0
    for cmd in expected_commands:
        if cmd.lower() in talon_content:
            commands_found += 1
            
    if commands_found == len(expected_commands) and len(expected_commands) > 0:
        score += 15
        feedback_parts.append("✅ All Talon voice commands mapped")
    elif commands_found > 0:
        score += int(15 * (commands_found / len(expected_commands)))
        feedback_parts.append(f"⚠️ Only {commands_found}/{len(expected_commands)} commands mapped")
    else:
        feedback_parts.append("❌ No voice commands mapped")
        
    # ================================================================
    # CRITERIA 3-6: Execution & Data Logging Validation
    # ================================================================
    csv_exists = result.get('csv_exists', False)
    csv_content = result.get('csv_content', '')
    error_exists = result.get('error_exists', False)
    error_content = result.get('error_content', '')
    
    found_test_marker = False
    found_coords = False

    if error_exists and error_content:
        feedback_parts.append(f"❌ Action threw exception during test execution: {error_content}")
    elif csv_exists:
        score += 10  # Action Executable points
        feedback_parts.append("✅ Action executed programmatically without exceptions")
    
    if csv_exists:
        lines = csv_content.strip().split('\n')
        
        # Check Header (10 points)
        if len(lines) > 0 and 'timestamp,x,y,feature' in lines[0].replace(' ', '').lower():
            score += 10
            feedback_parts.append("✅ CSV header format correct")
        else:
            feedback_parts.append("❌ CSV header missing or incorrect")
            
        # Check Data Content
        for line in lines[1:]:
            parts = [p.strip() for p in line.split(',')]
            if len(parts) >= 4:
                # Expected format: Timestamp, 512, 384, TestVerificationMarker
                x_val = parts[1]
                y_val = parts[2]
                feature_val = parts[3]
                
                if feature_val == "TestVerificationMarker":
                    found_test_marker = True
                    try:
                        x_num = float(x_val)
                        y_num = float(y_val)
                        # We injected a move to 512, 384 exactly
                        if abs(x_num - 512) < 5 and abs(y_num - 384) < 5:
                            found_coords = True
                    except ValueError:
                        pass
                        
        if found_test_marker:
            score += 10
            feedback_parts.append("✅ Correct programmatic feature argument logged")
        else:
            feedback_parts.append("❌ Expected feature string not logged in CSV")
            
        if found_coords:
            score += 30
            feedback_parts.append("✅ Dynamic X/Y coordinates successfully captured and logged")
        else:
            feedback_parts.append("❌ Coordinates not correctly logged from live mouse position")
            
    else:
        feedback_parts.append("❌ CSV report file was not created by the action")

    # ================================================================
    # CRITERION 7: VLM Trajectory Verification (10 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            if frames and final:
                vlm_result = query_vlm(
                    images=frames + [final],
                    prompt="""Analyze the trajectory frames and final screenshot of a computer agent.
TASK: Create a Talon voice command package that logs fingerprint minutiae to a CSV.
Check if the agent used a text editor to write the Python and Talon files.

Respond in JSON format:
{
    "wrote_python_code": true/false,
    "wrote_talon_code": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""
                )
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('wrote_python_code') and parsed.get('wrote_talon_code'):
                        score += 10
                        feedback_parts.append("✅ VLM confirmed trajectory shows coding activity")
                    else:
                        feedback_parts.append("⚠️ VLM did not clearly see coding in trajectory")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")

    # Pass condition requires logging the dynamic coordinates
    passed = score >= 70 and found_coords
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }