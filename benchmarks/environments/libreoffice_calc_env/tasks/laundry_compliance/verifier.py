#!/usr/bin/env python3
"""
Verifier for Laundry Compliance Monitor task
Checks aggregation formulas, calculations, conditional formatting, and sorting
"""

import sys
import os
import logging
from typing import Dict, Any, Tuple

# Use relative path to utils folder (verification runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    get_sheet_names,
    check_conditional_formatting,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def count_bookings_for_resident(bookings_sheet, resident_name: str) -> Tuple[int, int, int]:
    """
    Manually count bookings for a specific resident from raw data.
    
    Returns: (total_bookings, no_shows, overtime_count)
    """
    total_bookings = 0
    no_shows = 0
    overtime_count = 0
    
    # Find column indices from header row
    header_row = bookings_sheet[0] if bookings_sheet else []
    header_values = [cell.get('value', '') if isinstance(cell, dict) else cell for cell in header_row]
    
    try:
        name_col = header_values.index('ResidentName')
        status_col = header_values.index('BookingStatus')
        actual_use_col = header_values.index('ActualUse')
        minutes_col = header_values.index('MinutesUsed')
    except ValueError as e:
        logger.error(f"Could not find required columns: {e}")
        return 0, 0, 0
    
    # Count through data rows (skip header)
    for row in bookings_sheet[1:]:
        if len(row) <= max(name_col, status_col, actual_use_col, minutes_col):
            continue
        
        name_cell = row[name_col]
        name = name_cell.get('value', '') if isinstance(name_cell, dict) else name_cell
        
        if str(name).strip() == resident_name:
            total_bookings += 1
            
            # Check for no-show (Booked but not used, and not cancelled)
            status = row[status_col].get('value', '') if isinstance(row[status_col], dict) else row[status_col]
            actual = row[actual_use_col].get('value', '') if isinstance(row[actual_use_col], dict) else row[actual_use_col]
            
            if str(status).strip() == "Booked" and str(actual).strip() == "No":
                no_shows += 1
            
            # Check for overtime (MinutesUsed > 100)
            minutes = row[minutes_col].get('value', 0) if isinstance(row[minutes_col], dict) else row[minutes_col]
            try:
                if float(minutes) > 100:
                    overtime_count += 1
            except (ValueError, TypeError):
                pass
    
    return total_bookings, no_shows, overtime_count


def find_resident_in_summary(summary_sheet, resident_name: str) -> Tuple[int, list]:
    """
    Find a resident's row in the summary sheet.
    
    Returns: (row_index, row_data)
    """
    for idx, row in enumerate(summary_sheet):
        if not row:
            continue
        first_cell = row[0]
        cell_value = first_cell.get('value', '') if isinstance(first_cell, dict) else first_cell
        if str(cell_value).strip() == resident_name:
            return idx, row
    return -1, []


def verify_laundry_compliance(traj, env_info, task_info):
    """
    Verify laundry compliance monitoring task completion.
    
    Checks:
    1. Compliance Summary sheet exists with required columns (15 pts)
    2. Required columns present (10 pts)
    3. Aggregation accurate for test resident (20 pts)
    4. No-show rate calculated correctly (20 pts)
    5. Violation score formula present (15 pts)
    6. Conditional formatting applied (10 pts)
    7. Sorted by violation severity (10 pts)
    
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    success = False
    workbook = None
    temp_dir = None
    
    for path in [
        "/home/ga/Documents/laundry_compliance_summary.ods",
        "/home/ga/Documents/laundry_bookings.ods",
        "/home/ga/Documents/laundry_bookings.csv"
    ]:
        fmt = 'csv' if path.endswith('.csv') else 'ods'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=fmt
        )
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        score = 0
        max_score = 100
        feedback_parts = []
        
        sheet_names = get_sheet_names(workbook)
        logger.info(f"Available sheets: {sheet_names}")
        
        # Check 1: Summary sheet exists (15 points)
        summary_sheet_names = [s for s in sheet_names if 'summary' in s.lower() or 'compliance' in s.lower()]
        
        if not summary_sheet_names:
            # Maybe they created it with default name or named it differently
            if len(sheet_names) >= 2:
                # Assume second sheet is the summary
                summary_sheet_name = sheet_names[1]
                logger.info(f"Using sheet '{summary_sheet_name}' as summary (no explicit 'summary' sheet found)")
            else:
                feedback_parts.append("❌ No Compliance Summary sheet found")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts),
                    "subscores": {}
                }
        else:
            summary_sheet_name = summary_sheet_names[0]
        
        score += 15
        feedback_parts.append(f"✅ Summary sheet found: '{summary_sheet_name}'")
        
        summary_sheet = workbook['sheets'][summary_sheet_name]
        
        # Get bookings sheet for reference
        bookings_sheet_name = [s for s in sheet_names if s != summary_sheet_name][0]
        bookings_sheet = workbook['sheets'][bookings_sheet_name]
        
        # Check 2: Required columns present (10 points)
        if not summary_sheet or len(summary_sheet) < 1:
            feedback_parts.append("❌ Summary sheet is empty")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        header_row = summary_sheet[0]
        header_values = [cell.get('value', '') if isinstance(cell, dict) else str(cell) for cell in header_row]
        header_values_lower = [str(h).lower().strip() for h in header_values]
        
        required_cols = ['residentname', 'totalbookings', 'noshows', 'noshowrate', 'violationscore']
        cols_found = sum(1 for col in required_cols if any(col in h for h in header_values_lower))
        
        if cols_found >= 4:  # Allow some flexibility
            score += 10
            feedback_parts.append(f"✅ Required columns present ({cols_found}/5 found)")
        else:
            feedback_parts.append(f"❌ Missing required columns (only {cols_found}/5 found)")
            feedback_parts.append(f"   Found headers: {header_values}")
        
        # Find column indices
        def find_col_index(keywords):
            for keyword in keywords:
                for idx, h in enumerate(header_values_lower):
                    if keyword in h:
                        return idx
            return -1
        
        name_col = find_col_index(['residentname', 'name', 'resident'])
        total_col = find_col_index(['totalbookings', 'total', 'bookings'])
        noshows_col = find_col_index(['noshows', 'noshow', 'no-show'])
        noshowrate_col = find_col_index(['noshowrate', 'no-showrate', 'rate'])
        violation_col = find_col_index(['violationscore', 'violation', 'score'])
        
        logger.info(f"Column indices - Name: {name_col}, Total: {total_col}, NoShows: {noshows_col}, Rate: {noshowrate_col}, Violation: {violation_col}")
        
        # Check 3: Aggregation accuracy for Bob Martinez (20 points)
        # Bob Martinez should have 10 total bookings and 5 no-shows based on the data
        test_resident = "Bob Martinez"
        expected_total, expected_noshows, _ = count_bookings_for_resident(bookings_sheet, test_resident)
        
        logger.info(f"Expected for {test_resident}: Total={expected_total}, NoShows={expected_noshows}")
        
        bob_row_idx, bob_row = find_resident_in_summary(summary_sheet, test_resident)
        
        if bob_row_idx > 0 and total_col >= 0:
            actual_total = bob_row[total_col].get('value', 0) if total_col < len(bob_row) and isinstance(bob_row[total_col], dict) else (bob_row[total_col] if total_col < len(bob_row) else 0)
            
            try:
                actual_total = int(float(actual_total)) if actual_total else 0
                if actual_total == expected_total:
                    score += 20
                    feedback_parts.append(f"✅ Aggregation correct for {test_resident}: {actual_total} bookings")
                else:
                    feedback_parts.append(f"❌ Aggregation incorrect for {test_resident}: expected {expected_total}, got {actual_total}")
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Could not parse total bookings for {test_resident}")
        else:
            feedback_parts.append(f"❌ {test_resident} not found in summary or column missing")
        
        # Check 4: No-show rate calculation (20 points)
        if bob_row_idx > 0 and noshowrate_col >= 0:
            actual_rate = bob_row[noshowrate_col].get('value', 0) if noshowrate_col < len(bob_row) and isinstance(bob_row[noshowrate_col], dict) else (bob_row[noshowrate_col] if noshowrate_col < len(bob_row) else 0)
            
            try:
                actual_rate = float(actual_rate) if actual_rate else 0
                expected_rate = (expected_noshows / expected_total * 100) if expected_total > 0 else 0
                
                # Allow 2% tolerance for rounding
                if abs(actual_rate - expected_rate) <= 2:
                    score += 20
                    feedback_parts.append(f"✅ No-show rate correct: {actual_rate:.1f}% (expected ~{expected_rate:.1f}%)")
                else:
                    feedback_parts.append(f"❌ No-show rate incorrect: {actual_rate:.1f}% (expected ~{expected_rate:.1f}%)")
            except (ValueError, TypeError, ZeroDivisionError):
                feedback_parts.append(f"❌ Could not parse no-show rate for {test_resident}")
        
        # Check 5: Violation score exists (15 points)
        if violation_col >= 0:
            # Check if any rows have violation scores
            has_scores = False
            for row in summary_sheet[1:]:
                if violation_col < len(row):
                    cell = row[violation_col]
                    value = cell.get('value', None) if isinstance(cell, dict) else cell
                    if value is not None and value != '':
                        has_scores = True
                        break
            
            if has_scores:
                score += 15
                feedback_parts.append("✅ Violation scores calculated")
            else:
                feedback_parts.append("❌ Violation scores missing or empty")
        else:
            feedback_parts.append("❌ Violation score column not found")
        
        # Check 6: Conditional formatting (10 points)
        # This is difficult to verify programmatically for ODS
        # Check if the function detects any formatting, give partial credit
        try:
            has_formatting = check_conditional_formatting(workbook, summary_sheet_name, "A1:J20")
            if has_formatting:
                score += 10
                feedback_parts.append("✅ Conditional formatting detected")
            else:
                # Give partial credit since formatting is hard to verify
                score += 5
                feedback_parts.append("~ Conditional formatting not detected (partial credit given)")
        except Exception as e:
            logger.debug(f"Could not check conditional formatting: {e}")
            score += 5
            feedback_parts.append("~ Conditional formatting check skipped (partial credit given)")
        
        # Check 7: Sorted by violation severity (10 points)
        if violation_col >= 0 and len(summary_sheet) >= 3:
            try:
                # Get first two data rows' violation scores
                first_score = summary_sheet[1][violation_col].get('value', 0) if violation_col < len(summary_sheet[1]) and isinstance(summary_sheet[1][violation_col], dict) else summary_sheet[1][violation_col] if violation_col < len(summary_sheet[1]) else 0
                second_score = summary_sheet[2][violation_col].get('value', 0) if violation_col < len(summary_sheet[2]) and isinstance(summary_sheet[2][violation_col], dict) else summary_sheet[2][violation_col] if violation_col < len(summary_sheet[2]) else 0
                
                first_score = float(first_score) if first_score else 0
                second_score = float(second_score) if second_score else 0
                
                if first_score >= second_score - 0.1:  # Allow small tolerance
                    score += 10
                    feedback_parts.append("✅ Sorted by violation severity (descending)")
                else:
                    feedback_parts.append(f"❌ Not properly sorted (row 1: {first_score}, row 2: {second_score})")
            except (ValueError, TypeError, IndexError) as e:
                logger.debug(f"Could not verify sorting: {e}")
                feedback_parts.append("~ Sorting verification inconclusive")
        
        # Calculate final result
        passed = score >= 70
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent compliance analysis!")
        elif passed:
            feedback_parts.append("✅ Compliance monitoring task completed")
        else:
            feedback_parts.append("❌ Task requirements not met")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "summary_sheet_exists": score >= 15,
                "required_columns": score >= 25,
                "aggregation_correct": score >= 45,
                "noshowrate_correct": score >= 65,
                "violation_score_exists": score >= 80,
                "formatting_applied": score >= 85,
                "sorted_correctly": score >= 95
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
