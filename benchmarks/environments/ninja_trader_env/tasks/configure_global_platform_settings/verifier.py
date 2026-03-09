#!/usr/bin/env python3
"""
Verifier for configure_global_platform_settings task.

Verifies:
1. Workspace was saved (file persistence)
2. Skin set to Slate Gray (Config check + VLM)
3. Timezone set to Eastern (Config check)
4. Global Sim Fill enabled (Config check)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\configure_global_platform_settings_result.json"

def verify_configure_global_platform_settings(traj, env_info, task_info):
    """
    Verify NinjaTrader platform configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON Result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env(RESULT_PATH, temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_path)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result file: {str(e)}"
        }

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Verification (60 points)
    
    # Criterion: Workspace Saved (15 pts)
    if result.get('workspace_saved', False):
        score += 15
        feedback_parts.append("Workspace saved (+15)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")
        
    # Criterion: Time Zone (20 pts)
    tz_setting = result.get('timezone_detected', 'Unknown')
    if "Eastern" in tz_setting or "UTC-05" in tz_setting:
        score += 20
        feedback_parts.append("Time zone correct (+20)")
    else:
        feedback_parts.append(f"Time zone incorrect or not found ({tz_setting})")
        
    # Criterion: Sim Fill (15 pts)
    sim_fill = str(result.get('sim_fill_detected', 'false')).lower()
    if sim_fill == 'true':
        score += 15
        feedback_parts.append("Sim fill enabled (+15)")
    else:
        feedback_parts.append("Sim fill check failed (0)")
        
    # Criterion: Skin - Config Check (10 pts)
    skin_setting = str(result.get('skin_detected', 'Unknown')).replace(" ", "").lower()
    config_skin_correct = "slategray" in skin_setting
    if config_skin_correct:
        score += 10
        feedback_parts.append("Skin config correct (+10)")
    else:
        feedback_parts.append(f"Skin config incorrect ({result.get('skin_detected')})")

    # 3. VLM Verification (40 points)
    # Why VLM? XML config changes might require restart or be complex.
    # Visual confirmation of Slate Gray theme is a strong signal.
    
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screenshot:
        prompt = """
        You are verifying a NinjaTrader 8 task.
        Goal: Change the theme/skin to 'Slate Gray'.
        
        Look at the screenshot.
        1. Does the application interface look like the 'Slate Gray' theme? 
           (Slate Gray has medium-gray window borders and toolbars, distinctly different from the default dark black/blue or light white themes).
        2. Is the NinjaTrader application visible?
        
        Respond JSON: {"is_slate_gray": true/false, "app_visible": true/false}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('app_visible'):
                score += 10 # App visible bonus
                if parsed.get('is_slate_gray'):
                    score += 30 # Visual confirmation of theme
                    feedback_parts.append("VLM confirmed Slate Gray theme (+30)")
                else:
                    # Fallback: if config was correct, maybe VLM is unsure
                    if config_skin_correct:
                        score += 15 # Partial credit if config ok but VLM unsure
                        feedback_parts.append("VLM unsure about theme, trusting config (+15)")
                    else:
                        feedback_parts.append("VLM did not see Slate Gray theme (0)")
            else:
                feedback_parts.append("App not visible in screenshot (0)")
                
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback if VLM fails but config was correct
            if config_skin_correct:
                score += 15
                feedback_parts.append("VLM failed, fallback to config (+15)")

    # 4. Final Scoring
    # Pass if score >= 60 AND (skin changed OR timezone changed)
    # This ensures they didn't just do nothing.
    
    key_action_taken = config_skin_correct or ("Eastern" in tz_setting)
    passed = (score >= 60) and key_action_taken
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }