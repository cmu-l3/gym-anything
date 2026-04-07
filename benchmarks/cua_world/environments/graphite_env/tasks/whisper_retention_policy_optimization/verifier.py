#!/usr/bin/env python3
"""
Verifier for whisper_retention_policy_optimization task.

Scoring (100 pts total):
- 15 pts: `[web_traffic]` section added to storage-schemas.conf
- 10 pts: Pattern correctly targets the namespace (`servers.web_traffic.*`)
- 10 pts: Retentions are correctly set (`1m:7d, 10m:30d`)
- 10 pts: Section is prioritized properly (appears before `[default]`)
- 15 pts: `speed_sensor_1.wsp` was successfully resized to match schemas
- 15 pts: `speed_sensor_2.wsp` was successfully resized to match schemas
- 25 pts: Data integrity was preserved (anti-gaming: agent didn't just delete and recreate the DB files)
"""

import json
import tempfile
import os
import re
import configparser
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_data_integrity(data_json):
    """
    Checks if the time-series data contains enough historical non-null values.
    If the agent simply deleted the WSP files to let Carbon recreate them,
    they would lose all past data, resulting in 0-2 datapoints.
    """
    if not isinstance(data_json, list) or len(data_json) == 0:
        return False
    
    datapoints = data_json[0].get("datapoints", [])
    # Count non-null datapoints
    valid_points = sum(1 for dp in datapoints if dp[0] is not None)
    
    # We expect several dozen/hundred datapoints from the historical NAB data.
    # If it's less than 5, it means the DB was wiped and freshly recreated.
    return valid_points >= 5


def check_wsp_resized(wsp_info):
    """
    Verify the Whisper DB structure matches 1m:7d, 10m:30d.
    1m:7d   -> 60 seconds per point, 10080 points
    10m:30d -> 600 seconds per point, 4320 points
    """
    if "error" in wsp_info:
        return False, f"File error: {wsp_info['error']}"
    
    archives = wsp_info.get("archives", [])
    if len(archives) != 2:
        return False, f"Expected 2 archives, found {len(archives)}"
    
    # Archives might not be guaranteed order, so we'll check by resolution
    res_60 = next((a for a in archives if a.get("secondsPerPoint") == 60), None)
    res_600 = next((a for a in archives if a.get("secondsPerPoint") == 600), None)
    
    if not res_60 or res_60.get("points") != 10080:
        return False, "High-res archive (1m:7d) incorrect or missing"
        
    if not res_600 or res_600.get("points") != 4320:
        return False, "Low-res archive (10m:30d) incorrect or missing"
        
    return True, "WSP resized correctly"


def verify_whisper_retention(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    max_score = 100
    feedback_parts = []

    # 1. Load result JSON
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp_json:
        tmp_json_path = tmp_json.name
    
    # 2. Load storage-schemas.conf
    with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as tmp_conf:
        tmp_conf_path = tmp_conf.name

    try:
        copy_from_env("/tmp/whisper_task_result.json", tmp_json_path)
        with open(tmp_json_path, 'r') as f:
            result = json.load(f)
            
        copy_from_env("/tmp/storage-schemas.conf.txt", tmp_conf_path)
        with open(tmp_conf_path, 'r') as f:
            conf_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve files: {e}"}
    finally:
        if os.path.exists(tmp_json_path): os.unlink(tmp_json_path)
        if os.path.exists(tmp_conf_path): os.unlink(tmp_conf_path)

    # --- Verify Configuration File ---
    # We use strict=False because some user edits might duplicate sections accidentally
    config = configparser.ConfigParser(strict=False)
    try:
        config.read_string(conf_content)
        sections = config.sections()
    except Exception as e:
        sections = []
        feedback_parts.append(f"Config parse error: {e}")

    has_section = False
    if "web_traffic" in sections:
        has_section = True
        score += 15
        feedback_parts.append("[+15] [web_traffic] section found")
        
        # Check pattern
        pattern = config.get("web_traffic", "pattern", fallback="").strip()
        # Ensure the regex would match 'servers.web_traffic.speed_sensor_1'
        try:
            if re.match(pattern, "servers.web_traffic.speed_sensor_1"):
                score += 10
                feedback_parts.append(f"[+10] Pattern matches namespace")
            else:
                feedback_parts.append(f"[-] Pattern '{pattern}' is invalid or doesn't match metric")
        except re.error:
            feedback_parts.append("[-] Pattern is an invalid regex")
            
        # Check retentions
        retentions = config.get("web_traffic", "retentions", fallback="").replace(" ", "")
        if retentions == "1m:7d,10m:30d":
            score += 10
            feedback_parts.append("[+10] Retentions configured correctly")
        else:
            feedback_parts.append(f"[-] Incorrect retentions: {retentions}")
            
        # Check order
        try:
            traffic_idx = sections.index("web_traffic")
            default_idx = sections.index("default")
            if traffic_idx < default_idx:
                score += 10
                feedback_parts.append("[+10] Section prioritized before [default]")
            else:
                feedback_parts.append("[-] Section priority wrong (after [default])")
        except ValueError:
            # If default is missing entirely, technically it's prioritized, but they broke the config
            feedback_parts.append("[-] [default] section missing, unable to verify priority")
    else:
        feedback_parts.append("[-] [web_traffic] section missing in config")


    # --- Verify Whisper DB Resizing ---
    whisper_info = result.get("whisper_info", {})
    
    # Sensor 1
    wsp1_info = whisper_info.get("speed_sensor_1.wsp", {"error": "not retrieved"})
    wsp1_ok, wsp1_msg = check_wsp_resized(wsp1_info)
    if wsp1_ok:
        score += 15
        feedback_parts.append(f"[+15] speed_sensor_1.wsp: {wsp1_msg}")
    else:
        feedback_parts.append(f"[-] speed_sensor_1.wsp: {wsp1_msg}")

    # Sensor 2
    wsp2_info = whisper_info.get("speed_sensor_2.wsp", {"error": "not retrieved"})
    wsp2_ok, wsp2_msg = check_wsp_resized(wsp2_info)
    if wsp2_ok:
        score += 15
        feedback_parts.append(f"[+15] speed_sensor_2.wsp: {wsp2_msg}")
    else:
        feedback_parts.append(f"[-] speed_sensor_2.wsp: {wsp2_msg}")


    # --- Verify Data Integrity ---
    data_1 = result.get("data_1", [])
    data_2 = result.get("data_2", [])
    
    integrity_1 = check_data_integrity(data_1)
    integrity_2 = check_data_integrity(data_2)
    
    if integrity_1 and integrity_2:
        score += 25
        feedback_parts.append("[+25] Data integrity preserved (historical metrics intact)")
    else:
        feedback_parts.append("[-] Data integrity lost. DB files were wiped or recreated without history.")


    # Calculate pass status
    # Must get at least 75 points (requires config + resizing + integrity preservation)
    passed = (score >= 75 and has_section and integrity_1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }