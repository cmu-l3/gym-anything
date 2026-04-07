#!/usr/bin/env python3
"""
Verifier for fleet_lease_service_lifecycle task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fleet_lease_service_lifecycle(traj, env_info, task_info):
    """
    Verifies that the vehicle, contract, odometer, and service records were created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fleet_lease_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error during export: {result['error']}"}

    # Get Metadata
    metadata = task_info.get('metadata', {})
    expected_plate = metadata.get('target_license_plate', 'TRK-885-XJ')
    expected_vin = metadata.get('target_vin', '1FT-YRN-2025-XK99')
    expected_contract_cost = metadata.get('contract_cost', 650.0)
    expected_odometer = metadata.get('odometer_value', 45)
    expected_service_cost = metadata.get('service_cost', 125.0)
    expected_vendor = metadata.get('vendor_name', 'Gemini Fleet Services')

    score = 0
    feedback = []

    # 1. Verify Vehicle (25 pts)
    if result.get('vehicle_found'):
        v_data = result['vehicle']
        # Check Plate
        if v_data.get('plate') == expected_plate:
            score += 15
            feedback.append("Vehicle found with correct license plate.")
        else:
            feedback.append(f"Vehicle found but plate mismatch (Expected {expected_plate}, got {v_data.get('plate')}).")
        
        # Check VIN
        if v_data.get('vin') == expected_vin:
            score += 10
            feedback.append("VIN matches.")
        else:
            feedback.append(f"VIN mismatch (Expected {expected_vin}, got {v_data.get('vin')}).")
    else:
        feedback.append("Vehicle not found.")

    # 2. Verify Contract (30 pts)
    if result.get('contract_found'):
        c_data = result['contract']
        # Check Cost
        if abs(c_data.get('cost', 0) - expected_contract_cost) < 1.0:
            score += 20
            feedback.append(f"Contract created with correct cost (${expected_contract_cost}).")
        else:
            feedback.append(f"Contract cost incorrect (Expected {expected_contract_cost}, got {c_data.get('cost')}).")
        
        # Check State
        if c_data.get('state') == 'open':
            score += 10
            feedback.append("Contract is active (In Progress).")
        else:
            feedback.append(f"Contract state is '{c_data.get('state')}' (Expected 'open').")
    else:
        feedback.append("No active contract found for the vehicle.")

    # 3. Verify Odometer (15 pts)
    if result.get('odometer_found'):
        o_val = result['odometer'].get('value', 0)
        if abs(o_val - expected_odometer) < 1.0:
            score += 15
            feedback.append(f"Odometer logged correctly ({expected_odometer} miles).")
        else:
            score += 5 # Partial credit for logging ANY odometer
            feedback.append(f"Odometer value incorrect (Expected {expected_odometer}, got {o_val}).")
    else:
        feedback.append("No odometer reading found.")

    # 4. Verify Service (20 pts)
    if result.get('service_found'):
        s_data = result['service']
        if abs(s_data.get('amount', 0) - expected_service_cost) < 1.0:
            score += 20
            feedback.append(f"Service logged with correct cost (${expected_service_cost}).")
        else:
            score += 10 # Partial for correct service but wrong cost
            feedback.append(f"Service logged but cost incorrect (Expected {expected_service_cost}, got {s_data.get('amount')}).")
    else:
        feedback.append("No service log found matching criteria.")

    # 5. Vendor Check (10 pts)
    # Check if vendor matches on contract OR service
    vendor_match = False
    if result.get('contract_found') and expected_vendor in result['contract'].get('vendor', ''):
        vendor_match = True
    if result.get('service_found') and expected_vendor in result['service'].get('vendor', ''):
        vendor_match = True
    
    if vendor_match:
        score += 10
        feedback.append("Vendor correctly linked.")
    else:
        feedback.append("Vendor 'Gemini Fleet Services' not linked to contract or service.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }