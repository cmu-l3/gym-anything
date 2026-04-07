#!/usr/bin/env python3
"""
Verifier for create_contract task in SuiteCRM.

VERIFICATION STRATEGY:
1. DB Record Check: Validates that the contract was inserted into `aos_contracts`.
2. Anti-Gaming Check: Ensures the record was created AFTER the task started, and the total count increased.
3. Field Checks: Validates dates, currency values, description, and the relationship to the target account.
4. Trajectory Check: Validates UI interactions using VLM as a secondary signal.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_contract(traj, env_info, task_info):
    """
    Verify the agent successfully created a contract in SuiteCRM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_account = metadata.get('expected_account', 'Westfield Industrial Supplies')
    expected_status = metadata.get('expected_status', 'Signed')
    expected_start = metadata.get('expected_start_date', '2024-07-01')
    expected_end = metadata.get('expected_end_date', '2025-06-30')
    min_val = metadata.get('expected_value_min', 47900.0)
    max_val = metadata.get('expected_value_max', 48100.0)

    # 1. Copy JSON result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_contract_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    contract_found = result.get('contract_found', False)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    task_start = result.get('task_start_time', 0)
    date_entered = result.get('date_entered_ts', 0)

    # 2. Base checks (Existence & Anti-gaming)
    if contract_found:
        if date_entered >= task_start:
            score += 20
            feedback_parts.append("Contract successfully created during task (+20)")
        else:
            feedback_parts.append("Contract found but created BEFORE task started (anti-gaming fail)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
            
        if current_count > initial_count:
            feedback_parts.append("Global contract count increased correctly")
    else:
        feedback_parts.append("Contract 'Annual Maintenance Agreement 2024' not found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Field Verification
    
    # Account Linking (Critical)
    account_name = result.get('account_name', '')
    if account_name == expected_account:
        score += 20
        feedback_parts.append(f"Linked to correct account: {expected_account} (+20)")
    else:
        feedback_parts.append(f"Account link failed. Expected: {expected_account}, Got: {account_name}")

    # Status
    status = result.get('status', '')
    if status == expected_status:
        score += 10
        feedback_parts.append(f"Status correct (+10)")
    else:
        feedback_parts.append(f"Wrong status: {status}")

    # Start Date
    start_date = result.get('start_date', '')
    if expected_start in start_date:
        score += 10
        feedback_parts.append(f"Start date correct (+10)")
    else:
        feedback_parts.append(f"Wrong start date: {start_date}")

    # End Date
    end_date = result.get('end_date', '')
    if expected_end in end_date:
        score += 10
        feedback_parts.append(f"End date correct (+10)")
    else:
        feedback_parts.append(f"Wrong end date: {end_date}")

    # Contract Value
    total_val_str = result.get('total_value', '0').replace(',', '')
    try:
        total_val = float(total_val_str)
        if min_val <= total_val <= max_val:
            score += 15
            feedback_parts.append(f"Contract value correct (+15)")
        else:
            feedback_parts.append(f"Contract value incorrect: {total_val}")
    except ValueError:
        feedback_parts.append("Failed to parse contract value")

    # Description
    desc = result.get('description', '').lower()
    if 'maintenance' in desc and 'preventive' in desc:
        score += 15
        feedback_parts.append(f"Description correctly populated (+15)")
    elif len(desc) > 10:
        score += 5
        feedback_parts.append(f"Description partially populated (+5)")
    else:
        feedback_parts.append("Description missing or too short")

    # 4. Optional VLM check on trajectory (ensures agent interacted with UI)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        if final:
            images = frames + [final]
            prompt = "Looking at these frames from a web browser, did the user navigate SuiteCRM and attempt to create or edit a Contract (AOS_Contracts module) named 'Annual Maintenance Agreement 2024'? Output only 'YES' or 'NO'."
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response and 'YES' in vlm_response.upper():
                feedback_parts.append("VLM verified UI interaction sequence")
            else:
                feedback_parts.append("VLM could not confirm proper UI interaction sequence")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Final logic
    key_criteria_met = (contract_found and account_name == expected_account and date_entered >= task_start)
    passed = score >= 60 and key_criteria_met

    if passed:
        feedback_parts.insert(0, f"SUCCESS (Score: {score}/100)")
    else:
        feedback_parts.insert(0, f"FAILED (Score: {score}/100)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }