#!/usr/bin/env python3
"""
Verifier for Renew Prescription task in OpenEMR

Verifies that the agent correctly renewed a prescription for patient Jayson Fadel.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- New prescription exists for correct patient: 30 points
- Correct drug (amLODIPine): 25 points
- Correct quantity (~90): 15 points
- Correct refills (~3): 15 points
- Created during task (anti-gaming): 10 points
- Visual/workflow confirmation: 5 points

Pass threshold: 70 points with new_prescription_found=true
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_renew_prescription(traj, env_info, task_info):
    """
    Verify that a prescription renewal was completed correctly.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    drug_pattern = metadata.get('drug_pattern', 'amlodipine').lower()
    expected_quantity = metadata.get('expected_quantity', 90)
    quantity_tolerance = metadata.get('quantity_tolerance', 10)
    expected_refills = metadata.get('expected_refills', 3)
    refills_tolerance = metadata.get('refills_tolerance', 1)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/renew_prescription_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "new_prescription_exists": False,
            "correct_drug": False,
            "correct_quantity": False,
            "correct_refills": False,
            "created_during_task": False,
            "workflow_confirmed": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_rx_count', 0)
        current_count = result.get('current_rx_count', 0)
        initial_max_id = result.get('initial_max_rx_id', 0)
        task_start = result.get('task_start_time', 0)
        new_rx_found = result.get('new_prescription_found', False)
        prescription = result.get('prescription', {})
        validation = result.get('validation', {})
        
        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, "
                   f"current={current_count}, found={new_rx_found}")
        logger.info(f"Prescription: {prescription}")
        
        # CRITERION 1: New prescription exists for correct patient (30 points)
        if patient_pid != expected_pid:
            feedback_parts.append(f"CRITICAL: Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Prescription not for correct patient (expected pid={expected_pid})",
                "subscores": subscores
            }
        
        if new_rx_found and current_count > initial_count:
            score += 30
            subscores["new_prescription_exists"] = True
            feedback_parts.append(f"✓ New prescription found for patient {expected_fname} {expected_lname} (pid={expected_pid})")
        else:
            feedback_parts.append(f"✗ No new prescription found for patient pid={expected_pid}")
            
            # Check if any prescriptions were added at all
            if current_count > initial_count:
                feedback_parts.append(f"Note: Prescription count increased ({initial_count}->{current_count}) but not detected as new")
            else:
                feedback_parts.append(f"Prescription count unchanged: {current_count}")
            
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: Correct drug - amLODIPine (25 points)
        rx_drug = prescription.get('drug', '').lower()
        if drug_pattern in rx_drug:
            score += 25
            subscores["correct_drug"] = True
            feedback_parts.append(f"✓ Correct drug (contains '{drug_pattern}')")
        else:
            feedback_parts.append(f"✗ Wrong drug - expected '{drug_pattern}', got '{prescription.get('drug', 'N/A')}'")
        
        # CRITERION 3: Correct quantity ~90 (15 points)
        rx_quantity_str = prescription.get('quantity', '0')
        try:
            # Extract numeric part
            rx_quantity = int(''.join(filter(str.isdigit, str(rx_quantity_str))) or '0')
            qty_min = expected_quantity - quantity_tolerance
            qty_max = expected_quantity + quantity_tolerance
            
            if qty_min <= rx_quantity <= qty_max:
                score += 15
                subscores["correct_quantity"] = True
                feedback_parts.append(f"✓ Correct quantity ({rx_quantity} within {qty_min}-{qty_max})")
            else:
                feedback_parts.append(f"✗ Quantity out of range - got {rx_quantity}, expected {qty_min}-{qty_max}")
        except (ValueError, TypeError) as e:
            feedback_parts.append(f"✗ Could not parse quantity: {rx_quantity_str}")
        
        # CRITERION 4: Correct refills ~3 (15 points)
        rx_refills_str = prescription.get('refills', '0')
        try:
            rx_refills = int(''.join(filter(str.isdigit, str(rx_refills_str))) or '0')
            ref_min = expected_refills - refills_tolerance
            ref_max = expected_refills + refills_tolerance
            
            if ref_min <= rx_refills <= ref_max:
                score += 15
                subscores["correct_refills"] = True
                feedback_parts.append(f"✓ Correct refills ({rx_refills} within {ref_min}-{ref_max})")
            else:
                feedback_parts.append(f"✗ Refills out of range - got {rx_refills}, expected {ref_min}-{ref_max}")
        except (ValueError, TypeError) as e:
            feedback_parts.append(f"✗ Could not parse refills: {rx_refills_str}")
        
        # CRITERION 5: Created during task - anti-gaming (10 points)
        rx_id_str = prescription.get('id', '0')
        date_valid = validation.get('date_valid', False)
        
        try:
            rx_id = int(rx_id_str) if rx_id_str else 0
            # Prescription ID should be greater than initial max
            if rx_id > initial_max_id and date_valid:
                score += 10
                subscores["created_during_task"] = True
                feedback_parts.append(f"✓ Prescription created during task (id={rx_id} > {initial_max_id})")
            elif rx_id > initial_max_id:
                score += 5  # Partial credit if ID is new but date check failed
                feedback_parts.append(f"~ Prescription appears new (id={rx_id}) but date validation unclear")
            else:
                feedback_parts.append(f"✗ Prescription may have existed before task (id={rx_id}, initial_max={initial_max_id})")
        except (ValueError, TypeError):
            if date_valid:
                score += 5
                feedback_parts.append("~ Date validation passed but ID check inconclusive")
            else:
                feedback_parts.append("✗ Could not verify prescription was created during task")
        
        # CRITERION 6: Workflow confirmation via trajectory (5 points)
        # Check if we have trajectory data showing the agent worked through the UI
        trajectory_frames = traj.get('frames', [])
        if len(trajectory_frames) >= 5:
            # Agent took multiple steps - likely did actual work
            score += 5
            subscores["workflow_confirmed"] = True
            feedback_parts.append(f"✓ Workflow confirmed ({len(trajectory_frames)} trajectory frames)")
        elif len(trajectory_frames) > 0:
            score += 2  # Some activity
            feedback_parts.append(f"~ Limited trajectory evidence ({len(trajectory_frames)} frames)")
        else:
            feedback_parts.append("✗ No trajectory frames available for workflow verification")
        
        # Determine pass/fail
        # Must have: new prescription + correct drug + at least one of quantity/refills correct
        key_criteria_met = (
            subscores["new_prescription_exists"] and 
            subscores["correct_drug"] and
            (subscores["correct_quantity"] or subscores["correct_refills"])
        )
        
        passed = score >= 70 and key_criteria_met
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "prescription_id": prescription.get('id'),
                "drug": prescription.get('drug'),
                "quantity": prescription.get('quantity'),
                "refills": prescription.get('refills'),
                "initial_count": initial_count,
                "current_count": current_count
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found in container")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run correctly",
            "subscores": {
                "new_prescription_exists": False,
                "correct_drug": False,
                "correct_quantity": False,
                "correct_refills": False,
                "created_during_task": False,
                "workflow_confirmed": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {
                "new_prescription_exists": False,
                "correct_drug": False,
                "correct_quantity": False,
                "correct_refills": False,
                "created_during_task": False,
                "workflow_confirmed": False
            }
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {
                "new_prescription_exists": False,
                "correct_drug": False,
                "correct_quantity": False,
                "correct_refills": False,
                "created_during_task": False,
                "workflow_confirmed": False
            }
        }


if __name__ == "__main__":
    # For local testing
    print("Verifier module loaded. Use verify_renew_prescription(traj, env_info, task_info)")