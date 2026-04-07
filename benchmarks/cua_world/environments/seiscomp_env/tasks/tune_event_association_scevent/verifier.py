#!/usr/bin/env python3
"""
Verifier for tune_event_association_scevent task.

Checks:
1. `scevent.cfg` file was modified
2. SeisComP's `scevent` daemon was restarted (PID changed)
3. SeisComP's `scevent` daemon is currently running (validating config didn't crash it)
4. Config contains correct `eventAssociation.maximumDistance`
5. Config contains correct `eventAssociation.maximumTimeDifference`
6. Config contains correct `eventAssociation.delayTimeSpan`
7. Config contains correct `eventAssociation.magTypes`

Total points: 100
Pass threshold: 75
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_seiscomp_config(text):
    """
    Robustly parses SeisComP .cfg files which can be either flat or INI-styled.
    Handles 'section.key = value' as well as '[section]\\n key = value'.
    """
    config = {}
    current_section = ""
    for line in text.split('\n'):
        line = line.strip()
        
        # Remove inline comments, but be careful of content
        if '#' in line:
            line = line.split('#')[0].strip()
        if not line:
            continue
            
        # Handle INI section headers
        if line.startswith('[') and line.endswith(']'):
            current_section = line[1:-1] + "."
            continue
            
        # Handle key-value pairs
        if '=' in line:
            parts = line.split('=', 1)
            k = parts[0].strip()
            v = parts[1].strip()
            
            # Remove string quotes if agent used them
            if v.startswith('"') and v.endswith('"'):
                v = v[1:-1]
            elif v.startswith("'") and v.endswith("'"):
                v = v[1:-1]
                
            # Compute full key
            if current_section and not k.startswith(current_section):
                full_key = current_section + k
            else:
                full_key = k
                
            config[full_key] = v
            
    return config

def verify_tune_event_association(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_max_dist = float(metadata.get('expected_max_distance', 2.5))
    expected_max_time = float(metadata.get('expected_max_time_diff', 60.0))
    expected_delay = int(metadata.get('expected_delay_time', 15))
    expected_mag_types = [m.lower() for m in metadata.get('expected_mag_types', ["mww", "mwp", "mw", "ml", "mb"])]

    # 1. Read JSON result from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_cfg = tempfile.NamedTemporaryFile(delete=False, suffix='.cfg')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        copy_from_env("/tmp/scevent.cfg.out", temp_cfg.name)
        
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        with open(temp_cfg.name, 'r') as f:
            cfg_text = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve test data: {e}"}
    finally:
        for tmp_file in [temp_json.name, temp_cfg.name]:
            if os.path.exists(tmp_file):
                os.unlink(tmp_file)

    score = 0
    feedback_parts = []
    
    # 2. Check System Operations (30 pts)
    config_modified = result.get('config_modified', False)
    scevent_restarted = result.get('scevent_restarted', False)
    scevent_running = result.get('scevent_running', False)
    
    if config_modified:
        score += 10
        feedback_parts.append("Config file was modified")
    else:
        feedback_parts.append("Config file was NOT modified")
        
    if scevent_restarted:
        score += 10
        feedback_parts.append("scevent service was restarted")
    else:
        feedback_parts.append("scevent service was NOT restarted")
        
    if scevent_running:
        score += 10
        feedback_parts.append("scevent service is actively running")
    else:
        feedback_parts.append("scevent crashed or is stopped (invalid config?)")

    # 3. Check Configuration Integrity (70 pts)
    config_data = parse_seiscomp_config(cfg_text)
    
    # Helper to flexibly find keys
    def get_val(key_suffix):
        for k, v in config_data.items():
            if k.endswith(key_suffix):
                return v
        return None

    # check maximumDistance (15 pts)
    max_dist_val = get_val('maximumDistance')
    if max_dist_val is not None:
        try:
            if float(max_dist_val) == expected_max_dist:
                score += 15
                feedback_parts.append("maximumDistance is correct")
            else:
                feedback_parts.append(f"maximumDistance incorrect: {max_dist_val}")
        except ValueError:
            feedback_parts.append("maximumDistance is not a valid number")
    else:
        feedback_parts.append("maximumDistance not found in config")

    # check maximumTimeDifference (15 pts)
    max_time_val = get_val('maximumTimeDifference')
    if max_time_val is not None:
        try:
            if float(max_time_val) == expected_max_time:
                score += 15
                feedback_parts.append("maximumTimeDifference is correct")
            else:
                feedback_parts.append(f"maximumTimeDifference incorrect: {max_time_val}")
        except ValueError:
            feedback_parts.append("maximumTimeDifference is not a valid number")
    else:
        feedback_parts.append("maximumTimeDifference not found in config")

    # check delayTimeSpan (15 pts)
    delay_time_val = get_val('delayTimeSpan')
    if delay_time_val is not None:
        try:
            if int(float(delay_time_val)) == expected_delay:
                score += 15
                feedback_parts.append("delayTimeSpan is correct")
            else:
                feedback_parts.append(f"delayTimeSpan incorrect: {delay_time_val}")
        except ValueError:
            feedback_parts.append("delayTimeSpan is not a valid number")
    else:
        feedback_parts.append("delayTimeSpan not found in config")

    # check magTypes (25 pts)
    mag_types_val = get_val('magTypes')
    if mag_types_val is not None:
        # split, strip, and lowercase for robust comparison
        parsed_mags = [m.strip().lower() for m in mag_types_val.split(',')]
        if parsed_mags == expected_mag_types:
            score += 25
            feedback_parts.append("magTypes priority list is correct")
        else:
            feedback_parts.append(f"magTypes incorrect: {parsed_mags} vs {expected_mag_types}")
    else:
        feedback_parts.append("magTypes not found in config")

    passed = score >= 75 and scevent_running
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }