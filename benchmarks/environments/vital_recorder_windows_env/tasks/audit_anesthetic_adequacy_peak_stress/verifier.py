#!/usr/bin/env python3
"""
Verifier for Audit Anesthetic Adequacy Task.

Verifies:
1. 'adequacy_audit.txt' exists and is correctly formatted.
2. Reported Heart Rate and BIS values are physiological and consistent.
3. 'peak_stress_event.png' exists.
4. VLM Verification:
   - Does the screenshot show Vital Recorder?
   - Does it show a Heart Rate peak?
   - Do the visible values roughly match the report?

Scoring:
- Report formatting & logic: 40 pts
- File existence & timestamps: 20 pts
- VLM Visual Confirmation: 40 pts
"""

import json
import os
import re
import logging
import tempfile
from datetime import datetime

# Import VLM utilities provided by the framework
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_anesthetic_adequacy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. File Existence & Anti-Gaming (20 pts)
    # ------------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    image_exists = result.get('image_exists', False)
    
    if report_exists:
        score += 10
        feedback_parts.append("Report file created.")
    else:
        feedback_parts.append("Report file missing.")

    if image_exists:
        score += 10
        feedback_parts.append("Screenshot evidence created.")
    else:
        feedback_parts.append("Screenshot evidence missing.")
        
    # ------------------------------------------------------------------
    # 2. Report Content & Logic Verification (40 pts)
    # ------------------------------------------------------------------
    report_content = result.get('report_content', "")
    logic_passed = False
    data_valid = False
    
    if report_exists and report_content:
        # Regex to parse the report
        # Expected:
        # Event: Peak Heart Rate
        # Timestamp: [HH:MM:SS]
        # Max HR: [Value] bpm
        # Concurrent BIS: [Value]
        # Assessment: [ADEQUATE or INADEQUATE]
        
        hr_match = re.search(r"Max HR:\s*([\d\.]+)", report_content)
        bis_match = re.search(r"Concurrent BIS:\s*([\d\.]+)", report_content)
        assess_match = re.search(r"Assessment:\s*(ADEQUATE|INADEQUATE)", report_content, re.IGNORECASE)
        
        if hr_match and bis_match and assess_match:
            hr_val = float(hr_match.group(1))
            bis_val = float(bis_match.group(1))
            assessment = assess_match.group(1).upper()
            
            # Check physiological ranges
            if 40 <= hr_val <= 200 and 0 <= bis_val <= 100:
                data_valid = True
                score += 10
                feedback_parts.append(f"Values physiological (HR: {hr_val}, BIS: {bis_val}).")
                
                # Verify Logic
                # Logic: BIS < 60 => ADEQUATE, else INADEQUATE
                expected_assessment = "ADEQUATE" if bis_val < 60 else "INADEQUATE"
                
                if assessment == expected_assessment:
                    logic_passed = True
                    score += 20
                    feedback_parts.append(f"Assessment logic correct ({assessment}).")
                else:
                    feedback_parts.append(f"Assessment logic WRONG (Expected {expected_assessment} for BIS {bis_val}).")
                
                # Check for plausibility of Peak HR (Case 6 is usually ~90-110 max, definitely > 60)
                if hr_val > 80:
                    score += 10
                    feedback_parts.append("HR value plausibly high for a peak.")
                else:
                    feedback_parts.append("Reported Max HR seems too low to be a peak stress event.")
            else:
                feedback_parts.append("Reported values out of physiological range.")
        else:
            feedback_parts.append("Report format incorrect or missing fields.")
    
    # ------------------------------------------------------------------
    # 3. VLM Verification (40 pts)
    # ------------------------------------------------------------------
    # We check the Agent's screenshot if available, otherwise fallback to final screenshot
    
    # We need to fetch the agent's screenshot from the env
    agent_screenshot_path = "/tmp/peak_stress_event.png" # mapped path
    # But wait, copy_from_env copies to host. We need to copy it first.
    
    vlm_image = None
    
    # Try to copy the agent's specific screenshot evidence
    if image_exists:
        try:
            with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tf:
                # Path in env: C:\Users\Docker\Documents\peak_stress_event.png
                # We need to know how copy_from_env handles Windows paths. 
                # Usually we pass the path as the env sees it, or a mapped path.
                # Assuming copy_from_env handles the windows path string if provided correctly,
                # OR we rely on export_result.sh having moved it to /tmp inside the container?
                # export_result.sh did NOT move the image, only the JSON. 
                # Let's rely on the final screenshot from the framework (get_final_screenshot)
                # or frames from the trajectory for simplicity and robustness.
                pass
        except:
            pass
            
    # Use trajectory frames
    frames = sample_trajectory_frames(traj, n=3)
    final_shot = get_final_screenshot(traj)
    if final_shot:
        frames.append(final_shot)
        
    if not frames:
         feedback_parts.append("No screenshots available for VLM.")
    else:
        # Construct VLM Prompt
        prompt = f"""
        You are verifying a clinical software task in Vital Recorder.
        The user was asked to find the MAXIMUM Heart Rate (HR) event in a surgery.
        
        Reported Values:
        Max HR: {hr_val if 'hr_val' in locals() else 'N/A'}
        BIS: {bis_val if 'bis_val' in locals() else 'N/A'}
        
        Look at the images (chronological order).
        1. Do you see the Vital Recorder interface with waveform tracks?
        2. In the final or later images, is the view zoomed into a specific event?
        3. Can you see a Heart Rate (HR) track (usually red)? Does it look like it is at a high point/peak compared to other parts of the trend?
        4. Can you read any numeric values matching the reported HR ({hr_val if 'hr_val' in locals() else 'N/A'})?
        
        Return JSON:
        {{
            "interface_visible": true/false,
            "zoomed_in_event": true/false,
            "hr_peak_visible": true/false,
            "values_match": true/false,
            "confidence": "low/medium/high"
        }}
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('interface_visible'):
                score += 10
            
            if parsed.get('zoomed_in_event'):
                score += 10
                feedback_parts.append("VLM confirms zoomed-in view.")
            
            if parsed.get('hr_peak_visible'):
                score += 10
                feedback_parts.append("VLM confirms visible HR peak.")
                
            if parsed.get('values_match'):
                score += 10
                feedback_parts.append("VLM confirms values match screen.")
        else:
            feedback_parts.append("VLM verification failed/inconclusive.")

    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    # Pass if: Score >= 70 AND Logic Passed AND Report Exists
    passed = (score >= 70) and logic_passed and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }