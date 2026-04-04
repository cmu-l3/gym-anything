#!/usr/bin/env python3
"""
Verifier for youth_soccer_carpool@1 task
Checks if carpool coordination spreadsheet meets requirements
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_youth_soccer_carpool(traj, env_info, task_info):
    """
    Verify the carpool coordination spreadsheet meets requirements.
    
    Checks:
    1. Has proper column headers (Date, Time, Event Type, Driver, Kids/Passengers, Contact)
    2. Contains at least 8 scheduled events (April schedule)
    3. All or most driver assignments are filled in
    4. Has a formula counting driver assignments (fairness tracking)
    5. Contact information column exists with data
    6. Data is organized in clear tabular format
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/soccer_carpool_april.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_carpool_')

    try:
        # Copy and parse the spreadsheet
        success, workbook, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            'xlsx'
        )

        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to parse spreadsheet: {error}"
            }

        # Get the active sheet
        sheet_name = workbook.sheetnames[0]
        sheet = workbook[sheet_name]

        feedback_parts = []
        score = 0.0
        max_score = 6.0

        # Get all data from the sheet
        data = get_sheet_data(workbook, sheet_name, max_rows=100, max_cols=15)

        if not data or len(data) < 5:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Spreadsheet appears empty or has insufficient data"
            }

        # Helper function to check if a cell contains a keyword
        def cell_contains_keyword(cell_value, keywords):
            if cell_value is None:
                return False
            cell_text = str(cell_value).lower().strip()
            return any(keyword.lower() in cell_text for keyword in keywords)

        # Criterion 1: Check for proper column headers
        # Look for header row with required keywords
        header_row_idx = None
        header_keywords = {
            'date': ['date', 'day', 'when'],
            'time': ['time', 'hour', 'clock'],
            'event': ['event', 'type', 'practice', 'game'],
            'driver': ['driver', 'parent', 'who'],
            'passenger': ['passenger', 'kid', 'child', 'player'],
            'contact': ['contact', 'phone', 'number', 'emergency']
        }

        best_header_score = 0
        best_header_idx = None

        for idx in range(min(25, len(data))):  # Check first 25 rows
            row = data[idx]
            if not row:
                continue
            
            # Count how many header keywords this row contains
            matches = 0
            for category, keywords in header_keywords.items():
                if any(cell_contains_keyword(cell, keywords) for cell in row[:12]):
                    matches += 1
            
            if matches > best_header_score:
                best_header_score = matches
                best_header_idx = idx

        if best_header_score >= 4:  # Need at least 4 out of 6 categories
            header_row_idx = best_header_idx
            score += 1.0
            feedback_parts.append(f"✅ Found proper column headers (row {header_row_idx + 1})")
        else:
            feedback_parts.append(f"❌ Missing proper column headers (found {best_header_score}/6 expected categories)")

        # Criterion 2: Count event entries (rows with substantial schedule data)
        event_count = 0
        event_rows = []

        if header_row_idx is not None:
            # Look for data rows after the header
            for idx in range(header_row_idx + 1, min(header_row_idx + 30, len(data))):
                row = data[idx]
                if not row:
                    continue

                # Check if row has substantial content (at least 3 non-empty, non-template cells)
                non_empty_count = 0
                has_date_like = False
                
                for cell in row[:10]:
                    if cell is not None:
                        cell_str = str(cell).strip()
                        if cell_str and len(cell_str) > 0:
                            # Exclude template text
                            if 'create' not in cell_str.lower() and '>>>' not in cell_str:
                                non_empty_count += 1
                                
                                # Check if cell looks like a date
                                if any(month in cell_str.lower() for month in ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec']):
                                    has_date_like = True
                                elif re.search(r'\d{1,2}[/-]\d{1,2}', cell_str):
                                    has_date_like = True

                # Count as event if has enough data
                if non_empty_count >= 3:
                    event_count += 1
                    event_rows.append(idx)

        if event_count >= 8:
            score += 1.5
            feedback_parts.append(f"✅ Contains {event_count} scheduled events (≥8 required)")
        elif event_count >= 6:
            score += 1.0
            feedback_parts.append(f"⚠️  Contains {event_count} events (need 8, but close)")
        else:
            feedback_parts.append(f"❌ Only {event_count} events found (need at least 8 for April schedule)")

        # Criterion 3: Check driver assignments are filled
        driver_col_idx = None
        if header_row_idx is not None:
            header_row = data[header_row_idx]
            for col_idx, cell in enumerate(header_row[:12]):
                if cell_contains_keyword(cell, ['driver', 'parent', 'who']):
                    driver_col_idx = col_idx
                    break

        filled_drivers = 0
        if driver_col_idx is not None and event_count > 0:
            for row_idx in event_rows:
                if row_idx < len(data) and driver_col_idx < len(data[row_idx]):
                    cell_value = data[row_idx][driver_col_idx]
                    if cell_value and str(cell_value).strip():
                        # Check it's not template text
                        if 'create' not in str(cell_value).lower() and '>>>' not in str(cell_value):
                            filled_drivers += 1

            driver_fill_rate = filled_drivers / event_count if event_count > 0 else 0
            if driver_fill_rate >= 0.75:  # 75% of events have drivers
                score += 1.0
                feedback_parts.append(f"✅ Driver assignments present ({filled_drivers}/{event_count} events)")
            elif driver_fill_rate >= 0.5:
                score += 0.5
                feedback_parts.append(f"⚠️  Some driver assignments ({filled_drivers}/{event_count} events)")
            else:
                feedback_parts.append(f"❌ Insufficient driver assignments ({filled_drivers}/{event_count} events)")
        else:
            feedback_parts.append("❌ Could not locate driver column or no events found")

        # Criterion 4: Check for formula (COUNTIF, COUNTIFS, or other counting formula)
        has_formula = False
        formula_location = None
        formula_type = None

        for row_idx, row in enumerate(sheet.iter_rows(max_row=100, max_col=15)):
            for col_idx, cell in enumerate(row):
                if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                    has_formula = True
                    formula_location = f"{chr(65 + col_idx)}{row_idx + 1}"
                    formula_type = cell.value[:20]
                    break
            if has_formula:
                break

        if has_formula:
            score += 1.0
            feedback_parts.append(f"✅ Contains formula for tracking (at {formula_location})")
        else:
            feedback_parts.append("❌ No formula found for driver fairness tracking (e.g., COUNTIF)")

        # Criterion 5: Check for contact information column
        contact_col_idx = None
        if header_row_idx is not None:
            header_row = data[header_row_idx]
            for col_idx, cell in enumerate(header_row[:12]):
                if cell_contains_keyword(cell, ['contact', 'phone', 'number', 'emergency']):
                    contact_col_idx = col_idx
                    break

        filled_contacts = 0
        if contact_col_idx is not None:
            for row_idx in event_rows[:15]:  # Check first 15 events
                if row_idx < len(data) and contact_col_idx < len(data[row_idx]):
                    cell_value = data[row_idx][contact_col_idx]
                    if cell_value and str(cell_value).strip():
                        cell_str = str(cell_value).strip()
                        # Check if it looks like contact info (has numbers or @ symbol)
                        if re.search(r'\d', cell_str) or '@' in cell_str:
                            filled_contacts += 1

            if filled_contacts >= 3:
                score += 0.75
                feedback_parts.append(f"✅ Contact information present ({filled_contacts} entries)")
            elif filled_contacts >= 1:
                score += 0.4
                feedback_parts.append(f"⚠️  Limited contact information ({filled_contacts} entries)")
            else:
                feedback_parts.append(f"❌ No valid contact information found")
        else:
            feedback_parts.append("❌ Could not locate contact information column")

        # Criterion 6: Check overall organization (reasonable structure)
        if header_row_idx is not None and event_count >= 5:
            # Check that data uses multiple columns
            max_cols_used = 0
            for row_idx in event_rows[:15]:
                if row_idx < len(data):
                    cols_in_row = sum(1 for cell in data[row_idx][:12] 
                                     if cell is not None and str(cell).strip())
                    max_cols_used = max(max_cols_used, cols_in_row)

            if max_cols_used >= 4:
                score += 0.75
                feedback_parts.append("✅ Well-organized tabular structure")
            elif max_cols_used >= 3:
                score += 0.4
                feedback_parts.append("⚠️  Basic tabular structure present")
            else:
                feedback_parts.append("⚠️  Spreadsheet could be better organized")
        else:
            feedback_parts.append("⚠️  Unable to assess overall organization")

        # Calculate final result
        normalized_score = min(score / max_score, 1.0)
        passed = normalized_score >= 0.65  # Pass threshold: 65%

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": round(normalized_score * 100),
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
