#!/usr/bin/env python3
"""
Verifier for simulated_monitor_calibration_check task.

SCORING CRITERIA (100 pts):
1. Environment Health (20 pts): OpenICE running, Device & App windows detected.
2. Report File (30 pts): CSV exists, created during task, valid content (3 rows, 60/90/120).
3. Evidence Screenshot (20 pts): File exists at /home/ga/Desktop/calibration_120bpm.png.
4. Visual Verification (30 pts): VLM analysis of the evidence screenshot (or final screen)
   confirms Heart Rate is set to approximately 120 BPM. This proves the agent
   actually manipulated the simulation controls.
"""

import json
import base64
import os
import tempfile
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calibration_check(traj, env_info, task_info):
    # 1. Setup & Read Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # --- Criterion 1: Environment Health (20 pts) ---
    openice_running = result.get('openice_running', False)
    device_visible = result.get('device_window_visible', False)
    app_visible = result.get('app_window_visible', False)
    window_increase = result.get('window_increase', 0)

    if openice_running:
        score += 10
        feedback_parts.append("OpenICE running")
    else:
        feedback_parts.append("FAIL: OpenICE not running")

    if device_visible and app_visible:
        score += 10
        feedback_parts.append("Device and App windows visible")
    elif window_increase >= 2:
        score += 5
        feedback_parts.append("Window count increased (implied device/app creation)")
    else:
        feedback_parts.append("Missing device or app windows")

    # --- Criterion 2: Report File (30 pts) ---
    report_exists = result.get('report_exists', False)
    report_valid = False
    
    if report_exists:
        score += 10
        feedback_parts.append("Report file exists")
        
        # Decode and Parse CSV
        try:
            content_b64 = result.get('report_content_base64', "")
            content = base64.b64decode(content_b64).decode('utf-8')
            
            # Check for header and rows
            rows = list(csv.reader(io.StringIO(content)))
            if len(rows) >= 4: # Header + 3 data rows
                # Basic content check
                found_60 = any("60" in r for r in rows)
                found_90 = any("90" in r for r in rows)
                found_120 = any("120" in r for r in rows)
                
                if found_60 and found_90 and found_120:
                    score += 20
                    report_valid = True
                    feedback_parts.append("Report content valid (found 60, 90, 120)")
                else:
                    score += 10
                    feedback_parts.append("Report content incomplete (missing some test points)")
            else:
                feedback_parts.append("Report format incorrect (too few rows)")
        except Exception as e:
            feedback_parts.append(f"Failed to parse report: {e}")
    else:
        feedback_parts.append("Report file NOT found")

    # --- Criterion 3: Evidence Screenshot Existence (20 pts) ---
    evidence_exists = result.get('evidence_screenshot_exists', False)
    if evidence_exists:
        score += 20
        feedback_parts.append("Evidence screenshot exists")
    else:
        feedback_parts.append("Evidence screenshot missing")

    # --- Criterion 4: Visual Verification of Interaction (30 pts) ---
    # We need to verify the HR was actually set to 120.
    # We prefer the specific evidence screenshot if it exists, otherwise the final screenshot.
    
    # Retrieve the image
    image_to_verify = None
    if evidence_exists:
        # Try to copy the evidence screenshot
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/tmp/evidence_screenshot.png", temp_img.name)
            image_to_verify = temp_img.name
        except:
            image_to_verify = None
    
    # Fallback to final screenshot in trajectory if evidence copy failed
    if not image_to_verify:
        # We rely on the framework providing the final screenshot path from the container
        # Note: verifier runs on host, so we need to copy the final screenshot from container if we use that
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/tmp/task_final_screenshot.png", temp_img.name)
            image_to_verify = temp_img.name
        except:
            image_to_verify = None

    vlm_score = 0
    if image_to_verify:
        from gym_anything.vlm import query_vlm
        
        prompt = """
        You are verifying a medical device simulator calibration task.
        Look at the screenshot. It should show:
        1. An OpenICE 'Multiparameter Monitor' device window (simulated device).
        2. A 'Vital Signs' application window displaying numbers/waveforms.
        
        CRITICAL CHECK:
        Can you see a Heart Rate (HR) or 'Heart' value of approximately 120?
        or 
        Can you see a user input/slider set to 120?
        
        If the value is 60, 70, or 80, the user likely FAILED to adjust it.
        
        Response JSON:
        {
            "device_window_visible": true/false,
            "vital_signs_app_visible": true/false,
            "heart_rate_value": "number or null",
            "is_hr_approx_120": true/false,
            "reasoning": "string"
        }
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=image_to_verify)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("is_hr_approx_120", False):
                    vlm_score = 30
                    feedback_parts.append("VLM confirmed HR is set to ~120 BPM")
                else:
                    # Partial credit if windows are visible but value is wrong/unclear
                    if parsed.get("device_window_visible") or parsed.get("vital_signs_app_visible"):
                        vlm_score = 10
                        feedback_parts.append(f"VLM saw windows but HR value unclear (saw {parsed.get('heart_rate_value')})")
                    else:
                        feedback_parts.append("VLM could not confirm device/values")
            else:
                feedback_parts.append("VLM query failed")
        except Exception as e:
            feedback_parts.append(f"VLM exception: {e}")
        
        # Cleanup
        if os.path.exists(image_to_verify):
            os.unlink(image_to_verify)
    else:
        feedback_parts.append("No screenshot available for VLM")

    score += vlm_score

    # Final Pass/Fail Check
    # Must have report + evidence screenshot + confirmed value (or at least valid report content)
    passed = (score >= 70) and report_valid and evidence_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }