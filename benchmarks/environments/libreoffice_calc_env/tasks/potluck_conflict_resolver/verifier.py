#!/usr/bin/env python3
"""
Verifier for Potluck Conflict Resolver task.

Checks:
1. Data imported (15+ rows, 5 columns)
2. Duplicate detection column with COUNTIF formula
3. Serving calculations (total and per-person)
4. Allergen flagging with SEARCH formula
5. Category summary with COUNTIF formulas
"""

import sys
import os
import logging
import re
from typing import Dict, Any, Tuple, List, Optional

# Add utils to path (relative path for host machine)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    get_sheet_names,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_by_keywords(workbook: Dict, sheet_name: str, keywords: List[str]) -> Optional[int]:
    """
    Find column index by searching for keywords in first row headers.
    
    Args:
        workbook: Parsed spreadsheet data
        sheet_name: Sheet name
        keywords: List of keywords to search for (case-insensitive)
    
    Returns:
        Column index (0-based) or None if not found
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        if not sheet_rows:
            return None
        
        header_row = sheet_rows[0]
        for col_idx, cell in enumerate(header_row):
            cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
            if cell_value:
                cell_text = str(cell_value).lower()
                for keyword in keywords:
                    if keyword.lower() in cell_text:
                        logger.info(f"Found column '{cell_value}' at index {col_idx} matching keyword '{keyword}'")
                        return col_idx
        
        return None
    except Exception as e:
        logger.error(f"Error finding column: {e}")
        return None


def check_countif_usage(workbook: Dict, sheet_name: str, col_idx: int, start_row: int = 1, check_rows: int = 10) -> bool:
    """
    Check if a column uses COUNTIF formula.
    
    Args:
        workbook: Parsed spreadsheet data
        sheet_name: Sheet name
        col_idx: Column index to check
        start_row: Starting row (default 1, skipping header)
        check_rows: Number of rows to check
    
    Returns:
        True if COUNTIF formula found, False otherwise
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        for row_idx in range(start_row, min(start_row + check_rows, len(sheet_rows))):
            if row_idx >= len(sheet_rows):
                break
            
            row = sheet_rows[row_idx]
            if col_idx >= len(row):
                continue
            
            cell = row[col_idx]
            formula = cell.get('formula', '') if isinstance(cell, dict) else ''
            
            if formula and 'COUNTIF' in formula.upper():
                logger.info(f"Found COUNTIF formula in row {row_idx}, col {col_idx}: {formula}")
                return True
        
        return False
    except Exception as e:
        logger.error(f"Error checking COUNTIF: {e}")
        return False


def check_search_formula_usage(workbook: Dict, sheet_name: str, col_idx: int, keywords: List[str], start_row: int = 1, check_rows: int = 10) -> bool:
    """
    Check if a column uses SEARCH/FIND formula with specific keywords.
    
    Args:
        workbook: Parsed spreadsheet data
        sheet_name: Sheet name
        col_idx: Column index to check
        keywords: Keywords to look for in formula (e.g., ["peanut", "nut"])
        start_row: Starting row
        check_rows: Number of rows to check
    
    Returns:
        True if SEARCH/FIND formula with keywords found
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        for row_idx in range(start_row, min(start_row + check_rows, len(sheet_rows))):
            if row_idx >= len(sheet_rows):
                break
            
            row = sheet_rows[row_idx]
            if col_idx >= len(row):
                continue
            
            cell = row[col_idx]
            formula = cell.get('formula', '') if isinstance(cell, dict) else ''
            
            if formula:
                formula_upper = formula.upper()
                if 'SEARCH' in formula_upper or 'FIND' in formula_upper:
                    # Check if any keyword is mentioned in formula
                    for keyword in keywords:
                        if keyword.lower() in formula.lower():
                            logger.info(f"Found SEARCH/FIND formula with '{keyword}' in row {row_idx}, col {col_idx}")
                            return True
        
        return False
    except Exception as e:
        logger.error(f"Error checking SEARCH formula: {e}")
        return False


def count_flagged_rows(workbook: Dict, sheet_name: str, col_idx: int, start_row: int = 1, max_rows: int = 20) -> int:
    """
    Count how many rows have non-empty values in a column (flagged rows).
    
    Args:
        workbook: Parsed spreadsheet data
        sheet_name: Sheet name
        col_idx: Column index
        start_row: Starting row (default 1, skip header)
        max_rows: Maximum rows to check
    
    Returns:
        Count of flagged rows
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        count = 0
        
        for row_idx in range(start_row, min(start_row + max_rows, len(sheet_rows))):
            if row_idx >= len(sheet_rows):
                break
            
            row = sheet_rows[row_idx]
            if col_idx >= len(row):
                continue
            
            cell = row[col_idx]
            value = cell.get('value', '') if isinstance(cell, dict) else cell
            
            if value and str(value).strip() and str(value).strip() != '':
                count += 1
        
        return count
    except Exception as e:
        logger.error(f"Error counting flagged rows: {e}")
        return 0


def find_sum_formula_in_sheet(workbook: Dict, sheet_name: str, target_column: int = 3) -> Optional[Tuple[int, int, Any]]:
    """
    Find a SUM formula that sums a specific column.
    
    Args:
        workbook: Parsed spreadsheet data
        sheet_name: Sheet name
        target_column: Column to look for in SUM (default 3 for column D/Servings)
    
    Returns:
        Tuple of (row, col, value) if found, None otherwise
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Check all cells for SUM formula
        for row_idx, row in enumerate(sheet_rows):
            for col_idx, cell in enumerate(row):
                formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                if formula and 'SUM' in formula.upper():
                    # Check if it references the target column
                    # Column D is index 3, which is column letter D
                    if 'D:D' in formula.upper() or 'D2:D' in formula.upper() or 'D1:D' in formula.upper():
                        value = cell.get('value', 0) if isinstance(cell, dict) else 0
                        logger.info(f"Found SUM formula at row {row_idx}, col {col_idx}: {formula} = {value}")
                        return (row_idx, col_idx, value)
        
        return None
    except Exception as e:
        logger.error(f"Error finding SUM formula: {e}")
        return None


def find_division_formula(workbook: Dict, sheet_name: str, divisor: int = 40) -> Optional[Tuple[int, int, Any]]:
    """
    Find a division formula that divides by a specific number (per-person calculation).
    
    Args:
        workbook: Parsed spreadsheet data
        sheet_name: Sheet name
        divisor: Expected divisor (default 40 for 40 people)
    
    Returns:
        Tuple of (row, col, value) if found, None otherwise
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        for row_idx, row in enumerate(sheet_rows):
            for col_idx, cell in enumerate(row):
                formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                if formula and '/' in formula:
                    # Check if divisor is in formula
                    if str(divisor) in formula:
                        value = cell.get('value', 0) if isinstance(cell, dict) else 0
                        logger.info(f"Found division formula at row {row_idx}, col {col_idx}: {formula} = {value}")
                        return (row_idx, col_idx, value)
        
        return None
    except Exception as e:
        logger.error(f"Error finding division formula: {e}")
        return None


def verify_category_summary(workbook: Dict, sheet_name: str, categories: List[str] = None) -> Tuple[bool, int]:
    """
    Verify that category summary exists with COUNTIF formulas.
    
    Args:
        workbook: Parsed spreadsheet data
        sheet_name: Sheet name
        categories: List of expected categories
    
    Returns:
        Tuple of (has_summary, count_of_categories_found)
    """
    if categories is None:
        categories = ["Appetizer", "Main", "Side", "Dessert"]
    
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        categories_found = 0
        
        # Search entire sheet for category names and nearby COUNTIF formulas
        for row_idx, row in enumerate(sheet_rows):
            for col_idx, cell in enumerate(row):
                value = cell.get('value', '') if isinstance(cell, dict) else cell
                
                # Check if this cell contains a category name
                if value:
                    value_str = str(value).strip()
                    for category in categories:
                        if category.lower() in value_str.lower():
                            # Found category name, check nearby cells for COUNTIF
                            # Check next few columns in same row
                            for check_col in range(col_idx + 1, min(col_idx + 4, len(row))):
                                if check_col < len(row):
                                    check_cell = row[check_col]
                                    check_formula = check_cell.get('formula', '') if isinstance(check_cell, dict) else ''
                                    if check_formula and 'COUNTIF' in check_formula.upper():
                                        logger.info(f"Found category '{category}' with COUNTIF in summary")
                                        categories_found += 1
                                        break
                            break
        
        has_summary = categories_found >= 3  # At least 3 out of 4 categories
        return has_summary, categories_found
    except Exception as e:
        logger.error(f"Error verifying category summary: {e}")
        return False, 0


def verify_potluck_analysis(traj, env_info, task_info):
    """
    Comprehensive verification of potluck coordination analysis.
    
    Checks 5 criteria:
    1. Data imported (15+ rows, 5 columns)
    2. Duplicate detection with COUNTIF (2+ flagged)
    3. Serving calculations (total and per-person)
    4. Allergen flagging with SEARCH (1+ flagged)
    5. Category summary with COUNTIF
    
    Pass threshold: 70% (3 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    temp_dir = None
    success = False
    workbook = None
    
    possible_paths = [
        ("/home/ga/Documents/potluck_analysis.ods", 'ods'),
        ("/home/ga/Documents/potluck_signups.ods", 'ods'),
        ("/home/ga/Documents/potluck_signups.csv", 'csv'),
    ]
    
    for container_path, file_format in possible_paths:
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
            "feedback": f"Failed to load spreadsheet file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = get_sheet_names(workbook)
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_rows = workbook['sheets'][sheet_name]
        
        criteria_met = 0
        total_criteria = 5
        feedback_parts = []
        subscores = {}
        
        # ===== Criterion 1: Data Import (20 points) =====
        row_count = len([row for row in sheet_rows if any(
            (cell.get('value', '') if isinstance(cell, dict) else cell) for cell in row
        )])
        
        col_count = len(sheet_rows[0]) if sheet_rows else 0
        
        if row_count >= 15 and col_count >= 5:
            criteria_met += 1
            feedback_parts.append(f"✅ Data imported: {row_count} rows, {col_count} columns")
            subscores['data_imported'] = True
        else:
            feedback_parts.append(f"❌ Data import incomplete: {row_count} rows, {col_count} columns (expected 15+ rows, 5+ columns)")
            subscores['data_imported'] = False
        
        # ===== Criterion 2: Duplicate Detection (20 points) =====
        duplicate_col = find_column_by_keywords(workbook, sheet_name, 
                                               ["duplicate", "conflict", "alert", "multiple", "check"])
        
        duplicate_criterion_met = False
        if duplicate_col is not None:
            # Check for COUNTIF formula
            has_countif = check_countif_usage(workbook, sheet_name, duplicate_col)
            if has_countif:
                # Count flagged rows
                flagged_count = count_flagged_rows(workbook, sheet_name, duplicate_col)
                if flagged_count >= 2:
                    criteria_met += 1
                    duplicate_criterion_met = True
                    feedback_parts.append(f"✅ Duplicate detection: COUNTIF formula, {flagged_count} rows flagged")
                else:
                    feedback_parts.append(f"⚠️  Duplicate detection: COUNTIF found but only {flagged_count} rows flagged (expected 2+)")
            else:
                feedback_parts.append("❌ Duplicate column exists but lacks COUNTIF formula")
        else:
            feedback_parts.append("❌ No duplicate detection column found")
        
        subscores['duplicate_detection'] = duplicate_criterion_met
        
        # ===== Criterion 3: Serving Calculations (20 points) =====
        sum_result = find_sum_formula_in_sheet(workbook, sheet_name, target_column=3)
        div_result = find_division_formula(workbook, sheet_name, divisor=40)
        
        serving_criterion_met = False
        if sum_result is not None:
            total_servings = sum_result[2]
            if 300 <= total_servings <= 350:  # Expected ~327
                if div_result is not None:
                    per_person = div_result[2]
                    if 7.0 <= per_person <= 9.5:  # Expected ~8.2
                        criteria_met += 1
                        serving_criterion_met = True
                        feedback_parts.append(f"✅ Serving calculations: Total={total_servings}, Per-person={per_person:.1f}")
                    else:
                        feedback_parts.append(f"⚠️  Serving calculations: Total correct but per-person={per_person:.1f} seems off")
                else:
                    feedback_parts.append(f"⚠️  Total servings calculated ({total_servings}) but per-person division not found")
            else:
                feedback_parts.append(f"❌ Total servings ({total_servings}) seems incorrect (expected ~327)")
        else:
            feedback_parts.append("❌ No serving calculations found (missing SUM formula)")
        
        subscores['serving_calculations'] = serving_criterion_met
        
        # ===== Criterion 4: Allergen Flagging (20 points) =====
        allergen_col = find_column_by_keywords(workbook, sheet_name,
                                              ["allergen", "allergy", "warning", "alert", "peanut"])
        
        allergen_criterion_met = False
        if allergen_col is not None:
            # Check for SEARCH/FIND formula
            has_search = check_search_formula_usage(workbook, sheet_name, allergen_col,
                                                   keywords=["peanut", "nut"])
            if has_search:
                # Count flagged rows
                flagged_count = count_flagged_rows(workbook, sheet_name, allergen_col)
                if flagged_count >= 1:
                    criteria_met += 1
                    allergen_criterion_met = True
                    feedback_parts.append(f"✅ Allergen flagging: SEARCH formula, {flagged_count} rows flagged")
                else:
                    feedback_parts.append("⚠️  Allergen formula exists but no rows flagged")
            else:
                feedback_parts.append("❌ Allergen column exists but lacks SEARCH/FIND formula")
        else:
            feedback_parts.append("❌ No allergen detection column found")
        
        subscores['allergen_flagging'] = allergen_criterion_met
        
        # ===== Criterion 5: Category Summary (20 points) =====
        has_summary, categories_found = verify_category_summary(workbook, sheet_name)
        
        category_criterion_met = False
        if has_summary:
            criteria_met += 1
            category_criterion_met = True
            feedback_parts.append(f"✅ Category summary: COUNTIF formulas for {categories_found}/4 categories")
        elif categories_found > 0:
            feedback_parts.append(f"⚠️  Partial category summary: {categories_found}/4 categories with COUNTIF")
        else:
            feedback_parts.append("❌ No category distribution summary found")
        
        subscores['category_summary'] = category_criterion_met
        
        # ===== Calculate Final Score =====
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (3 out of 5 criteria)
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent potluck analysis!")
        elif passed:
            feedback_parts.append("✅ Potluck analysis completed successfully")
        else:
            feedback_parts.append("❌ Analysis incomplete - need at least 3/5 criteria")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "criteria_met": f"{criteria_met}/{total_criteria}",
                "row_count": row_count,
                "col_count": col_count
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
