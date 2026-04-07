#!/usr/bin/env python3
"""
Verifier for configure_virustotal_integration task.

Verifies:
1. ossec.conf was modified (anti-gaming)
2. VirusTotal integration block exists in XML
3. Parameters (API key, group, level, format) are correct
4. Wazuh manager service is running (config is valid)
5. Wazuh API confirms integration is loaded
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_virustotal_integration(traj, env_info, task_info):
    """
    Verify Wazuh VirusTotal integration configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_api_key = metadata.get('expected_api_key', "9c3a5b8e2f1d4a7c6b0e9f8d7c5a3b1e4f2d6a8c0b9e7f5d3a1c4b6e8f0a2d74")
    expected_group = metadata.get('expected_group', "syscheck")
    expected_level = metadata.get('expected_level', "7")
    expected_format = metadata.get('expected_format', "json")

    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Extract data from result
    config_modified = result.get('config_modified', False)
    manager_running = result.get('manager_running', False)
    api_integration_found = result.get('api_integration_found', False)
    xml_data = result.get('xml_parsed', {})
    
    # 1. Anti-Gaming: Was config modified?
    if not config_modified:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Configuration file was not modified. No changes detected."
        }
    
    # 2. XML Block Existence (15 pts)
    if xml_data.get('found_block'):
        score += 15
        feedback_parts.append("Integration block found")
    else:
        feedback_parts.append("Integration block missing or malformed")
    
    # 3. Parameter Verification
    
    # API Key (20 pts)
    actual_key = xml_data.get('api_key', '')
    if actual_key == expected_api_key:
        score += 20
        feedback_parts.append("API Key correct")
    elif actual_key:
        feedback_parts.append(f"Incorrect API Key")
    else:
        feedback_parts.append("API Key missing")
        
    # Group (15 pts)
    actual_group = xml_data.get('group', '')
    if actual_group == expected_group:
        score += 15
        feedback_parts.append("Group filter correct")
    else:
        feedback_parts.append(f"Group filter incorrect (found: '{actual_group}')")
        
    # Level (15 pts)
    actual_level = xml_data.get('level', '')
    if str(actual_level) == str(expected_level):
        score += 15
        feedback_parts.append("Alert level correct")
    else:
        feedback_parts.append(f"Alert level incorrect (found: '{actual_level}')")
        
    # Format (10 pts)
    actual_format = xml_data.get('format', '')
    if actual_format == expected_format:
        score += 10
        feedback_parts.append("Alert format correct")
    else:
        feedback_parts.append(f"Alert format incorrect (found: '{actual_format}')")
        
    # 4. Operational Check: Manager Running (15 pts)
    if manager_running:
        score += 15
        feedback_parts.append("Manager service is running")
    else:
        feedback_parts.append("Manager service is NOT running (likely config error)")
        
    # 5. Operational Check: API Confirmation (10 pts)
    if api_integration_found:
        score += 10
        feedback_parts.append("API confirms integration loaded")
    else:
        if manager_running:
            feedback_parts.append("Manager running but API does not show integration (restart may be pending or config ignored)")
        else:
            feedback_parts.append("API check failed (manager down)")

    # Pass Threshold: 70
    # Must have manager running and correct API key to be considered useful
    passed = score >= 70 and manager_running and (xml_data.get('api_key', '') == expected_api_key)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }