#!/usr/bin/env python3
"""
Verifier for configure_mixed_units_personalize task.

Validates that the Subsurface configuration file has been properly updated
with a mixed units setup without overriding unchanged metric defaults.
Also uses VLM on trajectory frames to verify GUI interaction.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_qt_ini(filepath):
    """Safely parse a Qt configuration INI file."""
    config = {}
    current_section = None
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('[') and line.endswith(']'):
                    current_section = line[1:-1]
                    if current_section not in config:
                        config[current_section] = {}
                elif '=' in line and current_section:
                    key, val = line.split('=', 1)
                    config[current_section][key.strip()] = val.strip()
    except Exception as e:
        logger.error(f"Error parsing {filepath}: {e}")
    return config

def verify_mixed_units_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check anti-gaming (file modified during task)
    task_start = result.get('task_start', 0)
    conf_mtime = result.get('conf_mtime', 0)
    
    if result.get('conf_exists') and conf_mtime > task_start:
        score += 10
        feedback_parts.append("Config modified during task (10/10)")
    else:
        feedback_parts.append("Config file was NOT modified (Did not save preferences)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Read and parse Subsurface.conf
    temp_conf = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    try:
        copy_from_env("/home/ga/.config/Subsurface/Subsurface.conf", temp_conf.name)
        config = parse_qt_ini(temp_conf.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read Subsurface.conf: {e}"}
    finally:
        if os.path.exists(temp_conf.name):
            os.unlink(temp_conf.name)

    units_cfg = config.get('Units', {})
    
    # Defaults in Qt config are often omitted, so treat missing as "0" (Metric)
    pressure_val = units_cfg.get('pressure', '0')
    temp_val = units_cfg.get('temperature', '0')
    length_val = units_cfg.get('length', '0')
    volume_val = units_cfg.get('volume', '0')
    weight_val = units_cfg.get('weight', '0')

    # 4. Score Unit Configurations
    # Metric/Default = '0', Imperial = '1'
    if pressure_val == '1':
        score += 25
        feedback_parts.append("Pressure set to PSI (25/25)")
    else:
        feedback_parts.append(f"Pressure is '{pressure_val}', expected '1' (PSI)")

    if temp_val == '1':
        score += 25
        feedback_parts.append("Temperature set to Fahrenheit (25/25)")
    else:
        feedback_parts.append(f"Temperature is '{temp_val}', expected '1' (Fahrenheit)")

    # Anti-gaming: Ensure they didn't just click the global "Imperial" preset
    metric_defaults_preserved = (length_val == '0' and volume_val == '0' and weight_val == '0')
    if metric_defaults_preserved:
        score += 20
        feedback_parts.append("Metric defaults preserved correctly (20/20)")
    else:
        feedback_parts.append(f"Metric defaults overwritten (length={length_val}, vol={volume_val}, weight={weight_val}) - Do not use the Imperial preset")

    # 5. VLM Trajectory Verification
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots from a task in Subsurface dive log.
        Did the agent navigate into the application's Preferences/Settings dialog and interact with the 'Units' tab?
        Look for the Preferences window with radio buttons for Metric, Imperial, and Personalize.
        Respond in JSON format: {"interacted_with_preferences": true/false}
        """
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        
        if vlm_res and vlm_res.get("parsed", {}).get("interacted_with_preferences", False):
            vlm_score = 20
            feedback_parts.append("VLM verified Preferences dialog interaction (20/20)")
        else:
            feedback_parts.append("VLM did not detect Preferences dialog interaction")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM isn't available, we don't penalize completely if programmatic is perfect
        if score == 80:
            vlm_score = 20
            feedback_parts.append("VLM skipped, but programmatic checks passed flawlessly (20/20)")

    score += vlm_score

    # Passing condition: Must reach >= 80, meaning target units were changed AND metric was preserved
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }