#!/usr/bin/env python3
"""
Verifier for Sleep Quality Analyzer task.
Checks CSV import, formula calculations, statistical functions, and conditional formatting.
"""

import sys
import os
import re
import logging

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_with_header(sheet_data, header_keywords):
    """
    Find column index that contains header matching keywords.
    
    Args:
        sheet_data: Sheet data dict with 'rows' or similar structure
        header_keywords: List of keywords to match in header (case-insensitive)
    
    Returns:
        Column index (0-based) or None if not found
    """
    try:
        # Get first row (header row)
        rows = sheet_data
        if not rows or len(rows) == 0:
            return None
        
        header_row = rows[0] if rows else []
        
        for col_idx, cell in enumerate(header_row):
            cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
            cell_str = str(cell_value).lower()
            
            # Check if any keyword matches
            for keyword in header_keywords:
                if keyword.lower() in cell_str:
                    return col_idx
        
        return None
    except Exception as e:
        logger.debug(f"Error finding column: {e}")
        return None


def find_efficiency_column(sheet_data):
    """Find the Sleep Efficiency column (usually column H or next to Time Asleep)."""
    keywords = ['efficiency', 'sleep efficiency', 'sleep eff']
    return find_column_with_header(sheet_data, keywords)


def extract_value_from_cell(cell_data):
    """Extract numeric value from cell data."""
    if isinstance(cell_data, dict):
        value = cell_data.get('value')
    else:
        value = cell_data
    
    if value is None:
        return None
    
    # Convert to float if possible
    try:
        return float(value)
    except (ValueError, TypeError):
        return None


def check_efficiency_formula(formula_string):
    """
    Check if formula matches expected pattern for sleep efficiency.
    Patterns: =(E/D)*100, =E/D*100, =(E3/D3)*100, etc.
    """
    if not formula_string:
        return False
    
    # Normalize: remove spaces, uppercase
    normalized = formula_string.replace(' ', '').upper()
    
    # Pattern 1: =(E\d+/D\d+)*100
    pattern1 = re.search(r'=\(E\d+/D\d+\)\*100', normalized)
    # Pattern 2: =E\d+/D\d+\*100 (without parentheses)
    pattern2 = re.search(r'=E\d+/D\d+\*100', normalized)
    # Pattern 3: =(Column/Column)*100 for other column references
    pattern3 = re.search(r'=\([A-Z]+\d+/[A-Z]+\d+\)\*100', normalized)
    
    return pattern1 is not None or pattern2 is not None or pattern3 is not None


def search_for_formula_pattern(sheet_data, formula_pattern, start_row=2, end_row=20):
    """
    Search for a formula matching pattern in specified row range.
    Returns (row_idx, col_idx, formula) or (None, None, None)
    """
    try:
        for row_idx in range(start_row, min(end_row, len(sheet_data))):
            row = sheet_data[row_idx]
            for col_idx, cell in enumerate(row):
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula and formula_pattern(formula):
                    return row_idx, col_idx, formula
        return None, None, None
    except Exception as e:
        logger.debug(f"Error searching formulas: {e}")
        return None, None, None


def verify_sleep_quality_analyzer(traj, env_info, task_info):
    """
    Verify sleep quality analyzer task completion.
    
    Checks:
    1. CSV data imported correctly
    2. Sleep efficiency formula present and correct
    3. Average sleep calculation accurate
    4. Poor sleep count (COUNTIF) correct
    5. Conditional formatting applied
    6. Formula consistency across rows
    7. No calculation errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the analysis file (might be saved as different name)
    container_paths = [
        "/home/ga/Documents/sleep_analysis_complete.ods",
        "/home/ga/Documents/sleep_data.ods",
        "/home/ga/Documents/sleep_data.csv"
    ]
    
    success = False
    file_info = None
    
    for container_path in container_paths:
        # Determine format from extension
        if container_path.endswith('.csv'):
            formats = ['csv', 'ods']
        else:
            formats = ['ods', 'csv']
        
        success, file_info, error = setup_calc_verification(copy_from_env, container_path, formats)
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load any expected file. Last error: {error}"
        }

    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_rows = data['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Criterion 1: CSV Data Imported Correctly
        # Check known values from CSV
        data_imported = True
        expected_checks = [
            ('A2', '2024-01-15'),  # First date
            ('E2', 6.8),           # First sleep duration
            ('E6', 7.8),           # Fifth sleep duration
        ]
        
        for cell_ref, expected in expected_checks:
            actual = get_cell_value(data, sheet_name, cell_ref)
            # Flexible matching for dates and numbers
            if actual is None:
                data_imported = False
                break
            
            if isinstance(expected, str):
                if str(expected) not in str(actual):
                    data_imported = False
                    break
            else:
                if abs(float(actual) - float(expected)) > 0.1:
                    data_imported = False
                    break
        
        if data_imported:
            criteria_passed += 1
            feedback_parts.append("✅ CSV data imported correctly")
        else:
            feedback_parts.append("❌ CSV data import issue or missing data")
        
        # Criterion 2: Sleep Efficiency Formula
        # Search for efficiency formula in likely columns (H, I, J)
        efficiency_formula_found = False
        efficiency_col = None
        
        for col_letter in ['H', 'I', 'J', 'K']:
            for row_num in range(2, 5):  # Check first few data rows
                cell_ref = f"{col_letter}{row_num}"
                formula = get_cell_formula(data, sheet_name, cell_ref)
                if formula and check_efficiency_formula(formula):
                    efficiency_formula_found = True
                    efficiency_col = col_letter
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Sleep efficiency formula found: {formula} in {cell_ref}")
                    break
            if efficiency_formula_found:
                break
        
        if not efficiency_formula_found:
            feedback_parts.append("❌ Sleep efficiency formula not found or incorrect pattern")
        
        # Criterion 3: Average Sleep Calculation
        # Search for AVERAGE formula anywhere in the sheet
        average_found = False
        average_value = None
        
        for row_idx, row in enumerate(sheet_rows):
            for col_idx, cell in enumerate(row):
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula and 'AVERAGE' in formula.upper() and 'E' in formula.upper():
                    value = extract_value_from_cell(cell)
                    # Expected average is approximately 6.8
                    if value and abs(value - 6.8) < 0.3:
                        average_found = True
                        average_value = value
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Average sleep calculated correctly: {value:.2f} hours")
                        break
            if average_found:
                break
        
        if not average_found:
            feedback_parts.append("❌ Average sleep calculation missing or incorrect (expected ~6.8 hours)")
        
        # Criterion 4: Poor Sleep Count (COUNTIF)
        # Search for COUNTIF formula
        countif_found = False
        countif_value = None
        
        for row_idx, row in enumerate(sheet_rows):
            for col_idx, cell in enumerate(row):
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula and 'COUNTIF' in formula.upper():
                    value = extract_value_from_cell(cell)
                    # Expected count is 5 nights with <7 hours
                    if value == 5 or (value and abs(value - 5) < 0.1):
                        countif_found = True
                        countif_value = value
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Poor sleep count correct: {int(value)} nights <7 hours")
                        break
            if countif_found:
                break
        
        if not countif_found:
            feedback_parts.append("❌ COUNTIF for insufficient sleep nights missing or incorrect (expected 5)")
        
        # Criterion 5: Conditional Formatting Applied
        # Check if conditional formatting exists on Time Asleep column (E)
        has_formatting = False
        try:
            # Check column E (Time Asleep) for conditional formatting
            has_formatting = check_conditional_formatting(data, sheet_name, "E3:E16")
            
            if has_formatting:
                criteria_passed += 1
                feedback_parts.append("✅ Conditional formatting applied to Time Asleep column")
            else:
                feedback_parts.append("❌ Conditional formatting not detected on Time Asleep column")
        except Exception as e:
            logger.debug(f"Could not check conditional formatting: {e}")
            feedback_parts.append("⚠️ Could not verify conditional formatting")
        
        # Criterion 6: Formula Consistency (efficiency formula in all rows)
        if efficiency_formula_found and efficiency_col:
            consistent_formulas = True
            formula_count = 0
            
            for row_num in range(3, 17):  # Rows 3-16 (14 data rows)
                cell_ref = f"{efficiency_col}{row_num}"
                formula = get_cell_formula(data, sheet_name, cell_ref)
                if formula and check_efficiency_formula(formula):
                    formula_count += 1
            
            # Should have formulas in at least 10 of 14 rows (allowing some flexibility)
            if formula_count >= 10:
                criteria_passed += 1
                feedback_parts.append(f"✅ Efficiency formula applied consistently ({formula_count}/14 rows)")
            else:
                feedback_parts.append(f"❌ Efficiency formula not consistently applied ({formula_count}/14 rows)")
        else:
            feedback_parts.append("❌ Cannot verify formula consistency (efficiency column not found)")
        
        # Criterion 7: No Calculation Errors
        # Check for #DIV/0!, #VALUE!, #REF!, #N/A errors
        has_errors = False
        error_cells = []
        
        for row_idx, row in enumerate(sheet_rows[:20]):  # Check first 20 rows
            for col_idx, cell in enumerate(row):
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value and isinstance(value, str):
                    if any(err in str(value).upper() for err in ['#DIV/0', '#VALUE', '#REF', '#N/A', '#NAME', '#NUM']):
                        has_errors = True
                        error_cells.append(f"Row{row_idx+1}Col{col_idx+1}")
        
        if not has_errors:
            criteria_passed += 1
            feedback_parts.append("✅ No calculation errors detected")
        else:
            feedback_parts.append(f"❌ Calculation errors found in: {', '.join(error_cells[:3])}")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold = 5/7 criteria
        
        if passed and score >= 85:
            feedback_parts.append("🎉 Sleep analysis completed successfully!")
        elif passed:
            feedback_parts.append("✅ Sleep analysis task completed")
        else:
            feedback_parts.append("❌ Sleep analysis requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "data_imported": data_imported,
                "efficiency_formula": efficiency_formula_found,
                "average_calculated": average_found,
                "countif_correct": countif_found,
                "conditional_formatting": has_formatting,
                "formula_consistency": formula_count >= 10 if efficiency_formula_found else False,
                "no_errors": not has_errors
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
        if file_info:
            cleanup_verification_temp(file_info.get('temp_dir'))
