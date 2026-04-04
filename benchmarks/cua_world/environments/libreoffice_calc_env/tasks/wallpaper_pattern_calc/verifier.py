#!/usr/bin/env python3
"""
Verifier for Wallpaper Pattern Calculator task.

Checks:
1. All inputs are present and reasonable
2. Formulas are used (not hardcoded values)
3. Strips per roll calculation is correct
4. Final roll count is mathematically accurate
5. Contingency is properly applied
"""

import sys
import os
import logging
import math

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_numeric_value(cell_value):
    """Extract numeric value from cell, handling various formats."""
    if cell_value is None:
        return None
    if isinstance(cell_value, (int, float)):
        return float(cell_value)
    # Try to parse string
    try:
        return float(str(cell_value).replace(',', '').strip())
    except (ValueError, AttributeError):
        return None


def find_input_values(sheet_data, sheet_name):
    """
    Find input values in the spreadsheet by searching for labels.
    Returns dict with input values.
    """
    inputs = {}
    rows = sheet_data['sheets'][sheet_name]
    
    # Search through rows for input labels
    for row_idx, row in enumerate(rows):
        for col_idx, cell in enumerate(row):
            cell_data = cell if isinstance(cell, dict) else {'value': cell}
            value = cell_data.get('value', '')
            value_str = str(value).lower() if value else ''
            
            # Look for input labels and get value from next column
            if 'height' in value_str and 'inches' in value_str and 'wall' not in value_str:
                next_cell = rows[row_idx][col_idx + 1] if col_idx + 1 < len(row) else None
                if next_cell:
                    next_val = next_cell.get('value') if isinstance(next_cell, dict) else next_cell
                    inputs['wall_height'] = extract_numeric_value(next_val)
            
            elif 'width' in value_str and 'inches' in value_str and 'door' not in value_str and 'roll' not in value_str and 'net' not in value_str:
                next_cell = rows[row_idx][col_idx + 1] if col_idx + 1 < len(row) else None
                if next_cell:
                    next_val = next_cell.get('value') if isinstance(next_cell, dict) else next_cell
                    inputs['wall_width'] = extract_numeric_value(next_val)
            
            elif 'door' in value_str and 'width' in value_str:
                next_cell = rows[row_idx][col_idx + 1] if col_idx + 1 < len(row) else None
                if next_cell:
                    next_val = next_cell.get('value') if isinstance(next_cell, dict) else next_cell
                    inputs['door_width'] = extract_numeric_value(next_val)
            
            elif 'roll' in value_str and 'width' in value_str:
                next_cell = rows[row_idx][col_idx + 1] if col_idx + 1 < len(row) else None
                if next_cell:
                    next_val = next_cell.get('value') if isinstance(next_cell, dict) else next_cell
                    inputs['roll_width'] = extract_numeric_value(next_val)
            
            elif 'roll' in value_str and 'length' in value_str:
                next_cell = rows[row_idx][col_idx + 1] if col_idx + 1 < len(row) else None
                if next_cell:
                    next_val = next_cell.get('value') if isinstance(next_cell, dict) else next_cell
                    inputs['roll_length'] = extract_numeric_value(next_val)
            
            elif 'pattern' in value_str and 'repeat' in value_str:
                next_cell = rows[row_idx][col_idx + 1] if col_idx + 1 < len(row) else None
                if next_cell:
                    next_val = next_cell.get('value') if isinstance(next_cell, dict) else next_cell
                    inputs['pattern_repeat'] = extract_numeric_value(next_val)
    
    return inputs


def find_calculation_results(sheet_data, sheet_name):
    """
    Find calculation results and formulas in the spreadsheet.
    Returns dict with calculation values and formulas.
    """
    results = {}
    rows = sheet_data['sheets'][sheet_name]
    
    for row_idx, row in enumerate(rows):
        for col_idx, cell in enumerate(row):
            cell_data = cell if isinstance(cell, dict) else {'value': cell}
            value = cell_data.get('value', '')
            value_str = str(value).lower() if value else ''
            
            # Look for calculation result labels
            if 'strips per roll' in value_str and 'usable' not in value_str:
                next_cell = rows[row_idx][col_idx + 1] if col_idx + 1 < len(row) else None
                if next_cell:
                    next_data = next_cell if isinstance(next_cell, dict) else {'value': next_cell}
                    results['strips_per_roll_value'] = extract_numeric_value(next_data.get('value'))
                    results['strips_per_roll_formula'] = next_data.get('formula')
            
            elif 'strips needed' in value_str:
                next_cell = rows[row_idx][col_idx + 1] if col_idx + 1 < len(row) else None
                if next_cell:
                    next_data = next_cell if isinstance(next_cell, dict) else {'value': next_cell}
                    results['strips_needed_value'] = extract_numeric_value(next_data.get('value'))
                    results['strips_needed_formula'] = next_data.get('formula')
            
            elif 'final' in value_str and 'rolls' in value_str:
                next_cell = rows[row_idx][col_idx + 1] if col_idx + 1 < len(row) else None
                if next_cell:
                    next_data = next_cell if isinstance(next_cell, dict) else {'value': next_cell}
                    results['final_rolls_value'] = extract_numeric_value(next_data.get('value'))
                    results['final_rolls_formula'] = next_data.get('formula')
            
            elif 'rolls before contingency' in value_str or ('rolls' in value_str and 'before' in value_str):
                next_cell = rows[row_idx][col_idx + 1] if col_idx + 1 < len(row) else None
                if next_cell:
                    next_data = next_cell if isinstance(next_cell, dict) else {'value': next_cell}
                    results['rolls_before_contingency_value'] = extract_numeric_value(next_data.get('value'))
                    results['rolls_before_contingency_formula'] = next_data.get('formula')
    
    return results


def calculate_expected_results(inputs):
    """
    Calculate expected results based on inputs.
    Returns dict with expected values.
    """
    wall_height = inputs.get('wall_height')
    wall_width = inputs.get('wall_width')
    door_width = inputs.get('door_width')
    roll_width = inputs.get('roll_width')
    roll_length = inputs.get('roll_length')
    pattern_repeat = inputs.get('pattern_repeat')
    
    if None in [wall_height, wall_width, door_width, roll_width, roll_length, pattern_repeat]:
        return None
    
    expected = {}
    
    # Pattern repeats per roll
    if pattern_repeat > 0:
        repeats_per_roll = math.floor(roll_length / pattern_repeat)
        usable_length = repeats_per_roll * pattern_repeat
    else:
        usable_length = roll_length
    
    # Strips per roll
    strips_per_roll = math.floor(usable_length / wall_height)
    expected['strips_per_roll'] = strips_per_roll
    
    # Net wall width
    net_wall_width = wall_width - door_width
    
    # Strips needed
    strips_needed = math.ceil(net_wall_width / roll_width)
    expected['strips_needed'] = strips_needed
    
    # Rolls before contingency
    rolls_before_contingency = math.ceil(strips_needed / strips_per_roll)
    expected['rolls_before_contingency'] = rolls_before_contingency
    
    # Final rolls with 10% contingency
    final_rolls = math.ceil(rolls_before_contingency * 1.1)
    expected['final_rolls'] = final_rolls
    
    return expected


def verify_wallpaper_calculator(traj, env_info, task_info):
    """
    Verify wallpaper calculator task completion.
    
    Checks:
    1. All inputs are present
    2. Formulas are used (not hardcoded values)
    3. Strips per roll calculation is correct
    4. Final roll count is accurate (±1 tolerance)
    5. Contingency is applied
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    temp_dir = None
    success = False
    
    for path in ['/home/ga/Documents/wallpaper_calculator.ods',
                 '/home/ga/Documents/wallpaper_calculator_template.csv',
                 '/home/ga/Documents/wallpaper_calculator_template.ods']:
        for fmt in ['ods', 'csv']:
            try:
                success, file_info, error = setup_calc_verification(
                    copy_from_env, path, [fmt]
                )
                if success:
                    temp_dir = file_info.get('temp_dir')
                    break
            except Exception as e:
                logger.debug(f"Failed to load {path} as {fmt}: {e}")
                continue
        if success:
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to load calculator file. Ensure you saved the file."
        }
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_names = list(sheet_data['sheets'].keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Extract inputs and results
        inputs = find_input_values(sheet_data, sheet_name)
        results = find_calculation_results(sheet_data, sheet_name)
        
        logger.info(f"Found inputs: {inputs}")
        logger.info(f"Found results: {results}")
        
        # Criterion 1: All inputs present and reasonable
        required_inputs = ['wall_height', 'wall_width', 'door_width', 'roll_width', 'roll_length', 'pattern_repeat']
        inputs_present = all(inputs.get(key) is not None for key in required_inputs)
        
        if inputs_present:
            # Check reasonableness
            if (84 <= inputs['wall_height'] <= 144 and
                48 <= inputs['wall_width'] <= 300 and
                0 <= inputs['door_width'] <= 72 and
                18 <= inputs['roll_width'] <= 27 and
                300 <= inputs['roll_length'] <= 500 and
                0 <= inputs['pattern_repeat'] <= 36):
                criteria_passed += 1
                feedback_parts.append("✅ All inputs present and reasonable")
            else:
                feedback_parts.append("⚠️ Inputs present but some values seem unreasonable")
                criteria_passed += 0.5
        else:
            missing = [k for k in required_inputs if inputs.get(k) is None]
            feedback_parts.append(f"❌ Missing inputs: {', '.join(missing)}")
        
        # Calculate expected results
        expected = calculate_expected_results(inputs) if inputs_present else None
        
        # Criterion 2: Formulas used (not hardcoded)
        formulas_found = 0
        formula_fields = ['strips_per_roll_formula', 'strips_needed_formula', 'final_rolls_formula']
        for field in formula_fields:
            if results.get(field):
                formulas_found += 1
        
        if formulas_found >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas used ({formulas_found}/3 key calculations)")
        elif formulas_found == 1:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Only {formulas_found} formula found (expected 3+)")
        else:
            feedback_parts.append("❌ No formulas detected (values may be hardcoded)")
        
        # Criterion 3: Strips per roll correct
        if expected and results.get('strips_per_roll_value') is not None:
            actual = results['strips_per_roll_value']
            expected_val = expected['strips_per_roll']
            if abs(actual - expected_val) < 0.01:
                criteria_passed += 1
                feedback_parts.append(f"✅ Strips per roll correct: {int(actual)}")
            else:
                feedback_parts.append(f"❌ Strips per roll incorrect: expected {expected_val}, got {actual}")
        else:
            feedback_parts.append("❌ Strips per roll not calculated")
        
        # Criterion 4: Final roll count accurate
        if expected and results.get('final_rolls_value') is not None:
            actual = results['final_rolls_value']
            expected_val = expected['final_rolls']
            # Allow ±1 tolerance for different valid approaches
            if abs(actual - expected_val) <= 1:
                criteria_passed += 1
                feedback_parts.append(f"✅ Final roll count accurate: {int(actual)} (expected {expected_val})")
            else:
                feedback_parts.append(f"❌ Final roll count incorrect: expected {expected_val}, got {actual}")
        else:
            feedback_parts.append("❌ Final roll count not calculated")
        
        # Criterion 5: Contingency applied
        if expected and results.get('rolls_before_contingency_value') and results.get('final_rolls_value'):
            before = results['rolls_before_contingency_value']
            after = results['final_rolls_value']
            # Check if final is roughly 10% more than before (within rounding)
            if after >= before and after <= before * 1.15:
                criteria_passed += 1
                feedback_parts.append(f"✅ Contingency applied: {int(before)} → {int(after)} rolls")
            else:
                feedback_parts.append(f"⚠️ Contingency may not be applied correctly")
                criteria_passed += 0.3
        elif results.get('final_rolls_formula'):
            # Check if formula contains 1.1 or similar
            formula_str = str(results['final_rolls_formula']).upper()
            if '1.1' in formula_str or '110' in formula_str:
                criteria_passed += 0.5
                feedback_parts.append("⚠️ Contingency in formula but couldn't verify calculation")
            else:
                feedback_parts.append("❌ No 10% contingency detected")
        else:
            feedback_parts.append("❌ Contingency calculation missing")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (3.5/5 criteria)
        
        # Add summary
        if passed:
            if score >= 90:
                feedback_parts.append("🎉 Excellent calculator implementation!")
            else:
                feedback_parts.append("✅ Calculator task completed")
        else:
            feedback_parts.append("❌ Calculator incomplete or has significant errors")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "inputs_present": inputs_present,
                "formulas_used": formulas_found >= 2,
                "strips_per_roll_correct": (
                    expected and results.get('strips_per_roll_value') is not None and
                    abs(results['strips_per_roll_value'] - expected['strips_per_roll']) < 0.01
                ) if expected else False,
                "final_rolls_accurate": (
                    expected and results.get('final_rolls_value') is not None and
                    abs(results['final_rolls_value'] - expected['final_rolls']) <= 1
                ) if expected else False
            }
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
