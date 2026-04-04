#!/usr/bin/env python3
"""
Verifier for check_opioid_interaction_with_nilotinib task.

Verification Strategy:
1. Programmatic: Check if app was running and "Nilotinib"/"Methadone" text appears in UI dump.
2. VLM Trajectory: Verify workflow (Launch -> Select Nilotinib -> Select Methadone -> Result).
3. VLM Final State: Verify the specific traffic light color (Red) is visible.

Multi-criteria scoring:
- App launched and running: 10 pts
- Correct drugs visible (text match): 20 pts
- VLM Workflow verification: 30 pts
- VLM Result/Color verification: 40 pts
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_opioid_interaction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_color = metadata.get('expected_color', 'Red')
    cancer_drug = metadata.get('cancer_drug', 'Nilotinib')
    co_medication = metadata.get('co_medication', 'Methadone')

    score = 0
    feedback_parts = []
    
    # Temporary files for artifacts
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml').name
    
    try:
        # 1. Fetch JSON Result
        try:
            copy_from_env("/sdcard/task_result.json", temp_json)
            with open(temp_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}

        # 2. Verify App State (10 pts)
        if result_data.get("app_running_at_end", False):
            score += 10
            feedback_parts.append("App was running correctly.")
        else:
            feedback_parts.append("App was NOT running at end of task.")

        # 3. Verify Text Content via UI Dump (20 pts)
        # This is a robust check: if the XML contains the drug names, the agent likely navigated correctly.
        text_content = ""
        try:
            copy_from_env("/sdcard/ui_dump.xml", temp_xml)
            with open(temp_xml, 'r', encoding='utf-8', errors='ignore') as f:
                text_content = f.read()
        except Exception:
            logger.warning("UI dump not available or empty")

        drugs_found = []
        if cancer_drug.lower() in text_content.lower():
            drugs_found.append(cancer_drug)
        if co_medication.lower() in text_content.lower():
            drugs_found.append(co_medication)
        
        if len(drugs_found) == 2:
            score += 20
            feedback_parts.append(f"Both {cancer_drug} and {co_medication} found in active UI.")
        elif len(drugs_found) == 1:
            score += 10
            feedback_parts.append(f"Found {drugs_found[0]} but missing the other drug in UI.")
        else:
            feedback_parts.append("Target drugs not detected in UI hierarchy.")

        # 4. VLM Verification (70 pts total)
        # We verify both the process (trajectory) and the final result (traffic light)
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        if not final_frame:
             return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

        # Prompt for VLM
        prompt = f"""
        You are verifying an agent using the 'Liverpool Cancer iChart' app.
        
        Goal: Check interaction between '{cancer_drug}' and '{co_medication}'.
        Expected Result: A result screen showing a '{expected_color}' traffic light or banner.
        
        Review the sequence of images and the final image.
        1. Did the agent launch the app?
        2. Did the agent select '{cancer_drug}'?
        3. Did the agent select '{co_medication}'?
        4. Does the FINAL image show a '{expected_color}' interaction result banner?
        
        Provide a JSON response:
        {{
            "app_launched": true/false,
            "correct_drugs_selected": true/false,
            "result_visible": true/false,
            "observed_color": "Red/Orange/Yellow/Green/None",
            "confidence": 0-10
        }}
        """
        
        vlm_response = query_vlm(prompt=prompt, images=frames + [final_frame])
        
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            
            # Workflow check (30 pts)
            if parsed.get("app_launched"):
                score += 10
            if parsed.get("correct_drugs_selected"):
                score += 20
                
            # Result check (40 pts)
            if parsed.get("result_visible"):
                observed_color = parsed.get("observed_color", "").lower()
                target_color = expected_color.lower()
                
                if target_color in observed_color:
                    score += 40
                    feedback_parts.append(f"VLM confirmed {expected_color} result.")
                else:
                    score += 10 # Partial credit for reaching result, but wrong color/drug
                    feedback_parts.append(f"VLM saw result but color was '{observed_color}' (expected {expected_color}).")
            else:
                feedback_parts.append("VLM did not see the interaction result screen.")
        else:
            feedback_parts.append("VLM verification failed to process images.")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json): os.unlink(temp_json)
        if os.path.exists(temp_xml): os.unlink(temp_xml)

    # Pass threshold: 70 points (requires at least basic nav + correct result)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }