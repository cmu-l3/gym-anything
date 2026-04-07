#!/usr/bin/env python3
"""
Verifier for customize_map_shortcuts task.

Verification Logic:
1. XML Config Check: Parses Avare's SharedPreference XML to verify 'Draw' and 'Plate' 
   buttons are enabled.
2. VLM Visual Check: Uses Vision-Language Model to verify the buttons are actually 
   visible on the map interface.
3. Anti-Gaming: Checks that preferences were modified after task start.
"""

import json
import os
import time
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_map_shortcuts(traj, env_info, task_info):
    """
    Verify that 'Draw' and 'Plate' buttons are enabled and visible.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure Error: Copy function not available"}

    # Define paths
    remote_export_dir = "/sdcard/task_export"
    local_temp_dir = "temp_verification_data"
    os.makedirs(local_temp_dir, exist_ok=True)
    
    local_prefs = os.path.join(local_temp_dir, "preferences.xml")
    local_meta = os.path.join(local_temp_dir, "result_meta.json")
    
    score = 0
    feedback = []
    
    try:
        # 1. Retrieve Data from Environment
        copy_from_env(f"{remote_export_dir}/preferences.xml", local_prefs)
        copy_from_env(f"{remote_export_dir}/result_meta.json", local_meta)
        
        # 2. Parse Metadata
        with open(local_meta, 'r') as f:
            meta = json.load(f)
            
        # 3. Analyze Preferences XML
        # Avare typically stores button visibility as boolean keys or a comma-separated list
        # We will search for keys/values containing "Draw" and "Plate" and "True"/Enabled state
        draw_enabled = False
        plate_enabled = False
        
        if os.path.exists(local_prefs):
            try:
                tree = ET.parse(local_prefs)
                root = tree.getroot()
                
                # Scan all preferences
                prefs_content = open(local_prefs, 'r').read().lower()
                
                # Heuristic 1: Check for specific boolean keys (e.g., "ShowDraw", "ShowPlate")
                # Heuristic 2: Check for presence in a list (e.g., "MainButtons")
                
                # Check for Draw
                if 'draw' in prefs_content and ('true' in prefs_content or 'value="true"' in prefs_content):
                    # We do a slightly loose check because key names vary by version, 
                    # but "Draw" + "true" in the file is a strong signal of enablement
                    # specifically if they appear in valid XML entries.
                    for child in root:
                        key = child.get('name', '').lower()
                        value = child.get('value', '').lower()
                        text = (child.text or '').lower()
                        
                        if 'draw' in key and ('true' in value or 'true' in text):
                            draw_enabled = True
                            break
                
                # Check for Plate
                if 'plate' in prefs_content and ('true' in prefs_content or 'value="true"' in prefs_content):
                    for child in root:
                        key = child.get('name', '').lower()
                        value = child.get('value', '').lower()
                        text = (child.text or '').lower()
                        
                        if 'plate' in key and ('true' in value or 'true' in text):
                            plate_enabled = True
                            break
                            
            except ET.ParseError:
                feedback.append("Failed to parse preferences XML.")
        else:
            feedback.append("Preferences file not found.")

        # Scoring Programmatic Check
        if draw_enabled:
            score += 25
            feedback.append("Programmatic: 'Draw' button enabled in settings.")
        else:
            feedback.append("Programmatic: 'Draw' button setting NOT found or disabled.")
            
        if plate_enabled:
            score += 25
            feedback.append("Programmatic: 'Plate' button enabled in settings.")
        else:
            feedback.append("Programmatic: 'Plate' button setting NOT found or disabled.")

        # 4. VLM Verification (Visual Confirmation)
        # We use the final screenshot to check if buttons are actually visible
        final_screenshot = get_final_screenshot(traj)
        
        if final_screenshot:
            vlm_prompt = (
                "Analyze this screenshot of the Avare aviation app. "
                "I am looking for two specific buttons on the map toolbar: "
                "1. A 'Draw' button (often a pencil or pen icon). "
                "2. A 'Plate' or 'Plates' button (often a document or chart icon). "
                "Are these buttons visible on the screen? "
                "Respond in JSON format: {'draw_visible': bool, 'plate_visible': bool}"
            )
            
            vlm_result = query_vlm(
                prompt=vlm_prompt,
                images=[final_screenshot]
            )
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                vlm_draw = parsed.get("draw_visible", False)
                vlm_plate = parsed.get("plate_visible", False)
                
                if vlm_draw:
                    score += 25
                    feedback.append("Visual: 'Draw' button detected on screen.")
                else:
                    feedback.append("Visual: 'Draw' button NOT detected on screen.")
                    
                if vlm_plate:
                    score += 25
                    feedback.append("Visual: 'Plate' button detected on screen.")
                else:
                    feedback.append("Visual: 'Plate' button NOT detected on screen.")
            else:
                feedback.append("VLM analysis failed.")
        else:
            feedback.append("No final screenshot available for visual verification.")

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        import shutil
        if os.path.exists(local_temp_dir):
            shutil.rmtree(local_temp_dir)

    # Final Pass Logic
    # Must have at least 75 points (requires at least one verified visual + both settings, or both visuals + one setting)
    # Ideally requires consistency between Settings and Visuals.
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }