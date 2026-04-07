#!/usr/bin/env python3
"""
Verifier for system_health_diagnostic task.
Verifies the agent's JSON report against ground truth data collected via API.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_system_health_diagnostic(traj, env_info, task_info):
    """
    Verify the system health report.
    
    Scoring Breakdown (100 pts total):
    - 5 pts: Report file exists
    - 5 pts: File created during task (anti-gaming)
    - 5 pts: Valid JSON format
    - 15 pts: Correct top-level structure (all 6 required keys)
    - 10 pts: Metadata correctness (timestamp valid, report_type correct)
    - 10 pts: System Info match (system name matches ground truth)
    - 20 pts: Cameras section (count matches ground truth, structure valid)
    - 20 pts: Users section (count matches ground truth, structure valid)
    - 10 pts: Server/Storage sections populated
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve task result (contains ground truth and file status)
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_result_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result_path)
        with open(temp_result_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result_path):
            os.unlink(temp_result_path)

    score = 0
    feedback_parts = []
    
    # Ground Truth Data
    ground_truth = task_result.get('ground_truth', {})
    gt_cam_count = ground_truth.get('camera_count', 0)
    gt_user_count = ground_truth.get('user_count', 0)
    gt_system_name = ground_truth.get('system_name', '')
    
    # Check 1: File Existence & Creation Time
    report_exists = task_result.get('report_exists', False)
    created_during = task_result.get('file_created_during_task', False)
    
    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not found at ~/reports/system_health_report.json"}
    
    score += 5
    feedback_parts.append("File exists")
    
    if created_during:
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("WARN: File timestamp predates task start")

    # 2. Retrieve Agent's Report
    report_path = task_result.get('report_path')
    agent_report = {}
    
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_report_path = f.name
        
    try:
        copy_from_env(report_path, temp_report_path)
        with open(temp_report_path, 'r') as f:
            agent_report = json.load(f)
        score += 5
        feedback_parts.append("Valid JSON")
    except json.JSONDecodeError:
        return {"passed": False, "score": score, "feedback": "File is not valid JSON"}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Could not read report file: {e}"}
    finally:
        if os.path.exists(temp_report_path):
            os.unlink(temp_report_path)

    # Check 3: Top-Level Structure
    required_keys = ["report_metadata", "server_info", "cameras", "users", "storage", "system_settings"]
    missing_keys = [k for k in required_keys if k not in agent_report]
    
    if not missing_keys:
        score += 15
        feedback_parts.append("Structure correct")
    else:
        feedback_parts.append(f"Missing keys: {', '.join(missing_keys)}")
        # If major keys missing, penalty
        score += max(0, 15 - (len(missing_keys) * 3))

    # Check 4: Metadata
    meta = agent_report.get('report_metadata', {})
    if meta.get('report_type') == 'system_health_diagnostic':
        score += 5
    
    # Validate timestamp format (ISO 8601-ish)
    ts = meta.get('generated_at', '')
    valid_ts = False
    try:
        if ts:
            # Simple check for ISO format chars
            if 'T' in ts and (ts.endswith('Z') or '+' in ts or '-' in ts):
                valid_ts = True
                score += 5
    except:
        pass
    if not valid_ts:
        feedback_parts.append("Invalid/missing timestamp")

    # Check 5: System Info
    rep_sys_name = meta.get('system_name', '')
    if rep_sys_name and rep_sys_name == gt_system_name:
        score += 10
        feedback_parts.append("System name matches")
    elif rep_sys_name:
        score += 5
        feedback_parts.append(f"System name mismatch ('{rep_sys_name}' vs '{gt_system_name}')")
    else:
        feedback_parts.append("System name missing")

    # Check 6: Cameras
    cams = agent_report.get('cameras', {})
    devices = cams.get('devices', [])
    summary = cams.get('summary', {})
    
    # Check device list count against ground truth (allow +/- 1 tolerance for timing)
    rep_dev_count = len(devices) if isinstance(devices, list) else 0
    if abs(rep_dev_count - gt_cam_count) <= 1 and rep_dev_count > 0:
        score += 10
    else:
        feedback_parts.append(f"Camera count incorrect ({rep_dev_count} vs {gt_cam_count})")
    
    # Check summary count
    if summary.get('total_count') == rep_dev_count:
        score += 5
    
    # Check device object structure
    if devices and isinstance(devices, list) and all(k in devices[0] for k in ['id', 'name', 'status']):
        score += 5

    # Check 7: Users
    users = agent_report.get('users', {})
    accounts = users.get('accounts', [])
    
    rep_user_count = len(accounts) if isinstance(accounts, list) else 0
    if abs(rep_user_count - gt_user_count) <= 1 and rep_user_count > 0:
        score += 15
    else:
        feedback_parts.append(f"User count incorrect ({rep_user_count} vs {gt_user_count})")
        
    if users.get('summary', {}).get('total_count') == rep_user_count:
        score += 5

    # Check 8: Other Sections (Servers/Storage)
    servers = agent_report.get('server_info', {}).get('servers', [])
    storage = agent_report.get('storage', {}).get('locations', [])
    
    if isinstance(servers, list) and len(servers) > 0:
        score += 5
    if isinstance(storage, list): # Storage might be empty but key must exist
        score += 5

    # Final Evaluation
    passed = score >= 70
    
    # CRITICAL GATE: Must have correct structure and roughly correct data
    if missing_keys or rep_dev_count == 0:
        passed = False
        feedback_parts.append("FAILED: Critical data missing")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }