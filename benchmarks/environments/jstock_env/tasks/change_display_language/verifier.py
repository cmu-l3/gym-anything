#!/usr/bin/env python3
"""
Verifier for Change Display Language task (JStock).

Verification logic:
1. Primary: Check if JStock configuration files contain German locale settings.
2. Secondary: VLM verification of the final screenshot (looking for German UI text).
3. Anti-gaming: Ensure config files were actually modified during the task session.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_display_language(traj, env_info, task_info):
    """
    Verify that JStock language was changed to German.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result data from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Configuration File Check (35 pts) ---
    found_german_config = result.get('found_german_config', False)
    config_modified = result.get('config_files_modified', False)
    matching_content = result.get('matching_config_content', '')

    if found_german_config and config_modified:
        score += 35
        feedback_parts.append("Configuration updated with German locale settings")
    elif found_german_config:
        # Found German setting but file timestamp didn't update? Suspicious but maybe valid if checking wrong file
        score += 15 
        feedback_parts.append("Found German settings, but verification of fresh modification failed")
    else:
        feedback_parts.append("No German language settings found in configuration files")

    # --- Criterion 2: Application State (10 pts) ---
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("JStock is running")
    else:
        feedback_parts.append("JStock is NOT running (did you forget to restart it?)")

    # --- Criterion 3: Visual Verification (VLM) (55 pts) ---
    # We rely heavily on VLM because config files can be cryptic in some versions
    final_screenshot = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_screenshot:
        try:
            # Query VLM to check for German UI elements
            prompt = (
                "Look at this screenshot of the JStock application. "
                "Is the user interface language set to German (Deutsch)? "
                "Check for German menu words like 'Datei' (File), 'Bearbeiten' (Edit), 'Hilfe' (Help), "
                "or column headers like 'Symbol', 'Letzt' (Last), 'Hoch' (High). "
                "Answer YES if the interface is clearly in German, NO otherwise."
            )
            vlm_response = query_vlm(images=[final_screenshot], prompt=prompt)
            
            if "YES" in vlm_response.upper():
                vlm_score = 55
                feedback_parts.append("Visual check passed: UI appears to be in German")
            else:
                feedback_parts.append("Visual check failed: UI does not appear to be in German")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("Visual verification encountered an error")
    
    score += vlm_score

    # Calculate final result
    # Pass threshold: 65 points (requires at least visual confirmation + app running OR config + visual)
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }