#!/usr/bin/env python3
"""
Verifier for Sourdough Starter Calculator task
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path for host machine compatibility
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_by_header(sheet_data, header_keywords):
    """
    Find column index by searching for keywords in header row.
    Returns column index (0-based) or None if not found.
    """
    if not sheet_data or len(sheet_data) == 0:
        return None
    
    header_row = sheet_data[0]
    for col_idx, cell in enumerate(header_row):
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        if cell_value:
            cell_str = str(cell_value).lower().replace('_', '').replace(' ', '')
            for keyword in header_keywords:
                if keyword.lower().replace('_', '').replace(' ', '') in cell_str:
                    return col_idx
    return None


def get_cell_from_sheet(sheet_data, row_idx, col_idx):
    """Get cell data from sheet data structure safely."""
    if row_idx < len(sheet_data) and col_idx < len(sheet_data[row_idx]):
        cell = sheet_data[row_idx][col_idx]
        if isinstance(cell, dict):
            return cell
        else:
            return {'value': cell, 'formula': None, 'type': 'unknown'}
    return {'value': None, 'formula': None, 'type': 'unknown'}


def check_hydration_formula(workbook, sheet_name, sheet_data, hydration_col_idx, flour_col_idx, water_col_idx, data_row=1):
    """Check if hydration formula is correct."""
    if hydration_col_idx is None:
        return False, "Hydration column not found"
    
    # Get cell formula (convert to cell reference like "I2")
    col_letter = chr(ord('A') + hydration_col_idx)
    cell_ref = f"{col_letter}{data_row + 1}"  # +1 because Excel/Calc uses 1-based
    
    formula = get_cell_formula(workbook, sheet_name, cell_ref)
    if not formula:
        # Try getting from sheet data directly
        cell = get_cell_from_sheet(sheet_data, data_row, hydration_col_idx)
        formula = cell.get('formula')
    
    if formula:
        formula_upper = formula.upper().replace(' ', '')
        # Check if formula contains division and multiplication by 100
        # Expected pattern: =(E2/D2)*100 or similar
        has_division = '/' in formula
        has_multiplication = '*100' in formula_upper or '*100)' in formula_upper
        
        if has_division and has_multiplication:
            # Verify the calculated value is reasonable
            flour = get_cell_from_sheet(sheet_data, data_row, flour_col_idx).get('value')
            water = get_cell_from_sheet(sheet_data, data_row, water_col_idx).get('value')
            hydration = get_cell_from_sheet(sheet_data, data_row, hydration_col_idx).get('value')
            
            if flour and water and hydration:
                expected = (float(water) / float(flour)) * 100
                actual = float(hydration)
                if abs(actual - expected) <= 2.0:  # 2% tolerance
                    return True, f"Hydration formula correct: {formula}"
                else:
                    return False, f"Hydration calculation incorrect: expected {expected:.1f}%, got {actual:.1f}%"
            return True, "Hydration formula present"
        
        return False, f"Hydration formula incomplete: {formula}"
    
    return False, "No hydration formula found"


def check_total_weight_formula(workbook, sheet_name, sheet_data, weight_col_idx, starter_col_idx, flour_col_idx, water_col_idx, data_row=1):
    """Check if total weight formula is correct."""
    if weight_col_idx is None:
        return False, "Total weight column not found"
    
    col_letter = chr(ord('A') + weight_col_idx)
    cell_ref = f"{col_letter}{data_row + 1}"
    
    formula = get_cell_formula(workbook, sheet_name, cell_ref)
    if not formula:
        cell = get_cell_from_sheet(sheet_data, data_row, weight_col_idx)
        formula = cell.get('formula')
    
    if formula:
        # Check if formula contains addition of three components
        # Count + signs (should have at least 2 for three components)
        plus_count = formula.count('+')
        
        if plus_count >= 2:
            # Verify the calculated value
            starter = get_cell_from_sheet(sheet_data, data_row, starter_col_idx).get('value')
            flour = get_cell_from_sheet(sheet_data, data_row, flour_col_idx).get('value')
            water = get_cell_from_sheet(sheet_data, data_row, water_col_idx).get('value')
            total = get_cell_from_sheet(sheet_data, data_row, weight_col_idx).get('value')
            
            if starter and flour and water and total:
                expected = float(starter) + float(flour) + float(water)
                actual = float(total)
                if abs(actual - expected) <= 1.0:  # 1g tolerance
                    return True, f"Total weight formula correct: {formula}"
                else:
                    return False, f"Total weight calculation incorrect: expected {expected}g, got {actual}g"
            return True, "Total weight formula present"
        
        return False, f"Total weight formula incomplete: {formula}"
    
    return False, "No total weight formula found"


def check_readiness_logic(workbook, sheet_name, sheet_data, ready_col_idx, hours_col_idx, weight_col_idx):
    """Check if readiness logic is implemented correctly."""
    if ready_col_idx is None:
        return False, "Readiness column not found"
    
    # Test a few rows to verify logic
    test_results = []
    
    for row_idx in range(1, min(4, len(sheet_data))):  # Test first 3 data rows
        hours = get_cell_from_sheet(sheet_data, row_idx, hours_col_idx).get('value')
        total_weight = get_cell_from_sheet(sheet_data, row_idx, weight_col_idx).get('value')
        ready_flag = get_cell_from_sheet(sheet_data, row_idx, ready_col_idx).get('value')
        
        if hours and total_weight and ready_flag is not None:
            hours_val = float(hours)
            weight_val = float(total_weight)
            ready_str = str(ready_flag).strip().upper()
            
            # Expected logic: ready if hours between 3-8 AND weight >= 150
            expected_ready = (3 <= hours_val <= 8 and weight_val >= 150)
            expected_flag = "YES" if expected_ready else "NO"
            
            test_results.append(ready_str == expected_flag)
    
    if len(test_results) > 0:
        correct_count = sum(test_results)
        if correct_count == len(test_results):
            return True, f"Readiness logic correct ({correct_count}/{len(test_results)} rows)"
        elif correct_count >= len(test_results) * 0.7:
            return True, f"Readiness logic mostly correct ({correct_count}/{len(test_results)} rows)"
        else:
            return False, f"Readiness logic incorrect ({correct_count}/{len(test_results)} rows correct)"
    
    # If can't test values, check if formula exists
    col_letter = chr(ord('A') + ready_col_idx)
    cell_ref = f"{col_letter}2"
    formula = get_cell_formula(workbook, sheet_name, cell_ref)
    
    if formula:
        formula_upper = formula.upper()
        has_if = 'IF' in formula_upper
        has_and = 'AND' in formula_upper
        
        if has_if and has_and:
            return True, "Readiness formula present with IF/AND logic"
        elif has_if:
            return True, "Readiness formula present (partial credit)"
        
        return False, f"Readiness formula incomplete: {formula}"
    
    return False, "No readiness formula found"


def check_summary_calculations(workbook, sheet_name, sheet_data, flour_col_idx):
    """Check for summary calculations (total flour, average hydration)."""
    summary_checks = {'total_flour': False, 'avg_hydration': False}
    
    # Look for SUM formulas in the spreadsheet (typically below data)
    data_rows = len(sheet_data)
    
    # Check rows below data (up to 10 rows after)
    for row_idx in range(data_rows, min(data_rows + 10, data_rows + 15)):
        for col_idx in range(10):  # Check first 10 columns
            col_letter = chr(ord('A') + col_idx)
            cell_ref = f"{col_letter}{row_idx + 1}"
            
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            if formula:
                formula_upper = formula.upper()
                
                if 'SUM' in formula_upper and not summary_checks['total_flour']:
                    # Check if it's summing the flour column
                    flour_col_letter = chr(ord('A') + flour_col_idx) if flour_col_idx is not None else 'D'
                    if flour_col_letter in formula_upper:
                        summary_checks['total_flour'] = True
                        logger.info(f"Found total flour SUM formula at {cell_ref}: {formula}")
                
                if 'AVERAGE' in formula_upper and not summary_checks['avg_hydration']:
                    summary_checks['avg_hydration'] = True
                    logger.info(f"Found average formula at {cell_ref}: {formula}")
    
    return summary_checks


def verify_sourdough_calculator(traj, env_info, task_info):
    """
    Verify sourdough starter calculator task completion.
    
    Checks:
    1. Hydration formula present and correct
    2. Total weight formula present and correct
    3. Readiness logic implemented (IF/AND)
    4. Total flour calculated (SUM)
    5. Values within reasonable range
    6. Average hydration calculated (AVERAGE)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        ("/home/ga/Documents/sourdough_analysis.ods", 'ods'),
        ("/home/ga/Documents/feeding_log.ods", 'ods'),
        ("/home/ga/Documents/feeding_log.csv", 'csv'),
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path, file_format in possible_paths:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file from {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not load spreadsheet file: {error}"
        }
    
    try:
        # Get sheet data
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = workbook['sheets'][sheet_name]
        
        logger.info(f"Sheet: {sheet_name}, Rows: {len(sheet_data)}")
        
        # Identify columns by header
        starter_col = find_column_by_header(sheet_data, ['starter', 'weight', 'starter_weight'])
        flour_col = find_column_by_header(sheet_data, ['flour', 'flour_added'])
        water_col = find_column_by_header(sheet_data, ['water', 'water_added'])
        temp_col = find_column_by_header(sheet_data, ['temp', 'temperature', 'room_temp'])
        hours_col = find_column_by_header(sheet_data, ['hours', 'since', 'hours_since'])
        
        # Look for calculated columns
        weight_total_col = find_column_by_header(sheet_data, ['total', 'totalweight', 'weight_after', 'total_weight'])
        hydration_col = find_column_by_header(sheet_data, ['hydration', 'hydration_percent'])
        ready_col = find_column_by_header(sheet_data, ['ready', 'bake', 'readytobake'])
        
        logger.info(f"Original columns - Starter: {starter_col}, Flour: {flour_col}, Water: {water_col}")
        logger.info(f"Calculated columns - Total: {weight_total_col}, Hydration: {hydration_col}, Ready: {ready_col}")
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Hydration formula
        if hydration_col is not None:
            hydration_ok, hydration_msg = check_hydration_formula(
                workbook, sheet_name, sheet_data, 
                hydration_col, flour_col, water_col
            )
            if hydration_ok:
                criteria_passed += 1
                feedback_parts.append(f"✅ {hydration_msg}")
            else:
                feedback_parts.append(f"❌ {hydration_msg}")
            subscores['hydration_formula'] = hydration_ok
        else:
            feedback_parts.append("❌ Hydration column not found")
            subscores['hydration_formula'] = False
        
        # Criterion 2: Total weight formula
        if weight_total_col is not None:
            weight_ok, weight_msg = check_total_weight_formula(
                workbook, sheet_name, sheet_data,
                weight_total_col, starter_col, flour_col, water_col
            )
            if weight_ok:
                criteria_passed += 1
                feedback_parts.append(f"✅ {weight_msg}")
            else:
                feedback_parts.append(f"❌ {weight_msg}")
            subscores['total_weight_formula'] = weight_ok
        else:
            feedback_parts.append("❌ Total weight column not found")
            subscores['total_weight_formula'] = False
        
        # Criterion 3: Readiness logic
        if ready_col is not None and weight_total_col is not None:
            ready_ok, ready_msg = check_readiness_logic(
                workbook, sheet_name, sheet_data,
                ready_col, hours_col, weight_total_col
            )
            if ready_ok:
                criteria_passed += 1
                feedback_parts.append(f"✅ {ready_msg}")
            else:
                feedback_parts.append(f"❌ {ready_msg}")
            subscores['readiness_logic'] = ready_ok
        else:
            feedback_parts.append("❌ Readiness column not found or dependencies missing")
            subscores['readiness_logic'] = False
        
        # Criterion 4 & 6: Summary calculations
        summary = check_summary_calculations(workbook, sheet_name, sheet_data, flour_col)
        
        if summary['total_flour']:
            criteria_passed += 1
            feedback_parts.append("✅ Total flour SUM formula found")
            subscores['total_flour_sum'] = True
        else:
            feedback_parts.append("❌ Total flour SUM formula not found")
            subscores['total_flour_sum'] = False
        
        if summary['avg_hydration']:
            criteria_passed += 1
            feedback_parts.append("✅ Average hydration formula found")
            subscores['avg_hydration'] = True
        else:
            feedback_parts.append("❌ Average hydration formula not found")
            subscores['avg_hydration'] = False
        
        # Criterion 5: Values within reasonable range
        values_reasonable = True
        if hydration_col is not None:
            # Check a few hydration values
            for row_idx in range(1, min(4, len(sheet_data))):
                hydration = get_cell_from_sheet(sheet_data, row_idx, hydration_col).get('value')
                if hydration:
                    hydration_val = float(hydration)
                    if not (70 <= hydration_val <= 150):
                        values_reasonable = False
                        break
        
        if values_reasonable:
            criteria_passed += 1
            feedback_parts.append("✅ Calculated values within reasonable range")
            subscores['values_reasonable'] = True
        else:
            feedback_parts.append("⚠️ Some calculated values outside expected range")
            subscores['values_reasonable'] = False
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add overall feedback
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent sourdough calculator implementation!")
        elif passed:
            feedback_parts.insert(0, "✅ Sourdough calculator task completed")
        else:
            feedback_parts.insert(0, "❌ Sourdough calculator requirements not fully met")
        
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
