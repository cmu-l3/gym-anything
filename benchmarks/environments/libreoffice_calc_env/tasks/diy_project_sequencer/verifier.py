#!/usr/bin/env python3
"""
Verifier for DIY Project Sequencer task
Validates dependency checking, earliest start calculation, critical path identification, and timeline calculation
"""

import sys
import os
import logging
import re
from typing import Dict, Any, List, Tuple, Optional

# Add utils to path (relative path for host execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_prerequisites(prereq_str: str) -> List[str]:
    """Parse semicolon-separated prerequisites into list"""
    if not prereq_str or prereq_str == "":
        return []
    return [p.strip() for p in str(prereq_str).split(';') if p.strip()]


def get_task_sequence_map(workbook: Dict, sheet_name: str) -> Dict[str, int]:
    """Build mapping of task name to sequence number"""
    task_seq_map = {}
    rows = workbook['sheets'][sheet_name]
    
    for i in range(1, min(13, len(rows))):  # Rows 2-13 (1-indexed becomes 1-12)
        if i >= len(rows):
            break
        row = rows[i]
        
        # Column A: Task Name, Column D: Sequence
        if len(row) > 0:
            task_name_cell = row[0]
            task_name = task_name_cell.get('value') if isinstance(task_name_cell, dict) else task_name_cell
            
        if len(row) > 3:
            seq_cell = row[3]
            seq = seq_cell.get('value') if isinstance(seq_cell, dict) else seq_cell
            
            if task_name and seq is not None:
                try:
                    task_seq_map[str(task_name).strip()] = int(float(seq))
                except (ValueError, TypeError):
                    logger.warning(f"Could not parse sequence for task {task_name}: {seq}")
    
    return task_seq_map


def verify_dependency_formulas(workbook: Dict, sheet_name: str) -> Tuple[bool, str, int]:
    """
    Verify that dependency check column (F) contains formulas
    Returns: (has_formulas, feedback, count_with_formulas)
    """
    rows = workbook['sheets'][sheet_name]
    formula_count = 0
    total_tasks = 12
    
    for i in range(1, min(13, len(rows))):  # Rows 2-13 (tasks)
        if i >= len(rows):
            break
        row = rows[i]
        
        if len(row) > 5:  # Column F (index 5)
            cell = row[5]
            formula = cell.get('formula') if isinstance(cell, dict) else None
            
            if formula and '=' in str(formula):
                # Check for conditional logic
                formula_upper = str(formula).upper()
                if 'IF' in formula_upper or 'AND' in formula_upper or 'OR' in formula_upper:
                    formula_count += 1
    
    has_formulas = formula_count >= 8  # At least 2/3 of tasks have formulas
    feedback = f"Dependency formulas: {formula_count}/{total_tasks} tasks"
    
    return has_formulas, feedback, formula_count


def verify_earliest_start_calculations(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Verify earliest start column (G) calculations
    Checks specific tasks where we know the correct answer
    """
    rows = workbook['sheets'][sheet_name]
    
    # Build task data structure
    tasks = []
    for i in range(1, min(13, len(rows))):
        if i >= len(rows):
            break
        row = rows[i]
        
        if len(row) < 7:
            continue
            
        task_name = row[0].get('value') if isinstance(row[0], dict) else row[0]
        duration = row[1].get('value') if isinstance(row[1], dict) else row[1]
        prereqs_str = row[2].get('value') if isinstance(row[2], dict) else row[2]
        earliest_start = row[6].get('value') if len(row) > 6 and isinstance(row[6], dict) else (row[6] if len(row) > 6 else None)
        
        tasks.append({
            'name': task_name,
            'duration': duration,
            'prerequisites': parse_prerequisites(prereqs_str) if prereqs_str else [],
            'earliest_start': earliest_start
        })
    
    # Check specific known cases
    checks_passed = 0
    total_checks = 0
    feedback_parts = []
    
    # Task 1 (Remove old tile) - should start on Day 1 (no prerequisites)
    if len(tasks) > 0 and tasks[0]['earliest_start'] is not None:
        total_checks += 1
        try:
            if abs(float(tasks[0]['earliest_start']) - 1.0) < 0.1:
                checks_passed += 1
            else:
                feedback_parts.append(f"Task 1 earliest start incorrect: got {tasks[0]['earliest_start']}, expected 1")
        except (ValueError, TypeError):
            feedback_parts.append(f"Task 1 earliest start not numeric: {tasks[0]['earliest_start']}")
    
    # Task 4 (Waterproof shower) - prerequisite is Task 2 (1 day duration)
    # Should start on Day 3 (Task 1 completes end of day 1, Task 2 completes end of day 2, this starts day 3)
    if len(tasks) > 3 and tasks[3]['earliest_start'] is not None:
        total_checks += 1
        try:
            expected = 3.0  # After Task 2 completes
            if abs(float(tasks[3]['earliest_start']) - expected) < 0.6:
                checks_passed += 1
            else:
                feedback_parts.append(f"Task 4 earliest start incorrect: got {tasks[3]['earliest_start']}, expected ~{expected}")
        except (ValueError, TypeError):
            feedback_parts.append(f"Task 4 earliest start not numeric: {tasks[3]['earliest_start']}")
    
    # Task 9 (Install fixtures) - has two prerequisites: "Paint walls" and "Grout tile"
    # Should wait for the longer of the two chains
    if len(tasks) > 8 and tasks[8]['earliest_start'] is not None:
        total_checks += 1
        try:
            # Should be at least Day 7 (after the tile chain completes)
            if float(tasks[8]['earliest_start']) >= 7.0:
                checks_passed += 1
            else:
                feedback_parts.append(f"Task 9 earliest start too early: got {tasks[8]['earliest_start']}, expected ≥7")
        except (ValueError, TypeError):
            feedback_parts.append(f"Task 9 earliest start not numeric: {tasks[8]['earliest_start']}")
    
    # At least half of checked calculations should be correct
    calculations_correct = total_checks > 0 and (checks_passed / total_checks) >= 0.5
    
    feedback = f"Earliest start calculations: {checks_passed}/{total_checks} checks passed"
    if feedback_parts:
        feedback += " | " + "; ".join(feedback_parts[:2])  # Limit feedback length
    
    return calculations_correct, feedback


def verify_critical_path_column(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Verify critical path column (H) exists and has content
    """
    rows = workbook['sheets'][sheet_name]
    values_found = 0
    
    for i in range(1, min(13, len(rows))):
        if i >= len(rows):
            break
        row = rows[i]
        
        if len(row) > 7:  # Column H (index 7)
            cell = row[7]
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if value and str(value).strip() != "":
                values_found += 1
    
    has_critical_path = values_found >= 8  # At least 2/3 of tasks have values
    feedback = f"Critical path column: {values_found}/12 tasks have values"
    
    return has_critical_path, feedback


def verify_total_duration(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Verify total project duration is calculated
    Should be in the summary section (rows 14-16)
    """
    rows = workbook['sheets'][sheet_name]
    
    # Check rows 14-16 for a total duration value
    for i in range(13, min(17, len(rows))):  # Rows 14-17
        if i >= len(rows):
            break
        row = rows[i]
        
        # Check all columns for a numeric value that could be total duration
        for j in range(len(row)):
            cell = row[j]
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if value and isinstance(value, (int, float)):
                # Total duration should be between 8 and 20 days (reasonable range)
                if 8 <= float(value) <= 20:
                    return True, f"Total duration calculated: {value} days"
    
    return False, "Total duration not found or incorrect"


def verify_violation_flagged(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Verify that the intentional dependency violation is flagged
    Task 8 (Paint walls, sequence 7) depends on Task 7 (Install ventilation fan, sequence 8)
    This should be flagged as a violation
    """
    rows = workbook['sheets'][sheet_name]
    
    # Task 8 is in row 8 (0-indexed row 7)
    if len(rows) <= 7:
        return False, "Task 8 not found"
    
    row = rows[7]  # Task 8: "Paint walls"
    
    if len(row) < 6:
        return False, "Dependency check column not found for Task 8"
    
    dep_check_cell = row[5]  # Column F
    value = dep_check_cell.get('value') if isinstance(dep_check_cell, dict) else dep_check_cell
    
    # Check if it's NOT "OK" (should be a warning/error message)
    if value and str(value).strip().upper() != "OK":
        # Should contain some indication of a problem
        value_str = str(value).upper()
        if any(keyword in value_str for keyword in ['WARN', 'ERROR', 'VIOLAT', 'AFTER', 'BEFORE', 'INCORRECT']):
            return True, f"✅ Violation correctly flagged: '{value}'"
        else:
            return True, f"⚠️ Task 8 flagged but message unclear: '{value}'"
    
    return False, "❌ Task 8 dependency violation not detected (shows OK or empty)"


def verify_no_formula_errors(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Verify that formulas don't have errors like #REF!, #VALUE!, #NAME!
    """
    rows = workbook['sheets'][sheet_name]
    error_count = 0
    checked_count = 0
    
    for i in range(1, min(13, len(rows))):
        if i >= len(rows):
            break
        row = rows[i]
        
        # Check columns F, G, H for errors
        for col_idx in [5, 6, 7]:
            if col_idx < len(row):
                cell = row[col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                checked_count += 1
                if value and isinstance(value, str):
                    if any(err in str(value).upper() for err in ['#REF!', '#VALUE!', '#NAME!', '#DIV/0!', '#N/A']):
                        error_count += 1
    
    no_errors = error_count == 0
    feedback = f"Formula errors: {error_count} errors in {checked_count} cells"
    
    return no_errors, feedback


def verify_project_sequencer(traj, env_info, task_info):
    """
    Main verifier for DIY Project Sequencer task
    
    Checks:
    1. Dependency check column has formulas with conditional logic
    2. Earliest start column has correct calculations
    3. Critical path column exists with values
    4. Total project duration is calculated
    5. Intentional dependency violation (Task 8) is flagged
    6. No formula errors (#REF!, #VALUE!, etc.)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/bathroom_renovation.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get sheet name
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}

        # Criterion 1: Dependency check formulas
        has_dep_formulas, dep_feedback, formula_count = verify_dependency_formulas(workbook, sheet_name)
        subscores['dependency_formulas'] = has_dep_formulas
        if has_dep_formulas:
            criteria_passed += 1
            feedback_parts.append(f"✅ {dep_feedback}")
        else:
            feedback_parts.append(f"❌ {dep_feedback} - need conditional formulas (IF/AND/OR)")

        # Criterion 2: Earliest start calculations
        earliest_correct, earliest_feedback = verify_earliest_start_calculations(workbook, sheet_name)
        subscores['earliest_start_correct'] = earliest_correct
        if earliest_correct:
            criteria_passed += 1
            feedback_parts.append(f"✅ {earliest_feedback}")
        else:
            feedback_parts.append(f"❌ {earliest_feedback}")

        # Criterion 3: Critical path column
        has_critical_path, cp_feedback = verify_critical_path_column(workbook, sheet_name)
        subscores['critical_path_exists'] = has_critical_path
        if has_critical_path:
            criteria_passed += 1
            feedback_parts.append(f"✅ {cp_feedback}")
        else:
            feedback_parts.append(f"❌ {cp_feedback}")

        # Criterion 4: Total duration calculated
        has_total, total_feedback = verify_total_duration(workbook, sheet_name)
        subscores['total_duration'] = has_total
        if has_total:
            criteria_passed += 1
            feedback_parts.append(f"✅ {total_feedback}")
        else:
            feedback_parts.append(f"❌ {total_feedback}")

        # Criterion 5: Violation flagged
        violation_flagged, violation_feedback = verify_violation_flagged(workbook, sheet_name)
        subscores['violation_detected'] = violation_flagged
        if violation_flagged:
            criteria_passed += 1
            feedback_parts.append(violation_feedback)
        else:
            feedback_parts.append(violation_feedback)

        # Criterion 6: No formula errors
        no_errors, error_feedback = verify_no_formula_errors(workbook, sheet_name)
        subscores['no_formula_errors'] = no_errors
        if no_errors:
            criteria_passed += 1
            feedback_parts.append(f"✅ {error_feedback}")
        else:
            feedback_parts.append(f"⚠️ {error_feedback}")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 4.5/6 criteria, round to 75%
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Project sequencing complete!")
        elif passed:
            feedback_parts.insert(0, "✅ Task validation completed")
        else:
            feedback_parts.insert(0, f"❌ Task incomplete ({criteria_passed}/{total_criteria} criteria)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "criteria_breakdown": {
                "dependency_formulas": has_dep_formulas,
                "earliest_start_calculations": earliest_correct,
                "critical_path_column": has_critical_path,
                "total_duration": has_total,
                "violation_detection": violation_flagged,
                "no_errors": no_errors
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
