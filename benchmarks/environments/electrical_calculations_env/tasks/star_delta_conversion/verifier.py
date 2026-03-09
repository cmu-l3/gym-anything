#!/usr/bin/env python3
"""
Verifier for Star-Delta Conversion task.

Strategies:
1. VLM Verification (Primary): Analyze screenshot for correct calculator and values.
2. UI Dump parsing (Secondary): Check for text presence in accessibility tree.
3. App State: Ensure app is running.
"""

import json
import os
import tempfile
import logging
import re
from typing import Dict, Any

# Import VLM utilities from the framework
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_star_delta_conversion(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Star-Delta conversion task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_inputs = set(metadata.get('input_values', [30, 60, 90]))
    expected_outputs = set(metadata.get('expected_values', [15, 10, 30]))

    # Setup temp files
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml').name

    score = 0
    feedback_parts = []
    
    try:
        # 1. Fetch artifacts from device
        try:
            copy_from_env("/sdcard/task_result.json", temp_result_json)
            with open(temp_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load result JSON: {e}")
            result_data = {}

        # 2. Check App State (10 points)
        if result_data.get("app_in_foreground", False):
            score += 10
            feedback_parts.append("App is in foreground")
        else:
            feedback_parts.append("App NOT in foreground")

        # 3. VLM Verification (Primary)
        # Use trajectory frames + final screenshot for robustness
        frames = sample_trajectory_frames(traj, n=3)
        final_shot = get_final_screenshot(traj)
        
        # If we couldn't get screenshot from traj, try pulling the specific one we saved
        if not final_shot:
            try:
                copy_from_env("/sdcard/task_final.png", temp_screenshot)
                if os.path.getsize(temp_screenshot) > 0:
                    final_shot = temp_screenshot
            except Exception:
                pass

        if final_shot:
            images_to_check = frames + [final_shot] if frames else [final_shot]
            
            prompt = f"""
            You are verifying an Electrical Engineering task in a mobile app.
            
            GOAL: The user should use the "Star-Delta" (or Delta-Star) calculator.
            INPUTS: The user should have entered resistances 30, 60, and 90 (order doesn't matter).
            OUTPUTS: The calculator should display results 15, 10, and 30 (order doesn't matter).
            
            Analyze the images (especially the last one) and answer:
            1. Is the "Star-Delta" or "Delta-Star" conversion screen visible?
            2. Are the input numbers 30, 60, 90 visible in input fields?
            3. Are the result numbers 15, 10, 30 visible as output/calculated values?
            
            Return JSON:
            {{
                "is_correct_calculator": boolean,
                "inputs_visible": boolean,
                "outputs_visible": boolean,
                "confidence": "high/medium/low"
            }}
            """
            
            vlm_response = query_vlm(prompt=prompt, images=images_to_check)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                # Score Calculator Screen (30 points)
                if parsed.get("is_correct_calculator"):
                    score += 30
                    feedback_parts.append("Correct calculator screen verified")
                else:
                    feedback_parts.append("Could not confirm correct calculator screen")
                
                # Score Inputs (30 points)
                if parsed.get("inputs_visible"):
                    score += 30
                    feedback_parts.append("Input values (30, 60, 90) verified")
                else:
                    feedback_parts.append("Input values missing or incorrect")
                    
                # Score Outputs (30 points)
                if parsed.get("outputs_visible"):
                    score += 30
                    feedback_parts.append("Output values (15, 10, 30) verified")
                else:
                    feedback_parts.append("Output values missing or incorrect")
            else:
                feedback_parts.append("Visual verification failed to process")

        else:
            feedback_parts.append("No screenshots available for verification")

        # 4. XML Backup Verification (Secondary/Tie-breaker)
        # If VLM was unsure, we can grep the XML dump for the numbers
        try:
            copy_from_env("/sdcard/ui_dump.xml", temp_xml)
            with open(temp_xml, 'r', errors='ignore') as f:
                xml_content = f.read()
                
            # Check for numbers if we missed points
            found_outputs = 0
            for val in [15, 10, 30]:
                # Look for value in text or content-desc attributes
                # Simple check: quote+"15"+quote or >15<
                if re.search(f'text="{val}"', xml_content) or re.search(f'text="{val}.0"', xml_content):
                    found_outputs += 1
            
            # If we found outputs in XML but VLM missed them, grant points
            if found_outputs == 3 and "Output values (15, 10, 30) verified" not in feedback_parts:
                score = max(score, score + 25) # Grant partial recovery points
                feedback_parts.append("Outputs verified via UI inspection")

        except Exception:
            pass # XML might not be available, ignore

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for fpath in [temp_result_json, temp_screenshot, temp_xml]:
            if os.path.exists(fpath):
                os.unlink(fpath)

    # Final Pass Check
    # Need at least 70 points (App open + Calculator + Inputs OR Outputs)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }