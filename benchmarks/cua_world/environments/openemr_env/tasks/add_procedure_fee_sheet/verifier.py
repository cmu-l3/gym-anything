#!/usr/bin/env python3
"""
Verifier for Add Procedure to Fee Sheet task in OpenEMR

MULTI-SIGNAL VERIFICATION:
1. Billing entry exists with correct code (25 points)
2. Correct code type (CPT4) (15 points)
3. Entry is active (activity=1) (15 points)
4. Entry linked to valid encounter (20 points)
5. Entry was created during task (15 points) - anti-gaming
6. Correct patient linked (10 points)

Pass threshold: 70 points minimum with billing entry existing
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_procedure_fee_sheet(traj, env_info, task_info):
    """
    Verify that procedure code 99213 was added to the fee sheet for patient Gerald Koss.
    
    Uses copy_from_env to read exported verification data from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Gerald')
    expected_lname = metadata.get('patient_lname', 'Koss')
    expected_code = metadata.get('expected_cpt_code', '99213')
    expected_code_type = metadata.get('expected_code_type', 'CPT4')
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/fee_sheet_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "billing_entry_exists": False,
            "correct_code_type": False,
            "entry_active": False,
            "encounter_linked": False,
            "created_during_task": False,
            "correct_patient": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_billing_count', 0)
        current_count = result.get('current_billing_count', 0)
        billing_found = result.get('billing_entry_found', False)
        new_entry = result.get('new_entry_created', False)
        billing = result.get('billing', {})
        validation = result.get('validation', {})
        
        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}")
        logger.info(f"Billing found={billing_found}, new_entry={new_entry}")
        logger.info(f"Billing data: {billing}")
        
        # CRITERION 1: Billing entry exists with correct code (25 points)
        if billing_found:
            billing_code = billing.get('code', '')
            if billing_code == expected_code:
                score += 25
                subscores["billing_entry_exists"] = True
                feedback_parts.append(f"Billing entry found with code {expected_code}")
            else:
                score += 10  # Partial credit for finding any billing entry
                feedback_parts.append(f"Billing entry found but wrong code: expected {expected_code}, got {billing_code}")
        else:
            feedback_parts.append(f"No billing entry found with code {expected_code}")
            # Check if any billing was added
            if current_count > initial_count:
                feedback_parts.append(f"Note: {current_count - initial_count} new billing entries added, but not with code {expected_code}")
            
            # Early return - no billing entry means task not complete
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": {
                    "billing_found": False,
                    "initial_count": initial_count,
                    "current_count": current_count
                }
            }
        
        # CRITERION 2: Correct code type - CPT4 (15 points)
        code_type = billing.get('code_type', '').upper()
        if code_type in ['CPT4', 'CPT']:
            score += 15
            subscores["correct_code_type"] = True
            feedback_parts.append(f"Correct code type: {code_type}")
        elif code_type:
            score += 5  # Partial credit
            feedback_parts.append(f"Code type is {code_type} (expected CPT4)")
        else:
            feedback_parts.append("Code type not specified")
        
        # CRITERION 3: Entry is active (activity=1) (15 points)
        activity = billing.get('activity', '')
        if str(activity) == '1':
            score += 15
            subscores["entry_active"] = True
            feedback_parts.append("Billing entry is active")
        elif str(activity) == '0':
            feedback_parts.append("WARNING: Billing entry is inactive/voided")
        else:
            # Some systems might not have activity field
            score += 10
            feedback_parts.append(f"Activity status: {activity}")
        
        # CRITERION 4: Entry linked to valid encounter (20 points)
        encounter_valid = validation.get('encounter_linked', False)
        encounter_id = billing.get('encounter', '')
        
        if encounter_valid:
            score += 20
            subscores["encounter_linked"] = True
            feedback_parts.append(f"Billing linked to valid encounter ({encounter_id})")
        elif encounter_id and encounter_id != '0':
            score += 10  # Partial - has encounter but couldn't verify
            feedback_parts.append(f"Billing has encounter ID {encounter_id} (not verified)")
        else:
            feedback_parts.append("Billing not linked to an encounter")
        
        # CRITERION 5: Entry created during task (15 points) - anti-gaming
        if new_entry:
            score += 15
            subscores["created_during_task"] = True
            feedback_parts.append(f"New billing entry created (count: {initial_count} -> {current_count})")
        else:
            # Check if count increased
            if current_count > initial_count:
                score += 15
                subscores["created_during_task"] = True
                feedback_parts.append(f"Billing count increased during task")
            else:
                feedback_parts.append("No new billing entry detected (may be pre-existing)")
        
        # CRITERION 6: Correct patient (10 points)
        if patient_pid == expected_pid:
            score += 10
            subscores["correct_patient"] = True
            feedback_parts.append(f"Correct patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"Patient mismatch: expected pid={expected_pid}, got {patient_pid}")
        
        # Determine if passed
        # Must have: billing entry exists AND correct code type
        key_criteria = subscores["billing_entry_exists"] and subscores["correct_code_type"]
        passed = score >= 70 and key_criteria
        
        # Bonus feedback
        if passed:
            feedback_parts.insert(0, "SUCCESS: Procedure code added to fee sheet")
        else:
            if score >= 50:
                feedback_parts.insert(0, "PARTIAL: Some criteria met but not complete")
            else:
                feedback_parts.insert(0, "FAILED: Fee sheet not properly updated")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "expected_code": expected_code,
                "expected_patient": expected_pid,
                "billing_data": billing,
                "initial_count": initial_count,
                "current_count": current_count
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may have failed",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }


def verify_with_vlm_fallback(traj, env_info, task_info):
    """
    Enhanced verification with VLM fallback for visual confirmation.
    
    Uses trajectory frames to verify the workflow was actually performed.
    """
    # First, run the primary database verification
    primary_result = verify_add_procedure_fee_sheet(traj, env_info, task_info)
    
    # If primary verification passed with high confidence, return it
    if primary_result.get('passed') and primary_result.get('score', 0) >= 85:
        return primary_result
    
    # Try VLM verification as supplementary check
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames from the trajectory (not just final screenshot)
        frames = sample_trajectory_frames(traj, n=5)
        
        if not frames:
            # No trajectory data, return primary result
            return primary_result
        
        vlm_prompt = """You are verifying if a computer agent successfully added a procedure code to a patient's fee sheet in OpenEMR.

Task: Add CPT code 99213 to the fee sheet for patient Gerald Koss.

Examine these screenshots from the agent's workflow and determine:
1. Did the agent navigate to a patient chart (look for patient name/demographics)?
2. Did the agent open an encounter or the Fee Sheet screen?
3. Is there a Fee Sheet form visible with fields for code type and code?
4. Did the agent enter code "99213" or "CPT4"?
5. Is there a success indication (saved, confirmation, etc.)?

Respond in JSON format:
{
    "patient_chart_accessed": true/false,
    "fee_sheet_opened": true/false,
    "code_entry_visible": true/false,
    "appears_successful": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_result:
            # Parse VLM response
            try:
                vlm_data = json.loads(vlm_result) if isinstance(vlm_result, str) else vlm_result
                
                # Add VLM bonus points if workflow is confirmed
                vlm_bonus = 0
                if vlm_data.get('patient_chart_accessed'):
                    vlm_bonus += 5
                if vlm_data.get('fee_sheet_opened'):
                    vlm_bonus += 5
                if vlm_data.get('code_entry_visible'):
                    vlm_bonus += 5
                if vlm_data.get('appears_successful') and vlm_data.get('confidence') == 'high':
                    vlm_bonus += 10
                
                # Update score with VLM bonus (cap at 100)
                new_score = min(100, primary_result.get('score', 0) + vlm_bonus)
                
                primary_result['score'] = new_score
                primary_result['vlm_verification'] = vlm_data
                
                # Re-evaluate passed status
                if new_score >= 70 and primary_result.get('subscores', {}).get('billing_entry_exists'):
                    primary_result['passed'] = True
                    
            except (json.JSONDecodeError, TypeError):
                # VLM didn't return valid JSON, ignore
                pass
                
    except ImportError:
        # VLM module not available
        pass
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
    
    return primary_result