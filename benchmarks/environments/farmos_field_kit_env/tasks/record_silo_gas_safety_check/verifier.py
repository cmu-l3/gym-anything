#!/usr/bin/env python3
"""
Verifier for record_silo_gas_safety_check task.

Strategy:
1. VLM Trajectory Verification:
   - Verify "Observation" type was selected.
   - Verify specific note content was typed ("Silo #2", "Ventilation").
   - Verify quantity fields (2, ppm, NO2 Level) were entered.
2. UI State Verification (Backup):
   - Parse XML dump to see if the log appears in the list with correct summary.
"""

import json
import os
import logging
import tempfile
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_silo_check(traj, env_info, task_info):
    """
    Verifies the agent created the Silo Gas Safety Check log correctly.
    """
    # 1. Setup and Load Artifacts
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    required_substrings = metadata.get('required_notes_substrings', [])
    
    # Files to retrieve
    files = {
        'result_json': '/sdcard/task_result.json',
        'ui_dump': '/sdcard/ui_dump.xml',
        'final_screenshot': '/sdcard/task_final.png'
    }
    
    local_files = {}
    
    # create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        # Retrieve files
        for name, path in files.items():
            dest = os.path.join(temp_dir, os.path.basename(path))
            try:
                copy_from_env(path, dest)
                if os.path.exists(dest):
                    local_files[name] = dest
            except Exception as e:
                logger.warning(f"Failed to copy {name} from {path}: {e}")

        # 2. VLM Verification (Primary High-Fidelity Check)
        # We sample frames to catch the data entry process
        frames = sample_trajectory_frames(traj, n=6)
        final_shot = get_final_screenshot(traj)
        
        # If we failed to get the final screenshot from env, try the trajectory one
        target_image = local_files.get('final_screenshot', final_shot)
        
        # Build VLM Prompt
        prompt = f"""
        You are verifying an agent's work in the farmOS app. 
        The task was to create a specific 'Observation' log for a Silo Safety Check.
        
        REQUIRED DATA ENTRY:
        1. Log Type: Must be "Observation" (NOT Activity, Harvest, or Input).
        2. Notes: Must contain "Silo #2" and "Ventilation".
        3. Quantity: Value "2", Unit "ppm", Label "NO2 Level".
        4. Final Step: The log must be saved and visible in the list.

        Review the screenshots provided (chronological order).
        
        Respond in JSON:
        {{
            "log_type_correct": boolean,
            "notes_entered": boolean,
            "quantity_value_correct": boolean,
            "quantity_unit_correct": boolean,
            "quantity_label_correct": boolean,
            "log_saved": boolean,
            "reasoning": "string explanation"
        }}
        """
        
        vlm_images = frames + [target_image] if target_image else frames
        
        vlm_result = query_vlm(
            prompt=prompt,
            images=vlm_images,
            model="gpt-4o" # or equivalent capable VLM
        )
        
        vlm_data = vlm_result.get('parsed', {})
        logger.info(f"VLM Result: {vlm_data}")

        # 3. XML Verification (Secondary/Validation)
        # Use the UI dump to check text presence in the final state (List View)
        xml_score = 0
        xml_feedback = []
        if 'ui_dump' in local_files:
            try:
                tree = ET.parse(local_files['ui_dump'])
                root_text = ET.tostring(tree.getroot(), encoding='utf8', method='text').decode('utf8')
                
                # Check for key phrases in the final UI (likely the list view)
                if "Observation" in root_text:
                    xml_score += 10
                    xml_feedback.append("Found 'Observation' in UI.")
                
                if "Silo" in root_text or "NO2" in root_text:
                    xml_score += 20
                    xml_feedback.append("Found log content details in UI.")
            except Exception as e:
                logger.warning(f"XML parsing failed: {e}")

        # 4. Scoring Logic
        score = 0
        feedback_parts = []

        # VLM Scoring (Max 80)
        if vlm_data.get('log_type_correct'):
            score += 20
            feedback_parts.append("Correct Log Type.")
        else:
            feedback_parts.append("Incorrect Log Type.")

        if vlm_data.get('notes_entered'):
            score += 20
            feedback_parts.append("Notes entered correctly.")
        
        if vlm_data.get('quantity_value_correct') and vlm_data.get('quantity_unit_correct'):
            score += 20
            feedback_parts.append("Quantity/Unit correct.")
        
        if vlm_data.get('quantity_label_correct'):
            score += 10
            feedback_parts.append("Quantity Label correct.")
        
        if vlm_data.get('log_saved'):
            score += 10
            feedback_parts.append("Log saved successfully.")

        # XML Bonus/Fallback (Max +20 if VLM uncertain, but capped at 100)
        score = min(100, score + (xml_score if score < 100 else 0))
        
        # Critical Failures
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) + f" (Reasoning: {vlm_data.get('reasoning', 'N/A')})"
        }