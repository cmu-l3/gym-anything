#!/usr/bin/env python3
"""
Verifier for Course Conflict Checker task

Checks:
1. Conflict detection column exists
2. Formulas are used (not manual text)
3. Known conflicts are detected
4. Conditional formatting applied
5. Credit calculation with SUM formula
6. Accurate credit total
7. Enrollment status indicator
8. No false positives
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Any, Optional

# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_verification_environment,
    get_cell_value,
    get_cell_formula,
    get_sheet_names,
    check_conditional_formatting,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_conflict_column(sheet_data: Dict, sheet_name: str) -> Optional[int]:
    """
    Find the column index containing conflict detection data.
    Looks for headers like "Time Conflicts", "Conflicts", "Conflict", etc.
    
    Returns:
        Column index (0-based) or None if not found
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        if not rows or len(rows) == 0:
            return None
        
        header_row = rows[0]
        
        # Search for conflict-related headers
        conflict_keywords = ['conflict', 'time conflict', 'schedule conflict', 'overlap']
        
        for col_idx, cell in enumerate(header_row):
            cell_value = cell.get('value', '') if isinstance(cell, dict) else cell
            if cell_value and isinstance(cell_value, str):
                cell_lower = cell_value.lower().strip()
                if any(keyword in cell_lower for keyword in conflict_keywords):
                    logger.info(f"Found conflict column at index {col_idx}: '{cell_value}'")
                    return col_idx
        
        # If not found by header, look for columns with formulas after column G (index 6)
        # that might contain conflict detection logic
        for col_idx in range(7, min(15, len(header_row))):
            # Check if multiple rows have formulas in this column
            formula_count = 0
            for row_idx in range(1, min(10, len(rows))):
                if col_idx < len(rows[row_idx]):
                    cell = rows[row_idx][col_idx]
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    if formula:
                        formula_count += 1
            
            if formula_count >= 3:  # At least 3 formulas suggest this might be the conflict column
                logger.info(f"Found potential conflict column at index {col_idx} (by formula presence)")
                return col_idx
        
        return None
        
    except Exception as e:
        logger.error(f"Error finding conflict column: {e}", exc_info=True)
        return None


def check_formula_presence(sheet_data: Dict, sheet_name: str, conflict_col: int) -> Tuple[bool, int]:
    """
    Check if formulas are present in the conflict column (not just manual text).
    
    Returns:
        (has_formulas, formula_count)
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        formula_count = 0
        
        # Check rows 2-8 (skip header at row 1, indices 1-7)
        for row_idx in range(1, min(8, len(rows))):
            if conflict_col < len(rows[row_idx]):
                cell = rows[row_idx][conflict_col]
                formula = cell.get('formula') if isinstance(cell, dict) else None
                
                if formula:
                    formula_count += 1
                    logger.debug(f"Found formula in row {row_idx + 1}: {formula}")
        
        has_formulas = formula_count >= 3  # At least 3 formulas expected
        logger.info(f"Formula check: {formula_count} formulas found, has_formulas={has_formulas}")
        return has_formulas, formula_count
        
    except Exception as e:
        logger.error(f"Error checking formulas: {e}", exc_info=True)
        return False, 0


def check_known_conflicts(sheet_data: Dict, sheet_name: str, conflict_col: int) -> Tuple[int, List[str]]:
    """
    Check if known conflicts are detected.
    
    Known conflicts:
    1. CS101 (row 2) vs MATH201 (row 3) - both MWF with time overlap
    2. PHYS101 (row 4) vs HIST150 (row 5) - both TTh with time overlap
    
    Returns:
        (conflicts_detected_count, feedback_list)
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        conflicts_found = 0
        feedback = []
        
        # Expected conflicts (row indices 1-based for display, 0-based internally)
        # CS101 is row 2 (index 1), should mention MATH201
        # MATH201 is row 3 (index 2), should mention CS101
        # PHYS101 is row 4 (index 3), should mention HIST150
        # HIST150 is row 5 (index 4), should mention PHYS101
        
        expected_conflicts = [
            (1, 'MATH201', 'CS101'),  # Row 2: CS101 should flag MATH201
            (2, 'CS101', 'MATH201'),   # Row 3: MATH201 should flag CS101
            (3, 'HIST150', 'PHYS101'), # Row 4: PHYS101 should flag HIST150
            (4, 'PHYS101', 'HIST150')  # Row 5: HIST150 should flag PHYS101
        ]
        
        detected_pairs = set()
        
        for row_idx, expected_course, current_course in expected_conflicts:
            if row_idx < len(rows) and conflict_col < len(rows[row_idx]):
                cell = rows[row_idx][conflict_col]
                cell_value = str(cell.get('value', '')) if isinstance(cell, dict) else str(cell)
                
                # Check if the expected conflicting course is mentioned
                if expected_course.upper() in cell_value.upper():
                    conflict_pair = tuple(sorted([current_course, expected_course]))
                    detected_pairs.add(conflict_pair)
                    logger.info(f"✓ Conflict detected: {current_course} ↔ {expected_course}")
        
        conflicts_found = len(detected_pairs)
        
        if conflicts_found >= 2:
            feedback.append(f"✅ {conflicts_found}/2 known conflict pairs detected")
        elif conflicts_found == 1:
            feedback.append(f"⚠️ Only {conflicts_found}/2 conflict pairs detected")
        else:
            feedback.append("❌ Known conflicts not detected")
        
        return conflicts_found, feedback
        
    except Exception as e:
        logger.error(f"Error checking known conflicts: {e}", exc_info=True)
        return 0, ["❌ Error checking conflicts"]


def check_false_positives(sheet_data: Dict, sheet_name: str, conflict_col: int) -> Tuple[bool, List[str]]:
    """
    Check for false positives (non-conflicting courses incorrectly flagged).
    
    Non-conflicting pairs to check:
    - CS101 (MWF) vs PHYS101 (TTh) - different days
    - ENGL102 (MW) vs CS201 (TTh) - different days
    
    Returns:
        (no_false_positives, feedback_list)
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        feedback = []
        false_positive_found = False
        
        # Check CS101 (row 2, index 1) shouldn't mention PHYS101 as conflict
        if 1 < len(rows) and conflict_col < len(rows[1]):
            cell = rows[1][conflict_col]
            cell_value = str(cell.get('value', '')) if isinstance(cell, dict) else str(cell)
            if 'PHYS101' in cell_value.upper():
                false_positive_found = True
                feedback.append("⚠️ False positive: CS101 incorrectly flags PHYS101")
        
        # Check ENGL102 (row 5, index 4) shouldn't mention CS201 as conflict
        if 4 < len(rows) and conflict_col < len(rows[4]):
            cell = rows[4][conflict_col]
            cell_value = str(cell.get('value', '')) if isinstance(cell, dict) else str(cell)
            if 'CS201' in cell_value.upper():
                false_positive_found = True
                feedback.append("⚠️ False positive: ENGL102 incorrectly flags CS201")
        
        if not false_positive_found:
            feedback.append("✅ No false positives detected")
        
        return not false_positive_found, feedback
        
    except Exception as e:
        logger.error(f"Error checking false positives: {e}", exc_info=True)
        return True, ["⚠️ Could not verify false positives"]


def find_credit_calculation(sheet_data: Dict, sheet_name: str) -> Tuple[bool, Optional[float], List[str]]:
    """
    Find and verify credit calculation with SUM formula.
    
    Returns:
        (has_sum_formula, calculated_total, feedback_list)
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        feedback = []
        
        # Search for SUM formula in reasonable area (rows 8-15, columns A-K)
        for row_idx in range(7, min(20, len(rows))):
            for col_idx in range(0, min(11, len(rows[row_idx]) if row_idx < len(rows) else 0)):
                if row_idx >= len(rows) or col_idx >= len(rows[row_idx]):
                    continue
                
                cell = rows[row_idx][col_idx]
                formula = cell.get('formula') if isinstance(cell, dict) else None
                
                if formula and 'SUM' in formula.upper():
                    # Found a SUM formula
                    cell_value = cell.get('value', 0) if isinstance(cell, dict) else cell
                    try:
                        total = float(cell_value) if cell_value else 0
                        logger.info(f"Found SUM formula at row {row_idx + 1}, col {col_idx}: {formula} = {total}")
                        
                        # Expected total: CS101(3) + MATH201(4) + PHYS101(4) + ENGL102(3) + HIST150(3) + CS201(3) = 20
                        expected_total = 20
                        
                        if abs(total - expected_total) <= 0.5:
                            feedback.append(f"✅ Credit calculation correct: {total} credits")
                            return True, total, feedback
                        else:
                            feedback.append(f"⚠️ Credit total incorrect: {total} (expected ~{expected_total})")
                            return True, total, feedback
                    except (ValueError, TypeError):
                        pass
        
        feedback.append("❌ SUM formula for credits not found")
        return False, None, feedback
        
    except Exception as e:
        logger.error(f"Error finding credit calculation: {e}", exc_info=True)
        return False, None, ["❌ Error checking credit calculation"]


def find_status_indicator(sheet_data: Dict, sheet_name: str, credit_total: Optional[float]) -> Tuple[bool, List[str]]:
    """
    Find and verify enrollment status indicator.
    
    Expected:
    - FULL-TIME if >= 12 credits
    - PART-TIME if < 12 credits
    - OVERLOAD if > 18 credits
    
    With 20 credits, should show OVERLOAD.
    
    Returns:
        (status_correct, feedback_list)
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        feedback = []
        
        if credit_total is None:
            feedback.append("⚠️ Cannot verify status (no credit total)")
            return False, feedback
        
        # Determine expected status
        if credit_total > 18:
            expected_status = 'OVERLOAD'
        elif credit_total >= 12:
            expected_status = 'FULL-TIME'
        else:
            expected_status = 'PART-TIME'
        
        # Search for status text or formula in reasonable area
        status_keywords = ['FULL-TIME', 'FULL TIME', 'PART-TIME', 'PART TIME', 'OVERLOAD', 
                          'FULL_TIME', 'PART_TIME']
        
        for row_idx in range(7, min(20, len(rows))):
            for col_idx in range(0, min(11, len(rows[row_idx]) if row_idx < len(rows) else 0)):
                if row_idx >= len(rows) or col_idx >= len(rows[row_idx]):
                    continue
                
                cell = rows[row_idx][col_idx]
                cell_value = str(cell.get('value', '')) if isinstance(cell, dict) else str(cell)
                cell_value_upper = cell_value.upper().replace('-', ' ').replace('_', ' ')
                
                # Check if any status keyword is present
                if any(keyword.replace('-', ' ').replace('_', ' ') in cell_value_upper for keyword in status_keywords):
                    logger.info(f"Found status indicator at row {row_idx + 1}, col {col_idx}: {cell_value}")
                    
                    expected_upper = expected_status.replace('-', ' ').replace('_', ' ')
                    if expected_upper in cell_value_upper:
                        feedback.append(f"✅ Status indicator correct: {cell_value}")
                        return True, feedback
                    else:
                        feedback.append(f"⚠️ Status indicator found but incorrect: {cell_value} (expected {expected_status})")
                        return False, feedback
        
        feedback.append("❌ Status indicator not found")
        return False, feedback
        
    except Exception as e:
        logger.error(f"Error finding status indicator: {e}", exc_info=True)
        return False, ["❌ Error checking status indicator"]


def verify_course_conflict_checker(traj, env_info, task_info):
    """
    Main verifier for course conflict checker task.
    
    Checks 8 criteria:
    1. Conflict column created
    2. Formulas present (not manual text)
    3. Known conflicts identified
    4. Conditional formatting applied
    5. Credit calculation present
    6. Accurate credit total
    7. Status indicator correct
    8. No false positives
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths
    file_paths = [
        ("/home/ga/Documents/course_conflicts.ods", ['ods']),
        ("/home/ga/Documents/fall_2025_courses.ods", ['ods']),
        ("/home/ga/Documents/fall_2025_courses.csv", ['csv']),
    ]
    
    success = False
    result = None
    
    for container_path, formats in file_paths:
        success, result = setup_verification_environment(
            copy_from_env,
            container_path,
            expected_formats=formats
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {result.get('error', 'Unknown error')}"
        }
    
    try:
        sheet_data = result.get('data', {})
        temp_dir = result.get('temp_dir', '')
        
        # Get first sheet
        sheet_names = get_sheet_names(sheet_data)
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        # Initialize scoring
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Conflict column exists
        conflict_col = find_conflict_column(sheet_data, sheet_name)
        if conflict_col is not None:
            criteria_passed += 1
            feedback_parts.append("✅ Conflict detection column created")
            subscores['conflict_column_exists'] = True
        else:
            feedback_parts.append("❌ Conflict detection column not found")
            subscores['conflict_column_exists'] = False
            # Can't continue without conflict column
            score = int((criteria_passed / total_criteria) * 100)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # Criterion 2: Formulas present
        has_formulas, formula_count = check_formula_presence(sheet_data, sheet_name, conflict_col)
        if has_formulas:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas detected ({formula_count} formulas)")
            subscores['formulas_present'] = True
        else:
            feedback_parts.append(f"❌ Insufficient formulas ({formula_count} found, need ≥3)")
            subscores['formulas_present'] = False
        
        # Criterion 3: Known conflicts identified
        conflicts_detected, conflict_feedback = check_known_conflicts(sheet_data, sheet_name, conflict_col)
        if conflicts_detected >= 2:
            criteria_passed += 1
            subscores['known_conflicts_detected'] = True
        else:
            subscores['known_conflicts_detected'] = False
        feedback_parts.extend(conflict_feedback)
        
        # Criterion 4: Conditional formatting applied
        # Note: This is approximate - checking if formatting rules exist
        has_cond_format = check_conditional_formatting(sheet_data, sheet_name, "A1:H10")
        if has_cond_format:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
            subscores['conditional_formatting'] = True
        else:
            # Give partial credit if conflict detection works
            if conflicts_detected >= 1:
                feedback_parts.append("⚠️ Conditional formatting not verified (may be present)")
                subscores['conditional_formatting'] = False
            else:
                feedback_parts.append("❌ Conditional formatting not detected")
                subscores['conditional_formatting'] = False
        
        # Criterion 5 & 6: Credit calculation
        has_sum, credit_total, credit_feedback = find_credit_calculation(sheet_data, sheet_name)
        if has_sum:
            criteria_passed += 1  # Criterion 5
            subscores['credit_calculation_present'] = True
            
            if credit_total is not None and abs(credit_total - 20) <= 0.5:
                criteria_passed += 1  # Criterion 6
                subscores['credit_total_correct'] = True
            else:
                subscores['credit_total_correct'] = False
        else:
            subscores['credit_calculation_present'] = False
            subscores['credit_total_correct'] = False
        feedback_parts.extend(credit_feedback)
        
        # Criterion 7: Status indicator
        status_correct, status_feedback = find_status_indicator(sheet_data, sheet_name, credit_total)
        if status_correct:
            criteria_passed += 1
            subscores['status_indicator_correct'] = True
        else:
            subscores['status_indicator_correct'] = False
        feedback_parts.extend(status_feedback)
        
        # Criterion 8: No false positives
        no_false_positives, fp_feedback = check_false_positives(sheet_data, sheet_name, conflict_col)
        if no_false_positives:
            criteria_passed += 1
            subscores['no_false_positives'] = True
        else:
            subscores['no_false_positives'] = False
        feedback_parts.extend(fp_feedback)
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 6/8 criteria (75%)
        
        # Add summary
        if passed:
            if score >= 90:
                feedback_parts.insert(0, "🎉 Excellent conflict detection system!")
            else:
                feedback_parts.insert(0, "✅ Conflict checker functional")
        else:
            feedback_parts.insert(0, "❌ Conflict checker incomplete")
        
        feedback_parts.append(f"Score: {criteria_passed}/{total_criteria} criteria met")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
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
        cleanup_verification_environment(temp_dir)
