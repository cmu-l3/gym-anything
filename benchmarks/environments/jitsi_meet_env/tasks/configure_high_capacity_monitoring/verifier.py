#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_js_config_value(content, key):
    """
    Robustly extract value for a key in a JS object using regex.
    Handles: key: value, key : value, comments, etc.
    """
    # Pattern looks for key, optional spaces, colon, optional spaces, value, optional comma
    # We look for simple scalars (numbers, booleans, strings)
    # Example: channelLastN: -1,
    pattern = re.compile(rf"{key}\s*:\s*([^,\n}}]+)", re.MULTILINE)
    match = pattern.search(content)
    if match:
        val_str = match.group(1).strip()
        # Clean up trailing comments if present
        val_str = re.split(r'//|/\*', val_str)[0].strip()
        
        # Convert to Python types
        if val_str == 'true': return True
        if val_str == 'false': return False
        try:
            return int(val_str)
        except ValueError:
            try:
                return float(val_str)
            except ValueError:
                return val_str.strip("'\"") # String
    return None

def verify_config_monitoring(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback = []
    
    # Define temp files
    result_json_path = tempfile.mktemp()
    served_config_path = tempfile.mktemp()
    physical_config_path = tempfile.mktemp()
    
    try:
        # Copy files from container
        copy_from_env("/tmp/task_result.json", result_json_path)
        
        if os.path.exists(result_json_path):
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        else:
            return {"passed": False, "score": 0, "feedback": "Task result file missing"}

        # Check service health
        if task_result.get("service_up", False):
            score += 10
            feedback.append("Jitsi Meet service is reachable (+10)")
        else:
            feedback.append("Jitsi Meet service is DOWN. Config changes may have broken the server.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # Analyze Served Config (Primary Verification)
        # This proves the config is actually live
        config_content = ""
        if task_result.get("served_config_exists", False):
            try:
                copy_from_env("/tmp/served_config.js", served_config_path)
                with open(served_config_path, 'r') as f:
                    config_content = f.read()
            except Exception as e:
                feedback.append(f"Failed to read served config: {e}")
        
        # Fallback to physical config if served config is empty (unlikely if service is up)
        if not config_content and task_result.get("physical_config_exists", False):
            feedback.append("Warning: Could not read served config, checking disk file instead.")
            try:
                copy_from_env("/tmp/physical_config.js", physical_config_path)
                with open(physical_config_path, 'r') as f:
                    config_content = f.read()
            except Exception:
                pass

        if not config_content:
            return {"passed": False, "score": score, "feedback": "Could not retrieve configuration content for verification."}

        # Verify Parameters
        reqs = task_info.get('metadata', {}).get('requirements', {})
        
        # 1. channelLastN: -1
        actual_last_n = parse_js_config_value(config_content, "channelLastN")
        if actual_last_n == -1:
            score += 30
            feedback.append("channelLastN correctly set to -1 (+30)")
        else:
            feedback.append(f"channelLastN incorrect (expected -1, found {actual_last_n})")

        # 2. enableLayerSuspension: false
        actual_suspension = parse_js_config_value(config_content, "enableLayerSuspension")
        if actual_suspension is False:
            score += 30
            feedback.append("enableLayerSuspension correctly set to false (+30)")
        else:
            feedback.append(f"enableLayerSuspension incorrect (expected false, found {actual_suspension})")

        # 3. disableAudioLevels: true
        actual_audio = parse_js_config_value(config_content, "disableAudioLevels")
        if actual_audio is True:
            score += 30
            feedback.append("disableAudioLevels correctly set to true (+30)")
        else:
            feedback.append(f"disableAudioLevels incorrect (expected true, found {actual_audio})")

        # Anti-gaming: Check if file was actually modified
        if task_result.get("file_modified_during_task", False):
            feedback.append("Configuration file verified modified during task.")
        else:
            # If they achieved the state but didn't modify the file, it might be a pre-existing state 
            # (though setup script tries to prevent this). Or they edited the wrong file but somehow served it.
            # We don't penalize heavily if the served config is correct, but we note it.
            feedback.append("Note: Config file timestamp indicates no modification (or edit happened very fast).")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for p in [result_json_path, served_config_path, physical_config_path]:
            if os.path.exists(p):
                try:
                    os.unlink(p)
                except:
                    pass

    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " | ".join(feedback)
    }