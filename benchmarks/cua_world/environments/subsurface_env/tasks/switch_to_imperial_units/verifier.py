#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import configparser

# The testing framework injects these in the env
import sys
from pathlib import Path

# Try to import VLM utilities (fallback to programmatic if missing)
try:
    sys.path.insert(0, str(Path(__file__).parent.parent))
    from vlm_utils import query_vlm, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_switch_to_imperial_units(traj, env_info, task_info):
    """
    Verifies that the agent changed the 5 primary units to imperial.
    
    1. Checks the `Subsurface.conf` INI file for exact unit values.
    2. Validates timestamp logic to detect "do nothing" attacks.
    3. Uses VLM to check trajectory frames to ensure the Preferences menu was opened.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_units = {
        'length': metadata.get('expected_length', '1'),
        'pressure': metadata.get('expected_pressure', '1'),
        'temperature': metadata.get('expected_temperature', '1'),
        'weight': metadata.get('expected_weight', '1'),
        'volume': metadata.get('expected_volume', '1')
    }

    # Setup temp files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_conf = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    
    try:
        try:
            copy_from_env('/tmp/task_result.json', temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

        try:
            copy_from_env('/home/ga/.config/Subsurface/Subsurface.conf', temp_conf.name)
        except Exception as e:
            logger.warning(f"Could not read config file: {e}")
            
        # 1. Check Anti-gaming timestamps
        task_start = result.get('task_start', 0)
        config_mtime = result.get('config_mtime', 0)
        
        if config_mtime > 0 and config_mtime <= task_start:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Config file was not modified after task started (anti-gaming check failed)."
            }

        # 2. Parse config file for 75 points (15 points per unit)
        config = configparser.ConfigParser()
        config.optionxform = str
        
        parsed_ok = False
        if os.path.exists(temp_conf.name) and os.path.getsize(temp_conf.name) > 0:
            try:
                config.read(temp_conf.name)
                parsed_ok = True
            except Exception as e:
                logger.error(f"Failed to parse config: {e}")

        score = 0
        feedback_parts = []
        units_correct = 0

        if parsed_ok and 'Units' in config:
            units = config['Units']
            for key, expected in expected_units.items():
                val = units.get(key, '0')
                if val == expected:
                    score += 15
                    units_correct += 1
                    feedback_parts.append(f"{key.capitalize()} is Imperial")
                else:
                    feedback_parts.append(f"{key.capitalize()} is Metric")
        else:
            feedback_parts.append("Could not read Units from configuration.")

        # 3. VLM Trajectory Verification for 25 points
        if VLM_AVAILABLE and traj:
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                prompt = (
                    "You are verifying if an AI agent successfully completed a task in the Subsurface dive log app.\n"
                    "Task: Switch all display units to imperial.\n"
                    "Does this sequence of screenshots show the user navigating to the 'Preferences' dialog "
                    "and interacting with the 'Units' tab/section?\n"
                    "Respond strictly with a JSON object: {\"preferences_units_opened\": true/false}"
                )
                try:
                    vlm_response = query_vlm(images=frames, prompt=prompt)
                    if vlm_response and vlm_response.get("success"):
                        parsed = vlm_response.get("parsed", {})
                        if parsed.get("preferences_units_opened"):
                            score += 25
                            feedback_parts.append("VLM confirmed Preferences interaction")
                        else:
                            feedback_parts.append("VLM did not detect Preferences interaction in trajectory")
                except Exception as e:
                    logger.error(f"VLM check failed: {e}")
                    feedback_parts.append("VLM check error")

        # Fallback if VLM not available but config is perfectly correct
        if not VLM_AVAILABLE and units_correct == 5:
            score += 25
            feedback_parts.append("VLM disabled, awarding trajectory points for perfect config")

        # Must have at least 4 out of 5 units correct, PLUS VLM confirmation or minimum threshold
        passed = score >= 70 and units_correct >= 4
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    finally:
        for tmp_file in [temp_result.name, temp_conf.name]:
            if os.path.exists(tmp_file):
                os.unlink(tmp_file)