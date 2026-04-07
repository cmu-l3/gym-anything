#!/usr/bin/env python3
"""Verifier for network_asset_lookup task.

Scoring Criteria (20 points each, 100 total):
1. CSV file exists and was created during the task (Anti-gaming check)
2. CSV file has the required headers (src_ip, department, asset_criticality)
3. Lookup Definition 'network_asset_lookup' exists and references the CSV
4. Automatic Lookup 'asset_context_for_security' exists and targets 'linux_secure'
5. Automatic Lookup correctly maps fields (outputs department and asset_criticality)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_network_asset_lookup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_name = metadata.get('expected_csv_name', 'network_assets.csv')
    expected_def_name = metadata.get('expected_def_name', 'network_asset_lookup')
    expected_auto_name = metadata.get('expected_auto_name', 'asset_context_for_security')
    expected_sourcetype = metadata.get('expected_sourcetype', 'linux_secure')

    # Read the exported results
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
    task_start = result.get('task_start_timestamp', 0)
    
    csv_data = result.get('csv', {})
    api_data = result.get('api_analysis', {})
    
    # ---------------------------------------------------------
    # Criterion 1: CSV exists and created during task (20 pts)
    # ---------------------------------------------------------
    csv_exists = csv_data.get('exists', False)
    csv_mtime = csv_data.get('mtime', 0)
    
    if csv_exists:
        # Give a 5-second buffer in case of very fast setup vs file write
        if csv_mtime >= (task_start - 5):
            score += 20
            feedback_parts.append("CSV file created during task")
        else:
            feedback_parts.append(f"FAIL: CSV file existed before task (mtime {csv_mtime} < start {task_start})")
            # If they cheated here, they likely didn't do the work. Give no credit for CSV existence.
            csv_exists = False 
    else:
        feedback_parts.append("FAIL: CSV file not found in Splunk lookup directories")

    # ---------------------------------------------------------
    # Criterion 2: CSV has the correct headers (20 pts)
    # ---------------------------------------------------------
    if csv_exists:
        headers = csv_data.get('headers', '').lower()
        required_headers = ['src_ip', 'department', 'asset_criticality']
        
        if all(h in headers for h in required_headers):
            score += 20
            feedback_parts.append("CSV contains required headers")
        else:
            feedback_parts.append(f"FAIL: CSV headers missing required fields (Got: {headers})")

    # ---------------------------------------------------------
    # Criterion 3: Lookup Definition exists and links CSV (20 pts)
    # ---------------------------------------------------------
    def_exists = api_data.get('lookup_def_exists', False)
    def_filename = api_data.get('lookup_def_filename', '')
    
    if def_exists:
        if expected_csv_name.lower() in def_filename.lower():
            score += 20
            feedback_parts.append(f"Lookup definition '{expected_def_name}' exists and links to CSV")
        else:
            feedback_parts.append(f"FAIL: Lookup definition exists but links to wrong file: '{def_filename}'")
    else:
        feedback_parts.append(f"FAIL: Lookup definition '{expected_def_name}' not found")

    # ---------------------------------------------------------
    # Criterion 4: Automatic Lookup exists for linux_secure (20 pts)
    # ---------------------------------------------------------
    auto_exists = api_data.get('auto_lookup_exists', False)
    auto_stanza = api_data.get('auto_lookup_stanza', '').lower()
    
    if auto_exists:
        if expected_sourcetype.lower() in auto_stanza:
            score += 20
            feedback_parts.append(f"Automatic lookup '{expected_auto_name}' exists and targets '{expected_sourcetype}'")
        else:
            feedback_parts.append(f"FAIL: Automatic lookup exists but targets wrong stanza: '{auto_stanza}'")
    else:
        feedback_parts.append(f"FAIL: Automatic lookup '{expected_auto_name}' not found")

    # ---------------------------------------------------------
    # Criterion 5: Auto Lookup maps correctly (20 pts)
    # ---------------------------------------------------------
    if auto_exists:
        content = api_data.get('auto_lookup_content', {})
        # The configuration string is usually in a 'value' field or similar
        config_string = str(content).lower()
        
        # Check that it uses the expected lookup definition and outputs required fields
        uses_def = expected_def_name.lower() in config_string
        outputs_dept = 'department' in config_string
        outputs_crit = 'asset_criticality' in config_string
        
        if uses_def and outputs_dept and outputs_crit:
            score += 20
            feedback_parts.append("Automatic lookup maps definition and output fields correctly")
        else:
            feedback_parts.append("FAIL: Automatic lookup is missing field mappings (check definition name and OUTPUTNEW)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }