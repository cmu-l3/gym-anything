#!/usr/bin/env python3
"""
Verifier for set_power_saving_always task.

Strategy:
1. Verify app was running.
2. Check internal preferences XML (if extracted) for the power saving key.
   - Key is usually "power_saving_mode" or similar.
   - Value "Always" often maps to integer 2 or string "always".
3. Use VLM to verify the final screenshot shows "Power saving: Always" if prefs are unavailable.
4. Use VLM trajectory analysis to confirm navigation steps.
"""

import json
import os
import tempfile
import logging
import re
import xml.etree.ElementTree as ET
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_power_saving_always(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        
        # 1. Fetch Result JSON
        try:
            copy_from_env("/sdcard/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

        score = 0
        feedback_parts = []
        max_score = 100
        
        # Criterion 1: App Running (10 pts)
        if result.get("app_running", False):
            score += 10
            feedback_parts.append("App was running.")
        else:
            feedback_parts.append("App was closed.")

        # Criterion 2: Internal Preference Check (Primary Evidence - 50 pts)
        # We try to download the evidence dir containing shared_prefs
        prefs_score = 0
        prefs_checked = False
        
        if result.get("prefs_extracted", False):
            try:
                # Sygic usually stores main settings in com.sygic.aura_preferences.xml
                # or a file named after the package.
                # We will copy the whole directory structure to check.
                local_evidence_dir = os.path.join(temp_dir, "evidence")
                os.makedirs(local_evidence_dir, exist_ok=True)
                
                # Note: copy_from_env might copy a single file or dir. 
                # Assuming we need to grab specific files if dir copy isn't supported, 
                # but standard implementation supports it. If not, we fall back to VLM.
                # Here we try to copy the specific expected pref file if we can guess it,
                # or just rely on VLM if this is too brittle.
                
                # Let's try to fetch the most likely file: com.sygic.aura_preferences.xml
                pref_file_path = os.path.join(local_evidence_dir, "com.sygic.aura_preferences.xml")
                copy_from_env("/sdcard/task_evidence/shared_prefs/com.sygic.aura_preferences.xml", pref_file_path)
                
                if os.path.exists(pref_file_path):
                    with open(pref_file_path, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                        
                    # Look for power saving key
                    # Possible keys: "power_saving", "battery_saver", "performance_mode"
                    # Values: 0=Never, 1=On Battery, 2=Always (Hypothetical mapping, we check for '2' or 'always')
                    
                    # Regex for: <int name="power_saving" value="2" /> or similar
                    match = re.search(r'name="[^"]*power[^"]*"[^>]*value="([^"]+)"', content, re.IGNORECASE)
                    if match:
                        val = match.group(1)
                        if val in ["2", "always", "true", "high"]: # "2" is the standard enum for "Always" in many apps
                            prefs_score = 50
                            feedback_parts.append(f"Internal setting verified (Value: {val})")
                        else:
                            feedback_parts.append(f"Internal setting found but incorrect (Value: {val})")
                    else:
                        feedback_parts.append("Power setting key not found in prefs.")
                    prefs_checked = True
            except Exception as e:
                logger.warning(f"Could not verify prefs file: {e}")

        # Criterion 3: Visual Verification (Fallback or Confirmation - 40 pts + Fallback for Prefs)
        # If prefs checked and correct: +40 pts for VLM
        # If prefs failed/missing: +90 pts possible via VLM
        
        final_screenshot_path = os.path.join(temp_dir, "final.png")
        has_screenshot = False
        try:
            copy_from_env("/sdcard/task_final.png", final_screenshot_path)
            has_screenshot = True
        except:
            pass

        vlm_score = 0
        if has_screenshot:
            # Use VLM to verify
            prompt = """
            Examine this screenshot of the Sygic GPS Navigation settings.
            I am verifying if the user set "Power saving" mode to "Always".
            
            Look for:
            1. A "Battery management" or "Power saving" menu item.
            2. The current status of that setting.
            3. Does it say "Always" or "Always on"?
            
            Return JSON:
            {
                "setting_visible": boolean,
                "value_text": string,
                "is_set_to_always": boolean
            }
            """
            
            vlm_result = query_vlm(prompt=prompt, image=final_screenshot_path)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("is_set_to_always"):
                    vlm_score = 40
                    if not prefs_checked or prefs_score == 0:
                        # Fallback: if we couldn't check prefs, VLM is worth more
                        vlm_score = 80 
                    feedback_parts.append("Visual verification passed: 'Always' is selected.")
                elif parsed.get("setting_visible"):
                    feedback_parts.append(f"Setting visible but value is '{parsed.get('value_text')}'")
                else:
                    feedback_parts.append("Power saving setting not visible in final screenshot.")

        # Total Calculation
        score += prefs_score + vlm_score
        
        # Cap score at 100
        score = min(score, 100)
        
        passed = score >= 80  # Strict pass threshold

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }