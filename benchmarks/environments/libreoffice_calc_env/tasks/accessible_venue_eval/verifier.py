#!/usr/bin/env python3
"""
Verifier for Accessible Venue Evaluator task.
Checks data standardization, cost calculations, requirements logic, and decision support.
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path for host-side verification
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_by_keywords(sheet_rows, keywords):
    """
    Find column index by searching for keywords in header row.
    Returns column index (0-based) or None if not found.
    """
    if not sheet_rows or len(sheet_rows) == 0:
        return None
    
    header_row = sheet_rows[0]
    for col_idx, cell in enumerate(header_row):
        cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
        if cell_value:
            cell_text = str(cell_value).lower()
            if any(keyword.lower() in cell_text for keyword in keywords):
                return col_idx
    return None


def check_text_parsing_accuracy(workbook, sheet_name, sheet_rows):
    """
    Verify that text descriptions were correctly parsed to Yes/No flags.
    Spot-checks a few venues for accuracy.
    """
    # Find relevant columns
    entry_col = find_column_by_keywords(sheet_rows, ['entry description', 'entry'])
    level_col = find_column_by_keywords(sheet_rows, ['level', 'ramped entry', 'level/ramped'])
    restroom_col = find_column_by_keywords(sheet_rows, ['restroom'])
    accessible_restroom_col = find_column_by_keywords(sheet_rows, ['accessible restroom'])
    
    if entry_col is None or level_col is None:
        return False, "Could not find entry or standardization columns"
    
    # Check a few specific cases from our test data
    checks_passed = 0
    total_checks = 0
    
    # Row 2 (index 1): "3 steps at main entrance but ramp available around back" -> should be Yes (has "ramp")
    if len(sheet_rows) > 1:
        total_checks += 1
        entry_desc = sheet_rows[1][entry_col].get('value', '') if isinstance(sheet_rows[1][entry_col], dict) else str(sheet_rows[1][entry_col])
        parsed_value = sheet_rows[1][level_col].get('value', '') if isinstance(sheet_rows[1][level_col], dict) else str(sheet_rows[1][level_col])
        
        # Should be Yes because "ramp available" is mentioned
        if 'ramp' in str(entry_desc).lower() and str(parsed_value).lower() in ['yes', 'y', 'true']:
            checks_passed += 1
            logger.info(f"✓ Venue 1 correctly parsed: ramp mentioned → {parsed_value}")
        elif 'step' in str(entry_desc).lower() and str(parsed_value).lower() in ['no', 'n', 'false']:
            checks_passed += 0.5  # Partial credit for recognizing steps
            logger.info(f"⚠ Venue 1 partial: recognized steps → {parsed_value}")
    
    # Row 3 (index 2): "Level entry from parking lot" -> should be Yes
    if len(sheet_rows) > 2:
        total_checks += 1
        entry_desc = sheet_rows[2][entry_col].get('value', '') if isinstance(sheet_rows[2][entry_col], dict) else str(sheet_rows[2][entry_col])
        parsed_value = sheet_rows[2][level_col].get('value', '') if isinstance(sheet_rows[2][level_col], dict) else str(sheet_rows[2][level_col])
        
        if 'level' in str(entry_desc).lower() and str(parsed_value).lower() in ['yes', 'y', 'true']:
            checks_passed += 1
            logger.info(f"✓ Venue 2 correctly parsed: level entry → {parsed_value}")
    
    # Row 4 (index 3): "5 steps at entrance with no ramp" -> should be No
    if len(sheet_rows) > 3:
        total_checks += 1
        entry_desc = sheet_rows[3][entry_col].get('value', '') if isinstance(sheet_rows[3][entry_col], dict) else str(sheet_rows[3][entry_col])
        parsed_value = sheet_rows[3][level_col].get('value', '') if isinstance(sheet_rows[3][level_col], dict) else str(sheet_rows[3][level_col])
        
        if 'step' in str(entry_desc).lower() and 'no ramp' in str(entry_desc).lower():
            if str(parsed_value).lower() in ['no', 'n', 'false']:
                checks_passed += 1
                logger.info(f"✓ Venue 3 correctly parsed: steps, no ramp → {parsed_value}")
    
    if total_checks == 0:
        return False, "Insufficient data rows to verify parsing"
    
    accuracy = checks_passed / total_checks
    return accuracy >= 0.6, f"Text parsing accuracy: {accuracy:.1%} ({checks_passed}/{total_checks} checks passed)"


def verify_cost_calculation(workbook, sheet_name, sheet_rows):
    """
    Verify Total Access Cost calculation accuracy.
    Checks formulas and spot-checks calculated values.
    """
    # Find cost columns
    parking_col = find_column_by_keywords(sheet_rows, ['parking cost'])
    companion_col = find_column_by_keywords(sheet_rows, ['companion required', 'companion'])
    equipment_col = find_column_by_keywords(sheet_rows, ['equipment rental', 'equipment'])
    total_cost_col = find_column_by_keywords(sheet_rows, ['total access cost', 'total cost'])
    
    if total_cost_col is None:
        return False, "Total Access Cost column not found"
    
    # Check formula in first data row
    if len(sheet_rows) > 1:
        formula = sheet_rows[1][total_cost_col].get('formula', '') if isinstance(sheet_rows[1][total_cost_col], dict) else None
        
        if formula:
            # Check if formula contains expected components
            has_if = 'IF' in formula.upper()
            has_sum_logic = '+' in formula or 'SUM' in formula.upper()
            
            if has_if and has_sum_logic:
                logger.info(f"✓ Total Cost formula looks good: {formula}")
            else:
                return False, f"Total Cost formula missing expected logic: {formula}"
        else:
            logger.warning("Total Cost appears to be a value, not a formula")
    
    # Spot-check specific venue costs
    checks_passed = 0
    total_checks = 0
    
    # Venue 1 (row 2): Parking $15, No companion, No equipment = $15
    if len(sheet_rows) > 1:
        total_checks += 1
        actual_cost = sheet_rows[1][total_cost_col].get('value', 0) if isinstance(sheet_rows[1][total_cost_col], dict) else sheet_rows[1][total_cost_col]
        try:
            actual_cost = float(actual_cost) if actual_cost else 0
            if abs(actual_cost - 15) < 0.01:
                checks_passed += 1
                logger.info(f"✓ Venue 1 cost correct: ${actual_cost}")
            else:
                logger.warning(f"✗ Venue 1 cost incorrect: expected $15, got ${actual_cost}")
        except (ValueError, TypeError):
            logger.warning(f"Could not parse venue 1 cost: {actual_cost}")
    
    # Venue 2 (row 3): Parking $0, No companion, No equipment = $0
    if len(sheet_rows) > 2:
        total_checks += 1
        actual_cost = sheet_rows[2][total_cost_col].get('value', 0) if isinstance(sheet_rows[2][total_cost_col], dict) else sheet_rows[2][total_cost_col]
        try:
            actual_cost = float(actual_cost) if actual_cost else 0
            if abs(actual_cost - 0) < 0.01:
                checks_passed += 1
                logger.info(f"✓ Venue 2 cost correct: ${actual_cost}")
        except (ValueError, TypeError):
            pass
    
    # Venue 3 (row 4): Parking $25, YES companion ($50), No equipment = $75
    if len(sheet_rows) > 3:
        total_checks += 1
        actual_cost = sheet_rows[3][total_cost_col].get('value', 0) if isinstance(sheet_rows[3][total_cost_col], dict) else sheet_rows[3][total_cost_col]
        try:
            actual_cost = float(actual_cost) if actual_cost else 0
            if abs(actual_cost - 75) < 0.01:
                checks_passed += 1
                logger.info(f"✓ Venue 3 cost correct (with companion): ${actual_cost}")
        except (ValueError, TypeError):
            pass
    
    if total_checks == 0:
        return False, "Could not verify cost calculations"
    
    accuracy = checks_passed / total_checks
    return accuracy >= 0.5, f"Cost calculation: {checks_passed}/{total_checks} spot-checks passed"


def verify_requirements_logic(workbook, sheet_name, sheet_rows):
    """
    Verify that Meets Min Requirements column uses correct AND logic.
    """
    # Find requirement columns
    level_col = find_column_by_keywords(sheet_rows, ['level', 'ramped entry', 'level/ramped'])
    accessible_restroom_col = find_column_by_keywords(sheet_rows, ['accessible restroom'])
    hearing_col = find_column_by_keywords(sheet_rows, ['hearing support', 'hearing assist'])
    meets_req_col = find_column_by_keywords(sheet_rows, ['meets min', 'meets requirement', 'pass'])
    
    if meets_req_col is None:
        return False, "Meets Min Requirements column not found"
    
    # Check formula in first data row
    if len(sheet_rows) > 1:
        formula = sheet_rows[1][meets_req_col].get('formula', '') if isinstance(sheet_rows[1][meets_req_col], dict) else None
        
        if formula:
            # Check if formula uses AND logic
            has_and = 'AND' in formula.upper()
            has_if = 'IF' in formula.upper()
            
            if has_and and has_if:
                logger.info(f"✓ Requirements formula uses AND logic: {formula}")
            else:
                return False, f"Requirements formula missing AND logic: {formula}"
        else:
            logger.warning("Requirements column appears to be values, not formulas")
    
    # Verify logic: check specific venues
    checks_passed = 0
    total_checks = 0
    
    # Venue 2 (row 3): Should PASS (level entry, accessible restroom, live captioning)
    if len(sheet_rows) > 2 and level_col and accessible_restroom_col and hearing_col:
        total_checks += 1
        level_val = str(sheet_rows[2][level_col].get('value', '') if isinstance(sheet_rows[2][level_col], dict) else sheet_rows[2][level_col])
        meets_val = str(sheet_rows[2][meets_req_col].get('value', '') if isinstance(sheet_rows[2][meets_req_col], dict) else sheet_rows[2][meets_req_col])
        
        # If level entry is Yes, and meets requirements is PASS/Yes, that's good
        if 'yes' in level_val.lower() and ('pass' in meets_val.lower() or 'yes' in meets_val.lower() or '✓' in meets_val):
            checks_passed += 1
            logger.info(f"✓ Venue 2 correctly marked as PASS")
    
    # Venue 3 (row 4): Should FAIL (5 steps, no ramp, no elevator, no hearing)
    if len(sheet_rows) > 3:
        total_checks += 1
        meets_val = str(sheet_rows[3][meets_req_col].get('value', '') if isinstance(sheet_rows[3][meets_req_col], dict) else sheet_rows[3][meets_req_col])
        
        if 'fail' in meets_val.lower() or 'no' in meets_val.lower() or '✗' in meets_val:
            checks_passed += 1
            logger.info(f"✓ Venue 3 correctly marked as FAIL")
    
    if total_checks == 0:
        return False, "Could not verify requirements logic"
    
    accuracy = checks_passed / total_checks
    return accuracy >= 0.5, f"Requirements logic: {checks_passed}/{total_checks} checks passed"


def verify_decision_support(workbook, sheet_name, sheet_rows):
    """
    Verify that Cost-Effectiveness Score exists and is calculated correctly.
    """
    cost_effectiveness_col = find_column_by_keywords(sheet_rows, 
        ['cost-effectiveness', 'cost effectiveness', 'effectiveness score', 'score'])
    importance_col = find_column_by_keywords(sheet_rows, ['importance', 'event importance'])
    total_cost_col = find_column_by_keywords(sheet_rows, ['total access cost', 'total cost'])
    
    if cost_effectiveness_col is None:
        return False, "Cost-Effectiveness Score column not created"
    
    # Check formula in first data row
    if len(sheet_rows) > 1:
        formula = sheet_rows[1][cost_effectiveness_col].get('formula', '') if isinstance(sheet_rows[1][cost_effectiveness_col], dict) else None
        
        if formula:
            # Check if formula divides importance by cost
            has_division = '/' in formula
            
            if has_division:
                logger.info(f"✓ Cost-Effectiveness formula found: {formula}")
                return True, "Cost-Effectiveness Score calculated with formula"
            else:
                logger.warning(f"Cost-Effectiveness formula lacks division: {formula}")
                return False, "Cost-Effectiveness formula missing division logic"
    
    # Check if at least some values exist
    values_exist = False
    for row_idx in range(1, min(len(sheet_rows), 7)):
        value = sheet_rows[row_idx][cost_effectiveness_col].get('value', None) if isinstance(sheet_rows[row_idx][cost_effectiveness_col], dict) else sheet_rows[row_idx][cost_effectiveness_col]
        if value and value != '' and value != 0:
            values_exist = True
            break
    
    if values_exist:
        return True, "Cost-Effectiveness Score values present"
    else:
        return False, "Cost-Effectiveness Score column empty"


def verify_accessible_venue_eval(traj, env_info, task_info):
    """
    Main verification function for Accessible Venue Evaluator task.
    
    Checks:
    1. Standardization columns created (Level/Ramped Entry, Accessible Restroom, Hearing Support, Accessible Parking)
    2. Text parsing accuracy (converts descriptions to Yes/No correctly)
    3. Total Access Cost calculation (correct formulas and values)
    4. Meets Min Requirements logic (AND formula works correctly)
    5. Decision support present (Cost-Effectiveness Score)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the file (try ODS first, fall back to CSV)
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/accessible_venues_evaluated.ods'),
        ('ods', '/home/ga/Documents/venues_raw_data.ods'),
        ('csv', '/home/ga/Documents/venues_raw_data.csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_rows = workbook['sheets'][sheet_name]
        
        if len(sheet_rows) < 2:
            return {"passed": False, "score": 0, "feedback": "Insufficient data rows in spreadsheet"}
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Standardization columns created
        required_columns = [
            (['level', 'ramped', 'level/ramped'], 'Level/Ramped Entry'),
            (['accessible restroom'], 'Accessible Restroom'),
            (['hearing support', 'hearing assist'], 'Hearing Support')
        ]
        
        standardization_complete = True
        for keywords, col_name in required_columns:
            col_idx = find_column_by_keywords(sheet_rows, keywords)
            if col_idx is None:
                standardization_complete = False
                feedback_parts.append(f"❌ Missing column: {col_name}")
                break
        
        if standardization_complete:
            criteria_passed += 1
            feedback_parts.append("✅ Standardization columns created")
            subscores['standardization_columns'] = True
        else:
            subscores['standardization_columns'] = False
        
        # Criterion 2: Text parsing accuracy
        parsing_ok, parsing_msg = check_text_parsing_accuracy(workbook, sheet_name, sheet_rows)
        if parsing_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {parsing_msg}")
            subscores['text_parsing'] = True
        else:
            feedback_parts.append(f"❌ {parsing_msg}")
            subscores['text_parsing'] = False
        
        # Criterion 3: Cost calculation correct
        cost_ok, cost_msg = verify_cost_calculation(workbook, sheet_name, sheet_rows)
        if cost_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {cost_msg}")
            subscores['cost_calculation'] = True
        else:
            feedback_parts.append(f"❌ {cost_msg}")
            subscores['cost_calculation'] = False
        
        # Criterion 4: Requirements logic valid
        req_ok, req_msg = verify_requirements_logic(workbook, sheet_name, sheet_rows)
        if req_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {req_msg}")
            subscores['requirements_logic'] = True
        else:
            feedback_parts.append(f"❌ {req_msg}")
            subscores['requirements_logic'] = False
        
        # Criterion 5: Decision support present
        decision_ok, decision_msg = verify_decision_support(workbook, sheet_name, sheet_rows)
        if decision_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {decision_msg}")
            subscores['decision_support'] = True
        else:
            feedback_parts.append(f"⚠️ {decision_msg}")
            subscores['decision_support'] = False
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 70% (4 out of 5 criteria, with first 3 being most important)
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent venue analysis! All criteria met.")
        elif passed:
            feedback_parts.insert(0, "✅ Venue evaluation completed successfully.")
        else:
            feedback_parts.insert(0, "❌ Venue evaluation incomplete or incorrect.")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_temp(temp_dir)
