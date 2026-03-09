#!/usr/bin/env python3
"""
Verifier for Clothing Swap Credit Manager task
Checks data entry, formulas, conditional formatting, sorting, and summary statistics
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    verify_cell_value,
    check_conditional_formatting,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_participant_row(workbook, sheet_name, participant_name):
    """Find the row number for a given participant name"""
    try:
        sheets = workbook.get('sheets', {})
        if sheet_name not in sheets:
            return None
        
        rows = sheets[sheet_name]
        for i, row in enumerate(rows):
            if i == 0:  # Skip header
                continue
            if len(row) > 0:
                cell_data = row[0]
                value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                if value and participant_name.lower() in str(value).lower():
                    return i + 1  # 1-indexed for cell references
        return None
    except Exception as e:
        logger.error(f"Error finding participant row: {e}")
        return None


def verify_clothing_swap_credits(traj, env_info, task_info):
    """
    Verify clothing swap credit tracking task completion.
    
    Checks:
    1. Check-in data entered: Sarah Martinez (6), James Chen (3), Priya Patel (8)
    2. Credits formula present and correct (Column E)
    3. Conditional formatting applied to Column E
    4. Data sorted by credits (ascending)
    5. Summary statistics present with formulas
    6. Calculations accurate
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/clothing_swap_credits.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        # Get first sheet
        sheet_names = get_sheet_names(workbook)
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []

        # Get sheet data for analysis
        sheets = workbook.get('sheets', {})
        sheet_data = sheets.get(sheet_name, [])

        # Find participant rows (they should be in rows 2, 3, 4 but let's be flexible)
        sarah_row = find_participant_row(workbook, sheet_name, "Sarah Martinez")
        james_row = find_participant_row(workbook, sheet_name, "James Chen")
        priya_row = find_participant_row(workbook, sheet_name, "Priya Patel")

        if not all([sarah_row, james_row, priya_row]):
            feedback_parts.append("⚠️ Warning: Could not locate all participants")
            sarah_row = sarah_row or 2
            james_row = james_row or 3
            priya_row = priya_row or 4

        # Criterion 1: Check-in data entered correctly
        sarah_value = get_cell_value(workbook, sheet_name, f"C{sarah_row}")
        james_value = get_cell_value(workbook, sheet_name, f"C{james_row}")
        priya_value = get_cell_value(workbook, sheet_name, f"C{priya_row}")

        checkin_correct = False
        if sarah_value == 6 and james_value == 3 and priya_value == 8:
            criteria_passed += 1
            checkin_correct = True
            feedback_parts.append("✅ Check-in data entered correctly (Sarah: 6, James: 3, Priya: 8)")
        else:
            feedback_parts.append(f"❌ Check-in data incorrect (Sarah: {sarah_value}, James: {james_value}, Priya: {priya_value})")

        # Criterion 2: Credits formula present and correct
        # Check multiple rows for formula presence
        formula_found = False
        formula_correct = False
        sample_row = 2
        
        for row_num in range(2, min(10, len(sheet_data) + 1)):  # Check first several rows
            formula = get_cell_formula(workbook, sheet_name, f"E{row_num}")
            if formula:
                formula_found = True
                formula_upper = formula.upper()
                # Check if formula has basic structure: subtraction of columns C and D
                # Could be =C2-D2 or =IF(ISBLANK(C2),...) or similar
                if ('C' in formula_upper and 'D' in formula_upper) or 'IF' in formula_upper or 'ISBLANK' in formula_upper:
                    formula_correct = True
                    sample_row = row_num
                    break

        if formula_correct:
            criteria_passed += 1
            formula_sample = get_cell_formula(workbook, sheet_name, f"E{sample_row}")
            feedback_parts.append(f"✅ Credits formula found (e.g., row {sample_row}: {formula_sample})")
        elif formula_found:
            feedback_parts.append(f"⚠️ Formula found but may not be correct")
        else:
            feedback_parts.append("❌ Credits formula missing in Column E")

        # Criterion 3: Conditional formatting applied
        # Check Column E for conditional formatting
        has_conditional_formatting = check_conditional_formatting(workbook, sheet_name, "E2:E20")
        
        if has_conditional_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting applied to Column E")
        else:
            # Conditional formatting detection can be unreliable, give partial credit if formulas exist
            if formula_correct:
                criteria_passed += 0.5
                feedback_parts.append("⚠️ Conditional formatting not detected (but formulas present)")
            else:
                feedback_parts.append("❌ Conditional formatting not detected")

        # Criterion 4: Data sorted by credits (check if values are in ascending order)
        credits_values = []
        for row_num in range(2, min(20, len(sheet_data) + 1)):
            val = get_cell_value(workbook, sheet_name, f"E{row_num}")
            if val and isinstance(val, (int, float)):
                credits_values.append(val)
            if len(credits_values) >= 5:  # Check first 5 numeric values
                break

        is_sorted = False
        if len(credits_values) >= 3:
            # Check if values are in ascending order (lowest first)
            sorted_values = sorted(credits_values)
            if credits_values == sorted_values:
                is_sorted = True
                criteria_passed += 1
                feedback_parts.append(f"✅ Data sorted by credits (ascending: {credits_values[:3]}...)")
            else:
                feedback_parts.append(f"❌ Data not sorted properly (found: {credits_values[:3]}, expected: {sorted_values[:3]})")
        else:
            feedback_parts.append("⚠️ Could not verify sorting (insufficient numeric values)")

        # Criterion 5: Summary statistics present
        # Look for summary formulas starting around row 22
        summary_formulas_found = 0
        summary_row_start = None
        
        # Search for summary section (look for "Total" or similar keywords)
        for row_num in range(20, min(30, len(sheet_data) + 1)):
            cell_val = get_cell_value(workbook, sheet_name, f"A{row_num}")
            if cell_val and 'total' in str(cell_val).lower():
                summary_row_start = row_num
                break
        
        if summary_row_start:
            # Check for formulas in the next 4 rows
            for offset in range(4):
                row_num = summary_row_start + offset
                formula = get_cell_formula(workbook, sheet_name, f"B{row_num}")
                if formula:
                    formula_upper = formula.upper()
                    if 'SUM' in formula_upper or 'COUNTIF' in formula_upper or any(op in formula_upper for op in ['+', '-', '*', '/']):
                        summary_formulas_found += 1

        if summary_formulas_found >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Summary statistics present ({summary_formulas_found} formulas found)")
        elif summary_formulas_found > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some summary formulas found ({summary_formulas_found}/4)")
        else:
            feedback_parts.append("❌ Summary statistics missing or incomplete")

        # Criterion 6: Spot-check calculation accuracy
        # Check one participant who checked in to verify formula calculation
        calc_correct = False
        
        # Find a participant with complete data (not Sarah/James/Priya since they were empty initially)
        for row_num in range(5, min(15, len(sheet_data) + 1)):
            actual_brought = get_cell_value(workbook, sheet_name, f"C{row_num}")
            items_taken = get_cell_value(workbook, sheet_name, f"D{row_num}")
            credits_shown = get_cell_value(workbook, sheet_name, f"E{row_num}")
            
            if isinstance(actual_brought, (int, float)) and isinstance(items_taken, (int, float)):
                expected_credits = actual_brought - items_taken
                if isinstance(credits_shown, (int, float)):
                    if abs(credits_shown - expected_credits) < 0.01:
                        calc_correct = True
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Calculations verified accurate (row {row_num}: {actual_brought}-{items_taken}={credits_shown})")
                        break
                    else:
                        feedback_parts.append(f"❌ Calculation error in row {row_num} (expected {expected_credits}, got {credits_shown})")
                        break
        
        if not calc_correct and criteria_passed > 0:
            # If other criteria passed but we couldn't verify calc, give benefit of doubt
            feedback_parts.append("⚠️ Could not verify calculation accuracy")

        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold = 4.2/6 criteria
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "checkin_data": checkin_correct,
                "credits_formula": formula_correct,
                "conditional_formatting": has_conditional_formatting,
                "data_sorted": is_sorted,
                "summary_statistics": summary_formulas_found >= 3,
                "calculations_accurate": calc_correct
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
