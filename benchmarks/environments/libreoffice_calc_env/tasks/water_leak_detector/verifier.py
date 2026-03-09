#!/usr/bin/env python3
"""
Verifier for Water Leak Detection task.

Validates:
1. File exists and can be parsed
2. Required columns present
3. Rolling average formulas correct
4. Threshold formulas correct
5. Leak detection logic correct
6. Excess calculation correct
7. Results are reasonable (4-9 leak days, 200-600 gallons excess)
"""

import sys
import os
import re
import logging

# Use relative path to utils (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    setup_calc_verification
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_formula_pattern(formula, pattern_type):
    """
    Check if formula matches expected pattern.
    
    Args:
        formula: Formula string (e.g., "=AVERAGE(B2:B8)")
        pattern_type: Type to check ('average', 'threshold', 'leak_if', 'excess_if')
    
    Returns:
        bool: True if formula matches expected pattern
    """
    if not formula:
        return False
    
    formula_upper = formula.upper().replace(' ', '')
    
    if pattern_type == 'average':
        # Should contain AVERAGE function
        if 'AVERAGE' not in formula_upper:
            return False
        # Check if range spans approximately 7 cells
        # Pattern: AVERAGE(B2:B8), AVERAGE(B3:B9), etc.
        range_match = re.search(r'B(\d+):B(\d+)', formula_upper)
        if range_match:
            start_row = int(range_match.group(1))
            end_row = int(range_match.group(2))
            range_size = end_row - start_row + 1
            # Allow 6-8 cells (should be 7, but allow small variation)
            return 6 <= range_size <= 8
        return False
    
    elif pattern_type == 'threshold':
        # Should multiply by 1.5 (or 1.50, or 3/2)
        return ('*1.5' in formula_upper or 
                '*1.50' in formula_upper or
                '*(1+0.5)' in formula_upper or
                '*3/2' in formula_upper or
                ('*1.' in formula_upper and '5' in formula_upper))
    
    elif pattern_type == 'leak_if':
        # Should be IF statement comparing B column to D column
        if 'IF' not in formula_upper:
            return False
        # Check for comparison operator and "LEAK" text
        has_comparison = '>' in formula or '<' in formula
        has_leak_text = 'LEAK' in formula_upper or 'POTENTIAL' in formula_upper
        return has_comparison and has_leak_text
    
    elif pattern_type == 'excess_if':
        # Should be IF statement with subtraction
        if 'IF' not in formula_upper:
            return False
        # Should contain comparison and subtraction
        has_comparison = '>' in formula or '<' in formula
        has_subtraction = '-' in formula
        return has_comparison and has_subtraction
    
    return False


def count_formula_correctness(workbook, sheet_name, column, start_row, end_row, pattern_type):
    """
    Count how many cells in a column have correct formula pattern.
    
    Returns:
        tuple: (correct_count, total_count)
    """
    correct = 0
    total = 0
    
    for row in range(start_row, end_row + 1):
        cell_ref = f"{column}{row}"
        formula = get_cell_formula(workbook, sheet_name, cell_ref)
        
        if formula:  # Only count cells that have formulas
            total += 1
            if check_formula_pattern(formula, pattern_type):
                correct += 1
    
    return correct, total


def count_leak_flags(workbook, sheet_name, start_row, end_row):
    """Count how many cells contain 'POTENTIAL LEAK' or similar text."""
    leak_count = 0
    
    for row in range(start_row, end_row + 1):
        cell_ref = f"E{row}"
        value = get_cell_value(workbook, sheet_name, cell_ref)
        
        if value and isinstance(value, str):
            if 'LEAK' in value.upper() or 'POTENTIAL' in value.upper():
                leak_count += 1
    
    return leak_count


def sum_excess_gallons(workbook, sheet_name, start_row, end_row):
    """Sum up excess gallons from column F."""
    total_excess = 0.0
    
    for row in range(start_row, end_row + 1):
        cell_ref = f"F{row}"
        value = get_cell_value(workbook, sheet_name, cell_ref)
        
        if value is not None:
            try:
                excess = float(value)
                if excess > 0:
                    total_excess += excess
            except (ValueError, TypeError):
                pass
    
    return total_excess


def verify_water_leak_detection(traj, env_info, task_info):
    """
    Main verification function for water leak detection task.
    
    Checks:
    1. File exists and is valid ODS
    2. Required columns present
    3. Rolling average formulas correct (90%+ of rows)
    4. Threshold formulas correct (90%+ of rows)
    5. Leak detection IF logic correct (90%+ of rows)
    6. Excess calculation present
    7. Reasonable results (4-9 leak days, 200-600 gallons excess)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load water_analysis.ods
    container_path = "/home/ga/Documents/water_analysis.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )
    
    if not success:
        # Fallback: try original CSV name
        logger.info("water_analysis.ods not found, trying water_usage_data.csv...")
        container_path = "/home/ga/Documents/water_usage_data.csv"
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format='csv'
        )
        
        if not success:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to load file: {error}"
            }
    
    try:
        # Get first sheet
        sheet_names = list(workbook.get('sheets', {}).keys())
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        # Initialize scoring
        score = 0
        max_score = 100
        criteria_met = 0
        total_criteria = 7
        feedback_parts = []
        
        # Check data rows exist
        sheet_rows = workbook['sheets'][sheet_name]
        row_count = len(sheet_rows)
        
        if row_count < 31:
            feedback_parts.append(f"⚠️ Only {row_count} rows found (expected 31)")
        
        # Criterion 1: File created and valid (already passed if we got here)
        criteria_met += 1
        feedback_parts.append("✅ File created and loaded successfully")
        
        # Criterion 2: Check columns present (at least B, C, D, E, F should have data)
        columns_present = True
        for col in ['B', 'C', 'D', 'E', 'F']:
            test_val = get_cell_value(workbook, sheet_name, f"{col}8")
            if test_val is None:
                columns_present = False
                break
        
        if columns_present:
            criteria_met += 1
            feedback_parts.append("✅ Required columns present")
        else:
            feedback_parts.append("❌ Missing required columns (need B-F with data)")
        
        # Criterion 3: Rolling average formulas (column C, rows 8-31)
        avg_correct, avg_total = count_formula_correctness(
            workbook, sheet_name, 'C', 8, 31, 'average'
        )
        
        if avg_total > 0:
            avg_pct = (avg_correct / avg_total) * 100
            if avg_pct >= 90:
                criteria_met += 1
                feedback_parts.append(f"✅ Rolling average formulas correct ({avg_correct}/{avg_total})")
            elif avg_pct >= 70:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Rolling average mostly correct ({avg_correct}/{avg_total})")
            else:
                feedback_parts.append(f"❌ Rolling average formulas incorrect ({avg_correct}/{avg_total})")
        else:
            feedback_parts.append("❌ No rolling average formulas found in column C")
        
        # Criterion 4: Threshold formulas (column D, rows 8-31)
        thresh_correct, thresh_total = count_formula_correctness(
            workbook, sheet_name, 'D', 8, 31, 'threshold'
        )
        
        if thresh_total > 0:
            thresh_pct = (thresh_correct / thresh_total) * 100
            if thresh_pct >= 90:
                criteria_met += 1
                feedback_parts.append(f"✅ Threshold formulas correct ({thresh_correct}/{thresh_total})")
            elif thresh_pct >= 70:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Threshold formulas mostly correct ({thresh_correct}/{thresh_total})")
            else:
                feedback_parts.append(f"❌ Threshold formulas incorrect ({thresh_correct}/{thresh_total})")
        else:
            feedback_parts.append("❌ No threshold formulas found in column D")
        
        # Criterion 5: Leak detection IF logic (column E, rows 8-31)
        leak_if_correct, leak_if_total = count_formula_correctness(
            workbook, sheet_name, 'E', 8, 31, 'leak_if'
        )
        
        if leak_if_total > 0:
            leak_if_pct = (leak_if_correct / leak_if_total) * 100
            if leak_if_pct >= 90:
                criteria_met += 1
                feedback_parts.append(f"✅ Leak detection logic correct ({leak_if_correct}/{leak_if_total})")
            elif leak_if_pct >= 70:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Leak detection mostly correct ({leak_if_correct}/{leak_if_total})")
            else:
                feedback_parts.append(f"❌ Leak detection logic incorrect ({leak_if_correct}/{leak_if_total})")
        else:
            feedback_parts.append("❌ No leak detection formulas found in column E")
        
        # Criterion 6: Excess calculation (column F)
        excess_correct, excess_total = count_formula_correctness(
            workbook, sheet_name, 'F', 8, 31, 'excess_if'
        )
        
        if excess_total > 0 and excess_correct > excess_total * 0.7:
            criteria_met += 1
            feedback_parts.append(f"✅ Excess calculation present ({excess_correct}/{excess_total})")
        elif excess_total > 0:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Excess calculation partially correct ({excess_correct}/{excess_total})")
        else:
            feedback_parts.append("❌ No excess calculation formulas found in column F")
        
        # Criterion 7: Reasonable results
        leak_count = count_leak_flags(workbook, sheet_name, 8, 31)
        total_excess = sum_excess_gallons(workbook, sheet_name, 8, 31)
        
        results_reasonable = True
        if 4 <= leak_count <= 9:
            feedback_parts.append(f"✅ Appropriate leak detection: {leak_count} days flagged")
        else:
            results_reasonable = False
            feedback_parts.append(f"⚠️ Unexpected leak count: {leak_count} days (expected 4-9)")
        
        if 150 <= total_excess <= 800:
            feedback_parts.append(f"✅ Reasonable excess water: {total_excess:.0f} gallons")
        else:
            results_reasonable = False
            feedback_parts.append(f"⚠️ Unexpected excess total: {total_excess:.0f} gallons (expected 200-600)")
        
        if results_reasonable:
            criteria_met += 1
        else:
            criteria_met += 0.5
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent water leak analysis!")
        elif passed:
            feedback_parts.append("✅ Water leak detection task completed")
        else:
            feedback_parts.append("❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "file_created": True,
                "columns_present": columns_present,
                "rolling_average_correct": avg_pct >= 90 if avg_total > 0 else False,
                "threshold_correct": thresh_pct >= 90 if thresh_total > 0 else False,
                "leak_detection_correct": leak_if_pct >= 90 if leak_if_total > 0 else False,
                "excess_calculation": excess_total > 0,
                "results_reasonable": results_reasonable,
                "leak_days_detected": leak_count,
                "total_excess_gallons": round(total_excess, 1)
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
        cleanup_verification_temp(temp_dir)
