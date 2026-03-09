#!/usr/bin/env python3
"""
Verifier for band_gig_manager@1 task

Checks that the spreadsheet has three sheets with appropriate:
- Gig tracking with payment formulas and totals
- Equipment inventory with maintenance date calculations
- Set list archive with song data
"""

import sys
import os
import logging
import tempfile
from datetime import datetime, timedelta
from typing import Dict, Any, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    get_sheet_data,
    count_filled_cells,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_for_formula_pattern(sheet, row_idx: int, col_idx: int, total_col: int, divisor: int = 4) -> bool:
    """
    Check if a cell contains a value that appears to be result of division formula.
    Since openpyxl with data_only=True shows values not formulas, we check if the value
    is approximately total/divisor.
    """
    try:
        cell_value = sheet.cell(row_idx, col_idx).value
        total_value = sheet.cell(row_idx, total_col).value
        
        if cell_value is None or total_value is None:
            return False
        
        if not isinstance(cell_value, (int, float)) or not isinstance(total_value, (int, float)):
            return False
        
        expected = total_value / divisor
        # Allow small rounding errors
        return abs(cell_value - expected) < 1.0
    except Exception as e:
        logger.debug(f"Error checking formula pattern: {e}")
        return False


def check_for_sum_formula(sheet, row_idx: int, col_idx: int, start_row: int, end_row: int) -> bool:
    """
    Check if a cell appears to contain a SUM formula result by verifying
    the value equals the sum of cells above it.
    """
    try:
        cell_value = sheet.cell(row_idx, col_idx).value
        
        if cell_value is None or not isinstance(cell_value, (int, float)):
            return False
        
        # Calculate sum of values in range
        calculated_sum = 0
        for r in range(start_row, end_row + 1):
            val = sheet.cell(r, col_idx).value
            if val and isinstance(val, (int, float)):
                calculated_sum += val
        
        # Check if cell value matches calculated sum (within tolerance)
        return abs(cell_value - calculated_sum) < 1.0
    except Exception as e:
        logger.debug(f"Error checking sum formula: {e}")
        return False


def check_for_date_formula(sheet, row_idx: int, last_maint_col: int, due_col: int, months: int = 6) -> bool:
    """
    Check if maintenance due date appears to be calculated as approximately
    'months' months after last maintenance date.
    """
    try:
        last_maint = sheet.cell(row_idx, last_maint_col).value
        due_date = sheet.cell(row_idx, due_col).value
        
        if last_maint is None or due_date is None:
            return False
        
        # Handle various date formats
        if isinstance(last_maint, datetime) and isinstance(due_date, datetime):
            diff_days = (due_date - last_maint).days
            # 6 months is approximately 180 days, allow range 150-210 days
            expected_min = months * 25  # ~150 days for 6 months
            expected_max = months * 35  # ~210 days for 6 months
            return expected_min <= diff_days <= expected_max
        
        return False
    except Exception as e:
        logger.debug(f"Error checking date formula: {e}")
        return False


def count_data_rows(sheet_data, min_cols: int = 2, skip_header: bool = True) -> int:
    """
    Count rows that have meaningful data (not empty or just whitespace).
    """
    count = 0
    start_idx = 1 if skip_header else 0
    
    for row in sheet_data[start_idx:]:
        # Check if row has data in at least min_cols columns
        non_empty = 0
        for cell in row[:min_cols * 2]:  # Check a reasonable range
            if cell is not None and str(cell).strip() != '':
                non_empty += 1
        
        if non_empty >= min_cols:
            count += 1
    
    return count


def verify_band_gig_manager(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify the band management spreadsheet task.
    
    Checks:
    1. File exists and has three required sheets
    2. Gig Log has 4+ gig entries with payment data
    3. Payment splits use formulas (division by 4)
    4. Total earnings row uses SUM formulas
    5. Equipment sheet has 5+ items
    6. Equipment has maintenance due date formulas (6 months calculation)
    7. Set Lists sheet has 3+ different configurations
    8. Set lists contain meaningful song data
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}
    
    filepath = "/home/ga/Documents/Spreadsheets/band_manager.xlsx"
    feedback_parts = []
    score = 0.0
    
    temp_file = None
    
    try:
        # Create temp file for copying
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
        temp_path = temp_file.name
        temp_file.close()
        
        # Copy file from container
        try:
            copy_from_env(filepath, temp_path)
        except Exception as e:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to copy file from container: {e}"
            }
        
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"File not found or empty: {filepath}"
            }
        
        # Parse workbook (data_only=True to get calculated values)
        wb = parse_xlsx_file(temp_path)
        if wb is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Failed to parse XLSX file - file may be corrupted"
            }
        
        # Check sheet names (case-insensitive)
        sheet_names_lower = [s.lower() for s in wb.sheetnames]
        required_sheets = {
            "gig log": "Gig Log",
            "equipment": "Equipment", 
            "set lists": "Set Lists"
        }
        
        actual_sheet_names = {}
        for req_lower, req_display in required_sheets.items():
            found = False
            for actual in wb.sheetnames:
                if actual.lower() == req_lower:
                    actual_sheet_names[req_lower] = actual
                    found = True
                    break
            if not found:
                feedback_parts.append(f"❌ Missing required sheet: '{req_display}'")
                return {
                    "passed": False,
                    "score": 0.0,
                    "feedback": " | ".join(feedback_parts)
                }
        
        feedback_parts.append("✅ All three required sheets present")
        score += 10.0
        
        # ===== VERIFY GIG LOG SHEET =====
        gig_sheet_name = actual_sheet_names["gig log"]
        gig_sheet = wb[gig_sheet_name]
        gig_data = get_sheet_data(wb, gig_sheet_name, max_rows=30, max_cols=10)
        
        # Count gig entries (rows with date and venue data)
        gig_rows = count_data_rows(gig_data, min_cols=2, skip_header=True)
        
        # Adjust for the total row - need actual gig entries
        # Look for rows before any "TOTAL" row
        actual_gig_rows = 0
        for i, row in enumerate(gig_data[1:], start=2):  # Skip header
            # Check if this is a total row
            first_cell = str(row[0]).lower() if row[0] else ""
            if "total" in first_cell:
                break
            # Check if row has meaningful gig data (at least venue and payment)
            if row[0] is not None or row[1] is not None:  # Date or venue
                if row[2] is not None:  # Total payment
                    actual_gig_rows += 1
        
        if actual_gig_rows >= 4:
            feedback_parts.append(f"✅ Gig Log has {actual_gig_rows} gig entries (required: 4+)")
            score += 20.0
        else:
            feedback_parts.append(f"❌ Gig Log has only {actual_gig_rows} gig entries (required: 4+)")
        
        # Check for payment formulas (division by 4) in multiple rows
        payment_formula_found = False
        payment_cols = [4, 5, 6, 7]  # Guitarist, Bassist, Drummer, Vocalist
        
        for row_idx in range(2, min(15, len(gig_data) + 1)):
            # Skip if this looks like a total row
            first_cell_val = gig_sheet.cell(row_idx, 1).value
            if first_cell_val and "total" in str(first_cell_val).lower():
                continue
            
            # Check if any payment column uses formula pattern
            for col_idx in payment_cols:
                if check_for_formula_pattern(gig_sheet, row_idx, col_idx, 3, 4):
                    payment_formula_found = True
                    break
            
            if payment_formula_found:
                break
        
        if payment_formula_found:
            feedback_parts.append("✅ Payment splits appear to use formulas (dividing by 4)")
            score += 20.0
        else:
            feedback_parts.append("⚠️ Payment splits should be calculated with formulas (e.g., =C2/4)")
            score += 5.0  # Partial credit
        
        # Check for SUM formulas in totals row
        sum_formula_found = False
        
        # Look for total row (typically has "TOTAL" in first column)
        total_row_idx = None
        for row_idx in range(2, min(20, len(gig_data) + 1)):
            cell_val = gig_sheet.cell(row_idx, 1).value
            if cell_val and "total" in str(cell_val).lower():
                total_row_idx = row_idx
                break
        
        if total_row_idx:
            # Check if any payment column has SUM formula
            for col_idx in payment_cols:
                if check_for_sum_formula(gig_sheet, total_row_idx, col_idx, 2, total_row_idx - 1):
                    sum_formula_found = True
                    break
        
        if sum_formula_found:
            feedback_parts.append("✅ Total earnings row uses SUM formulas")
            score += 15.0
        else:
            feedback_parts.append("⚠️ Should include total earnings per member using SUM formulas")
            score += 3.0  # Partial credit if total row exists at all
        
        # ===== VERIFY EQUIPMENT SHEET =====
        equip_sheet_name = actual_sheet_names["equipment"]
        equip_sheet = wb[equip_sheet_name]
        equip_data = get_sheet_data(wb, equip_sheet_name, max_rows=30, max_cols=10)
        
        # Count equipment entries
        equip_rows = count_data_rows(equip_data, min_cols=2, skip_header=True)
        
        if equip_rows >= 5:
            feedback_parts.append(f"✅ Equipment inventory has {equip_rows} items (required: 5+)")
            score += 15.0
        else:
            feedback_parts.append(f"❌ Equipment inventory has only {equip_rows} items (required: 5+)")
            score += int((equip_rows / 5) * 15)  # Partial credit
        
        # Check for maintenance due date formula (6 months calculation)
        maint_formula_found = False
        
        # Columns: Item, Owner, Purchase, Warranty, Last Maint, Due Date, Cost
        # Last Maintenance likely column 5, Due Date likely column 6
        last_maint_col = 5
        due_col = 6
        
        for row_idx in range(2, min(15, len(equip_data) + 1)):
            if check_for_date_formula(equip_sheet, row_idx, last_maint_col, due_col, 6):
                maint_formula_found = True
                break
        
        if maint_formula_found:
            feedback_parts.append("✅ Maintenance due dates calculated with formulas (~6 months)")
            score += 15.0
        else:
            feedback_parts.append("⚠️ Maintenance due dates should be calculated (6 months after last maintenance)")
            score += 3.0  # Partial credit if dates exist
        
        # ===== VERIFY SET LISTS SHEET =====
        setlist_sheet_name = actual_sheet_names["set lists"]
        setlist_sheet = wb[setlist_sheet_name]
        setlist_data = get_sheet_data(wb, setlist_sheet_name, max_rows=30, max_cols=10)
        
        # Count set list entries
        setlist_rows = count_data_rows(setlist_data, min_cols=2, skip_header=True)
        
        if setlist_rows >= 3:
            feedback_parts.append(f"✅ Set Lists sheet has {setlist_rows} set configurations (required: 3+)")
            score += 10.0
        else:
            feedback_parts.append(f"❌ Set Lists sheet has only {setlist_rows} configurations (required: 3+)")
            score += int((setlist_rows / 3) * 10)  # Partial credit
        
        # Check that set lists contain meaningful song data (at least 8 songs per set)
        sets_with_songs = 0
        
        for i, row in enumerate(setlist_data[1:], start=2):
            # Songs typically in column 2 (index 1)
            songs_cell = row[1] if len(row) > 1 else None
            
            if songs_cell and isinstance(songs_cell, str):
                # Count commas or song names (rough heuristic)
                song_count = songs_cell.count(',') + 1
                # Or check length
                if song_count >= 5 or len(songs_cell) > 50:
                    sets_with_songs += 1
        
        if sets_with_songs >= 2:
            feedback_parts.append(f"✅ Set lists contain song information ({sets_with_songs} sets with songs)")
            score += 5.0
        else:
            feedback_parts.append("⚠️ Set lists should include actual song names (8+ songs per set)")
        
        # Final scoring
        passed = score >= 70.0
        
        # Cleanup
        if temp_path and os.path.exists(temp_path):
            os.unlink(temp_path)
        
        return {
            "passed": passed,
            "score": round(score, 1),
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.exception("Error during verification")
        
        # Cleanup on error
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
        
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }


# Entry point for gym-anything
verify_task = verify_band_gig_manager