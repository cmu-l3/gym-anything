#!/usr/bin/env python3
"""
Verifier for Blood Donation Tracker task
"""

import sys
import os
import logging
import re
from datetime import datetime, timedelta

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
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


def parse_date(date_value):
    """Parse date from various formats"""
    if isinstance(date_value, str):
        # Try common date formats
        for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d']:
            try:
                return datetime.strptime(date_value, fmt)
            except ValueError:
                continue
        return None
    elif isinstance(date_value, datetime):
        return date_value
    else:
        return None


def validate_eligibility_calculation(donation_date_str, donation_type, calculated_eligible_str, 
                                    waiting_periods):
    """
    Validate that eligibility date is correctly calculated.
    
    Args:
        donation_date_str: Date of donation (string or date)
        donation_type: Type of donation
        calculated_eligible_str: Calculated eligible date
        waiting_periods: Dict mapping donation types to waiting periods
        
    Returns:
        bool: True if calculation is correct (within 1 day tolerance)
    """
    try:
        donation_dt = parse_date(donation_date_str)
        if not donation_dt:
            logger.warning(f"Could not parse donation date: {donation_date_str}")
            return False
        
        if donation_type not in waiting_periods:
            logger.warning(f"Unknown donation type: {donation_type}")
            return False
        
        expected_eligible = donation_dt + timedelta(days=waiting_periods[donation_type])
        
        actual_eligible = parse_date(calculated_eligible_str)
        if not actual_eligible:
            logger.warning(f"Could not parse calculated date: {calculated_eligible_str}")
            return False
        
        # Allow 1 day tolerance for different calculation methods
        diff_days = abs((expected_eligible - actual_eligible).days)
        
        if diff_days <= 1:
            return True
        else:
            logger.info(f"Date mismatch: expected {expected_eligible.date()}, got {actual_eligible.date()}, diff={diff_days} days")
            return False
            
    except Exception as e:
        logger.error(f"Error validating calculation: {e}")
        return False


def check_formula_pattern(formula):
    """
    Check if formula contains expected patterns for lookup and date arithmetic.
    
    Returns:
        dict with 'has_lookup', 'has_addition', 'has_absolute_ref'
    """
    if not formula:
        return {'has_lookup': False, 'has_addition': False, 'has_absolute_ref': False}
    
    formula_upper = formula.upper()
    
    # Check for lookup functions
    has_vlookup = 'VLOOKUP' in formula_upper
    has_index = 'INDEX' in formula_upper
    has_match = 'MATCH' in formula_upper
    has_lookup = has_vlookup or (has_index and has_match)
    
    # Check for addition (date arithmetic)
    has_addition = '+' in formula
    
    # Check for absolute references ($ signs)
    has_absolute_ref = '$' in formula
    
    return {
        'has_lookup': has_lookup,
        'has_addition': has_addition,
        'has_absolute_ref': has_absolute_ref
    }


def verify_blood_donation_tracker(traj, env_info, task_info):
    """
    Verify blood donation tracker task completion.
    
    Checks:
    1. Reference table exists with correct waiting periods
    2. Formulas use VLOOKUP or INDEX-MATCH
    3. Date arithmetic is correct (donation date + waiting period)
    4. At least 3 spot-checked dates are mathematically correct
    5. Summary shows next available donation date
    6. Formula uses absolute references for reference table
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/blood_donation_tracker.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        sheet_names = get_sheet_names(workbook)
        
        # Find donation log and reference table sheets
        donation_sheet = None
        reference_sheet = None
        
        for name in sheet_names:
            name_lower = name.lower()
            if 'donation' in name_lower and 'log' in name_lower:
                donation_sheet = name
            elif 'reference' in name_lower or 'ref' in name_lower:
                reference_sheet = name
        
        # Fallback to sheet indices if names not found
        if not donation_sheet and len(sheet_names) >= 1:
            donation_sheet = sheet_names[0]
        if not reference_sheet and len(sheet_names) >= 2:
            reference_sheet = sheet_names[1]
        
        if not donation_sheet:
            return {"passed": False, "score": 0, "feedback": "Could not find donation log sheet"}

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []

        # Expected waiting periods
        expected_waiting_periods = {
            'Whole Blood': 56,
            'Platelets': 7,
            'Plasma': 28,
            'Double Red Cells': 112
        }

        # Criterion 1: Reference table exists with correct values
        reference_table_correct = False
        if reference_sheet:
            # Check reference table values
            ref_correct_count = 0
            for i, (dtype, period) in enumerate(expected_waiting_periods.items(), start=2):
                type_val = get_cell_value(workbook, reference_sheet, f'A{i}')
                period_val = get_cell_value(workbook, reference_sheet, f'B{i}')
                
                if type_val and dtype.lower() in str(type_val).lower():
                    if period_val == period or str(period_val) == str(period):
                        ref_correct_count += 1
            
            if ref_correct_count >= 3:  # At least 3 out of 4 correct
                criteria_passed += 1
                reference_table_correct = True
                feedback_parts.append(f"✅ Reference table correct ({ref_correct_count}/4 entries)")
            else:
                feedback_parts.append(f"❌ Reference table incomplete or incorrect ({ref_correct_count}/4 entries)")
        else:
            feedback_parts.append("❌ Reference table sheet not found")

        # Criterion 2 & 3: Check formulas in eligibility column
        formulas_with_lookup = 0
        formulas_with_addition = 0
        formulas_with_absolute = 0
        total_formulas_checked = 0
        
        # Check rows 2-9 (8 donation records)
        for row in range(2, 10):
            formula = get_cell_formula(workbook, donation_sheet, f'C{row}')
            if formula:
                total_formulas_checked += 1
                pattern = check_formula_pattern(formula)
                
                if pattern['has_lookup']:
                    formulas_with_lookup += 1
                if pattern['has_addition']:
                    formulas_with_addition += 1
                if pattern['has_absolute_ref']:
                    formulas_with_absolute += 1

        # At least 50% of formulas should have lookup functions
        if total_formulas_checked >= 4 and formulas_with_lookup >= (total_formulas_checked * 0.5):
            criteria_passed += 1
            feedback_parts.append(f"✅ Lookup formulas used ({formulas_with_lookup}/{total_formulas_checked} cells)")
        elif total_formulas_checked > 0:
            feedback_parts.append(f"❌ Missing lookup formulas ({formulas_with_lookup}/{total_formulas_checked} cells have VLOOKUP/INDEX-MATCH)")
        else:
            feedback_parts.append("❌ No formulas found in Next Eligible Date column")

        # Check date arithmetic (addition)
        if total_formulas_checked >= 4 and formulas_with_addition >= (total_formulas_checked * 0.5):
            criteria_passed += 1
            feedback_parts.append(f"✅ Date arithmetic present ({formulas_with_addition}/{total_formulas_checked} cells)")
        elif total_formulas_checked > 0:
            feedback_parts.append(f"❌ Date arithmetic missing in formulas")

        # Criterion 4: Validate calculation accuracy (spot check 3 dates)
        correct_calculations = 0
        checked_calculations = 0
        
        # Spot check rows 2, 4, 6
        for row in [2, 4, 6]:
            donation_date = get_cell_value(workbook, donation_sheet, f'A{row}')
            donation_type = get_cell_value(workbook, donation_sheet, f'B{row}')
            calculated_eligible = get_cell_value(workbook, donation_sheet, f'C{row}')
            
            if donation_date and donation_type and calculated_eligible:
                checked_calculations += 1
                if validate_eligibility_calculation(donation_date, donation_type, 
                                                   calculated_eligible, expected_waiting_periods):
                    correct_calculations += 1
                    logger.info(f"✓ Row {row}: {donation_type} calculation correct")
                else:
                    logger.info(f"✗ Row {row}: {donation_type} calculation incorrect")

        if checked_calculations >= 3 and correct_calculations >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculations accurate ({correct_calculations}/{checked_calculations} spot-checked)")
        elif checked_calculations > 0:
            feedback_parts.append(f"❌ Calculation errors found ({correct_calculations}/{checked_calculations} correct)")
        else:
            feedback_parts.append("❌ Could not verify calculations (no data in eligibility column)")

        # Criterion 5: Check for summary calculation
        summary_found = False
        summary_correct = False
        
        # Check rows 11-15 for summary area
        for row in range(11, 16):
            cell_a = get_cell_value(workbook, donation_sheet, f'A{row}')
            if cell_a and ('next' in str(cell_a).lower() or 'available' in str(cell_a).lower()):
                # Found summary label, check adjacent cells for formula
                for col in ['B', 'C']:
                    summary_formula = get_cell_formula(workbook, donation_sheet, f'{col}{row}')
                    summary_value = get_cell_value(workbook, donation_sheet, f'{col}{row}')
                    
                    if summary_formula and ('MIN' in summary_formula.upper() or 'SMALL' in summary_formula.upper()):
                        summary_found = True
                        if summary_value:
                            summary_correct = True
                        break
                
                if summary_found:
                    break

        if summary_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Summary calculation present and functional")
        elif summary_found:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Summary area exists but may not be calculating correctly")
        else:
            feedback_parts.append("❌ Summary calculation not found")

        # Criterion 6: Check for absolute references
        if total_formulas_checked >= 4 and formulas_with_absolute >= (total_formulas_checked * 0.5):
            criteria_passed += 1
            feedback_parts.append(f"✅ Absolute references used ({formulas_with_absolute}/{total_formulas_checked} cells)")
        elif total_formulas_checked > 0:
            feedback_parts.append(f"⚠️ Few absolute references found (may cause errors when copying)")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "reference_table": reference_table_correct,
                "lookup_formulas": formulas_with_lookup >= (total_formulas_checked * 0.5) if total_formulas_checked > 0 else False,
                "date_arithmetic": formulas_with_addition >= (total_formulas_checked * 0.5) if total_formulas_checked > 0 else False,
                "calculation_accuracy": correct_calculations >= 3 if checked_calculations >= 3 else False,
                "summary_present": summary_correct,
                "absolute_references": formulas_with_absolute >= (total_formulas_checked * 0.5) if total_formulas_checked > 0 else False
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
