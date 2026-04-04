#!/usr/bin/env python3
"""
Verifier for Water Leak Forensics task.
Validates analytical reasoning, formula usage, and forensic data analysis.
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_column_data(sheet_data, col_letter, start_row=1, end_row=None):
    """Extract data from a specific column"""
    sheets = sheet_data.get('sheets', {})
    if not sheets:
        return []
    
    sheet_name = list(sheets.keys())[0]
    rows = sheets[sheet_name]
    
    # Convert column letter to index
    col_idx = ord(col_letter.upper()) - ord('A')
    
    data = []
    max_row = end_row if end_row else len(rows)
    
    for i in range(start_row - 1, min(max_row, len(rows))):
        if i < len(rows) and col_idx < len(rows[i]):
            cell = rows[i][col_idx]
            value = cell.get('value') if isinstance(cell, dict) else cell
            data.append(value)
        else:
            data.append(None)
    
    return data


def check_formula_exists(sheet_data, sheet_name, col_letter, start_row=2, min_count=10):
    """Check if formulas exist in a column"""
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return False
    
    rows = sheets[sheet_name]
    col_idx = ord(col_letter.upper()) - ord('A')
    
    formula_count = 0
    for i in range(start_row - 1, min(start_row - 1 + 50, len(rows))):
        if i < len(rows) and col_idx < len(rows[i]):
            cell = rows[i][col_idx]
            formula = cell.get('formula') if isinstance(cell, dict) else None
            if formula:
                formula_count += 1
    
    return formula_count >= min_count


def verify_water_leak_forensics(traj, env_info, task_info):
    """
    Verify water leak forensics analysis task.
    
    Checks:
    1. Data properly imported (55+ rows of meter readings)
    2. Daily usage calculated with formulas (difference between consecutive readings)
    3. Baseline established (~75-110 gallons/day from first ~20 days)
    4. Leak date identified (should be around day 22-24, within ±3 days)
    5. Waste quantified (cumulative excess, total 5,000-9,000 gallons)
    6. Cost calculated (waste × $0.0045/gal, result $22.50-$40.50)
    7. Summary report with key findings
    8. Formulas used (not manual entry)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/results/water_leak_analysis.ods",
        "/home/ga/Documents/water_leak_analysis.ods",
        "/home/ga/Documents/water_meter_readings.ods",
    ]
    
    success = False
    file_info = None
    error = None
    
    for container_path in possible_paths:
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            ['ods', 'xlsx']
        )
        if success:
            logger.info(f"Found analysis file at: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load analysis file. Tried: {', '.join(possible_paths)}. Error: {error}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        sheets = sheet_data.get('sheets', {})
        
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = list(sheets.keys())[0]
        rows = sheets[sheet_name]
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Data properly imported (55+ rows)
        non_empty_rows = sum(1 for row in rows if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row))
        
        if non_empty_rows >= 55:
            criteria_passed += 1
            feedback_parts.append(f"✅ Data imported ({non_empty_rows} rows)")
            subscores['data_imported'] = True
        else:
            feedback_parts.append(f"❌ Insufficient data ({non_empty_rows} rows, expected 55+)")
            subscores['data_imported'] = False
        
        # Criterion 2: Daily usage calculated with formulas
        # Typically in column C or similar
        has_daily_usage_formulas = False
        daily_usage_col = None
        
        for col_letter in ['C', 'D', 'E']:
            if check_formula_exists(sheet_data, sheet_name, col_letter, start_row=3, min_count=10):
                has_daily_usage_formulas = True
                daily_usage_col = col_letter
                break
        
        if has_daily_usage_formulas:
            criteria_passed += 1
            feedback_parts.append(f"✅ Daily usage formulas found (column {daily_usage_col})")
            subscores['daily_usage_calculated'] = True
        else:
            feedback_parts.append("❌ Daily usage formulas not detected")
            subscores['daily_usage_calculated'] = False
        
        # Criterion 3: Baseline established (~75-110 gallons/day)
        # Look for a cell with value in this range that might be labeled
        baseline_found = False
        baseline_value = None
        
        # Check common locations for summary data (first few rows, or columns to the right)
        for row_idx in range(min(10, len(rows))):
            for col_idx in range(min(10, len(rows[row_idx]))):
                cell = rows[row_idx][col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                if isinstance(value, (int, float)) and 75 <= value <= 110:
                    # Check if there's a label nearby suggesting this is baseline
                    # Check cell to the left
                    if col_idx > 0:
                        left_cell = rows[row_idx][col_idx - 1]
                        left_value = left_cell.get('value') if isinstance(left_cell, dict) else left_cell
                        if isinstance(left_value, str) and any(word in left_value.lower() for word in ['baseline', 'normal', 'average', 'usage', 'daily']):
                            baseline_found = True
                            baseline_value = value
                            break
                    # Also accept if this is clearly an average formula
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    if formula and 'AVERAGE' in formula.upper():
                        baseline_found = True
                        baseline_value = value
                        break
            if baseline_found:
                break
        
        if baseline_found:
            criteria_passed += 1
            feedback_parts.append(f"✅ Baseline established ({baseline_value:.1f} gal/day)")
            subscores['baseline_established'] = True
        else:
            feedback_parts.append("❌ Baseline calculation not found (expected ~75-110 gal/day)")
            subscores['baseline_established'] = False
        
        # Criterion 4: Leak date identified (around day 22-24)
        # Look for date references or row numbers indicating leak start
        leak_date_identified = False
        
        # Search for dates around 3/22-3/24/2024 or labels like "leak start"
        for row_idx in range(min(15, len(rows))):
            for col_idx in range(min(10, len(rows[row_idx]))):
                cell = rows[row_idx][col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                if isinstance(value, str):
                    # Check for date patterns
                    if '3/22' in value or '3/23' in value or '3/24' in value or '03/22' in value or '03/23' in value or '03/24' in value:
                        # Check if there's a label suggesting this is leak-related
                        if col_idx > 0:
                            left_cell = rows[row_idx][col_idx - 1]
                            left_value = left_cell.get('value') if isinstance(left_cell, dict) else left_cell
                            if isinstance(left_value, str) and any(word in left_value.lower() for word in ['leak', 'start', 'anomaly', 'begin']):
                                leak_date_identified = True
                                break
        
        # Alternative: check if there's a distinct pattern in daily usage column
        if not leak_date_identified and daily_usage_col:
            usage_data = get_column_data(sheet_data, daily_usage_col, start_row=2)
            # Look for sustained jump around row 22-24
            for i in range(15, min(30, len(usage_data) - 3)):
                if usage_data[i] and isinstance(usage_data[i], (int, float)):
                    if usage_data[i] > 200:  # Likely post-leak value
                        # Check if previous values were lower
                        if i > 0 and usage_data[i-1] and isinstance(usage_data[i-1], (int, float)):
                            if usage_data[i-1] < 150:  # Likely pre-leak
                                leak_date_identified = True
                                break
        
        if leak_date_identified:
            criteria_passed += 1
            feedback_parts.append("✅ Leak start date identified")
            subscores['leak_date_identified'] = True
        else:
            feedback_parts.append("❌ Leak start date not clearly identified")
            subscores['leak_date_identified'] = False
        
        # Criterion 5: Waste quantified (5,000-9,000 gallons total)
        waste_found = False
        waste_value = None
        
        for row_idx in range(min(15, len(rows))):
            for col_idx in range(min(10, len(rows[row_idx]))):
                cell = rows[row_idx][col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                if isinstance(value, (int, float)) and 5000 <= value <= 9000:
                    # Check for label suggesting this is waste/total
                    if col_idx > 0:
                        left_cell = rows[row_idx][col_idx - 1]
                        left_value = left_cell.get('value') if isinstance(left_cell, dict) else left_cell
                        if isinstance(left_value, str) and any(word in left_value.lower() for word in ['waste', 'total', 'excess', 'lost', 'wasted']):
                            waste_found = True
                            waste_value = value
                            break
                    # Also check formula suggesting summation
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    if formula and 'SUM' in formula.upper():
                        waste_found = True
                        waste_value = value
                        break
            if waste_found:
                break
        
        if waste_found:
            criteria_passed += 1
            feedback_parts.append(f"✅ Water waste calculated ({waste_value:.0f} gallons)")
            subscores['waste_quantified'] = True
        else:
            feedback_parts.append("❌ Total water waste not found (expected 5,000-9,000 gallons)")
            subscores['waste_quantified'] = False
        
        # Criterion 6: Cost calculated ($22.50-$40.50)
        cost_found = False
        cost_value = None
        
        for row_idx in range(min(15, len(rows))):
            for col_idx in range(min(10, len(rows[row_idx]))):
                cell = rows[row_idx][col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                if isinstance(value, (int, float)) and 22.5 <= value <= 40.5:
                    # Check for label suggesting this is cost
                    if col_idx > 0:
                        left_cell = rows[row_idx][col_idx - 1]
                        left_value = left_cell.get('value') if isinstance(left_cell, dict) else left_cell
                        if isinstance(left_value, str) and any(word in left_value.lower() for word in ['cost', 'dollar', 'price', 'amount', '$', 'financial']):
                            cost_found = True
                            cost_value = value
                            break
                    # Also check if formula multiplies by 0.0045
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    if formula and ('0.0045' in formula or '0.00450' in formula):
                        cost_found = True
                        cost_value = value
                        break
            if cost_found:
                break
        
        if cost_found:
            criteria_passed += 1
            feedback_parts.append(f"✅ Cost calculated (${cost_value:.2f})")
            subscores['cost_calculated'] = True
        else:
            feedback_parts.append("❌ Financial cost not found (expected $22.50-$40.50)")
            subscores['cost_calculated'] = False
        
        # Criterion 7: Summary report exists
        # Check if first few rows have labels/summary structure
        summary_exists = False
        label_count = 0
        
        for row_idx in range(min(10, len(rows))):
            for col_idx in range(min(5, len(rows[row_idx]))):
                cell = rows[row_idx][col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                if isinstance(value, str) and any(word in value.lower() for word in 
                    ['baseline', 'normal', 'leak', 'start', 'waste', 'cost', 'summary', 'finding', 'total', 'days']):
                    label_count += 1
        
        if label_count >= 3:
            summary_exists = True
            criteria_passed += 1
            feedback_parts.append("✅ Summary report present")
            subscores['summary_report'] = True
        else:
            feedback_parts.append("❌ Summary report not clearly formatted")
            subscores['summary_report'] = False
        
        # Criterion 8: Formulas used (not just hardcoded)
        # Check multiple columns for formulas
        formula_columns = 0
        for col_letter in ['C', 'D', 'E', 'F', 'G']:
            if check_formula_exists(sheet_data, sheet_name, col_letter, start_row=2, min_count=5):
                formula_columns += 1
        
        if formula_columns >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas used for calculations ({formula_columns} columns)")
            subscores['formulas_used'] = True
        else:
            feedback_parts.append("❌ Insufficient formula usage (calculations may be hardcoded)")
            subscores['formulas_used'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 6/8 criteria
        
        # Add overall assessment
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent forensic analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Water leak analysis completed")
        else:
            feedback_parts.insert(0, "❌ Analysis incomplete or incorrect")
        
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
        cleanup_verification_temp(file_info.get('temp_dir'))
