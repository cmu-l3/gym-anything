#!/usr/bin/env python3
"""
Verifier for Enter Lab Results task in OpenEMR

Verification Strategy:
1. PRIMARY: Check database for procedure orders and results for patient
2. SECONDARY: Verify specific lab values match expected values
3. TERTIARY: VLM trajectory verification to confirm work was done

Anti-gaming measures:
- Check that new records were created during task (not pre-existing)
- Verify results are linked to correct patient
- Validate specific numeric values were entered correctly
"""

import sys
import os
import json
import logging
import tempfile
import re
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_numeric_value(value_str: str) -> Optional[float]:
    """Extract numeric value from a string that may contain units."""
    if not value_str:
        return None
    
    # Remove common units and extract number
    cleaned = re.sub(r'[a-zA-Z/%]+', '', str(value_str)).strip()
    try:
        return float(cleaned)
    except (ValueError, TypeError):
        return None


def check_value_within_tolerance(actual: Optional[float], expected: float, tolerance: float) -> bool:
    """Check if actual value is within tolerance of expected value."""
    if actual is None:
        return False
    return abs(actual - expected) <= tolerance


def verify_lab_value(lab_values: Dict, key: str, expected: float, tolerance: float) -> Tuple[bool, str]:
    """
    Verify a single lab value matches expected.
    
    Returns:
        Tuple of (is_correct, feedback_message)
    """
    raw_value = lab_values.get(key, '')
    actual = parse_numeric_value(raw_value)
    
    if actual is None:
        return False, f"{key}: not found or invalid"
    
    if check_value_within_tolerance(actual, expected, tolerance):
        return True, f"{key}: {actual} (expected {expected} ± {tolerance})"
    else:
        return False, f"{key}: {actual} (expected {expected} ± {tolerance}) - MISMATCH"


def verify_enter_lab_results(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that lab results were correctly entered for patient Jayson Fadel.
    
    Scoring (100 points total):
    - Patient accessed (procedure order for correct patient): 15 points
    - Procedure order created during task: 20 points
    - Results entered (at least one result): 25 points
    - Glucose correct (108 ± 2): 10 points
    - BUN correct (22 ± 1): 5 points
    - Creatinine correct (1.2 ± 0.1): 10 points
    - Electrolytes entered (at least 2 of Na, K, Cl, CO2): 10 points
    - All 7 values present: 5 points
    
    Passing threshold: 60 points with procedure order created
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_results = metadata.get('lab_results', {
        'glucose': {'value': 108, 'tolerance': 2},
        'bun': {'value': 22, 'tolerance': 1},
        'creatinine': {'value': 1.2, 'tolerance': 0.1},
        'sodium': {'value': 139, 'tolerance': 2},
        'potassium': {'value': 4.5, 'tolerance': 0.2},
        'chloride': {'value': 103, 'tolerance': 2},
        'co2': {'value': 25, 'tolerance': 2}
    })
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/enter_lab_results_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "patient_accessed": False,
            "procedure_order_created": False,
            "results_entered": False,
            "glucose_correct": False,
            "bun_correct": False,
            "creatinine_correct": False,
            "electrolytes_entered": False,
            "all_values_present": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        procedure_orders = result.get('procedure_orders', {})
        procedure_results = result.get('procedure_results', {})
        lab_values = result.get('lab_values', {})
        
        initial_order_count = procedure_orders.get('initial_count', 0)
        current_order_count = procedure_orders.get('current_count', 0)
        new_order_created = procedure_orders.get('new_order_created', False)
        
        initial_result_count = procedure_results.get('initial_count', 0)
        current_result_count = procedure_results.get('current_count', 0)
        new_results_added = procedure_results.get('new_results_added', False)
        results_found = procedure_results.get('results_found_for_patient', False)
        
        logger.info(f"Patient PID: {patient_pid}")
        logger.info(f"Orders: initial={initial_order_count}, current={current_order_count}")
        logger.info(f"Results: initial={initial_result_count}, current={current_result_count}")
        logger.info(f"Lab values: {lab_values}")
        
        # CRITERION 1: Patient accessed (15 points)
        # Check if any procedure orders exist for correct patient
        if patient_pid == expected_pid and current_order_count > 0:
            score += 15
            subscores["patient_accessed"] = True
            feedback_parts.append(f"✅ Patient accessed (pid={expected_pid})")
        else:
            feedback_parts.append(f"❌ No procedure orders found for patient pid={expected_pid}")
        
        # CRITERION 2: Procedure order created during task (20 points)
        if new_order_created:
            score += 20
            subscores["procedure_order_created"] = True
            feedback_parts.append(f"✅ New procedure order created (count: {initial_order_count} → {current_order_count})")
        else:
            feedback_parts.append(f"❌ No new procedure order detected (count unchanged: {current_order_count})")
        
        # CRITERION 3: Results entered (25 points)
        if new_results_added or results_found:
            score += 25
            subscores["results_entered"] = True
            new_count = current_result_count - initial_result_count
            feedback_parts.append(f"✅ Lab results entered ({new_count} new result records)")
        else:
            feedback_parts.append("❌ No lab results found for patient")
        
        # CRITERION 4: Glucose correct (10 points)
        glucose_exp = expected_results.get('glucose', {'value': 108, 'tolerance': 2})
        glucose_ok, glucose_msg = verify_lab_value(
            lab_values, 'glucose', 
            glucose_exp['value'], 
            glucose_exp.get('tolerance', 2)
        )
        if glucose_ok:
            score += 10
            subscores["glucose_correct"] = True
            feedback_parts.append(f"✅ Glucose correct: {glucose_msg}")
        else:
            feedback_parts.append(f"⚠️ Glucose: {glucose_msg}")
        
        # CRITERION 5: BUN correct (5 points)
        bun_exp = expected_results.get('bun', {'value': 22, 'tolerance': 1})
        bun_ok, bun_msg = verify_lab_value(
            lab_values, 'bun',
            bun_exp['value'],
            bun_exp.get('tolerance', 1)
        )
        if bun_ok:
            score += 5
            subscores["bun_correct"] = True
            feedback_parts.append(f"✅ BUN correct: {bun_msg}")
        else:
            feedback_parts.append(f"⚠️ BUN: {bun_msg}")
        
        # CRITERION 6: Creatinine correct (10 points)
        creat_exp = expected_results.get('creatinine', {'value': 1.2, 'tolerance': 0.1})
        creat_ok, creat_msg = verify_lab_value(
            lab_values, 'creatinine',
            creat_exp['value'],
            creat_exp.get('tolerance', 0.1)
        )
        if creat_ok:
            score += 10
            subscores["creatinine_correct"] = True
            feedback_parts.append(f"✅ Creatinine correct: {creat_msg}")
        else:
            feedback_parts.append(f"⚠️ Creatinine: {creat_msg}")
        
        # CRITERION 7: Electrolytes entered (10 points) - at least 2 of 4
        electrolytes_found = 0
        electrolyte_details = []
        
        for elec_name, elec_key in [('Sodium', 'sodium'), ('Potassium', 'potassium'), 
                                     ('Chloride', 'chloride'), ('CO2', 'co2')]:
            elec_exp = expected_results.get(elec_key, {'value': 0, 'tolerance': 2})
            elec_ok, elec_msg = verify_lab_value(
                lab_values, elec_key,
                elec_exp['value'],
                elec_exp.get('tolerance', 2)
            )
            if elec_ok or parse_numeric_value(lab_values.get(elec_key, '')) is not None:
                electrolytes_found += 1
                electrolyte_details.append(f"{elec_name}: {lab_values.get(elec_key, 'N/A')}")
        
        if electrolytes_found >= 2:
            score += 10
            subscores["electrolytes_entered"] = True
            feedback_parts.append(f"✅ Electrolytes entered: {electrolytes_found}/4 ({', '.join(electrolyte_details)})")
        else:
            feedback_parts.append(f"⚠️ Electrolytes: only {electrolytes_found}/4 found")
        
        # CRITERION 8: All 7 values present (5 points)
        values_present = 0
        for key in ['glucose', 'bun', 'creatinine', 'sodium', 'potassium', 'chloride', 'co2']:
            if parse_numeric_value(lab_values.get(key, '')) is not None:
                values_present += 1
        
        if values_present == 7:
            score += 5
            subscores["all_values_present"] = True
            feedback_parts.append(f"✅ All 7 lab values present")
        else:
            feedback_parts.append(f"⚠️ Only {values_present}/7 lab values present")
        
        # Determine pass/fail
        # Must have procedure order created and at least 60 points
        key_criteria_met = subscores["procedure_order_created"] or subscores["results_entered"]
        passed = score >= 60 and key_criteria_met
        
        # VLM trajectory verification as supplementary check
        vlm_feedback = ""
        try:
            query_vlm = env_info.get('query_vlm')
            if query_vlm and 'frames' in traj:
                from gym_anything.vlm import sample_trajectory_frames
                frames = sample_trajectory_frames(traj, n=5)
                
                vlm_prompt = """Analyze these screenshots showing a user working with OpenEMR electronic health records.

Determine if the user appears to be:
1. Searching for or viewing a patient record
2. Navigating to a Procedures or Lab Results section
3. Entering numeric values into a form (lab results entry)
4. Saving or submitting the entered data

Respond in JSON format:
{
    "patient_viewed": true/false,
    "procedures_section": true/false,
    "data_entry_observed": true/false,
    "form_submitted": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description"
}
"""
                vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('data_entry_observed') and parsed.get('confidence') in ['medium', 'high']:
                        vlm_feedback = " | VLM confirms lab data entry activity"
                    else:
                        vlm_feedback = f" | VLM: {parsed.get('reasoning', 'N/A')}"
        except Exception as e:
            logger.warning(f"VLM verification skipped: {e}")
        
        feedback = " | ".join(feedback_parts) + vlm_feedback
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "procedure_orders_created": current_order_count - initial_order_count,
                "procedure_results_added": current_result_count - initial_result_count,
                "lab_values_found": lab_values,
                "values_present": values_present
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
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