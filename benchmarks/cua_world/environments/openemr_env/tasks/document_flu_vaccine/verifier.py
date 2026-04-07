#!/usr/bin/env python3
"""
Verifier for Document Flu Vaccination task in OpenEMR

Multi-signal verification to prevent gaming:
1. Immunization record exists for correct patient (30 points)
2. Lot number matches FL2024-3892 (20 points)
3. Manufacturer contains Sanofi (15 points)
4. Administration date is today ±1 day (15 points)
5. Record created during task - anti-gaming (10 points)
6. Additional fields correct (route, site) (10 points)

Pass threshold: 65 points with immunization record created requirement
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_document_flu_vaccine(traj, env_info, task_info):
    """
    Verify that flu vaccination was correctly documented in OpenEMR.
    
    Uses copy_from_env to read exported verification data from container.
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
    expected_lot = metadata.get('lot_number', 'FL2024-3892')
    expected_manufacturer = metadata.get('manufacturer', 'Sanofi Pasteur')
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/document_flu_vaccine_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to read verification data: {e}"
            }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    subscores = {
        "record_created": False,
        "lot_number_correct": False,
        "manufacturer_correct": False,
        "date_correct": False,
        "timing_valid": False,
        "additional_fields": False
    }
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    initial_count = result.get('initial_imm_count', 0)
    current_count = result.get('current_imm_count', 0)
    imm_found = result.get('immunization_found', False)
    immunization = result.get('immunization', {})
    validation = result.get('validation', {})
    task_start = result.get('task_start_time', 0)
    
    logger.info(f"Verification data: pid={patient_pid}, initial={initial_count}, current={current_count}, found={imm_found}")
    logger.info(f"Immunization: {immunization}")
    
    # ================================================================
    # CRITERION 1: Immunization record exists for correct patient (30 points)
    # ================================================================
    if patient_pid != expected_pid:
        feedback_parts.append(f"CRITICAL: Wrong patient ID (expected {expected_pid})")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    if imm_found and current_count > initial_count:
        score += 30
        subscores["record_created"] = True
        feedback_parts.append(f"Immunization record created for patient (pid={expected_pid})")
    elif imm_found:
        # Record exists but count didn't increase - possible pre-existing
        score += 15
        feedback_parts.append("Immunization record found but may have pre-existed")
    else:
        feedback_parts.append("No immunization record found for patient")
        # Check if immunizations were added elsewhere
        initial_total = result.get('initial_total_imm', 0)
        current_total = result.get('current_total_imm', 0)
        if current_total > initial_total:
            feedback_parts.append(f"Note: Immunization was added but to wrong patient")
        
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # ================================================================
    # CRITERION 2: Lot number matches (20 points)
    # ================================================================
    lot_number = immunization.get('lot_number', '').strip()
    if expected_lot.lower() in lot_number.lower() or lot_number.lower() in expected_lot.lower():
        score += 20
        subscores["lot_number_correct"] = True
        feedback_parts.append(f"Lot number correct: {lot_number}")
    elif lot_number:
        # Partial match check for typos
        if any(part in lot_number.upper() for part in ['FL2024', '3892']):
            score += 10
            feedback_parts.append(f"Lot number partially correct: {lot_number} (expected {expected_lot})")
        else:
            feedback_parts.append(f"Lot number incorrect: {lot_number} (expected {expected_lot})")
    else:
        feedback_parts.append(f"Lot number not entered (expected {expected_lot})")
    
    # ================================================================
    # CRITERION 3: Manufacturer correct (15 points)
    # ================================================================
    manufacturer = immunization.get('manufacturer', '').strip()
    if 'sanofi' in manufacturer.lower():
        score += 15
        subscores["manufacturer_correct"] = True
        feedback_parts.append(f"Manufacturer correct: {manufacturer}")
    elif manufacturer:
        feedback_parts.append(f"Manufacturer incorrect: {manufacturer} (expected Sanofi Pasteur)")
    else:
        feedback_parts.append("Manufacturer not entered")
    
    # ================================================================
    # CRITERION 4: Administration date is today ±1 day (15 points)
    # ================================================================
    admin_date_str = immunization.get('administered_date', '')
    if admin_date_str:
        try:
            admin_date = datetime.strptime(admin_date_str, '%Y-%m-%d').date()
            today = datetime.now().date()
            date_diff = abs((admin_date - today).days)
            
            if date_diff == 0:
                score += 15
                subscores["date_correct"] = True
                feedback_parts.append(f"Administration date correct: {admin_date_str}")
            elif date_diff <= 1:
                score += 12
                subscores["date_correct"] = True
                feedback_parts.append(f"Administration date acceptable: {admin_date_str} (within 1 day)")
            else:
                feedback_parts.append(f"Administration date outside range: {admin_date_str} (expected today)")
        except ValueError:
            feedback_parts.append(f"Invalid date format: {admin_date_str}")
    else:
        feedback_parts.append("Administration date not entered")
    
    # ================================================================
    # CRITERION 5: Record created during task - anti-gaming (10 points)
    # ================================================================
    if validation.get('timing_valid', False):
        score += 10
        subscores["timing_valid"] = True
        feedback_parts.append("Record created during task (anti-gaming passed)")
    else:
        # Check create timestamp manually
        create_ts = immunization.get('create_timestamp', 0)
        try:
            create_ts = int(create_ts) if create_ts else 0
            if create_ts >= task_start and task_start > 0:
                score += 10
                subscores["timing_valid"] = True
                feedback_parts.append("Record timing verified")
            elif current_count > initial_count:
                # Fallback: count increased
                score += 7
                subscores["timing_valid"] = True
                feedback_parts.append("New record detected via count")
            else:
                feedback_parts.append("Record timing could not be verified")
        except (ValueError, TypeError):
            if current_count > initial_count:
                score += 5
                feedback_parts.append("Record appears new (count increased)")
    
    # ================================================================
    # CRITERION 6: Additional fields correct (10 points)
    # Route and administration site
    # ================================================================
    additional_points = 0
    
    route = immunization.get('route', '').lower()
    if 'intramuscular' in route or 'im' in route:
        additional_points += 5
        feedback_parts.append("Route correct (Intramuscular)")
    elif route:
        feedback_parts.append(f"Route entered: {route}")
    
    site = immunization.get('administration_site', '').lower()
    if 'deltoid' in site or ('left' in site and 'arm' in site):
        additional_points += 5
        feedback_parts.append("Administration site correct (Left Deltoid)")
    elif site:
        additional_points += 2  # Partial credit for any site entered
        feedback_parts.append(f"Administration site entered: {site}")
    
    if additional_points > 0:
        score += additional_points
        if additional_points >= 8:
            subscores["additional_fields"] = True
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Determine pass/fail
    # Must have: record created + at least one of (lot or manufacturer correct)
    key_criteria_met = (
        subscores["record_created"] and 
        (subscores["lot_number_correct"] or subscores["manufacturer_correct"])
    )
    
    passed = score >= 65 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Final score: {score}/100, passed={passed}")
    logger.info(f"Subscores: {subscores}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "details": {
            "patient_pid": patient_pid,
            "expected_pid": expected_pid,
            "record_found": imm_found,
            "initial_count": initial_count,
            "current_count": current_count,
            "lot_number_entered": immunization.get('lot_number', ''),
            "manufacturer_entered": immunization.get('manufacturer', ''),
            "date_entered": immunization.get('administered_date', '')
        }
    }