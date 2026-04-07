#!/usr/bin/env python3
"""Verifier for scripted_input_pipeline task.

Checks:
1. Script placed in the correct directory (/opt/splunk/etc/apps/search/bin/) (15 pts)
2. Script is executable (10 pts)
3. Script contains real dynamic telemetry commands (no hardcoded echo values) (20 pts)
4. Splunk Scripted Input is correctly configured via REST API (20 pts)
5. Saved search 'Live_Telemetry_Monitor' exists and queries target data (15 pts)
6. Data successfully executed and ingested into the index (20 pts)

Pass threshold: 75 points.
"""

import json
import tempfile
import os
import base64
import logging
import re

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Commands that indicate the agent is trying to grab real system metrics
DYNAMIC_CMDS = [
    'df ', 'free ', 'uptime', 'vmstat', 'iostat', 'top ', 'ps ', 
    '/proc/meminfo', '/proc/loadavg', '/proc/stat', 'sar ', 'mpstat',
    'subprocess', 'os.popen', 'psutil'
]

def verify_scripted_input_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_bin_path = metadata.get('expected_bin_path', '/opt/splunk/etc/apps/search/bin/')
    expected_index = metadata.get('expected_index', 'system_logs')
    expected_sourcetype = metadata.get('expected_sourcetype', 'os_telemetry')
    expected_search_name = metadata.get('expected_search_name', 'Live_Telemetry_Monitor')
    expected_event_marker = metadata.get('expected_event_marker', 'event_type=live_os_telemetry')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/scripted_input_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    subscores = {}

    script_path = result.get('script_path', '')
    script_exec = result.get('script_executable', False)
    script_content_b64 = result.get('script_content_b64', '')
    inputs_api = result.get('inputs_api', {})
    search_api = result.get('search_api', {})
    event_count = result.get('event_count', 0)

    # Decode script content
    script_content = ""
    if script_content_b64:
        try:
            script_content = base64.b64decode(script_content_b64).decode('utf-8')
        except:
            pass

    # Criterion 1: Script Placement (15 pts)
    if script_path and script_path.startswith(expected_bin_path):
        score += 15
        feedback_parts.append(f"Script placed correctly: {os.path.basename(script_path)}")
        subscores['script_placement'] = True
    else:
        feedback_parts.append("FAIL: Script not found in /opt/splunk/etc/apps/search/bin/")
        subscores['script_placement'] = False

    # Criterion 2: Executable (10 pts)
    if script_exec:
        score += 10
        feedback_parts.append("Script is executable (+x)")
        subscores['script_executable'] = True
    else:
        feedback_parts.append("FAIL: Script is not executable (missing chmod +x)")
        subscores['script_executable'] = False

    # Criterion 3: Real Telemetry Logic (20 pts)
    has_dynamic_logic = False
    has_event_marker = expected_event_marker in script_content
    
    if script_content:
        if any(cmd in script_content for cmd in DYNAMIC_CMDS):
            has_dynamic_logic = True
            
    if has_dynamic_logic and has_event_marker:
        score += 20
        feedback_parts.append("Script uses real dynamic OS commands and includes event marker")
        subscores['real_logic'] = True
    elif has_dynamic_logic:
        score += 10
        feedback_parts.append("Script uses real dynamic commands but missing required event_type marker")
        subscores['real_logic'] = False
    elif script_content:
        feedback_parts.append("FAIL: Script appears to use hardcoded strings instead of real OS metrics commands")
        subscores['real_logic'] = False
    else:
        feedback_parts.append("FAIL: Script content is empty or unreadable")
        subscores['real_logic'] = False

    # Criterion 4: Input Configured (20 pts)
    input_entries = inputs_api.get('entry', [])
    input_configured = False
    
    script_basename = os.path.basename(script_path) if script_path else "UNKNOWN_SCRIPT"
    
    for entry in input_entries:
        name = entry.get('name', '')
        content = entry.get('content', {})
        
        # Check if this input matches the script name created, or has the correct sourcetype as fallback
        if script_basename in name or content.get('sourcetype') == expected_sourcetype:
            if content.get('index') == expected_index:
                input_configured = True
                break

    if input_configured:
        score += 20
        feedback_parts.append(f"Scripted Input properly configured for index '{expected_index}'")
        subscores['input_configured'] = True
    else:
        feedback_parts.append("FAIL: Scripted Input not configured properly (check path, sourcetype, or index)")
        subscores['input_configured'] = False

    # Criterion 5: Saved Search Created (15 pts)
    search_entries = search_api.get('entry', [])
    search_configured = False
    
    if search_entries:
        entry = search_entries[0]
        content = entry.get('content', {})
        query = content.get('search', '').lower()
        if expected_index in query and 'event_type' in query:
            search_configured = True
            
    if search_configured:
        score += 15
        feedback_parts.append(f"Saved search '{expected_search_name}' exists and queries the correct data")
        subscores['search_created'] = True
    else:
        feedback_parts.append(f"FAIL: Saved search '{expected_search_name}' missing or incorrect query")
        subscores['search_created'] = False

    # Criterion 6: Data Ingested (20 pts)
    if event_count > 0:
        score += 20
        feedback_parts.append(f"Success: {event_count} events generated by script were ingested into Splunk!")
        subscores['data_ingested'] = True
    else:
        feedback_parts.append("FAIL: No events found in index. Splunk failed to run script or ingest data.")
        subscores['data_ingested'] = False

    passed = score >= 75 and subscores.get('input_configured', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "event_count": event_count,
            "script_path": script_path,
            "script_preview": script_content[:100] + "..." if len(script_content) > 100 else script_content
        }
    }