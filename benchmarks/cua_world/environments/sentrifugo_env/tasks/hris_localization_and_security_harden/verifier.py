#!/usr/bin/env python3
"""
Verifier for hris_localization_and_security_harden task.

This task utilizes a robust hybrid verification strategy:
1. Programmatic DB Check: Verifies the exact state of the "main_modules" table to ensure 
   Assets and Expenses are deactivated (20 pts each), while strongly penalizing the 
   deactivation of core modules (Anti-Gaming AP-8).
2. VLM Trajectory Check: Verifies the application of Localization (Timezone, Date Format) 
   and Password Policy settings by analyzing the visual trajectory of the agent's actions,
   as Sentrifugo's internal config structures for these vary.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hris_localization_security(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in env."}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Evaluate Module Deactivations (Programmatic Database)
    # ---------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hris_security_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read exported result: {e}")
        result = {"modules": {}}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    modules = result.get('modules', {})
    
    # Check core module integrity first (Anti-Gaming AP-8 check)
    core_modules = ['Employees', 'Leave Management', 'Time', 'Organization']
    deactivated_core = [m for m in core_modules if str(modules.get(m, '1')) == '0']
    
    if deactivated_core:
        feedback_parts.append(f"CRITICAL FAILURE: Agent deactivated core modules ({', '.join(deactivated_core)}).")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Verify target modules
    if str(modules.get('Assets', '1')) == '0':
        score += 20
        feedback_parts.append("Assets module deactivated (+20)")
    else:
        feedback_parts.append("Assets module NOT deactivated")

    if str(modules.get('Expenses', '1')) == '0':
        score += 20
        feedback_parts.append("Expenses module deactivated (+20)")
    else:
        feedback_parts.append("Expenses module NOT deactivated")

    # ---------------------------------------------------------
    # 2. Evaluate Localization & Security (VLM Trajectory Analysis)
    # ---------------------------------------------------------
    if not query_vlm:
        feedback_parts.append("VLM query not available for UI verification.")
    else:
        # Import dynamic framework helpers
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=8)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            Examine these screenshots from an agent configuring the Sentrifugo HRMS global settings.
            Did the agent successfully apply the following settings? Look for filled forms, dropdown selections, and "Save" operations in the 'Site Config' area.
            Return a JSON object with strict boolean values indicating if there is clear visual evidence of these settings being applied:
            {
              "timezone_europe_berlin": true/false,
              "date_format_ddmmyyyy": true/false,
              "password_length_12": true/false,
              "password_expiry_90": true/false,
              "password_req_upper": true/false,
              "password_req_lower": true/false,
              "password_req_number": true/false,
              "password_req_special": true/false
            }
            """
            
            vlm_response = query_vlm(prompt=prompt, images=images)
            vlm_data = vlm_response.get('parsed', {})
            
            # Localization (30 points)
            if vlm_data.get('timezone_europe_berlin'):
                score += 15
                feedback_parts.append("Timezone set to Europe/Berlin (+15)")
            else:
                feedback_parts.append("Timezone not configured correctly")
                
            if vlm_data.get('date_format_ddmmyyyy'):
                score += 15
                feedback_parts.append("Date format set to DD/MM/YYYY (+15)")
            else:
                feedback_parts.append("Date format not configured correctly")
                
            # Password Constraints (30 points)
            if vlm_data.get('password_length_12') and vlm_data.get('password_expiry_90'):
                score += 15
                feedback_parts.append("Password Length (12) and Expiry (90) configured (+15)")
            else:
                feedback_parts.append("Password Length/Expiry missing or incorrect")
                
            # Complexity (15 points for all 4)
            complexities = [
                vlm_data.get('password_req_upper'),
                vlm_data.get('password_req_lower'),
                vlm_data.get('password_req_number'),
                vlm_data.get('password_req_special')
            ]
            
            complexity_score = sum([3.75 for c in complexities if c])
            score += complexity_score
            if complexity_score == 15.0:
                feedback_parts.append("All character complexities enforced (+15)")
            elif complexity_score > 0:
                feedback_parts.append(f"Partial character complexities enforced (+{complexity_score})")
            else:
                feedback_parts.append("Character complexities not enforced")
                
        except Exception as e:
            logger.error(f"VLM trajectory analysis failed: {e}")
            feedback_parts.append(f"VLM analysis failed: {e}")

    # ---------------------------------------------------------
    # 3. Final Scoring
    # ---------------------------------------------------------
    score = int(score) # Floor rounding for partial complexity
    pass_threshold = task_info.get('metadata', {}).get('pass_threshold', 70)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }