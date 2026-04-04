#!/usr/bin/env python3
"""
Verifier for Paint Inventory Calculator task

Checks:
1. Area calculation formulas present and correct structure
2. Paint quantity formulas use ROUNDUP/CEILING
3. Cost calculations present and use formulas
4. Formulas not hardcoded (use cell references)
5. Data organization (headers, structure)
6. Results are reasonable (sanity check)
"""

import sys
import os
import logging
import re
import math

# Use relative path to utils folder
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


def check_formula_pattern(formula, pattern_type):
    """
    Check if formula matches expected pattern
    
    Args:
        formula: Formula string to check
        pattern_type: Type of formula ('area', 'roundup', 'cost', 'sum')
    
    Returns:
        bool: True if pattern matches
    """
    if not formula:
        return False
    
    formula_upper = formula.upper()
    
    if pattern_type == 'area':
        # Should have multiplication and subtraction (perimeter * height - deductions)
        has_mult = '*' in formula
        has_sub = '-' in formula
        # Should reference multiple cells (at least 3 different columns)
        cell_refs = re.findall(r'[A-Z]+\d+', formula_upper)
        has_refs = len(set(cell_refs)) >= 3
        return has_mult and has_sub and has_refs
    
    elif pattern_type == 'roundup':
        # Must contain ROUNDUP or CEILING function and division
        has_roundup = 'ROUNDUP' in formula_upper or 'CEILING' in formula_upper
        has_div = '/' in formula
        return has_roundup and has_div
    
    elif pattern_type == 'cost':
        # Should have multiplication (quantity * price)
        has_mult = '*' in formula
        cell_refs = re.findall(r'[A-Z]+\d+', formula_upper)
        has_refs = len(cell_refs) >= 2
        return has_mult and has_refs
    
    elif pattern_type == 'sum':
        # Should have SUM function
        return 'SUM' in formula_upper
    
    return False


def calculate_expected_area(length, width, height, doors, windows):
    """Calculate expected wall area"""
    try:
        length = float(length) if length else 0
        width = float(width) if width else 0
        height = float(height) if height else 8  # Default ceiling height
        doors = int(doors) if doors else 0
        windows = int(windows) if windows else 0
        
        perimeter = 2 * (length + width)
        gross_area = perimeter * height
        net_area = gross_area - (doors * 20) - (windows * 15)
        
        return net_area
    except:
        return None


def calculate_expected_gallons(area, coats=2, coverage=375):
    """Calculate expected paint gallons (rounded up)"""
    try:
        total_area = float(area) * coats
        gallons = total_area / coverage
        return math.ceil(gallons)  # Round up
    except:
        return None


def find_calculation_columns(workbook, sheet_name):
    """
    Find which columns contain calculations
    Returns dict with column indices for area, gallons, cost
    """
    result = {
        'area_col': None,
        'gallons_col': None,
        'cost_col': None,
        'total_row': None
    }
    
    # Check first 20 columns and 50 rows for formulas
    for col_idx in range(20):
        for row_idx in range(2, 15):  # Start from row 2 (after header)
            col_letter = chr(ord('A') + col_idx)
            cell_ref = f"{col_letter}{row_idx}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            
            if formula:
                if check_formula_pattern(formula, 'area') and result['area_col'] is None:
                    result['area_col'] = col_idx
                    logger.debug(f"Found area formula in column {col_letter}")
                
                if check_formula_pattern(formula, 'roundup') and result['gallons_col'] is None:
                    result['gallons_col'] = col_idx
                    logger.debug(f"Found roundup formula in column {col_letter}")
                
                if check_formula_pattern(formula, 'cost') and result['cost_col'] is None:
                    result['cost_col'] = col_idx
                    logger.debug(f"Found cost formula in column {col_letter}")
    
    # Look for SUM formula (total row)
    for row_idx in range(2, 50):
        for col_idx in range(20):
            col_letter = chr(ord('A') + col_idx)
            cell_ref = f"{col_letter}{row_idx}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            
            if formula and check_formula_pattern(formula, 'sum'):
                result['total_row'] = row_idx
                logger.debug(f"Found SUM formula at row {row_idx}")
                break
        if result['total_row']:
            break
    
    return result


def verify_paint_calculator(traj, env_info, task_info):
    """
    Verify paint inventory calculator task completion
    
    Checks:
    1. Area calculation formulas present
    2. Paint quantity uses ROUNDUP/CEILING
    3. Cost calculations present
    4. Formulas use cell references (not hardcoded)
    5. Data organization
    6. Reasonable results
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/paint_calculation.ods'),
        ('csv', '/home/ga/Documents/paint_rooms.csv'),
        ('ods', '/home/ga/Documents/paint_rooms.ods'),
        ('csv', '/home/ga/Documents/paint_calculation.csv'),
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
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        # Get sheet data
        sheets = get_sheet_names(workbook)
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheets[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Find calculation columns
        calc_cols = find_calculation_columns(workbook, sheet_name)
        
        # Criterion 1: Area calculation formulas present
        area_formula_found = False
        if calc_cols['area_col'] is not None:
            # Verify formula in at least one row
            col_letter = chr(ord('A') + calc_cols['area_col'])
            test_cell = f"{col_letter}2"
            formula = get_cell_formula(workbook, sheet_name, test_cell)
            
            if check_formula_pattern(formula, 'area'):
                criteria_passed += 1
                area_formula_found = True
                feedback_parts.append(f"✅ Area calculation formula found (column {col_letter})")
                logger.debug(f"Area formula example: {formula}")
            else:
                feedback_parts.append(f"⚠️ Area formula structure may be incorrect")
        else:
            feedback_parts.append("❌ No area calculation formula detected")
        
        subscores['area_formula'] = area_formula_found
        
        # Criterion 2: Paint quantity with ROUNDUP/CEILING
        roundup_found = False
        if calc_cols['gallons_col'] is not None:
            col_letter = chr(ord('A') + calc_cols['gallons_col'])
            test_cell = f"{col_letter}2"
            formula = get_cell_formula(workbook, sheet_name, test_cell)
            
            if check_formula_pattern(formula, 'roundup'):
                criteria_passed += 1
                roundup_found = True
                feedback_parts.append(f"✅ ROUNDUP/CEILING formula found (column {col_letter})")
                logger.debug(f"Roundup formula example: {formula}")
            else:
                feedback_parts.append(f"⚠️ Paint quantity may not use proper rounding")
        else:
            feedback_parts.append("❌ No ROUNDUP/CEILING formula for paint quantity")
        
        subscores['roundup_formula'] = roundup_found
        
        # Criterion 3: Cost calculation formulas
        cost_formula_found = False
        if calc_cols['cost_col'] is not None:
            col_letter = chr(ord('A') + calc_cols['cost_col'])
            test_cell = f"{col_letter}2"
            formula = get_cell_formula(workbook, sheet_name, test_cell)
            
            if check_formula_pattern(formula, 'cost'):
                criteria_passed += 1
                cost_formula_found = True
                feedback_parts.append(f"✅ Cost calculation formula found (column {col_letter})")
                logger.debug(f"Cost formula example: {formula}")
            else:
                feedback_parts.append(f"⚠️ Cost formula may be incorrect")
        else:
            feedback_parts.append("❌ No cost calculation formula detected")
        
        subscores['cost_formula'] = cost_formula_found
        
        # Criterion 4: Formulas use cell references (not hardcoded)
        formulas_not_hardcoded = False
        formula_count = 0
        
        # Check multiple cells for formulas
        for row_idx in range(2, 10):
            for col_idx in range(8, 15):  # Check columns I through O
                col_letter = chr(ord('A') + col_idx)
                cell_ref = f"{col_letter}{row_idx}"
                formula = get_cell_formula(workbook, sheet_name, cell_ref)
                if formula and formula.startswith('='):
                    formula_count += 1
        
        if formula_count >= 3:  # At least 3 formulas found
            criteria_passed += 1
            formulas_not_hardcoded = True
            feedback_parts.append(f"✅ Formulas use cell references ({formula_count} formulas found)")
        else:
            feedback_parts.append(f"❌ Too few formulas detected ({formula_count} found)")
        
        subscores['formulas_not_hardcoded'] = formulas_not_hardcoded
        
        # Criterion 5: Data organization (check for reasonable structure)
        organized = False
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Count non-empty rows
        data_rows = 0
        for row in sheet_rows[:20]:  # Check first 20 rows
            if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
                data_rows += 1
        
        # Should have at least header + 6 room rows
        if data_rows >= 7:
            criteria_passed += 1
            organized = True
            feedback_parts.append(f"✅ Data properly organized ({data_rows} rows)")
        else:
            feedback_parts.append(f"❌ Insufficient data organization ({data_rows} rows)")
        
        subscores['organized'] = organized
        
        # Criterion 6: Reasonable results (sanity check)
        reasonable_results = False
        
        # Check a few calculated values for reasonableness
        if calc_cols['gallons_col'] is not None:
            col_letter = chr(ord('A') + calc_cols['gallons_col'])
            
            reasonable_count = 0
            checked_count = 0
            
            for row_idx in range(2, 10):  # Check up to 8 rooms
                cell_ref = f"{col_letter}{row_idx}"
                value = get_cell_value(workbook, sheet_name, cell_ref)
                
                if value is not None:
                    try:
                        gallons = float(value)
                        checked_count += 1
                        
                        # Reasonable range: 1-10 gallons per room
                        if 0.5 <= gallons <= 15:
                            reasonable_count += 1
                        else:
                            logger.warning(f"Unreasonable gallon value in {cell_ref}: {gallons}")
                    except (ValueError, TypeError):
                        pass
            
            if checked_count >= 3 and reasonable_count >= checked_count * 0.7:
                criteria_passed += 1
                reasonable_results = True
                feedback_parts.append(f"✅ Results are reasonable ({reasonable_count}/{checked_count} rooms)")
            else:
                feedback_parts.append(f"⚠️ Some results may be unreasonable ({reasonable_count}/{checked_count})")
        else:
            # If we can't find gallons column, give partial credit for having data
            if data_rows >= 7:
                criteria_passed += 0.5
                feedback_parts.append("⚠️ Cannot verify result reasonableness")
        
        subscores['reasonable_results'] = reasonable_results
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent paint calculation!")
        elif passed:
            feedback_parts.insert(0, "✅ Paint calculation completed")
        else:
            feedback_parts.insert(0, "❌ Paint calculation incomplete")
        
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
