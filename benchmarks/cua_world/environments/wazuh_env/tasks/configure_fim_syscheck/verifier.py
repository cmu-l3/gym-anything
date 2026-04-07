#!/usr/bin/env python3
"""
Verifier for configure_fim_syscheck task.

Evaluates:
1. XML content of ossec.conf (modified by agent).
2. Active configuration via Wazuh API (confirms restart).
3. Anti-gaming checks (file modification).
"""

import json
import base64
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_fim_syscheck(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_settings', {})

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Anti-gaming: Check if file was modified
    if not result.get('file_modified', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "ossec.conf was not modified. No work performed."
        }

    # 2. Parse ossec.conf XML
    conf_b64 = result.get('ossec_conf_b64', '')
    if not conf_b64:
        return {"passed": False, "score": 0, "feedback": "Could not read ossec.conf content"}

    try:
        conf_str = base64.b64decode(conf_b64).decode('utf-8')
        # Wrap in root if strictly needed, but ossec.conf usually has <ossec_config> root
        root = ET.fromstring(conf_str)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid XML in ossec.conf: {e}"}

    # Find syscheck section
    # Note: Wazuh config usually looks like <ossec_config><syscheck>...</syscheck></ossec_config>
    syscheck = root.find('syscheck')
    if syscheck is None:
        # Try finding inside global or root
        syscheck = root.find('.//syscheck')
        
    if syscheck is None:
        return {"passed": False, "score": 0, "feedback": "<syscheck> section not found in configuration"}

    # --- Check Settings ---

    # Frequency (10 pts)
    freq = syscheck.find('frequency')
    if freq is not None and freq.text.strip() == expected.get('frequency'):
        score += 10
        feedback_parts.append("Frequency correct")
    else:
        feedback_parts.append(f"Frequency incorrect (expected {expected.get('frequency')})")

    # Alert new files (5 pts)
    alert_new = syscheck.find('alert_new_files')
    if alert_new is not None and alert_new.text.strip().lower() == expected.get('alert_new_files'):
        score += 5
        feedback_parts.append("Alert new files correct")
    else:
        feedback_parts.append("Alert new files incorrect")

    # File Limit (5 pts)
    # Could be <file_limit><entries>100000</entries></file_limit>
    file_limit = syscheck.find('file_limit')
    entries_val = None
    if file_limit is not None:
        entries = file_limit.find('entries')
        if entries is not None:
            entries_val = entries.text.strip()
    
    if entries_val == expected.get('file_limit'):
        score += 5
        feedback_parts.append("File limit correct")
    else:
        feedback_parts.append("File limit incorrect")

    # Directories (50 pts total)
    # Logic: iterate through all <directories> tags, normalize attributes, check against expected
    
    # Parse actual directories from XML
    actual_dirs = []
    for d_node in syscheck.findall('directories'):
        paths = d_node.text.strip().split(',') if d_node.text else []
        attrs = d_node.attrib
        for p in paths:
            actual_dirs.append({'path': p.strip(), 'attrs': attrs})

    expected_dirs = expected.get('directories', [])
    dir_score = 0
    
    for exp_dir in expected_dirs:
        path = exp_dir['path']
        exp_attrs = exp_dir['attrs']
        
        # Find match
        match = False
        for act in actual_dirs:
            if act['path'] == path:
                # Check attributes
                attr_match = True
                for k, v in exp_attrs.items():
                    if act['attrs'].get(k) != v:
                        attr_match = False
                        break
                if attr_match:
                    match = True
                    break
        
        if match:
            dir_score += 10
            feedback_parts.append(f"Directory {path} configured correctly")
        else:
            feedback_parts.append(f"Directory {path} missing or attributes incorrect")

    score += dir_score

    # Ignore entries (15 pts total)
    actual_ignores = [node.text.strip() for node in syscheck.findall('ignore') if node.text]
    expected_ignores = expected.get('ignores', [])
    
    ignore_score = 0
    for ign in expected_ignores:
        if ign in actual_ignores:
            ignore_score += 5
    
    if ignore_score == 15:
        feedback_parts.append("All ignore entries present")
    else:
        feedback_parts.append(f"Ignore entries partial match ({ignore_score}/15 pts)")
        
    score += ignore_score

    # 3. Check API Status (15 pts)
    # If the API returns the config with our changes, it means the manager was successfully restarted
    # and the config is valid.
    api_config_b64 = result.get('api_config_b64', '')
    manager_active = result.get('manager_active', False)
    
    if manager_active and api_config_b64:
        try:
            api_json_str = base64.b64decode(api_config_b64).decode('utf-8')
            api_data = json.loads(api_json_str)
            
            # Navigate nested API response: data -> affected_items[0] -> syscheck
            # Structure depends on exact API, but let's check basic presence
            # Usually: {"data": {"affected_items": [{"frequency": 3600, ...}]}}
            items = api_data.get('data', {}).get('affected_items', [])
            if items:
                config = items[0]
                # Check one key indicator (frequency) to ensure it's the NEW config
                if str(config.get('frequency', '')) == expected.get('frequency'):
                    score += 15
                    feedback_parts.append("Manager active with new configuration")
                else:
                    feedback_parts.append("Manager active but running OLD configuration (did not restart?)")
            else:
                 feedback_parts.append("Manager active but returned no config")
        except Exception as e:
            feedback_parts.append(f"Failed to parse API response: {e}")
    else:
        feedback_parts.append("Manager API not reachable (manager likely down)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }