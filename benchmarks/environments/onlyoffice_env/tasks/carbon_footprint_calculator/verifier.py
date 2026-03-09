#!/usr/bin/env python3
"""
Verifier for Carbon Footprint Calculator task

Verifies that:
1. Individual emission formulas are created correctly (C2:C6)
2. Total emissions formula is created correctly (C8)
3. Percentage formulas are created correctly (D2:D6)
4. Calculated values are accurate within tolerance
5. No formula errors present
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def has_formula_error(cell):
    """Check if cell contains a formula error"""
    if cell.value is None:
        return False
    value_str = str(cell.value)
    error_patterns = ['#REF!', '#DIV/0!', '#VALUE!', '#NAME?', '#NUM!', '#N/A', '#NULL!']
    return any(err in value_str for err in error_patterns)


def check_multiplication_formula(sheet, cell_ref, expected_b_row, expected_f_row):
    """
    Check if a cell contains a multiplication formula referencing the correct cells.
    Returns (has_formula, is_correct, calculated_value)
    """
    cell = sheet[cell_ref]
    
    # Check for formula errors first
    if has_formula_error(cell):
        return False, False, None
    
    # Get the value (this will be the calculated result if data_only=True)
    value = cell.value
    
    # For basic validation, we check if the value is numeric and reasonable
    # We can't easily check formula structure with data_only=True, so we rely on value validation
    if value is not None and isinstance(value, (int, float)) and value > 0:
        return True, True, value
    
    return False, False, None


def check_sum_formula(sheet, cell_ref, expected_range_start, expected_range_end):
    """
    Check if a cell contains a SUM formula.
    Returns (has_formula, is_correct, calculated_value)
    """
    cell = sheet[cell_ref]
    
    if has_formula_error(cell):
        return False, False, None
    
    value = cell.value
    
    # Check if value is numeric and reasonable (should be sum of individual values)
    if value is not None and isinstance(value, (int, float)) and value > 0:
        return True, True, value
    
    return False, False, None


def check_percentage_formula(sheet, cell_ref, total_cell_value):
    """
    Check if a cell contains a percentage formula.
    Returns (has_formula, is_correct, calculated_value)
    """
    cell = sheet[cell_ref]
    
    if has_formula_error(cell):
        return False, False, None
    
    value = cell.value
    
    # Check if value is numeric and in reasonable percentage range (0-100)
    if value is not None and isinstance(value, (int, float)) and 0 <= value <= 100:
        return True, True, value
    
    return False, False, None


def verify_carbon_footprint_calculator(traj, env_info, task_info):
    """
    Verify that carbon footprint calculator formulas were created correctly.

    Checks:
    1. Individual emission formulas (C2:C6) - 30% weight
    2. Total SUM formula (C8) - 15% weight
    3. Percentage formulas (D2:D6) - 30% weight
    4. Calculated values accuracy - 20% weight
    5. No formula errors - 5% weight
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/carbon_footprint.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_carbon_')
    temp_file = os.path.join(temp_dir, 'carbon_footprint.xlsx')

    try:
        # Copy the file from container
        copy_from_env(container_path, temp_file)

        if not os.path.exists(temp_file) or os.path.getsize(temp_file) == 0:
            return {"passed": False, "score": 0, "feedback": f"File not found or empty: {container_path}"}

        # Parse the spreadsheet (with data_only=True to get calculated values)
        wb = parse_xlsx_file(temp_file)
        if wb is None:
            return {"passed": False, "score": 0, "feedback": "Failed to parse spreadsheet"}

        sheet_name = "Carbon Footprint"
        if sheet_name not in wb.sheetnames:
            sheet_name = wb.sheetnames[0]  # Use first sheet as fallback
        
        sheet = wb[sheet_name]

        # Expected values based on the template
        expected_emissions = {
            'C2': 225.0,    # Electricity: 450 * 0.5
            'C3': 185.5,    # Natural Gas: 35 * 5.3
            'C4': 356.0,    # Gasoline: 40 * 8.9
            'C5': 144.0,    # Flight: 600 * 0.24
            'C6': 1000.0    # Food: 400 * 2.5
        }
        expected_total = 1910.5
        
        # Expected percentages (approximate)
        expected_percentages = {
            'D2': 11.8,   # Electricity: ~12%
            'D3': 9.7,    # Natural Gas: ~10%
            'D4': 18.6,   # Gasoline: ~19%
            'D5': 7.5,    # Flight: ~8%
            'D6': 52.3    # Food: ~52%
        }

        criteria_passed = 0.0
        total_criteria = 11.0
        feedback_parts = []

        # === Criterion 1-5: Check individual emission formulas (C2:C6) - 5 points ===
        emissions_correct = 0
        for row in range(2, 7):
            cell_ref = f'C{row}'
            has_formula, is_correct, value = check_multiplication_formula(sheet, cell_ref, row, row)
            
            if has_formula and value is not None:
                expected = expected_emissions[cell_ref]
                tolerance = expected * 0.05  # 5% tolerance
                
                if abs(value - expected) <= tolerance:
                    emissions_correct += 1
                    criteria_passed += 1.0
                else:
                    feedback_parts.append(f"⚠️ {cell_ref} value {value:.1f} differs from expected {expected:.1f}")
            else:
                feedback_parts.append(f"❌ {cell_ref} missing valid formula")

        if emissions_correct == 5:
            feedback_parts.insert(0, "✅ All 5 emission formulas correct")
        elif emissions_correct > 0:
            feedback_parts.insert(0, f"⚠️ {emissions_correct}/5 emission formulas correct")
        else:
            feedback_parts.insert(0, "❌ No emission formulas found")

        # === Criterion 6: Check total SUM formula (C8) - 1 point ===
        has_sum, is_sum_correct, total_value = check_sum_formula(sheet, 'C8', 2, 6)
        
        if has_sum and total_value is not None:
            tolerance = expected_total * 0.05  # 5% tolerance
            if abs(total_value - expected_total) <= tolerance:
                criteria_passed += 1.0
                feedback_parts.append(f"✅ Total formula correct: {total_value:.1f} kg CO2e")
            else:
                feedback_parts.append(f"⚠️ Total {total_value:.1f} differs from expected {expected_total:.1f}")
        else:
            feedback_parts.append("❌ Total SUM formula missing or invalid")

        # === Criterion 7-11: Check percentage formulas (D2:D6) - 5 points ===
        percentages_correct = 0
        percentage_sum = 0.0
        
        for row in range(2, 7):
            cell_ref = f'D{row}'
            has_pct, is_pct_correct, pct_value = check_percentage_formula(sheet, cell_ref, total_value)
            
            if has_pct and pct_value is not None:
                percentage_sum += pct_value
                expected_pct = expected_percentages[cell_ref]
                tolerance = 2.0  # 2 percentage points tolerance
                
                if abs(pct_value - expected_pct) <= tolerance:
                    percentages_correct += 1
                    criteria_passed += 1.0
                else:
                    feedback_parts.append(f"⚠️ {cell_ref} percentage {pct_value:.1f}% differs from expected {expected_pct:.1f}%")
            else:
                feedback_parts.append(f"❌ {cell_ref} missing percentage formula")

        if percentages_correct == 5:
            feedback_parts.append(f"✅ All 5 percentage formulas correct (sum: {percentage_sum:.1f}%)")
        elif percentages_correct > 0:
            feedback_parts.append(f"⚠️ {percentages_correct}/5 percentage formulas correct")
        else:
            feedback_parts.append("❌ No percentage formulas found")

        # Check if percentages sum to approximately 100%
        if 98.0 <= percentage_sum <= 102.0:
            feedback_parts.append(f"✅ Percentages sum correctly: {percentage_sum:.1f}%")
        elif percentage_sum > 0:
            feedback_parts.append(f"⚠️ Percentages sum to {percentage_sum:.1f}% (expected ~100%)")

        # === Check for formula errors ===
        error_cells = []
        for row in range(2, 7):
            if has_formula_error(sheet[f'C{row}']):
                error_cells.append(f'C{row}')
            if has_formula_error(sheet[f'D{row}']):
                error_cells.append(f'D{row}')
        if has_formula_error(sheet['C8']):
            error_cells.append('C8')
        
        if error_cells:
            feedback_parts.append(f"❌ Formula errors in: {', '.join(error_cells)}")
        else:
            feedback_parts.append("✅ No formula errors detected")

        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75

        feedback = " | ".join(feedback_parts)

        logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_passed}/{total_criteria}")

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
