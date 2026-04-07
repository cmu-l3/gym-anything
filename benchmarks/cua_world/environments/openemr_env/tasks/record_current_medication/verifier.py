#!/usr/bin/env python3
"""
Verifier for Record Current Medication task in OpenEMR

This task tests medication reconciliation - adding a patient-reported medication
to their active medication list (NOT writing a new prescription).

Verification Strategy:
1. PRIMARY: Query database for Metformin entry linked to patient pid=3
2. Check both prescriptions table and lists table (medication type)
3. Verify medication was added during task execution (anti-gaming)
4. Validate drug name, dosage information, and active status

Scoring (100 points total):
- Medication entry exists: 30 points
- Correct patient (pid=3): 20 points  
- Correct drug name (Metformin): 20 points
- Dosage/directions present: 15 points
- Active status: 10 points
- Created after task start: 5 points

Pass threshold: 70 points with medication entry exists AND correct patient
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_record_current_medication(traj, env_info, task_info):
    """
    Verify that Metformin was added to patient Jayson Fadel's medication list.
    
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
            "feedback": "Copy function not available for verification"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    expected_drug = metadata.get('expected_drug', 'Metformin').lower()
    expected_strength = metadata.get('expected_strength', '500')
    expected_directions = metadata.get('expected_directions', 'twice daily').lower()

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/record_medication_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        # Initialize scoring
        score = 0
        feedback_parts = []
        subscores = {
            "medication_entry_exists": False,
            "correct_patient": False,
            "correct_drug_name": False,
            "dosage_present": False,
            "active_status": False,
            "created_after_start": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        task_start = result.get('task_start_timestamp', 0)
        initial_rx_count = result.get('initial_rx_count', 0)
        current_rx_count = result.get('current_rx_count', 0)
        initial_medlist_count = result.get('initial_medlist_count', 0)
        current_medlist_count = result.get('current_medlist_count', 0)
        new_entry_created = result.get('new_entry_created', False)
        
        rx_entry = result.get('prescriptions_entry', {})
        list_entry = result.get('lists_entry', {})

        logger.info(f"Patient PID: {patient_pid}, Expected: {expected_pid}")
        logger.info(f"RX entry: {rx_entry}")
        logger.info(f"List entry: {list_entry}")

        # Determine which entry to evaluate (prefer prescriptions, fall back to lists)
        entry_found = False
        drug_name = ""
        dosage_info = ""
        is_active = False
        entry_source = ""

        if rx_entry.get('found', False):
            entry_found = True
            entry_source = "prescriptions"
            drug_name = rx_entry.get('drug', '').lower()
            dosage_info = rx_entry.get('dosage', '').lower()
            # Active can be string "1" or int 1
            active_val = rx_entry.get('active', '0')
            is_active = str(active_val) == '1'
            logger.info(f"Found in prescriptions: drug='{drug_name}', dosage='{dosage_info}', active={is_active}")
        elif list_entry.get('found', False):
            entry_found = True
            entry_source = "lists"
            drug_name = list_entry.get('title', '').lower()
            dosage_info = list_entry.get('comments', '').lower()
            # Activity can be string "1" or int 1
            activity_val = list_entry.get('activity', '0')
            is_active = str(activity_val) == '1'
            logger.info(f"Found in lists: title='{drug_name}', comments='{dosage_info}', active={is_active}")

        # CRITERION 1: Medication entry exists (30 points)
        if entry_found:
            score += 30
            subscores["medication_entry_exists"] = True
            feedback_parts.append(f"✅ Medication entry found in {entry_source} table")
        else:
            feedback_parts.append("❌ No Metformin entry found in medication records")
            # Check if any new entries were created at all
            if current_rx_count > initial_rx_count:
                feedback_parts.append(f"  Note: {current_rx_count - initial_rx_count} new prescription(s) added, but not Metformin")
            if current_medlist_count > initial_medlist_count:
                feedback_parts.append(f"  Note: {current_medlist_count - initial_medlist_count} new medication list entry(ies) added, but not Metformin")
            
            # Cannot pass without medication entry
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Correct patient (20 points)
        if patient_pid == expected_pid:
            score += 20
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ CRITICAL: Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            # Wrong patient is a critical failure
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 3: Correct drug name (20 points)
        if expected_drug in drug_name:
            score += 20
            subscores["correct_drug_name"] = True
            feedback_parts.append(f"✅ Correct drug: Metformin found in '{drug_name}'")
        else:
            feedback_parts.append(f"❌ Drug name mismatch: expected '{expected_drug}', got '{drug_name}'")

        # CRITERION 4: Dosage/directions present (15 points)
        # Check for strength (500) or directions (twice daily) or any dosage info
        has_strength = expected_strength in drug_name or expected_strength in dosage_info
        has_directions = 'twice' in dosage_info or 'daily' in dosage_info or 'bid' in dosage_info.lower()
        has_mg = 'mg' in drug_name.lower() or 'mg' in dosage_info.lower()
        has_any_dosage = len(dosage_info.strip()) > 0 or has_strength or has_mg
        
        if has_strength or has_directions or has_any_dosage:
            score += 15
            subscores["dosage_present"] = True
            dosage_details = []
            if has_strength:
                dosage_details.append(f"strength={expected_strength}mg")
            if has_directions:
                dosage_details.append("directions present")
            if has_any_dosage and not (has_strength or has_directions):
                dosage_details.append(f"dosage info: '{dosage_info[:50]}'")
            feedback_parts.append(f"✅ Dosage information present: {', '.join(dosage_details)}")
        else:
            feedback_parts.append("❌ Dosage/directions not found or incomplete")

        # CRITERION 5: Active status (10 points)
        if is_active:
            score += 10
            subscores["active_status"] = True
            feedback_parts.append("✅ Medication marked as active")
        else:
            feedback_parts.append("❌ Medication not marked as active (or status unclear)")

        # CRITERION 6: Created after task start (5 points) - anti-gaming
        if new_entry_created:
            score += 5
            subscores["created_after_start"] = True
            feedback_parts.append("✅ New entry created during task execution")
        else:
            feedback_parts.append("⚠️ Could not confirm entry was newly created (may have existed before)")

        # Calculate pass/fail
        # Must have: medication entry exists AND correct patient AND score >= 70
        key_criteria_met = subscores["medication_entry_exists"] and subscores["correct_patient"]
        passed = key_criteria_met and score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "expected_pid": expected_pid,
                "entry_source": entry_source,
                "drug_found": drug_name,
                "expected_drug": expected_drug,
                "initial_rx_count": initial_rx_count,
                "current_rx_count": current_rx_count,
                "initial_medlist_count": initial_medlist_count,
                "current_medlist_count": current_medlist_count
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Verification failed: Result file not found. Export script may not have run.",
            "subscores": {
                "medication_entry_exists": False,
                "correct_patient": False,
                "correct_drug_name": False,
                "dosage_present": False,
                "active_status": False,
                "created_after_start": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification failed: Invalid JSON in result file: {str(e)}",
            "subscores": {
                "medication_entry_exists": False,
                "correct_patient": False,
                "correct_drug_name": False,
                "dosage_present": False,
                "active_status": False,
                "created_after_start": False
            }
        }
    except Exception as e:
        logger.error(f"Unexpected verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "subscores": {
                "medication_entry_exists": False,
                "correct_patient": False,
                "correct_drug_name": False,
                "dosage_present": False,
                "active_status": False,
                "created_after_start": False
            }
        }


if __name__ == "__main__":
    # Test stub for standalone execution
    print("Record Current Medication Verifier")
    print("===================================")
    print("This verifier checks that Metformin was added to patient Jayson Fadel's medication list.")
    print("")
    print("Scoring criteria:")
    print("  - Medication entry exists: 30 points")
    print("  - Correct patient (pid=3): 20 points")
    print("  - Correct drug (Metformin): 20 points")
    print("  - Dosage present: 15 points")
    print("  - Active status: 10 points")
    print("  - Created during task: 5 points")
    print("")
    print("Pass threshold: 70 points with medication entry AND correct patient")