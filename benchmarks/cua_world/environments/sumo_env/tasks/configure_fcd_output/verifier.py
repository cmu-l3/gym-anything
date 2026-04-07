#!/usr/bin/env python3
"""
Verifier for configure_fcd_output@1 task in SUMO.
Validates the creation of a valid SUMO configuration file and
evaluates the generated Floating Car Data (FCD) XML file.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_fcd_output(traj, env_info, task_info):
    """
    Verify the FCD configuration task.

    Checks:
    1. Config file exists, is valid XML, and retains network inputs (20 points)
    2. Config has FCD output properly set with period and time bounds (20 points)
    3. FCD XML file exists and is of reasonable size (15 points)
    4. FCD XML contains valid <timestep> and <vehicle> elements (20 points)
    5. FCD timestamps span approx 500s with 1.0s gap (15 points)
    6. Tripinfo XML exists and files were created post-start (10 points)

    Pass threshold: 60 points with key criteria met.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata expectations
    metadata = task_info.get('metadata', {})
    expected_fcd_period = metadata.get('fcd_period', "1.0")
    expected_begin = metadata.get('begin_time', "0")
    expected_end = metadata.get('end_time', "500")
    min_fcd_size = metadata.get('min_fcd_size_bytes', 102400)

    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Config Validation (20 points)
    if result.get("config_valid"):
        score += 10
        feedback_parts.append("Config valid XML (+10)")
    else:
        feedback_parts.append("Config missing or invalid")

    if result.get("config_retains_inputs"):
        score += 10
        feedback_parts.append("Config retains inputs (+10)")
    else:
        feedback_parts.append("Config missing original inputs")

    # 2. Config Output Settings (20 points)
    if result.get("config_fcd_path_correct"):
        score += 10
        feedback_parts.append("FCD path correct (+10)")
    elif result.get("config_has_fcd_output"):
        score += 5
        feedback_parts.append("FCD output set but path incorrect (+5)")
    
    fcd_period = result.get("config_fcd_period", "")
    if fcd_period in [expected_fcd_period, "1", "1.00"]:
        score += 5
        feedback_parts.append("FCD period correct (+5)")

    if result.get("config_has_begin_end"):
        begin = result.get("config_begin", "")
        end = result.get("config_end", "")
        if begin in [expected_begin, "0.0"] and end in [expected_end, "500.0"]:
            score += 5
            feedback_parts.append("Time bounds correct (+5)")
        else:
            score += 2
            feedback_parts.append("Time bounds present but incorrect (+2)")

    # 3. FCD File Existence (15 points)
    fcd_size = result.get("fcd_file_size", 0)
    if result.get("fcd_file_exists"):
        if fcd_size > min_fcd_size:
            score += 15
            feedback_parts.append(f"FCD file generated, robust size ({fcd_size//1024} KB) (+15)")
        elif fcd_size > 0:
            score += 8
            feedback_parts.append(f"FCD file generated, small size ({fcd_size//1024} KB) (+8)")
    else:
        feedback_parts.append("FCD file missing")

    # 4. FCD Data Structure (20 points)
    if result.get("fcd_has_timesteps") and result.get("fcd_timestep_count", 0) > 100:
        score += 10
        feedback_parts.append("FCD contains sufficient timesteps (+10)")
    elif result.get("fcd_has_timesteps"):
        score += 5
        feedback_parts.append("FCD contains some timesteps (+5)")
        
    if result.get("fcd_has_required_attrs"):
        score += 10
        feedback_parts.append("FCD vehicles have correct attributes (x, y, speed) (+10)")
    elif result.get("fcd_has_vehicles"):
        score += 5
        feedback_parts.append("FCD has vehicles but missing attributes (+5)")

    # 5. FCD Time Span & Period Gap (15 points)
    time_span = result.get("fcd_time_span", 0)
    if time_span >= 400:
        score += 10
        feedback_parts.append("FCD time span covers run (+10)")
    elif time_span >= 100:
        score += 5
        feedback_parts.append("FCD time span partial (+5)")

    avg_gap = result.get("fcd_avg_timestep_gap")
    if avg_gap is not None and 0.8 <= avg_gap <= 1.2:
        score += 5
        feedback_parts.append("FCD timestep gap ~1.0s (+5)")
    elif avg_gap is not None and avg_gap > 0:
        score += 2
        feedback_parts.append("FCD timestep gap valid but not 1.0s (+2)")

    # 6. Secondary outputs and Anti-Gaming (10 points)
    if result.get("tripinfo_exists"):
        score += 5
        feedback_parts.append("Tripinfo exists (+5)")
        
    if result.get("files_created_after_start"):
        score += 5
        feedback_parts.append("Outputs are new (anti-gaming check passed) (+5)")
    else:
        feedback_parts.append("WARNING: Outputs pre-date task start (potential gaming)")

    # Determine Pass/Fail
    # Key criteria: config is valid, FCD file exists, file is new
    key_criteria = (
        result.get("config_valid", False) and 
        result.get("fcd_file_exists", False) and 
        result.get("files_created_after_start", False)
    )
    passed = score >= 60 and key_criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }