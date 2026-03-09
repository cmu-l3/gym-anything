#!/usr/bin/env python3
"""
Verifier for Meal Train Coordinator task
Checks for validation formulas and summary statistics
"""

import sys
import os
import logging
from typing import Dict, Any, Tuple, List

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_formulas_in_row(row: List[Dict], keywords: List[str]) -> Tuple[bool, str]:
    """
    Search for formulas in a row that contain specific keywords.
    
    Args:
        row: List of cell dictionaries
        keywords: List of keywords to search for in formulas (case-insensitive)
    
    Returns:
        Tuple of (found, formula_text)
    """
    for cell in row:
        if not isinstance(cell, dict):
            continue
        
        formula = cell.get('formula', '')
        if not formula:
            continue
        
        formula_upper = formula.upper()
        for keyword in keywords:
            if keyword.upper() in formula_upper:
                return True, formula
    
    return False, ""


def find_formulas_in_sheet(sheet_rows: List[List], keywords: List[str], max_rows: int = 30) -> Tuple[bool, List[str]]:
    """
    Search entire sheet for formulas containing keywords.
    
    Args:
        sheet_rows: List of rows from sheet
        keywords: Keywords to search for
        max_rows: Maximum number of rows to check
    
    Returns:
        Tuple of (found, list_of_formulas)
    """
    found_formulas = []
    
    for row_idx, row in enumerate(sheet_rows[:max_rows]):
        found, formula = find_formulas_in_row(row, keywords)
        if found:
            found_formulas.append(formula)
    
    return len(found_formulas) > 0, found_formulas


def check_gap_detection(sheet_rows: List[List]) -> Tuple[bool, str]:
    """
    Check if gap detection formula exists.
    Should detect the April 5 -> April 9 gap (4 days).
    """
    # Look for date arithmetic or DATEDIF
    date_formulas = ['DATEDIF', '-', 'DAYS']
    
    found, formulas = find_formulas_in_sheet(sheet_rows, date_formulas, max_rows=25)
    
    if found:
        # Check if any cell shows a value indicating a gap was detected (3 or 4 days)
        for row in sheet_rows[:25]:
            for cell in row:
                if not isinstance(cell, dict):
                    continue
                value = cell.get('value')
                # Look for gap values (3, 4, or 5 days - allowing some variation)
                if isinstance(value, (int, float)) and 3 <= value <= 5:
                    formula = cell.get('formula', '')
                    if formula and any(kw in formula.upper() for kw in ['DATEDIF', '-', 'DAYS']):
                        return True, f"Gap detection working (found {value} day gap)"
        
        return True, "Gap formula found but may not be detecting correctly"
    
    return False, "No gap detection formula found"


def check_duplicate_detection(sheet_rows: List[List]) -> Tuple[bool, str]:
    """
    Check if duplicate detection formula exists.
    Should flag the duplicate April 12 entries.
    """
    # Look for COUNTIF formulas
    found, formulas = find_formulas_in_sheet(sheet_rows, ['COUNTIF'], max_rows=25)
    
    if found:
        # Check if any cell has "DUPLICATE" or warning indicators
        for row in sheet_rows[:25]:
            for cell in row:
                if not isinstance(cell, dict):
                    continue
                value = str(cell.get('value', '')).upper()
                if any(indicator in value for indicator in ['DUPLICATE', 'DUP', '⚠', 'WARNING']):
                    return True, f"Duplicate detection working (found flag: {value})"
        
        return True, "COUNTIF formula found but may not be flagging duplicates"
    
    return False, "No duplicate detection formula found"


def check_dietary_validation(sheet_rows: List[List]) -> Tuple[bool, str]:
    """
    Check if dietary validation formula exists.
    Should flag the chicken soup entry.
    """
    # Look for text search functions
    search_functions = ['SEARCH', 'FIND', 'IF']
    
    found, formulas = find_formulas_in_sheet(sheet_rows, search_functions, max_rows=25)
    
    if found:
        # Check if any cell flags dietary issues
        for row in sheet_rows[:25]:
            row_text = ' '.join(str(cell.get('value', '')) for cell in row if isinstance(cell, dict))
            
            # Check if this row contains "chicken" (the dietary issue)
            if 'CHICKEN' in row_text.upper() or 'MEAT' in row_text.upper():
                # Look for warning indicators in this row
                for cell in row:
                    if not isinstance(cell, dict):
                        continue
                    value = str(cell.get('value', '')).upper()
                    formula = cell.get('formula', '')
                    
                    if formula and any(kw in formula.upper() for kw in ['SEARCH', 'FIND', 'IF']):
                        if any(flag in value for flag in ['ISSUE', '⚠', 'WARNING', 'X', '✗', 'PROBLEM']):
                            return True, f"Dietary validation working (flagged chicken issue)"
        
        return True, "Search formula found but may not be detecting dietary issues"
    
    return False, "No dietary validation formula found"


def check_summary_statistics(sheet_rows: List[List]) -> Tuple[int, List[str]]:
    """
    Check for summary statistics formulas.
    Returns count of summary formulas found and their details.
    """
    summary_functions = ['COUNT', 'SUM', 'AVERAGE', 'MAX', 'MIN', 'COUNTA']
    summary_found = []
    
    # Check all rows (summaries often at bottom or side)
    for row_idx, row in enumerate(sheet_rows):
        for cell in row:
            if not isinstance(cell, dict):
                continue
            
            formula = cell.get('formula', '')
            value = cell.get('value')
            
            if not formula:
                continue
            
            formula_upper = formula.upper()
            
            # Check if it's a summary-type formula
            for func in summary_functions:
                if func in formula_upper:
                    # Avoid counting formulas in data rows (likely in first 20 rows)
                    # Summaries are typically separate or at the end
                    if row_idx >= 15 or any(keyword in formula_upper for keyword in ['COUNTA', 'COUNT', 'MAX', 'MIN']):
                        if isinstance(value, (int, float)) and value > 0:
                            summary_found.append(f"{func} formula (result: {value})")
                            break
    
    return len(summary_found), summary_found


def check_total_meals_accuracy(sheet_rows: List[List]) -> Tuple[bool, str]:
    """
    Check if total meals count is approximately correct (~18).
    """
    for row in sheet_rows:
        for cell in row:
            if not isinstance(cell, dict):
                continue
            
            value = cell.get('value')
            formula = cell.get('formula', '')
            
            if isinstance(value, (int, float)) and 15 <= value <= 22:
                if 'COUNT' in formula.upper():
                    return True, f"Meal count appears accurate ({value} meals)"
    
    return False, "Meal count not found or inaccurate"


def check_data_integrity(sheet_rows: List[List]) -> Tuple[bool, str]:
    """
    Check that original volunteer data is preserved.
    Should have at least 15 rows with volunteer names and dates.
    """
    volunteer_count = 0
    date_count = 0
    
    for row_idx, row in enumerate(sheet_rows[1:25]):  # Skip header, check first 24 data rows
        if len(row) < 2:
            continue
        
        # Check first column (should be dates)
        first_cell = row[0] if isinstance(row[0], dict) else {'value': row[0]}
        date_val = first_cell.get('value')
        
        # Check second column (should be volunteer names)
        second_cell = row[1] if len(row) > 1 and isinstance(row[1], dict) else {'value': row[1] if len(row) > 1 else None}
        volunteer_val = second_cell.get('value')
        
        if date_val:
            date_count += 1
        
        if volunteer_val and isinstance(volunteer_val, str) and len(volunteer_val) > 2:
            volunteer_count += 1
    
    if volunteer_count >= 15 and date_count >= 15:
        return True, f"Original data preserved ({volunteer_count} volunteers, {date_count} dates)"
    else:
        return False, f"Data may be incomplete (found {volunteer_count} volunteers, {date_count} dates)"


def verify_meal_train_coordinator(traj, env_info, task_info):
    """
    Verify meal train coordination task completion.
    
    Checks:
    1. Gap detection formula works
    2. Duplicate detection formula works  
    3. Dietary validation formula works
    4. Summary statistics present (at least 2)
    5. Summary values accurate
    6. Original data preserved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to copy the validated file (ODS format preferred)
    container_paths = [
        "/home/ga/Documents/meal_train_validated.ods",
        "/home/ga/Documents/meal_train.ods",
        "/home/ga/Documents/meal_train.csv"
    ]
    
    success = False
    workbook = None
    temp_dir = None
    error = ""
    
    for path in container_paths:
        # Determine format from extension
        file_format = 'csv' if path.endswith('.csv') else 'ods'
        
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=file_format
        )
        
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load meal train file: {error}"
        }
    
    try:
        # Get sheet data
        sheet_names = list(workbook.get('sheets', {}).keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Initialize scoring
        criteria_met = 0
        max_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Gap Detection
        gap_ok, gap_msg = check_gap_detection(sheet_rows)
        subscores['gap_detection'] = gap_ok
        if gap_ok:
            criteria_met += 1
            feedback_parts.append(f"✅ Gap detection: {gap_msg}")
        else:
            feedback_parts.append(f"❌ Gap detection: {gap_msg}")
        
        # Criterion 2: Duplicate Detection
        dup_ok, dup_msg = check_duplicate_detection(sheet_rows)
        subscores['duplicate_detection'] = dup_ok
        if dup_ok:
            criteria_met += 1
            feedback_parts.append(f"✅ Duplicate detection: {dup_msg}")
        else:
            feedback_parts.append(f"❌ Duplicate detection: {dup_msg}")
        
        # Criterion 3: Dietary Validation
        diet_ok, diet_msg = check_dietary_validation(sheet_rows)
        subscores['dietary_validation'] = diet_ok
        if diet_ok:
            criteria_met += 1
            feedback_parts.append(f"✅ Dietary validation: {diet_msg}")
        else:
            feedback_parts.append(f"❌ Dietary validation: {diet_msg}")
        
        # Criterion 4: Summary Statistics Present
        summary_count, summary_details = check_summary_statistics(sheet_rows)
        subscores['summary_statistics_present'] = summary_count >= 2
        if summary_count >= 2:
            criteria_met += 1
            feedback_parts.append(f"✅ Summary statistics: {summary_count} found")
            logger.info(f"Summary details: {summary_details}")
        else:
            feedback_parts.append(f"❌ Summary statistics: Only {summary_count} found (need 2+)")
        
        # Criterion 5: Summary Accuracy
        total_ok, total_msg = check_total_meals_accuracy(sheet_rows)
        subscores['summary_accuracy'] = total_ok
        if total_ok:
            criteria_met += 1
            feedback_parts.append(f"✅ Summary accuracy: {total_msg}")
        else:
            feedback_parts.append(f"⚠️ Summary accuracy: {total_msg}")
        
        # Criterion 6: Data Integrity
        data_ok, data_msg = check_data_integrity(sheet_rows)
        subscores['data_integrity'] = data_ok
        if data_ok:
            criteria_met += 1
            feedback_parts.append(f"✅ Data integrity: {data_msg}")
        else:
            feedback_parts.append(f"❌ Data integrity: {data_msg}")
        
        # Calculate final score
        score = int((criteria_met / max_criteria) * 100)
        passed = score >= 70  # 70% threshold = 4/6 criteria
        
        # Add final message
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent meal train validation!")
        elif passed:
            feedback_parts.append("✅ Meal train validation completed")
        else:
            feedback_parts.append("❌ Meal train validation incomplete")
        
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
