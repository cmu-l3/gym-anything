#!/usr/bin/env python3
"""
Verifier for order_lab_tests task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Procedure order exists for correct patient (25 points)
2. Order was created during task (not pre-existing) (20 points)
3. Order contains procedure code/test (20 points)
4. Test is lipid-related (20 points)
5. Clinical notes present (10 points)
6. Workflow bonus (5 points)

Pass threshold: 65 points with order exists criterion met

Anti-gaming measures:
- Timestamp verification ensures order was created after task start
- Patient ID must match expected (pid=5)
- Order ID must be greater than initial max ID
"""

import json
import tempfile
import os
import logging
import re
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_order_lab_tests(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that a lipid panel lab order was created for patient Rosetta Effertz.
    
    Uses copy_from_env to read pre-exported verification data from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Rosetta')
    expected_lname = metadata.get('patient_lname', 'Effertz')
    lipid_keywords = metadata.get('expected_test_keywords', 
                                   ['lipid', 'cholesterol', 'ldl', 'hdl', 'triglyceride'])
    
    # Scoring weights from metadata
    score_order_exists = metadata.get('score_order_exists', 25)
    score_created_during = metadata.get('score_created_during_task', 20)
    score_has_code = metadata.get('score_has_test_code', 20)
    score_lipid = metadata.get('score_lipid_related', 20)
    score_notes = metadata.get('score_clinical_notes', 10)
    score_workflow = metadata.get('score_workflow_bonus', 5)
    
    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "order_exists": False,
        "created_during_task": False,
        "has_test_code": False,
        "lipid_related": False,
        "clinical_notes": False,
        "workflow_verified": False
    }
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    initial_count = result.get('initial_order_count', 0)
    current_count = result.get('current_order_count', 0)
    initial_max_id = result.get('initial_max_order_id', 0)
    current_max_id = result.get('current_max_order_id', 0)
    new_order_created = result.get('new_order_created', False)
    order_created_during = result.get('order_created_during_task', False)
    order = result.get('order', {})
    procedure_codes = result.get('procedure_codes', {})
    validation = result.get('validation', {})
    
    logger.info(f"Verification data: pid={patient_pid}, initial={initial_count}, "
                f"current={current_count}, new_order={new_order_created}")
    
    # ================================================================
    # CRITERION 1: Order exists for correct patient (25 points)
    # ================================================================
    order_patient_id = order.get('patient_id', '')
    try:
        order_patient_id_int = int(order_patient_id) if order_patient_id else 0
    except ValueError:
        order_patient_id_int = 0
    
    if new_order_created and order_patient_id_int == expected_pid:
        score += score_order_exists
        subscores["order_exists"] = True
        feedback_parts.append(f"✓ New procedure order created for patient pid={expected_pid} ({expected_fname} {expected_lname})")
    elif new_order_created and order_patient_id_int != expected_pid:
        # Partial credit - order created but wrong patient
        score += 5
        feedback_parts.append(f"✗ Order created for WRONG patient (expected pid={expected_pid}, got {order_patient_id_int})")
        # This is a critical failure - return early with low score
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "reason": "Order created for wrong patient",
                "expected_pid": expected_pid,
                "actual_pid": order_patient_id_int
            }
        }
    elif current_count > initial_count:
        # Some order exists but we couldn't identify it properly
        score += 10
        feedback_parts.append(f"○ Order count increased but details unclear (initial={initial_count}, current={current_count})")
    else:
        feedback_parts.append(f"✗ No new procedure order found for patient pid={expected_pid}")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "reason": "No procedure order created",
                "initial_count": initial_count,
                "current_count": current_count
            }
        }
    
    # ================================================================
    # CRITERION 2: Order created during task (20 points)
    # Anti-gaming check: order ID must be greater than initial max
    # ================================================================
    order_id = order.get('order_id', '')
    try:
        order_id_int = int(order_id) if order_id else 0
    except ValueError:
        order_id_int = 0
    
    if order_created_during and order_id_int > initial_max_id:
        score += score_created_during
        subscores["created_during_task"] = True
        feedback_parts.append(f"✓ Order created during task (id={order_id_int} > initial_max={initial_max_id})")
    elif order_id_int > 0:
        # Order exists but may be pre-existing
        score += 5
        feedback_parts.append(f"○ Order exists but may be pre-existing (id={order_id_int}, initial_max={initial_max_id})")
    else:
        feedback_parts.append(f"✗ Could not verify order creation timestamp")
    
    # ================================================================
    # CRITERION 3: Order contains procedure code (20 points)
    # ================================================================
    procedure_code = procedure_codes.get('code', '')
    procedure_name = procedure_codes.get('name', '')
    
    if procedure_code or procedure_name:
        score += score_has_code
        subscores["has_test_code"] = True
        feedback_parts.append(f"✓ Order contains procedure code/name: {procedure_code or procedure_name}")
    else:
        feedback_parts.append(f"✗ No procedure code found in order")
    
    # ================================================================
    # CRITERION 4: Test is lipid-related (20 points)
    # ================================================================
    has_lipid = validation.get('has_lipid_test', False)
    
    # Also check ourselves in case export missed it
    all_text = f"{procedure_code} {procedure_name} {order.get('clinical_hx', '')} {procedure_codes.get('diagnoses', '')}".lower()
    manual_lipid_check = any(keyword in all_text for keyword in lipid_keywords)
    
    if has_lipid or manual_lipid_check:
        score += score_lipid
        subscores["lipid_related"] = True
        feedback_parts.append(f"✓ Order contains lipid-related test")
    else:
        # Check if any medical test was ordered (partial credit)
        if procedure_code or procedure_name:
            score += 5
            feedback_parts.append(f"○ Test ordered but not lipid-related: {procedure_name or procedure_code}")
        else:
            feedback_parts.append(f"✗ No lipid-related test found in order")
    
    # ================================================================
    # CRITERION 5: Clinical notes present (10 points)
    # ================================================================
    has_notes = validation.get('has_clinical_notes', False)
    clinical_hx = order.get('clinical_hx', '')
    diagnoses = procedure_codes.get('diagnoses', '')
    
    # Manual check for clinical context
    clinical_text = f"{clinical_hx} {diagnoses}".lower()
    clinical_keywords = ['wellness', 'screen', 'cardiovascular', 'annual', 'preventive', 'exam', 'checkup']
    manual_notes_check = any(kw in clinical_text for kw in clinical_keywords)
    
    if has_notes or manual_notes_check:
        score += score_notes
        subscores["clinical_notes"] = True
        feedback_parts.append(f"✓ Clinical notes/indication present")
    elif clinical_hx or diagnoses:
        # Some notes exist but not matching expected keywords
        score += 5
        feedback_parts.append(f"○ Clinical notes exist but may not match expected context")
    else:
        feedback_parts.append(f"○ No clinical notes found (optional)")
    
    # ================================================================
    # CRITERION 6: Workflow bonus (5 points)
    # Give benefit of doubt for proper navigation
    # ================================================================
    # If we got this far with a valid order, assume workflow was followed
    if subscores["order_exists"] and subscores["created_during_task"]:
        score += score_workflow
        subscores["workflow_verified"] = True
        feedback_parts.append(f"✓ Workflow completed successfully")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = (score_order_exists + score_created_during + score_has_code + 
                 score_lipid + score_notes + score_workflow)
    
    # Passing criteria: score >= 65 AND order exists for correct patient
    key_criteria_met = subscores["order_exists"] and subscores["created_during_task"]
    passed = score >= 65 and key_criteria_met
    
    logger.info(f"Final score: {score}/{max_score}, passed={passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "expected_patient": f"{expected_fname} {expected_lname} (pid={expected_pid})",
            "order_id": order_id,
            "procedure": procedure_name or procedure_code or "Unknown",
            "initial_count": initial_count,
            "current_count": current_count,
            "max_possible_score": max_score
        }
    }


if __name__ == "__main__":
    # Test stub for local development
    print("Verifier module loaded successfully")
    print("Function: verify_order_lab_tests")
    print("Expected patient: Rosetta Effertz (pid=5)")
    print("Expected test: Lipid Panel")