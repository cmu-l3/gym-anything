#!/usr/bin/env python3
"""
Verifier for configure_classroom task.

VERIFICATION STRATEGY:
1. Configuration File Verification (Primary):
   - Check `enableAudio=true` (or equivalent)
   - Check `filterLevelMax=2`
   - Check `filterLevelMin=1`
   - Check `isVirtualKeyboard=true`
2. Anti-Gaming:
   - Verify config file modification time > task start time
   - Verify values actually changed from initial state
3. VLM Verification (Secondary):
   - Use trajectory to verify the settings dialog was actually opened and interacted with
"""

import json
import os
import tempfile
import logging
import configparser
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils if available (assumed to be provided by framework)
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False


def parse_ini_string(ini_content):
    """Robustly parse INI content, handling loose formatting."""
    config = configparser.ConfigParser(strict=False)
    try:
        config.read_string(ini_content)
        return config
    except configparser.Error:
        # Fallback: simple line parsing if ConfigParser fails
        data = {}
        for line in ini_content.split('\n'):
            if '=' in line:
                key, val = line.split('=', 1)
                data[key.strip()] = val.strip()
        return {'General': data}  # Mock structure


def verify_configure_classroom(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Check Config File Existence & Timestamp (10 pts)
    config_found = result.get('config_found', False)
    config_modified = result.get('config_modified_during_task', False)
    
    if not config_found:
        return {"passed": False, "score": 0, "feedback": "GCompris configuration file not found."}

    if config_modified:
        score += 10
        feedback.append("Config modified during task (+10)")
    else:
        feedback.append("WARNING: Config file not modified during task (possible 'do nothing' or fast gaming)")

    # 3. Parse Config Content
    config_content = result.get('config_content', "")
    config = parse_ini_string(config_content)
    
    # Helper to get value case-insensitively
    def get_val(key, default=None):
        # Check standard section
        if 'General' in config:
            for k in config['General']:
                if k.lower() == key.lower():
                    return config['General'][k]
        # Fallback for flat dict from simple parser
        if isinstance(config, dict) and 'General' in config:
             for k in config['General']:
                if k.lower() == key.lower():
                    return config['General'][k]
        return default

    # 4. Check Criteria
    
    # Criterion 1: Audio Enabled (20 pts)
    # GCompris uses 'enableAudio=true' (or possibly 'audio=true' in older versions)
    audio_val = get_val('enableAudio')
    if audio_val and audio_val.lower() == 'true':
        score += 20
        feedback.append("Audio enabled (+20)")
    else:
        feedback.append(f"Audio NOT enabled (found: {audio_val})")

    # Criterion 2: Max Difficulty = 2 (25 pts)
    max_diff = get_val('filterLevelMax')
    if max_diff == '2':
        score += 25
        feedback.append("Max difficulty set to 2 (+25)")
    else:
        feedback.append(f"Max difficulty incorrect (found: {max_diff}, expected: 2)")

    # Criterion 3: Min Difficulty = 1 (10 pts)
    min_diff = get_val('filterLevelMin')
    if min_diff == '1':
        score += 10
        feedback.append("Min difficulty set to 1 (+10)")
    else:
        feedback.append(f"Min difficulty incorrect (found: {min_diff}, expected: 1)")

    # Criterion 4: Virtual Keyboard Enabled (20 pts)
    # Check 'isVirtualKeyboard' or 'virtualKeyboard'
    vk_val = get_val('isVirtualKeyboard') or get_val('virtualKeyboard')
    if vk_val and vk_val.lower() == 'true':
        score += 20
        feedback.append("Virtual keyboard enabled (+20)")
    else:
        feedback.append(f"Virtual keyboard NOT enabled (found: {vk_val})")

    # 5. VLM Verification for Process (15 pts)
    # Use VLM to confirm they actually opened the settings menu
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            # We look for the settings dialog which usually has sliders and toggles overlaid on the main menu
            prompt = """
            Does the user open the 'Settings' or 'Configuration' dialog in these screenshots?
            Look for a panel overlay with:
            1. Sliders (often for difficulty levels with stars)
            2. Toggle switches (checkboxes or ON/OFF buttons)
            3. A wrench/gear icon that was clicked
            
            Respond with JSON: {"settings_opened": boolean, "confidence": float}
            """
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('settings_opened', False):
                    vlm_score = 15
                    feedback.append("VLM confirmed settings dialog usage (+15)")
                else:
                    feedback.append("VLM did not detect settings dialog")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if config was modified, give partial points
            if config_modified:
                vlm_score = 10
                feedback.append("VLM failed, fallback to file timestamp (+10)")
    else:
        # Fallback if VLM not available
        if config_modified:
            vlm_score = 15
            feedback.append("VLM unavailable, trusting file timestamp (+15)")
            
    score += vlm_score

    # 6. Anti-Gaming Check: "Do Nothing" Detection
    initial_content = result.get('initial_content', "")
    if initial_content == config_content:
        score = 0
        feedback = ["FAILED: No changes detected in configuration file."]
    
    passed = score >= 60 and config_modified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }