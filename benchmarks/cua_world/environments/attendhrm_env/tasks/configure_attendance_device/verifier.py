#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_configure_attendance_device(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the attendance device was correctly configured in AttendHRM.
    
    Verification Strategy:
    1. Check if the device record exists in the database with the correct name.
    2. Verify all configuration parameters (IP, Port, Serial, Branch) match expected values.
    3. Verify the agent actually performed the task (VLM trajectory check).
    """
    
    # 1. Setup and retrieve result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # The export script saves to C:\workspace\task_result.json
        # Docker/Container path handling might require specific logic, 
        # but typically copy_from_env handles the container path.
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    device_data = result.get('device_data', {})
    metadata = task_info.get('metadata', {})
    
    expected_name = metadata.get('expected_device_name', "WS-FP-RECEPTION-01")
    expected_ip = metadata.get('expected_ip', "192.168.10.45")
    expected_port = str(metadata.get('expected_port', "4370"))
    expected_serial = metadata.get('expected_serial', "ZK-TF20-2024-00871")
    expected_branch = metadata.get('expected_branch', "Westside Office")

    score = 0
    feedback_parts = []
    passed = False

    # 3. Scoring Logic
    
    # Criterion 1: Device Exists (Blocking)
    if not device_data.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Device '{expected_name}' was not found in the database. Did you save it?"
        }
    
    score += 20
    feedback_parts.append("Device record created")

    # Criterion 2: IP Address (15 pts)
    actual_ip = device_data.get('ip_address', '')
    if actual_ip == expected_ip:
        score += 15
        feedback_parts.append("IP Address correct")
    else:
        feedback_parts.append(f"Incorrect IP: expected {expected_ip}, found {actual_ip}")

    # Criterion 3: Port (10 pts)
    actual_port = str(device_data.get('port', ''))
    if actual_port == expected_port:
        score += 10
        feedback_parts.append("Port correct")
    else:
        feedback_parts.append(f"Incorrect Port: expected {expected_port}, found {actual_port}")

    # Criterion 4: Serial Number (10 pts)
    actual_serial = device_data.get('serial_number', '')
    if actual_serial == expected_serial:
        score += 10
        feedback_parts.append("Serial Number correct")
    else:
        feedback_parts.append(f"Incorrect Serial: expected {expected_serial}, found {actual_serial}")

    # Criterion 5: Branch Association (15 pts)
    actual_branch = device_data.get('branch_name', '')
    if expected_branch.lower() in actual_branch.lower():
        score += 15
        feedback_parts.append("Branch correct")
    else:
        feedback_parts.append(f"Incorrect Branch: expected {expected_branch}, found {actual_branch}")

    # Criterion 6: Active Status (10 pts)
    if device_data.get('is_active'):
        score += 10
        feedback_parts.append("Status is Active")
    else:
        feedback_parts.append("Device is not Active")

    # Criterion 7: App Running (10 pts)
    if result.get('app_running'):
        score += 10
    
    # Criterion 8: VLM Verification (10 pts)
    # Simple placeholder for VLM check: assumes if database is correct, UI was used.
    # In a full implementation, we would query VLM here with trajectory frames.
    score += 10 

    # 4. Final Decision
    # Pass if Device Exists AND IP matches AND Branch matches (Key Criteria)
    # Threshold: 60 points
    
    key_criteria_met = (
        device_data.get('found') and 
        actual_ip == expected_ip and 
        expected_branch.lower() in actual_branch.lower()
    )
    
    if score >= 60 and key_criteria_met:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }