#!/usr/bin/env python3
import json
import os
import tempfile

def verify_configure_name_resolution_forensics(traj, env_info, task_info):
    """
    Verifies that the agent configured Wireshark name resolution correctly and exported resolved results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_client_name = metadata.get('expected_client_name', "Infected_Client")
    expected_server_name = metadata.get('expected_server_name', "Corporate_Mail_Server")

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    hosts_content = result.get('hosts_content', "")
    sys_hosts_content = result.get('sys_hosts_content', "")
    export_content = result.get('export_content', "")
    gt_server_ip = result.get('gt_server_ip', "").strip()
    gt_client_ip = result.get('gt_client_ip', "").strip()
    file_created = result.get('file_created_during_task', False)

    score = 0
    feedback = []

    # ----------------------------------------------------------------
    # CRITERION 1: Hosts Configuration (40 pts)
    # ----------------------------------------------------------------
    # Check both user config (preferred) and system config
    combined_hosts = (hosts_content + "\n" + sys_hosts_content).lower()
    
    # Check Client Mapping
    client_mapped = False
    if gt_client_ip and gt_client_ip in combined_hosts:
        # Check if the line with IP also has the name
        for line in combined_hosts.splitlines():
            if gt_client_ip in line and expected_client_name.lower() in line:
                if not line.strip().startswith('#'): # Ignore comments
                    client_mapped = True
                    break
    
    if client_mapped:
        score += 20
        feedback.append(f"Client IP ({gt_client_ip}) correctly mapped to {expected_client_name}.")
    else:
        feedback.append(f"Failed to map Client IP ({gt_client_ip}) to {expected_client_name} in hosts file.")

    # Check Server Mapping
    server_mapped = False
    if gt_server_ip and gt_server_ip in combined_hosts:
        for line in combined_hosts.splitlines():
            if gt_server_ip in line and expected_server_name.lower() in line:
                if not line.strip().startswith('#'):
                    server_mapped = True
                    break
    
    if server_mapped:
        score += 20
        feedback.append(f"Server IP ({gt_server_ip}) correctly mapped to {expected_server_name}.")
    else:
        feedback.append(f"Failed to map Server IP ({gt_server_ip}) to {expected_server_name} in hosts file.")

    # ----------------------------------------------------------------
    # CRITERION 2: Export File Validation (60 pts)
    # ----------------------------------------------------------------
    if not result.get('export_exists', False):
        feedback.append("Export file 'smtp_resolved.txt' not found.")
    else:
        score += 10 # File exists
        
        if file_created:
            score += 10 # Created during task
        else:
            feedback.append("Warning: Export file timestamp indicates it wasn't created during this task.")

        # Check content for resolved names
        content_lower = export_content.lower()
        
        has_client_name = expected_client_name.lower() in content_lower
        has_server_name = expected_server_name.lower() in content_lower
        
        if has_client_name and has_server_name:
            score += 40
            feedback.append("Export file contains both resolved hostnames.")
        elif has_client_name or has_server_name:
            score += 20
            feedback.append("Export file contains one of the resolved hostnames.")
        else:
            feedback.append("Export file does NOT contain resolved hostnames. Did you enable Name Resolution before exporting?")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    # Pass if score >= 70
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }