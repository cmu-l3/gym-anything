#!/usr/bin/env python3
"""
Verifier for Car Maintenance Tracker task
"""

import sys
import os
import logging
import zipfile
from xml.etree import ElementTree as ET
import re

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    parse_ods_file
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Service intervals (in miles)
SERVICE_INTERVALS = {
    'Oil Change': 5000,
    'Tire Rotation': 7500,
    'Brake Inspection': 15000,
    'Air Filter': 20000
}

CURRENT_MILEAGE = 47500


def check_conditional_formatting_in_ods(filepath):
    """
    Check if conditional formatting exists in ODS file by parsing XML.
    
    Returns:
        bool: True if conditional formatting detected
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False
            
            content_xml = ods_zip.read('content.xml')
            content_str = content_xml.decode('utf-8', errors='ignore')
            
            # Look for conditional formatting indicators in ODS XML
            # LibreOffice uses calcext:conditional-formats or style:map
            indicators = [
                'conditional-format',
                'calcext:conditional-format',
                'style:map',
                'condition=',
                'apply-style-name'
            ]
            
            for indicator in indicators:
                if indicator in content_str:
                    logger.info(f"Found conditional formatting indicator: {indicator}")
                    return True
            
            return False
    
    except Exception as e:
        logger.warning(f"Could not check conditional formatting: {e}")
        return False


def extract_formula_references(formula):
    """
    Extract cell references from a formula.
    
    Returns:
        list: Cell references found in formula
    """
    if not formula:
        return []
    
    # Match cell references like A1, B10, $A$1, etc.
    pattern = r'\$?[A-Z]+\$?\d+'
    matches = re.findall(pattern, formula.upper())
    return matches


def verify_next_service_formula(formula, service_type, mileage_at_service):
    """
    Verify that the "Next Service Due" formula is reasonable.
    
    Args:
        formula: Formula string
        service_type: Type of service
        mileage_at_service: Mileage when service was performed
        
    Returns:
        bool: True if formula looks correct
    """
    if not formula:
        return False
    
    formula_upper = formula.upper()
    
    # Check if formula references the mileage column (C) or uses appropriate interval
    interval = SERVICE_INTERVALS.get(service_type, 5000)
    
    # Basic checks:
    # 1. Formula should contain a reference to column C or the specific mileage
    # 2. Should contain addition operation
    # 3. Should reference the interval value or contain IF statement
    
    has_addition = '+' in formula_upper
    references = extract_formula_references(formula)
    has_column_c_ref = any('C' in ref for ref in references)
    
    # Check if formula contains the interval value or IF statement
    has_interval = str(interval) in formula or 'IF' in formula_upper
    
    return has_addition and (has_column_c_ref or has_interval)


def verify_miles_until_formula(formula):
    """
    Verify that the "Miles Until Next Service" formula is reasonable.
    
    Args:
        formula: Formula string
        
    Returns:
        bool: True if formula looks correct
    """
    if not formula:
        return False
    
    formula_upper = formula.upper()
    
    # Check if formula:
    # 1. Contains subtraction
    # 2. References column E (Next Service Due)
    # 3. References cell B1 (current mileage)
    
    has_subtraction = '-' in formula_upper
    references = extract_formula_references(formula)
    has_column_e_ref = any('E' in ref for ref in references)
    has_b1_ref = any('B1' in ref for ref in references)
    
    return has_subtraction and has_column_e_ref and has_b1_ref


def verify_car_maintenance_tracker(traj, env_info, task_info):
    """
    Verify car maintenance tracker task completion.
    
    Checks:
    1. Column E formulas present (Next Service Due)
    2. Column F formulas present (Miles Until Next)
    3. Conditional formatting exists on Column F
    4. Calculations accurate (spot check)
    5. Missing mileage data filled
    6. Total cost calculated
    7. At least one overdue item identified
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    temp_dir = None
    workbook = None
    filepath = None
    
    for path in [
        "/home/ga/Documents/car_maintenance_analyzed.ods",
        "/home/ga/Documents/car_maintenance_log.ods",
        "/home/ga/Documents/car_maintenance_log.csv"
    ]:
        file_ext = path.split('.')[-1]
        format_type = 'ods' if file_ext == 'ods' else 'csv'
        
        success, wb, error, td = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=format_type
        )
        
        if success:
            workbook = wb
            temp_dir = td
            # Get the actual filepath from temp directory
            filepath = os.path.join(td, f"result.{file_ext}")
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not workbook:
        return {"passed": False, "score": 0, "feedback": "Failed to load maintenance log file"}
    
    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Current mileage should be in B1
        current_mileage_cell = get_cell_value(workbook, sheet_name, 'B1')
        if current_mileage_cell and abs(float(current_mileage_cell) - CURRENT_MILEAGE) < 100:
            logger.info(f"✓ Current mileage confirmed: {current_mileage_cell}")
        
        # Data starts at row 4 (after headers in row 3)
        data_start_row = 4
        data_end_row = 13  # Approximately 10 service records
        
        # CRITERION 1: Check for formulas in Column E (Next Service Due)
        col_e_formula_count = 0
        col_e_total = 0
        
        for row in range(data_start_row, data_end_row + 1):
            cell_ref = f"E{row}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            value = get_cell_value(workbook, sheet_name, cell_ref)
            
            if value is not None and value != '':
                col_e_total += 1
                if formula:
                    col_e_formula_count += 1
                    logger.debug(f"Formula in {cell_ref}: {formula}")
        
        col_e_formula_percentage = col_e_formula_count / col_e_total if col_e_total > 0 else 0
        
        if col_e_formula_percentage >= 0.6:  # At least 60% of cells have formulas
            criteria_passed += 1
            feedback_parts.append(f"✅ Column E formulas present ({col_e_formula_count}/{col_e_total} cells)")
            subscores['column_e_formulas'] = True
        else:
            feedback_parts.append(f"❌ Column E missing formulas ({col_e_formula_count}/{col_e_total} cells have formulas)")
            subscores['column_e_formulas'] = False
        
        # CRITERION 2: Check for formulas in Column F (Miles Until Next)
        col_f_formula_count = 0
        col_f_total = 0
        
        for row in range(data_start_row, data_end_row + 1):
            cell_ref = f"F{row}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            value = get_cell_value(workbook, sheet_name, cell_ref)
            
            if value is not None and value != '':
                col_f_total += 1
                if formula:
                    col_f_formula_count += 1
                    logger.debug(f"Formula in {cell_ref}: {formula}")
        
        col_f_formula_percentage = col_f_formula_count / col_f_total if col_f_total > 0 else 0
        
        if col_f_formula_percentage >= 0.6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Column F formulas present ({col_f_formula_count}/{col_f_total} cells)")
            subscores['column_f_formulas'] = True
        else:
            feedback_parts.append(f"❌ Column F missing formulas ({col_f_formula_count}/{col_f_total} cells have formulas)")
            subscores['column_f_formulas'] = False
        
        # CRITERION 3: Check for conditional formatting
        has_conditional_fmt = False
        
        if filepath and filepath.endswith('.ods'):
            has_conditional_fmt = check_conditional_formatting_in_ods(filepath)
        
        if has_conditional_fmt:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
            subscores['conditional_formatting'] = True
        else:
            feedback_parts.append("⚠️  Conditional formatting not detected (may be present but not parseable)")
            subscores['conditional_formatting'] = False
            # Give partial credit since detection is difficult
            criteria_passed += 0.3
        
        # CRITERION 4: Spot-check calculation accuracy
        # Check a few specific rows for correct calculations
        test_cases = [
            # (row, service_type, mileage_at_service)
            (4, 'Oil Change', 25000),  # Row 4
            (7, 'Brake Inspection', 32000),  # Row 7
            (9, 'Tire Rotation', 40000),  # Row 9
        ]
        
        calc_correct_count = 0
        calc_total = 0
        
        for row, service_type, expected_mileage in test_cases:
            # Check if mileage matches
            mileage = get_cell_value(workbook, sheet_name, f"C{row}")
            
            if mileage and abs(float(mileage) - expected_mileage) < 1000:
                # Check Next Service Due calculation
                next_due = get_cell_value(workbook, sheet_name, f"E{row}")
                interval = SERVICE_INTERVALS.get(service_type, 5000)
                expected_next_due = expected_mileage + interval
                
                if next_due:
                    calc_total += 1
                    if abs(float(next_due) - expected_next_due) <= 1:
                        calc_correct_count += 1
                        logger.debug(f"Row {row} Next Due correct: {next_due}")
                    else:
                        logger.debug(f"Row {row} Next Due incorrect: expected {expected_next_due}, got {next_due}")
        
        calc_accuracy = calc_correct_count / calc_total if calc_total > 0 else 0
        
        if calc_accuracy >= 0.6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculations accurate (spot check: {calc_correct_count}/{calc_total} correct)")
            subscores['calculations_accurate'] = True
        else:
            feedback_parts.append(f"❌ Calculation errors (spot check: {calc_correct_count}/{calc_total} correct)")
            subscores['calculations_accurate'] = False
        
        # CRITERION 5: Check if missing mileage data was filled
        # Row 8 (2023-02-14 Oil Change) should have mileage filled in
        row_8_mileage = get_cell_value(workbook, sheet_name, 'C8')
        
        missing_data_filled = False
        if row_8_mileage and row_8_mileage != '':
            try:
                mileage_val = float(row_8_mileage)
                # Should be between 30000 and 40000 (between the previous and next oil changes)
                if 32000 <= mileage_val <= 38000:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Missing mileage filled (C8: {mileage_val})")
                    subscores['missing_data_filled'] = True
                    missing_data_filled = True
                else:
                    feedback_parts.append(f"⚠️  C8 filled but value seems incorrect ({mileage_val})")
                    subscores['missing_data_filled'] = False
            except (ValueError, TypeError):
                feedback_parts.append("❌ C8 mileage not filled or invalid")
                subscores['missing_data_filled'] = False
        else:
            feedback_parts.append("❌ Missing mileage data not filled (C8 empty)")
            subscores['missing_data_filled'] = False
        
        # CRITERION 6: Check total cost calculation
        # Total cost should be in summary area (around D13-E15)
        total_cost_found = False
        total_cost_correct = False
        
        for row in range(13, 16):
            for col in ['D', 'E', 'F']:
                cell_ref = f"{col}{row}"
                formula = get_cell_formula(workbook, sheet_name, cell_ref)
                value = get_cell_value(workbook, sheet_name, cell_ref)
                
                if formula and 'SUM' in formula.upper():
                    total_cost_found = True
                    # Expected total: 45+30+45+120+45+35+50+25+50+35 = 480
                    expected_total = 480
                    if value and abs(float(value) - expected_total) <= 10:
                        total_cost_correct = True
                        logger.info(f"Total cost found in {cell_ref}: {value}")
                        break
            if total_cost_found:
                break
        
        if total_cost_correct:
            criteria_passed += 1
            feedback_parts.append(f"✅ Total cost calculated correctly")
            subscores['total_cost_calculated'] = True
        elif total_cost_found:
            feedback_parts.append(f"⚠️  Total cost formula found but value may be incorrect")
            subscores['total_cost_calculated'] = False
            criteria_passed += 0.5
        else:
            feedback_parts.append("❌ Total cost not calculated")
            subscores['total_cost_calculated'] = False
        
        # CRITERION 7: Check for overdue items (negative values in Column F)
        overdue_count = 0
        
        for row in range(data_start_row, data_end_row + 1):
            miles_until = get_cell_value(workbook, sheet_name, f"F{row}")
            
            if miles_until is not None:
                try:
                    miles_val = float(miles_until)
                    if miles_val < 0:
                        overdue_count += 1
                        logger.debug(f"Overdue service found in row {row}: {miles_val} miles")
                except (ValueError, TypeError):
                    pass
        
        if overdue_count >= 1:
            criteria_passed += 1
            feedback_parts.append(f"✅ Overdue items identified ({overdue_count} services)")
            subscores['overdue_items_identified'] = True
        else:
            feedback_parts.append("❌ No overdue items identified (check formulas in Column F)")
            subscores['overdue_items_identified'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (5/7 criteria)
        
        # Build feedback summary
        if passed and score >= 95:
            feedback_parts.insert(0, "🎉 Excellent work! Maintenance tracker fully functional")
        elif passed:
            feedback_parts.insert(0, "✅ Maintenance tracker completed successfully")
        else:
            feedback_parts.insert(0, "❌ Maintenance tracker incomplete - review requirements")
        
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
        if temp_dir:
            cleanup_verification_temp(temp_dir)
