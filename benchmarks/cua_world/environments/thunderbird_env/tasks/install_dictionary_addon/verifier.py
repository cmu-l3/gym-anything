#!/usr/bin/env python3
import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dictionary_addon(traj, env_info, task_info):
    """
    Verify that the Spanish dictionary was installed and composition settings were correctly applied.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_addon_id = metadata.get('expected_addon_id', 'es-es@dictionaries.addons.mozilla.org')
    expected_dict_code = metadata.get('expected_dict_code', 'es-ES')

    # Copy result JSON
    result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_result = f.name
    try:
        copy_from_env("/tmp/task_result.json", temp_result)
        with open(temp_result, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result):
            os.unlink(temp_result)

    # Copy extensions.json
    extensions_data = {}
    if result.get('extensions_exists'):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_ext = f.name
        try:
            copy_from_env("/tmp/extensions.json", temp_ext)
            with open(temp_ext, 'r') as f:
                extensions_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load extensions.json: {e}")
        finally:
            if os.path.exists(temp_ext):
                os.unlink(temp_ext)

    # Copy prefs.js
    prefs_content = ""
    if result.get('prefs_exists'):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.js') as f:
            temp_prefs = f.name
        try:
            copy_from_env("/tmp/prefs.js", temp_prefs)
            with open(temp_prefs, 'r') as f:
                prefs_content = f.read()
        except Exception as e:
            logger.error(f"Failed to load prefs.js: {e}")
        finally:
            if os.path.exists(temp_prefs):
                os.unlink(temp_prefs)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # CRITERION 1: Add-on Installed (30 points)
    # ================================================================
    addon_installed = False
    addons = extensions_data.get('addons', [])
    for addon in addons:
        if addon.get('id') == expected_addon_id and addon.get('active', False):
            addon_installed = True
            break
    
    if addon_installed:
        score += 30
        feedback_parts.append("Spanish dictionary add-on installed and active")
    else:
        feedback_parts.append("Spanish dictionary add-on NOT found or not active")

    # ================================================================
    # CRITERION 2: Inline spellcheck enabled (25 points)
    # ================================================================
    inline_match = re.search(r'user_pref\("mail\.spellcheck\.inline",\s*(true|false)\);', prefs_content)
    inline_enabled = False
    if inline_match and inline_match.group(1) == "true":
        inline_enabled = True
        score += 25
        feedback_parts.append("Inline spellcheck enabled")
    else:
        feedback_parts.append("Inline spellcheck NOT enabled")

    # ================================================================
    # CRITERION 3: Default dictionary set (25 points)
    # ================================================================
    dict_match = re.search(r'user_pref\("spellchecker\.dictionary",\s*"([^"]+)"\);', prefs_content)
    dict_set = False
    if dict_match and dict_match.group(1) == expected_dict_code:
        dict_set = True
        score += 25
        feedback_parts.append("Default dictionary set to Spanish")
    elif dict_match:
        feedback_parts.append(f"Default dictionary set to wrong language: {dict_match.group(1)}")
    else:
        feedback_parts.append("Default dictionary NOT set to Spanish")

    # ================================================================
    # CRITERION 4: VLM Trajectory Verification (20 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            # Extract images from trajectory
            frames = [step['observation']['image'] for step in traj if 'observation' in step and 'image' in step['observation']]
            if len(frames) > 0:
                # Sample 3 frames evenly across the trajectory
                step_size = max(1, len(frames) // 3)
                sampled_frames = frames[::step_size][:3]
                
                prompt = """Analyze these screenshots from a Thunderbird session.
                Did the agent open the 'Add-ons and Themes' manager OR the 'Settings' tab?
                Respond strictly in JSON: {"settings_opened": true/false}"""
                
                vlm_res = query_vlm(prompt=prompt, images=sampled_frames)
                if vlm_res and vlm_res.get('parsed', {}).get('settings_opened', False):
                    vlm_score = 20
                    feedback_parts.append("VLM verified Settings/Add-ons interaction")
                else:
                    feedback_parts.append("VLM did not detect Settings/Add-ons interaction")
            else:
                feedback_parts.append("No trajectory frames for VLM")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            vlm_score = 0
    else:
        # Give points if VLM is unavailable to not penalize
        vlm_score = 20
        
    score += vlm_score

    # ================================================================
    # ANTI-GAMING CHECK
    # ================================================================
    task_start = result.get('task_start', 0)
    prefs_mtime = result.get('prefs_mtime', 0)
    modified_during_task = prefs_mtime >= task_start
    
    if not modified_during_task and (inline_enabled or dict_set):
        score -= 50
        feedback_parts.append("WARNING: Preferences were not modified during the task execution time.")

    # Must achieve at least 70% to pass
    passed = (score >= 70) and modified_during_task and addon_installed

    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback_parts)
    }