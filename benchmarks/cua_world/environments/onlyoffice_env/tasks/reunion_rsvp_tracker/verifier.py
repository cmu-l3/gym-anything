#!/usr/bin/env python3
"""
Verifier for Reunion RSVP Tracker task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_reunion_rsvp_tracker(traj, env_info, task_info):
    """
    Verify reunion RSVP tracker spreadsheet task.

    Checks:
    1. File exists and is valid XLSX
    2. Required column headers present
    3. Correct number of data rows (~8 classmates)
    4. Key classmate names present (spot checks)
    5. Summary section with correct formulas:
       - Total Confirmed (should be 6)
       - Total Headcount (should be 9)
       - Expected Revenue (should be ~$405)
    6. Currency formatting applied
    7. Bold headers
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/reunion_tracker.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_reunion_')

    try:
        # Check 1: File exists and parses
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Could not find or parse reunion_tracker.xlsx: {error}"
            }

        feedback_parts = []
        score = 0
        max_score = 10
        
        score += 1
        feedback_parts.append("✅ File exists and is valid XLSX")

        # Get first sheet
        sheet_names = wb.sheetnames
        if not sheet_names:
            return {
                "passed": False,
                "score": 0.1,
                "feedback": "❌ Spreadsheet has no sheets"
            }
        
        sheet = wb[sheet_names[0]]

        # Check 2: Column headers present
        # Read first few rows to find headers
        header_row = None
        header_row_idx = None
        
        for row_idx in range(1, 5):  # Check first 4 rows for headers
            row_values = [cell.value for cell in sheet[row_idx] if cell.value]
            row_text = " ".join([str(v).lower() for v in row_values if v])
            
            # Check if this looks like a header row
            header_indicators = ["last name", "first name", "rsvp", "guest", "meal"]
            matches = sum(1 for indicator in header_indicators if indicator in row_text)
            
            if matches >= 3:
                header_row = row_values
                header_row_idx = row_idx
                break
        
        if header_row:
            score += 1
            feedback_parts.append(f"✅ Column headers found (row {header_row_idx})")
        else:
            feedback_parts.append("❌ Could not find column headers")
            return {
                "passed": False,
                "score": score / max_score,
                "feedback": " | ".join(feedback_parts)
            }

        # Check 3: Data rows (should have ~8 classmates)
        data_start_row = header_row_idx + 1 if header_row_idx else 2
        data_rows = []
        
        for row_idx in range(data_start_row, min(data_start_row + 20, sheet.max_row + 1)):
            row_data = [cell.value for cell in sheet[row_idx]]
            # Check if row has substantial data (at least 3 non-empty cells in first 8 columns)
            non_empty = sum(1 for cell in row_data[:8] if cell is not None and str(cell).strip() and str(cell).strip() not in ['-', 'N/A', ''])
            
            if non_empty >= 3:
                # Check this isn't a summary row by looking for summary keywords
                row_text = " ".join([str(cell).lower() for cell in row_data[:8] if cell])
                if not any(keyword in row_text for keyword in ["total", "confirmed", "summary", "headcount", "revenue", "cost", "meals", "vegetarian", "chicken", "beef"]):
                    data_rows.append(row_data)

        num_data_rows = len(data_rows)
        if 7 <= num_data_rows <= 10:
            score += 1.5
            feedback_parts.append(f"✅ Data rows present ({num_data_rows} rows, expected ~8)")
        elif 5 <= num_data_rows < 7 or 10 < num_data_rows <= 12:
            score += 0.75
            feedback_parts.append(f"⚠️ Acceptable number of data rows ({num_data_rows}, expected ~8)")
        else:
            feedback_parts.append(f"❌ Insufficient or too many data rows (found {num_data_rows}, expected ~8)")

        # Check 4: Key names present (spot check)
        all_cell_text = ""
        for row_idx in range(1, min(25, sheet.max_row + 1)):
            for cell in sheet[row_idx]:
                if cell.value:
                    all_cell_text += str(cell.value).lower() + " "

        key_names = ["chen", "rodriguez", "thompson"]
        names_found = [name for name in key_names if name in all_cell_text]
        
        if len(names_found) >= 3:
            score += 1.5
            feedback_parts.append(f"✅ Key classmate names found (Chen, Rodriguez, Thompson)")
        elif len(names_found) >= 2:
            score += 1
            feedback_parts.append(f"⚠️ Most key names found ({len(names_found)}/3)")
        else:
            feedback_parts.append(f"❌ Missing key classmate names (found {len(names_found)}/3)")

        # Check 5: Summary section - look for summary labels and their values
        # We need to find: Total Confirmed (~6), Total Headcount (~9), Revenue (~405)
        
        confirmed_count_found = False
        headcount_found = False
        revenue_found = False
        
        # Scan all cells for summary section
        for row_idx in range(1, min(35, sheet.max_row + 1)):
            for col_idx in range(1, 6):  # Check first 5 columns
                try:
                    cell = sheet.cell(row_idx, col_idx)
                    if cell.value and isinstance(cell.value, str):
                        cell_text = str(cell.value).lower().strip()
                        
                        # Check for "Total Confirmed" or similar
                        if ("confirmed" in cell_text or "total yes" in cell_text) and "total" in cell_text:
                            # Check adjacent cells for the value
                            for offset in [1, 2]:
                                value_cell = sheet.cell(row_idx, col_idx + offset)
                                if value_cell.value is not None:
                                    try:
                                        val = float(value_cell.value) if value_cell.value is not None else None
                                        if val is not None and 5 <= val <= 7:
                                            confirmed_count_found = True
                                            break
                                    except:
                                        pass
                        
                        # Check for "Total Headcount" or "Total Attendees"
                        if (("headcount" in cell_text or "attendees" in cell_text or "people" in cell_text) and "total" in cell_text) or \
                           (cell_text == "total" and row_idx > data_start_row + 8):  # Likely summary
                            for offset in [1, 2]:
                                value_cell = sheet.cell(row_idx, col_idx + offset)
                                if value_cell.value is not None:
                                    try:
                                        val = float(value_cell.value) if value_cell.value is not None else None
                                        if val is not None and 8 <= val <= 10:
                                            headcount_found = True
                                            break
                                    except:
                                        pass
                        
                        # Check for "Revenue" or "Total Cost"
                        if "revenue" in cell_text or ("total" in cell_text and "cost" in cell_text) or "total amount" in cell_text:
                            for offset in [1, 2]:
                                value_cell = sheet.cell(row_idx, col_idx + offset)
                                if value_cell.value is not None:
                                    try:
                                        val = float(value_cell.value) if value_cell.value is not None else None
                                        if val is not None and 360 <= val <= 450:  # Allow some variance
                                            revenue_found = True
                                            break
                                    except:
                                        pass
                
                except Exception as e:
                    continue

        summary_score = 0
        if confirmed_count_found:
            summary_score += 1
            feedback_parts.append("✅ Total Confirmed count found (~6)")
        else:
            feedback_parts.append("❌ Total Confirmed count not found")

        if headcount_found:
            summary_score += 1
            feedback_parts.append("✅ Total Headcount found (~9)")
        else:
            feedback_parts.append("❌ Total Headcount not found")

        if revenue_found:
            summary_score += 1.5
            feedback_parts.append("✅ Expected Revenue calculation found (~$405)")
        else:
            feedback_parts.append("❌ Expected Revenue calculation not found")

        score += summary_score

        # Check 6: Currency formatting
        currency_formatted = False
        for row_idx in range(1, min(35, sheet.max_row + 1)):
            for cell in sheet[row_idx]:
                if cell.number_format:
                    # Check for currency symbols in number format
                    if any(symbol in str(cell.number_format) for symbol in ['$', '€', '£', 'currency', 'accounting']):
                        currency_formatted = True
                        break
            if currency_formatted:
                break

        if currency_formatted:
            score += 1
            feedback_parts.append("✅ Currency formatting applied")
        else:
            feedback_parts.append("⚠️ No currency formatting detected")

        # Check 7: Bold headers
        headers_bold = False
        if header_row_idx:
            for cell in sheet[header_row_idx]:
                if cell.value and cell.font and cell.font.bold:
                    headers_bold = True
                    break

        if headers_bold:
            score += 1
            feedback_parts.append("✅ Bold formatting applied to headers")
        else:
            feedback_parts.append("⚠️ Headers not bold")

        # Calculate final result
        normalized_score = score / max_score
        passed = normalized_score >= 0.7  # Need at least 70% to pass

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)