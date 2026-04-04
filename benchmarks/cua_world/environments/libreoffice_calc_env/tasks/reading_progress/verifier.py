#!/usr/bin/env python3
"""
Verifier for Reading Challenge Progress Tracker task.
Checks for summary statistics, calculated columns, genre counts, and conditional formatting.
"""

import sys
import os
import logging
import re
from typing import Dict, Any, Tuple, List, Optional

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_for_formula_pattern(sheet_data: List[List[Dict]], pattern: str, case_insensitive: bool = True) -> bool:
    """
    Search for a formula pattern in all cells of a sheet.
    
    Args:
        sheet_data: List of rows, each containing list of cell dicts
        pattern: String pattern to search for (e.g., "TODAY", "IF", "COUNTIF")
        case_insensitive: Whether to ignore case
        
    Returns:
        True if pattern found in any formula
    """
    pattern_to_match = pattern.upper() if case_insensitive else pattern
    
    for row in sheet_data:
        for cell in row:
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula:
                    formula_check = formula.upper() if case_insensitive else formula
                    if pattern_to_match in formula_check:
                        return True
    return False


def count_formula_occurrences(sheet_data: List[List[Dict]], pattern: str) -> int:
    """
    Count how many times a formula pattern appears in the sheet.
    
    Args:
        sheet_data: List of rows containing cell dicts
        pattern: Formula pattern to count (e.g., "COUNTIF")
        
    Returns:
        Number of occurrences
    """
    count = 0
    pattern_upper = pattern.upper()
    
    for row in sheet_data:
        for cell in row:
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula and pattern_upper in formula.upper():
                    count += 1
    return count


def check_for_formula_with_operators(sheet_data: List[List[Dict]], operators: List[str], value: str) -> bool:
    """
    Check if there's a formula containing specific operators and a value.
    Used to detect projection formulas like (x/y)*52
    
    Args:
        sheet_data: Sheet data
        operators: List of operators to check for (e.g., ["*", "/"])
        value: Value to look for (e.g., "52")
        
    Returns:
        True if matching formula found
    """
    for row in sheet_data:
        for cell in row:
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula:
                    has_all_operators = all(op in formula for op in operators)
                    has_value = value in formula
                    if has_all_operators and has_value:
                        return True
    return False


def count_non_empty_cells_in_column(sheet_data: List[List[Dict]], column_index: int = None, column_with_header: str = None) -> int:
    """
    Count non-empty cells in a column.
    
    Args:
        sheet_data: Sheet data
        column_index: Column index (0-based), or
        column_with_header: Find column by header name
        
    Returns:
        Count of non-empty cells (excluding header)
    """
    if column_with_header:
        # Find column index by header
        if len(sheet_data) > 0:
            header_row = sheet_data[0]
            for idx, cell in enumerate(header_row):
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                if cell_value and column_with_header.lower() in str(cell_value).lower():
                    column_index = idx
                    break
        
        if column_index is None:
            return 0
    
    count = 0
    for row_idx, row in enumerate(sheet_data):
        if row_idx == 0:  # Skip header
            continue
        if column_index < len(row):
            cell = row[column_index]
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value is not None and str(value).strip() != '':
                count += 1
    
    return count


def check_for_formula_errors(sheet_data: List[List[Dict]]) -> bool:
    """
    Check if there are any formula errors in the sheet.
    
    Args:
        sheet_data: Sheet data
        
    Returns:
        True if errors found, False otherwise
    """
    for row in sheet_data:
        for cell in row:
            if isinstance(cell, dict):
                value = cell.get('value')
                if value and isinstance(value, str):
                    # Check for common error values
                    if value.startswith('#') and any(err in value.upper() for err in ['#DIV/0', '#VALUE', '#REF', '#NAME', '#N/A', '#NUM']):
                        return True
    return False


def verify_reading_progress_tracker(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify reading challenge progress tracker implementation.
    
    Checks for:
    1. Summary statistics (current week, expected books, actual books, avg rating)
    2. Calculated progress status column (IF logic)
    3. Genre count formulas (COUNTIF - at least 3)
    4. Conditional formatting applied
    5. Date functions (TODAY) used
    6. End-of-year projection formula
    7. Accurate book count (18)
    8. Valid formula syntax throughout
    
    Pass threshold: 70% (6/8 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    temp_dir = None
    success = False
    workbook = None
    
    possible_files = [
        ('ods', '/home/ga/Documents/reading_challenge_tracker.ods'),
        ('ods', '/home/ga/Documents/reading_log.ods'),
        ('csv', '/home/ga/Documents/reading_log.csv'),
        ('csv', '/home/ga/Documents/reading_challenge_tracker.csv'),
    ]
    
    for file_format, container_path in possible_files:
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
            "feedback": f"Failed to load spreadsheet file. Tried: {', '.join(f[1] for f in possible_files)}"
        }
    
    try:
        # Get first sheet
        sheets = workbook.get('sheets', {})
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = list(sheets.keys())[0]
        sheet_data = sheets[sheet_name]
        
        criteria_met = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Summary statistics present (TODAY, AVERAGE)
        has_today = check_for_formula_pattern(sheet_data, "TODAY", case_insensitive=True)
        has_weeknum = check_for_formula_pattern(sheet_data, "WEEKNUM", case_insensitive=True)
        has_average = check_for_formula_pattern(sheet_data, "AVERAGE", case_insensitive=True)
        has_counta = check_for_formula_pattern(sheet_data, "COUNTA", case_insensitive=True) or \
                     check_for_formula_pattern(sheet_data, "COUNT", case_insensitive=True)
        
        summary_present = (has_today or has_weeknum) and has_average
        subscores['summary_statistics'] = summary_present
        
        if summary_present:
            criteria_met += 1
            feedback_parts.append("✅ Summary statistics present (date functions & average)")
        else:
            missing = []
            if not (has_today or has_weeknum):
                missing.append("date function (TODAY/WEEKNUM)")
            if not has_average:
                missing.append("AVERAGE")
            feedback_parts.append(f"❌ Missing summary statistics: {', '.join(missing)}")
        
        # Criterion 2: Calculated column with IF logic
        has_if_logic = check_for_formula_pattern(sheet_data, "IF", case_insensitive=True)
        subscores['if_logic'] = has_if_logic
        
        if has_if_logic:
            criteria_met += 1
            feedback_parts.append("✅ Calculated progress status column with IF logic")
        else:
            feedback_parts.append("❌ No IF statement found for progress status")
        
        # Criterion 3: Genre counts (COUNTIF - at least 3)
        has_countif = check_for_formula_pattern(sheet_data, "COUNTIF", case_insensitive=True)
        countif_count = count_formula_occurrences(sheet_data, "COUNTIF")
        
        genre_counts_adequate = has_countif and countif_count >= 3
        subscores['genre_counts'] = genre_counts_adequate
        
        if genre_counts_adequate:
            criteria_met += 1
            feedback_parts.append(f"✅ Genre counts present ({countif_count} COUNTIF formulas)")
        else:
            if countif_count > 0:
                feedback_parts.append(f"⚠️ Insufficient genre count formulas (found {countif_count}, need 3+)")
            else:
                feedback_parts.append("❌ No COUNTIF formulas found for genre analysis")
        
        # Criterion 4: Conditional formatting (if detectable)
        has_conditional_format = False
        try:
            # Try to detect conditional formatting
            # Note: This is format-dependent and may not always work
            has_conditional_format = check_conditional_formatting(workbook, sheet_name, "A1:Z100")
        except Exception as e:
            logger.debug(f"Could not check conditional formatting: {e}")
        
        subscores['conditional_formatting'] = has_conditional_format
        
        if has_conditional_format:
            criteria_met += 1
            feedback_parts.append("✅ Conditional formatting detected")
        else:
            # Don't penalize too heavily as this is hard to detect
            feedback_parts.append("⚠️ Conditional formatting not detected (may still be present)")
        
        # Criterion 5: Date functions used
        date_functions_present = has_today or has_weeknum
        subscores['date_functions'] = date_functions_present
        
        if date_functions_present:
            criteria_met += 1
            functions_found = []
            if has_today:
                functions_found.append("TODAY")
            if has_weeknum:
                functions_found.append("WEEKNUM")
            feedback_parts.append(f"✅ Date functions used: {', '.join(functions_found)}")
        else:
            feedback_parts.append("❌ No date functions detected (TODAY/WEEKNUM)")
        
        # Criterion 6: Projection formula (contains multiplication/division with 52)
        has_projection = check_for_formula_with_operators(sheet_data, ["*", "/"], "52") or \
                        check_for_formula_with_operators(sheet_data, ["*"], "52")
        subscores['projection_formula'] = has_projection
        
        if has_projection:
            criteria_met += 1
            feedback_parts.append("✅ End-of-year projection formula present")
        else:
            feedback_parts.append("❌ No projection formula found (expected formula with *52)")
        
        # Criterion 7: Accurate book count (18 books)
        book_count = count_non_empty_cells_in_column(sheet_data, column_with_header="Book Title")
        if book_count == 0:
            # Fallback: try column 1 (B column)
            book_count = count_non_empty_cells_in_column(sheet_data, column_index=1)
        
        accurate_count = book_count == 18
        subscores['accurate_count'] = accurate_count
        
        if accurate_count:
            criteria_met += 1
            feedback_parts.append(f"✅ Accurate book count ({book_count} books)")
        else:
            feedback_parts.append(f"⚠️ Book count mismatch (expected 18, found {book_count})")
        
        # Criterion 8: Valid formulas (no errors)
        has_errors = check_for_formula_errors(sheet_data)
        no_errors = not has_errors
        subscores['valid_formulas'] = no_errors
        
        if no_errors:
            criteria_met += 1
            feedback_parts.append("✅ All formulas syntactically valid")
        else:
            feedback_parts.append("❌ Formula errors detected in spreadsheet")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 6/8 criteria
        
        # Add summary feedback
        if passed:
            if score >= 90:
                feedback_parts.insert(0, "🎉 Excellent progress tracker implementation!")
            else:
                feedback_parts.insert(0, "✅ Progress tracker meets requirements")
        else:
            feedback_parts.insert(0, "❌ Progress tracker incomplete - needs more analysis")
        
        feedback_parts.append(f"\nScore: {criteria_met}/{total_criteria} criteria met ({score}%)")
        
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
