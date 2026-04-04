#!/usr/bin/env python3
"""
Verifier for Festival Scheduler task.

Checks:
1. Duration standardization (mixed formats → integer minutes)
2. Total block calculation (duration + 20 buffer)
3. Venue assignment logic (constraints satisfied)
4. Time slot assignment (valid slots, fit within windows)
5. Conflict detection (same venue + time flagged)
6. No formula errors
"""

import sys
import os
import logging
import re
from typing import Dict, List, Any, Tuple, Optional

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
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


# Duration parsing reference for validation
DURATION_TEST_CASES = {
    "45": 45,
    "1:35": 95,
    "2h 15m": 135,
    "about 95 minutes": 95,
    "105": 105,
    "1h 50m": 110,
    "82": 82,
    "38": 38,
    "2:10": 130,
    "118": 118,
    "1:25": 85,
    "52": 52
}

# Valid time slots with maximum duration windows (in minutes)
VALID_TIME_SLOTS = {
    "2:00 PM": 110,   # Must finish by 3:50 PM
    "4:00 PM": 140,   # Must finish by 6:20 PM
    "6:30 PM": 110,   # Must finish by 8:20 PM
    "8:30 PM": 90     # Must finish by 10:00 PM
}

# Venue constraints
MAIN_THEATER = "Main Theater"
GALLERY_SPACE = "Gallery Space"


def normalize_time_slot(slot_str: str) -> str:
    """Normalize time slot string for comparison."""
    if not slot_str:
        return ""
    
    # Convert to uppercase and strip
    normalized = str(slot_str).strip().upper()
    
    # Try to match common formats
    if "2:00" in normalized or "2 PM" in normalized or "14:00" in normalized:
        return "2:00 PM"
    elif "4:00" in normalized or "4 PM" in normalized or "16:00" in normalized:
        return "4:00 PM"
    elif "6:30" in normalized or "6:30PM" in normalized or "18:30" in normalized:
        return "6:30 PM"
    elif "8:30" in normalized or "8:30PM" in normalized or "20:30" in normalized:
        return "8:30 PM"
    
    return slot_str.strip()


def verify_duration_standardization(workbook: Dict, sheet_name: str) -> Tuple[bool, str, Dict]:
    """
    Verify that Duration_Minutes column exists and contains correct conversions.
    
    Returns:
        (success, feedback, details_dict)
    """
    try:
        # Find Duration_Minutes column
        header_row = workbook['sheets'][sheet_name][0]
        duration_col_idx = None
        original_col_idx = None
        
        for idx, cell in enumerate(header_row):
            cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).strip()
            if 'duration_minutes' in cell_val.lower() or 'duration (minutes)' in cell_val.lower():
                duration_col_idx = idx
            elif 'duration_original' in cell_val.lower() or 'duration original' in cell_val.lower():
                original_col_idx = idx
        
        if duration_col_idx is None:
            return False, "Duration_Minutes column not found", {}
        
        # Check sample conversions
        rows = workbook['sheets'][sheet_name]
        correct_conversions = 0
        total_conversions = 0
        errors = []
        
        for row_idx in range(1, min(len(rows), 13)):  # Check up to 12 films
            if row_idx >= len(rows):
                break
            
            row = rows[row_idx]
            if duration_col_idx >= len(row):
                continue
            
            duration_cell = row[duration_col_idx]
            duration_val = duration_cell.get('value', '') if isinstance(duration_cell, dict) else duration_cell
            
            # Check if it's a numeric value
            try:
                duration_minutes = float(duration_val) if duration_val else None
                if duration_minutes is not None:
                    # Verify it's in reasonable range
                    if 20 <= duration_minutes <= 180:
                        correct_conversions += 1
                    else:
                        errors.append(f"Row {row_idx + 1}: Duration {duration_minutes} out of reasonable range (20-180 min)")
                    total_conversions += 1
            except (ValueError, TypeError):
                errors.append(f"Row {row_idx + 1}: Duration not numeric: {duration_val}")
                total_conversions += 1
        
        if total_conversions == 0:
            return False, "No duration data found", {}
        
        accuracy = correct_conversions / total_conversions
        success = accuracy >= 0.9  # Allow 10% margin for edge cases
        
        feedback = f"Duration standardization: {correct_conversions}/{total_conversions} correct"
        if errors and len(errors) <= 3:
            feedback += f" | Issues: {'; '.join(errors[:3])}"
        
        return success, feedback, {
            'accuracy': accuracy,
            'correct': correct_conversions,
            'total': total_conversions
        }
        
    except Exception as e:
        logger.error(f"Error verifying duration standardization: {e}", exc_info=True)
        return False, f"Error checking durations: {str(e)}", {}


def verify_time_block_calculation(workbook: Dict, sheet_name: str) -> Tuple[bool, str, Dict]:
    """
    Verify that Total_Block_Minutes = Duration_Minutes + 20.
    
    Returns:
        (success, feedback, details_dict)
    """
    try:
        # Find columns
        header_row = workbook['sheets'][sheet_name][0]
        duration_col_idx = None
        block_col_idx = None
        
        for idx, cell in enumerate(header_row):
            cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).strip().lower()
            if 'duration_minutes' in cell_val or 'duration (minutes)' in cell_val:
                duration_col_idx = idx
            elif 'total_block' in cell_val or 'total block' in cell_val or 'block_minutes' in cell_val:
                block_col_idx = idx
        
        if block_col_idx is None:
            return False, "Total_Block_Minutes column not found", {}
        
        if duration_col_idx is None:
            return False, "Duration_Minutes column not found (needed for block calculation)", {}
        
        # Check calculations
        rows = workbook['sheets'][sheet_name]
        correct_calculations = 0
        total_calculations = 0
        
        for row_idx in range(1, min(len(rows), 13)):
            if row_idx >= len(rows):
                break
            
            row = rows[row_idx]
            if duration_col_idx >= len(row) or block_col_idx >= len(row):
                continue
            
            duration_cell = row[duration_col_idx]
            block_cell = row[block_col_idx]
            
            duration_val = duration_cell.get('value', '') if isinstance(duration_cell, dict) else duration_cell
            block_val = block_cell.get('value', '') if isinstance(block_cell, dict) else block_cell
            
            try:
                duration_num = float(duration_val) if duration_val else None
                block_num = float(block_val) if block_val else None
                
                if duration_num is not None and block_num is not None:
                    expected_block = duration_num + 20
                    if abs(block_num - expected_block) <= 1:  # Allow 1 min tolerance
                        correct_calculations += 1
                    total_calculations += 1
            except (ValueError, TypeError):
                total_calculations += 1
        
        if total_calculations == 0:
            return False, "No time block calculations found", {}
        
        accuracy = correct_calculations / total_calculations
        success = accuracy >= 0.9
        
        feedback = f"Time block calculation: {correct_calculations}/{total_calculations} correct"
        
        return success, feedback, {
            'accuracy': accuracy,
            'correct': correct_calculations,
            'total': total_calculations
        }
        
    except Exception as e:
        logger.error(f"Error verifying time blocks: {e}", exc_info=True)
        return False, f"Error checking time blocks: {str(e)}", {}


def verify_venue_assignment(workbook: Dict, sheet_name: str) -> Tuple[bool, str, Dict]:
    """
    Verify venue assignment logic:
    - Films >120 min should be in Main Theater
    - All films have valid venue assignments
    
    Returns:
        (success, feedback, details_dict)
    """
    try:
        # Find columns
        header_row = workbook['sheets'][sheet_name][0]
        duration_col_idx = None
        venue_col_idx = None
        
        for idx, cell in enumerate(header_row):
            cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).strip().lower()
            if 'duration_minutes' in cell_val or 'duration (minutes)' in cell_val:
                duration_col_idx = idx
            elif 'venue' in cell_val or 'assigned_venue' in cell_val:
                venue_col_idx = idx
        
        if venue_col_idx is None:
            return False, "Assigned_Venue column not found", {}
        
        # Check assignments
        rows = workbook['sheets'][sheet_name]
        constraint_violations = 0
        valid_assignments = 0
        total_assignments = 0
        
        for row_idx in range(1, min(len(rows), 13)):
            if row_idx >= len(rows):
                break
            
            row = rows[row_idx]
            if venue_col_idx >= len(row):
                continue
            
            venue_cell = row[venue_col_idx]
            venue_val = str(venue_cell.get('value', '') if isinstance(venue_cell, dict) else venue_cell).strip()
            
            if not venue_val or venue_val.lower() in ['none', 'n/a', '']:
                continue
            
            total_assignments += 1
            
            # Check if venue is valid
            if MAIN_THEATER in venue_val or GALLERY_SPACE in venue_val:
                valid_assignments += 1
                
                # Check constraint: films >120 min should be in Main Theater
                if duration_col_idx is not None and duration_col_idx < len(row):
                    duration_cell = row[duration_col_idx]
                    duration_val = duration_cell.get('value', '') if isinstance(duration_cell, dict) else duration_cell
                    try:
                        duration_num = float(duration_val) if duration_val else None
                        if duration_num is not None and duration_num > 120:
                            if MAIN_THEATER not in venue_val:
                                constraint_violations += 1
                    except (ValueError, TypeError):
                        pass
        
        if total_assignments == 0:
            return False, "No venue assignments found", {}
        
        success = (valid_assignments >= 0.9 * total_assignments and constraint_violations == 0)
        
        feedback = f"Venue assignments: {valid_assignments}/{total_assignments} valid"
        if constraint_violations > 0:
            feedback += f" | {constraint_violations} constraint violations (>120 min not in Main Theater)"
        
        return success, feedback, {
            'valid': valid_assignments,
            'total': total_assignments,
            'violations': constraint_violations
        }
        
    except Exception as e:
        logger.error(f"Error verifying venue assignments: {e}", exc_info=True)
        return False, f"Error checking venues: {str(e)}", {}


def verify_time_slot_assignment(workbook: Dict, sheet_name: str) -> Tuple[bool, str, Dict]:
    """
    Verify time slot assignments:
    - All slots are valid (2:00 PM, 4:00 PM, 6:30 PM, 8:30 PM)
    - Films fit within their time slot windows
    
    Returns:
        (success, feedback, details_dict)
    """
    try:
        # Find columns
        header_row = workbook['sheets'][sheet_name][0]
        block_col_idx = None
        slot_col_idx = None
        
        for idx, cell in enumerate(header_row):
            cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).strip().lower()
            if 'total_block' in cell_val or 'block_minutes' in cell_val:
                block_col_idx = idx
            elif 'time_slot' in cell_val or 'time slot' in cell_val or 'slot' in cell_val:
                slot_col_idx = idx
        
        if slot_col_idx is None:
            return False, "Time_Slot column not found", {}
        
        # Check assignments
        rows = workbook['sheets'][sheet_name]
        valid_slots = 0
        fit_checks_passed = 0
        total_assignments = 0
        
        for row_idx in range(1, min(len(rows), 13)):
            if row_idx >= len(rows):
                break
            
            row = rows[row_idx]
            if slot_col_idx >= len(row):
                continue
            
            slot_cell = row[slot_col_idx]
            slot_val = str(slot_cell.get('value', '') if isinstance(slot_cell, dict) else slot_cell).strip()
            
            if not slot_val or slot_val.lower() in ['none', 'n/a', '']:
                continue
            
            total_assignments += 1
            normalized_slot = normalize_time_slot(slot_val)
            
            # Check if slot is valid
            if normalized_slot in VALID_TIME_SLOTS:
                valid_slots += 1
                
                # Check if film fits within slot window
                if block_col_idx is not None and block_col_idx < len(row):
                    block_cell = row[block_col_idx]
                    block_val = block_cell.get('value', '') if isinstance(block_cell, dict) else block_cell
                    try:
                        block_num = float(block_val) if block_val else None
                        if block_num is not None:
                            max_duration = VALID_TIME_SLOTS[normalized_slot]
                            if block_num <= max_duration:
                                fit_checks_passed += 1
                    except (ValueError, TypeError):
                        pass
        
        if total_assignments == 0:
            return False, "No time slot assignments found", {}
        
        success = (valid_slots >= 0.9 * total_assignments and 
                  fit_checks_passed >= 0.8 * valid_slots)
        
        feedback = f"Time slots: {valid_slots}/{total_assignments} valid"
        if fit_checks_passed < valid_slots:
            feedback += f" | {valid_slots - fit_checks_passed} films may not fit in assigned slots"
        
        return success, feedback, {
            'valid': valid_slots,
            'total': total_assignments,
            'fit_passed': fit_checks_passed
        }
        
    except Exception as e:
        logger.error(f"Error verifying time slots: {e}", exc_info=True)
        return False, f"Error checking time slots: {str(e)}", {}


def verify_conflict_detection(workbook: Dict, sheet_name: str) -> Tuple[bool, str, Dict]:
    """
    Verify that conflicts are properly detected or schedule is conflict-free.
    
    Returns:
        (success, feedback, details_dict)
    """
    try:
        # Find columns
        header_row = workbook['sheets'][sheet_name][0]
        venue_col_idx = None
        slot_col_idx = None
        conflict_col_idx = None
        
        for idx, cell in enumerate(header_row):
            cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).strip().lower()
            if 'venue' in cell_val:
                venue_col_idx = idx
            elif 'time_slot' in cell_val or 'slot' in cell_val:
                slot_col_idx = idx
            elif 'conflict' in cell_val:
                conflict_col_idx = idx
        
        # Build schedule to detect actual conflicts
        rows = workbook['sheets'][sheet_name]
        schedule = {}  # (venue, slot) -> [row_indices]
        
        for row_idx in range(1, min(len(rows), 13)):
            if row_idx >= len(rows):
                break
            
            row = rows[row_idx]
            if venue_col_idx is None or slot_col_idx is None:
                continue
            if venue_col_idx >= len(row) or slot_col_idx >= len(row):
                continue
            
            venue_cell = row[venue_col_idx]
            slot_cell = row[slot_col_idx]
            
            venue_val = str(venue_cell.get('value', '') if isinstance(venue_cell, dict) else venue_cell).strip()
            slot_val = str(slot_cell.get('value', '') if isinstance(slot_cell, dict) else slot_cell).strip()
            
            if venue_val and slot_val:
                normalized_slot = normalize_time_slot(slot_val)
                key = (venue_val, normalized_slot)
                if key not in schedule:
                    schedule[key] = []
                schedule[key].append(row_idx)
        
        # Count actual conflicts
        actual_conflicts = sum(1 for rows in schedule.values() if len(rows) > 1)
        
        # If conflict column exists, check if it's accurate
        if conflict_col_idx is not None:
            correct_flags = 0
            total_flags = 0
            
            for row_idx in range(1, min(len(rows), 13)):
                if row_idx >= len(rows):
                    break
                
                row = rows[row_idx]
                if conflict_col_idx >= len(row):
                    continue
                
                conflict_cell = row[conflict_col_idx]
                conflict_val = str(conflict_cell.get('value', '') if isinstance(conflict_cell, dict) else conflict_cell).strip().upper()
                
                # Determine if this row actually has a conflict
                has_conflict = False
                if venue_col_idx < len(row) and slot_col_idx < len(row):
                    venue_val = str(row[venue_col_idx].get('value', '') if isinstance(row[venue_col_idx], dict) else row[venue_col_idx]).strip()
                    slot_val = str(row[slot_col_idx].get('value', '') if isinstance(row[slot_col_idx], dict) else row[slot_col_idx]).strip()
                    if venue_val and slot_val:
                        normalized_slot = normalize_time_slot(slot_val)
                        key = (venue_val, normalized_slot)
                        if key in schedule and len(schedule[key]) > 1:
                            has_conflict = True
                
                # Check if flag matches reality
                is_flagged = 'CONFLICT' in conflict_val or 'YES' in conflict_val or 'X' in conflict_val
                is_ok = 'OK' in conflict_val or 'NO' in conflict_val or conflict_val == ''
                
                if (has_conflict and is_flagged) or (not has_conflict and is_ok):
                    correct_flags += 1
                total_flags += 1
            
            flag_accuracy = correct_flags / total_flags if total_flags > 0 else 0
            success = flag_accuracy >= 0.8 or actual_conflicts == 0
            
            feedback = f"Conflict detection: {correct_flags}/{total_flags} flags correct | {actual_conflicts} actual conflicts"
        else:
            # No conflict column, just check if schedule is conflict-free
            success = actual_conflicts == 0
            if success:
                feedback = "✅ Schedule is conflict-free (no conflict column needed)"
            else:
                feedback = f"❌ {actual_conflicts} scheduling conflicts detected (no conflict column found)"
        
        return success, feedback, {
            'actual_conflicts': actual_conflicts,
            'has_conflict_column': conflict_col_idx is not None
        }
        
    except Exception as e:
        logger.error(f"Error verifying conflicts: {e}", exc_info=True)
        return False, f"Error checking conflicts: {str(e)}", {}


def verify_no_formula_errors(workbook: Dict, sheet_name: str) -> Tuple[bool, str, Dict]:
    """
    Verify that there are no formula errors (#REF!, #VALUE!, etc.).
    
    Returns:
        (success, feedback, details_dict)
    """
    try:
        rows = workbook['sheets'][sheet_name]
        error_cells = []
        total_cells = 0
        
        for row_idx, row in enumerate(rows[:13]):  # Check first 13 rows
            for col_idx, cell in enumerate(row):
                cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell)
                total_cells += 1
                
                # Check for common formula errors
                if any(err in cell_val.upper() for err in ['#REF!', '#VALUE!', '#DIV/0!', '#N/A', '#NAME?', '#NUM!']):
                    error_cells.append(f"Row {row_idx + 1}, Col {col_idx + 1}")
        
        success = len(error_cells) == 0
        
        if success:
            feedback = "✅ No formula errors detected"
        else:
            feedback = f"❌ {len(error_cells)} formula errors found"
            if len(error_cells) <= 3:
                feedback += f": {', '.join(error_cells)}"
        
        return success, feedback, {
            'error_count': len(error_cells),
            'total_cells': total_cells
        }
        
    except Exception as e:
        logger.error(f"Error checking formula errors: {e}", exc_info=True)
        return False, f"Error checking formulas: {str(e)}", {}


def verify_festival_scheduler(traj, env_info, task_info):
    """
    Main verifier for Festival Scheduler task.
    
    Checks:
    1. Duration standardization (mixed formats → minutes)
    2. Total block calculation (duration + 20 buffer)
    3. Venue assignment logic
    4. Time slot assignment (valid slots, fit within windows)
    5. Conflict detection
    6. No formula errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to find the output file
    temp_dir = None
    success = False
    workbook = None
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/festival_schedule.ods",
        "/home/ga/Documents/film_submissions.ods",
        "/home/ga/Documents/film_submissions.csv"
    ]
    
    for path in possible_paths:
        fmt = 'ods' if path.endswith('.ods') else 'csv'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=fmt
        )
        if success:
            logger.info(f"Successfully loaded file from: {path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load festival schedule file. Tried: {', '.join(possible_paths)}"
        }
    
    try:
        # Get sheet name
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        # Run all verification checks
        criteria_results = {}
        feedback_parts = []
        
        # 1. Duration standardization
        success1, feedback1, details1 = verify_duration_standardization(workbook, sheet_name)
        criteria_results['duration_standardization'] = success1
        feedback_parts.append(("✅" if success1 else "❌") + " " + feedback1)
        
        # 2. Time block calculation
        success2, feedback2, details2 = verify_time_block_calculation(workbook, sheet_name)
        criteria_results['time_block_calculation'] = success2
        feedback_parts.append(("✅" if success2 else "❌") + " " + feedback2)
        
        # 3. Venue assignment
        success3, feedback3, details3 = verify_venue_assignment(workbook, sheet_name)
        criteria_results['venue_assignment'] = success3
        feedback_parts.append(("✅" if success3 else "❌") + " " + feedback3)
        
        # 4. Time slot assignment
        success4, feedback4, details4 = verify_time_slot_assignment(workbook, sheet_name)
        criteria_results['time_slot_assignment'] = success4
        feedback_parts.append(("✅" if success4 else "❌") + " " + feedback4)
        
        # 5. Conflict detection
        success5, feedback5, details5 = verify_conflict_detection(workbook, sheet_name)
        criteria_results['conflict_detection'] = success5
        feedback_parts.append(("✅" if success5 else "❌") + " " + feedback5)
        
        # 6. No formula errors
        success6, feedback6, details6 = verify_no_formula_errors(workbook, sheet_name)
        criteria_results['no_formula_errors'] = success6
        feedback_parts.append(("✅" if success6 else "❌") + " " + feedback6)
        
        # Calculate score
        criteria_passed = sum(1 for v in criteria_results.values() if v)
        total_criteria = len(criteria_results)
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (need 5/6 criteria or equivalent)
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        if passed:
            feedback = f"🎉 Festival schedule completed! ({criteria_passed}/{total_criteria} criteria) | " + feedback
        else:
            feedback = f"Schedule incomplete ({criteria_passed}/{total_criteria} criteria) | " + feedback
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": criteria_results
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
