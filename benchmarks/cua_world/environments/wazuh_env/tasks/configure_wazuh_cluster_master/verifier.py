#!/usr/bin/env python3
"""
Verifier for configure_wazuh_cluster_master task.

Checks:
1. ossec.conf was modified.
2. XML configuration is correct (Cluster enabled, correct name, key, etc.).
3. wazuh-clusterd daemon is running.
4. API reports cluster is active and node is master.
"""

import json
import os
import tempfile
import logging
import re
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_wazuh_cluster_master(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_cluster_name = metadata.get('expected_cluster_name', 'security-ops-cluster')
    expected_node_name = metadata.get('expected_node_name', 'wazuh-master-01')
    expected_node_type = metadata.get('expected_node_type', 'master')
    expected_key = metadata.get('expected_key', 'c987654321fedcba0123456789abcdef')
    expected_bind_addr = metadata.get('expected_bind_addr', '0.0.0.0')

    # Load result
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
    feedback = []

    # 1. Anti-gaming: File modified
    if result.get('file_modified', False):
        score += 5
        feedback.append("Configuration file was modified.")
    else:
        feedback.append("Configuration file was NOT modified.")

    # 2. Check XML Configuration
    cluster_xml_str = result.get('cluster_block', '').strip()
    config_correct = False
    
    if not cluster_xml_str:
        feedback.append("Could not find <cluster> block in configuration.")
    else:
        try:
            # Wrap in root to make it valid XML for parsing if needed, though <cluster> is root here
            # xml.etree requires a single root.
            root = ET.fromstring(cluster_xml_str)
            
            # Check <disabled>
            disabled = root.find('disabled')
            if disabled is not None and disabled.text.strip().lower() == 'no':
                score += 15
                feedback.append("Cluster module is enabled.")
            else:
                feedback.append("Cluster module is NOT enabled (disabled != no).")

            # Check <name>
            name = root.find('name')
            if name is not None and name.text.strip() == expected_cluster_name:
                score += 10
                feedback.append(f"Cluster name is correct ({expected_cluster_name}).")
            else:
                val = name.text.strip() if name is not None else "None"
                feedback.append(f"Cluster name incorrect. Expected: {expected_cluster_name}, Got: {val}")

            # Check <node_name>
            node_name = root.find('node_name')
            if node_name is not None and node_name.text.strip() == expected_node_name:
                score += 10
                feedback.append(f"Node name is correct ({expected_node_name}).")
            else:
                val = node_name.text.strip() if node_name is not None else "None"
                feedback.append(f"Node name incorrect. Expected: {expected_node_name}, Got: {val}")

            # Check <node_type>
            node_type = root.find('node_type')
            if node_type is not None and node_type.text.strip() == expected_node_type:
                score += 10
                feedback.append(f"Node type is correct ({expected_node_type}).")
            else:
                val = node_type.text.strip() if node_type is not None else "None"
                feedback.append(f"Node type incorrect. Expected: {expected_node_type}, Got: {val}")

            # Check <key>
            key = root.find('key')
            if key is not None and key.text.strip() == expected_key:
                score += 10
                feedback.append("Cluster key is correct.")
            else:
                feedback.append("Cluster key is incorrect.")

            # Check <bind_addr>
            bind = root.find('bind_addr')
            if bind is not None and bind.text.strip() == expected_bind_addr:
                score += 10
                feedback.append(f"Bind address is correct ({expected_bind_addr}).")
            else:
                feedback.append("Bind address is incorrect.")

        except ET.ParseError:
            feedback.append("Failed to parse XML configuration. Syntax error?")

    # 3. Check Daemon Status
    if result.get('daemon_running', False):
        score += 20
        feedback.append("wazuh-clusterd process is running.")
    else:
        feedback.append("wazuh-clusterd process is NOT running.")

    # 4. Check API Status
    api_status = result.get('api_status', {})
    # API /cluster/status returns: {"data": {"enabled": "yes", "running": "yes"}}
    api_data = api_status.get('data', {})
    if isinstance(api_data, dict):
        if api_data.get('enabled') == 'yes' and api_data.get('running') == 'yes':
            score += 10
            feedback.append("API confirms cluster is running.")
        else:
            feedback.append(f"API reports cluster not running (enabled={api_data.get('enabled')}, running={api_data.get('running')}).")
    
    # 5. Check Control Status Output (fallback)
    control_status = result.get('control_status', '')
    if "wazuh-clusterd is running" in control_status:
         # Already handled by daemon_running check, but confirms service manager sees it
         pass

    # Final scoring logic
    # Pass if daemon is running AND configuration is mostly correct
    passed = score >= 80 and result.get('daemon_running', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }