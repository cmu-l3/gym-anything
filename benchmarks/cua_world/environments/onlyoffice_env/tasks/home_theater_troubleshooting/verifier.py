#!/usr/bin/env python3
"""
Verifier for Home Theater Troubleshooting Log task

Checks:
1. File exists at correct path
2. Has proper column headers (Date, Equipment/Source, Symptom, Action Taken, Result)
3. Has at least 8 data rows with troubleshooting incidents
4. Contains a COUNTIF formula (or similar) counting symptoms
5. Has conditional formatting applied
6. Data is sorted chronologically by date
7. Data accuracy - entries match source notes
"""

import sys
import os
import logging
import tempfile
import re
from datetime import datetime
from typing import Dict, List, Tuple, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_header(header: str) -> str:
    """Normalize header text for comparison"""
    if not header:
        return ""
    return str(header).lower().strip().replace('/', '').replace('-', '').replace('_', '')


def check_headers(workbook, sheet_name: str) -> Tuple[bool, List[str], str]:
    """
    Check if spreadsheet has required column headers.
    Returns: (has_required_headers, found_headers, feedback)
    """
    try:
        sheet = workbook[sheet_name]
        
        # Get first row (headers)
        headers = []
        for col_idx in range(1, 10):  # Check first 9 columns
            cell_value = sheet.cell(row=1, column=col_idx).value
            if cell_value:
                headers.append(str(cell_value))
            else:
                headers.append("")
        
        # Normalize headers
        normalized = [normalize_header(h) for h in headers]
        
        # Required headers (flexible matching)
        required = {
            'date': ['date', 'datetime', 'when'],
            'equipment': ['equipment', 'source', 'equipmentsource', 'device'],
            'symptom': ['symptom', 'problem', 'issue', 'error'],
            'action': ['action', 'actiontaken', 'fix', 'solution', 'tried', 'attempted'],
            'result': ['result', 'outcome', 'status', 'success']
        }
        
        found_required = {
            'date': False,
            'equipment': False,
            'symptom': False,
            'action': False,
            'result': False
        }
        
        for norm_header in normalized:
            for req_key, variations in required.items():
                if any(var in norm_header for var in variations):
                    found_required[req_key] = True
        
        all_found = all(found_required.values())
        
        if all_found:
            feedback = f"✅ All required headers found: {', '.join(headers[:5])}"
        else:
            missing = [k for k, v in found_required.items() if not v]
            feedback = f"❌ Missing headers: {', '.join(missing)}. Found: {', '.join(headers[:5])}"
        
        return all_found, headers, feedback
        
    except Exception as e:
        logger.error(f"Error checking headers: {e}")
        return False, [], f"❌ Error reading headers: {str(e)}"


def count_data_rows(workbook, sheet_name: str) -> Tuple[int, str]:
    """
    Count number of filled data rows (excluding header).
    Returns: (row_count, feedback)
    """
    try:
        sheet = workbook[sheet_name]
        
        row_count = 0
        for row_idx in range(2, 50):  # Check up to row 50
            # Check if at least 3 columns have data in this row
            filled_cols = 0
            for col_idx in range(1, 6):
                cell_value = sheet.cell(row=row_idx, column=col_idx).value
                if cell_value and str(cell_value).strip():
                    filled_cols += 1
            
            if filled_cols >= 3:
                row_count += 1
            elif row_count > 0:
                # Stop counting if we hit empty rows after finding data
                break
        
        if row_count >= 8:
            feedback = f"✅ Found {row_count} data rows (required: 8)"
        else:
            feedback = f"❌ Found only {row_count} data rows (required: 8)"
        
        return row_count, feedback
        
    except Exception as e:
        logger.error(f"Error counting rows: {e}")
        return 0, f"❌ Error counting rows: {str(e)}"


def check_formula_exists(workbook, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if a COUNTIF formula exists anywhere in the sheet.
    Returns: (formula_found, feedback)
    """
    try:
        # Need to load workbook with data_only=False to see formulas
        sheet = workbook[sheet_name]
        
        formula_found = False
        formula_location = None
        
        # Search for COUNTIF in formula cells
        for row_idx in range(1, 30):
            for col_idx in range(1, 15):
                cell = sheet.cell(row=row_idx, column=col_idx)
                
                # Check if cell has a formula
                if cell.data_type == 'f':  # Formula type
                    formula = str(cell.value).upper()
                    if 'COUNTIF' in formula or 'COUNTIFS' in formula:
                        formula_found = True
                        formula_location = f"{chr(64+col_idx)}{row_idx}"
                        logger.info(f"Found COUNTIF formula at {formula_location}: {cell.value}")
                        break
                # Also check for manual counting that might be correct
                elif cell.data_type == 'n' and isinstance(cell.value, (int, float)):
                    # Could be result of a formula - check nearby cells for labels
                    pass
            
            if formula_found:
                break
        
        if formula_found:
            feedback = f"✅ COUNTIF formula found at {formula_location}"
        else:
            # Be lenient - check if there's any numeric count labeled appropriately
            feedback = "❌ No COUNTIF formula found (partial credit if count is present)"
        
        return formula_found, feedback
        
    except Exception as e:
        logger.error(f"Error checking formulas: {e}")
        return False, f"❌ Error checking formulas: {str(e)}"


def check_conditional_formatting(workbook, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if conditional formatting is applied to the sheet.
    Returns: (formatting_found, feedback)
    """
    try:
        sheet = workbook[sheet_name]
        
        # Check if any conditional formatting rules exist
        if hasattr(sheet, 'conditional_formatting') and sheet.conditional_formatting:
            cf_rules = sheet.conditional_formatting
            if len(cf_rules.cf_rules) > 0:
                return True, f"✅ Conditional formatting applied ({len(cf_rules.cf_rules)} rule(s))"
        
        # Alternative check: look for cells with background colors in data rows
        colored_cells = 0
        for row_idx in range(2, 20):
            for col_idx in range(1, 6):
                cell = sheet.cell(row=row_idx, column=col_idx)
                if cell.fill and cell.fill.start_color and cell.fill.start_color.rgb:
                    color = cell.fill.start_color.rgb
                    # Check if it's not white (default)
                    if color and color.upper() not in ['FFFFFF', '00FFFFFF', 'FFFFFFFF']:
                        colored_cells += 1
        
        if colored_cells >= 2:
            return True, f"✅ Conditional formatting detected (found {colored_cells} highlighted cells)"
        
        return False, "❌ No conditional formatting detected"
        
    except Exception as e:
        logger.error(f"Error checking conditional formatting: {e}")
        return False, f"❌ Error checking formatting: {str(e)}"


def parse_date_flexible(date_str: str) -> Optional[datetime]:
    """Parse date from various formats"""
    if not date_str:
        return None
    
    date_str = str(date_str).strip()
    
    # Try common formats
    formats = [
        '%m/%d/%Y', '%m/%d/%y',
        '%Y-%m-%d', '%d-%m-%Y',
        '%m-%d-%Y', '%m-%d-%y',
        '%B %d %Y', '%b %d %Y',
        '%m.%d.%Y', '%m.%d.%y'
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except:
            pass
    
    # Try to extract just numbers
    numbers = re.findall(r'\d+', date_str)
    if len(numbers) >= 2:
        try:
            month = int(numbers[0])
            day = int(numbers[1])
            year = int(numbers[2]) if len(numbers) >= 3 else 2024
            if year < 100:
                year += 2000
            return datetime(year, month, day)
        except:
            pass
    
    return None


def check_chronological_order(workbook, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if dates are sorted chronologically.
    Returns: (is_sorted, feedback)
    """
    try:
        sheet = workbook[sheet_name]
        
        dates = []
        for row_idx in range(2, 30):
            date_cell = sheet.cell(row=row_idx, column=1).value
            if not date_cell:
                break
            
            parsed_date = parse_date_flexible(date_cell)
            if parsed_date:
                dates.append(parsed_date)
        
        if len(dates) < 3:
            return False, "❌ Not enough valid dates to check sorting"
        
        # Check if sorted
        is_sorted = all(dates[i] <= dates[i+1] for i in range(len(dates)-1))
        
        if is_sorted:
            feedback = f"✅ Data sorted chronologically ({len(dates)} dates checked)"
        else:
            feedback = f"❌ Data not sorted chronologically (checked {len(dates)} dates)"
        
        return is_sorted, feedback
        
    except Exception as e:
        logger.error(f"Error checking chronological order: {e}")
        return False, f"❌ Error checking date order: {str(e)}"


def check_data_accuracy(workbook, sheet_name: str) -> Tuple[int, str]:
    """
    Check if data entries match the source notes file.
    Returns: (matching_count, feedback)
    """
    try:
        sheet = workbook[sheet_name]
        
        # Expected incidents from notes (partial matching)
        expected_keywords = [
            ('3/15', 'ps5', 'audio', 'cutout', 'hdmi cable'),
            ('3/17', 'rear', 'speaker', 'not connecting', 'power cycle'),
            ('3/18', 'roku', 'hdmi', 'handshake', 'firmware'),
            ('3/20', 'roku', 'audio', 'cutout', 'hdmi port'),
            ('3/22', 'blu-ray', 'lip sync', 'delay', 'audio delay'),
            ('3/23', 'rear', 'speaker', 'dropout', 'antenna'),
            ('3/24', 'audio', 'cutout', 'back', 'frustrated'),
            ('3/25', 'roku', 'optical', 'no cutout', 'arc'),
            ('3/27', 'ps5', 'optical', 'testing'),
            ('3/28', 'ps5', 'lip sync', 'delay', '100ms')
        ]
        
        matching_incidents = 0
        
        for row_idx in range(2, 30):
            row_text = ""
            for col_idx in range(1, 6):
                cell_value = sheet.cell(row=row_idx, column=col_idx).value
                if cell_value:
                    row_text += " " + str(cell_value).lower()
            
            if not row_text.strip():
                break
            
            # Check if this row matches any expected incident
            for expected in expected_keywords:
                matches = sum(1 for keyword in expected if keyword.lower() in row_text)
                if matches >= 3:  # At least 3 keywords match
                    matching_incidents += 1
                    break
        
        if matching_incidents >= 6:
            feedback = f"✅ Data accuracy good: {matching_incidents}/8+ entries match source notes"
        elif matching_incidents >= 4:
            feedback = f"⚠️ Data accuracy acceptable: {matching_incidents}/8+ entries match source notes"
        else:
            feedback = f"❌ Data accuracy low: only {matching_incidents}/8+ entries match source notes"
        
        return matching_incidents, feedback
        
    except Exception as e:
        logger.error(f"Error checking data accuracy: {e}")
        return 0, f"❌ Error checking data accuracy: {str(e)}"


def verify_troubleshooting_log(traj, env_info, task_info):
    """
    Main verification function for Home Theater Troubleshooting Log task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/theater_troubleshooting.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_theater_')
    
    try:
        # Copy file from container
        temp_file_path = os.path.join(temp_dir, 'theater_troubleshooting.xlsx')
        
        try:
            copy_from_env(container_path, temp_file_path)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"File not found at {container_path}: {str(e)}"
            }
        
        if not os.path.exists(temp_file_path) or os.path.getsize(temp_file_path) < 1000:
            return {
                "passed": False,
                "score": 0,
                "feedback": "File not found or too small (< 1KB)"
            }
        
        # Parse spreadsheet
        workbook = parse_xlsx_file(temp_file_path)
        if not workbook:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to parse XLSX file"
            }
        
        # Get the active sheet
        sheet_name = workbook.sheetnames[0]
        logger.info(f"Checking sheet: {sheet_name}")
        
        # Initialize scoring
        total_criteria = 7
        criteria_passed = 0
        feedback_parts = []
        
        # Criterion 1: File exists (already passed if we got here)
        criteria_passed += 1
        feedback_parts.append("✅ File exists at correct path")
        
        # Criterion 2: Check column headers
        has_headers, headers, header_feedback = check_headers(workbook, sheet_name)
        if has_headers:
            criteria_passed += 1
        feedback_parts.append(header_feedback)
        
        # Criterion 3: Count data rows (at least 8)
        row_count, row_feedback = count_data_rows(workbook, sheet_name)
        if row_count >= 8:
            criteria_passed += 1
        feedback_parts.append(row_feedback)
        
        # Criterion 4: Check for COUNTIF formula
        has_formula, formula_feedback = check_formula_exists(workbook, sheet_name)
        if has_formula:
            criteria_passed += 1
        else:
            # Partial credit: check if there's a labeled count anywhere
            for row_idx in range(1, 30):
                for col_idx in range(1, 10):
                    cell = workbook[sheet_name].cell(row=row_idx, column=col_idx)
                    if cell.value and isinstance(cell.value, (int, float)) and 2 <= cell.value <= 10:
                        # Found a number that could be the count
                        criteria_passed += 0.5
                        formula_feedback += " (partial credit for count value)"
                        break
        feedback_parts.append(formula_feedback)
        
        # Criterion 5: Check conditional formatting
        has_formatting, formatting_feedback = check_conditional_formatting(workbook, sheet_name)
        if has_formatting:
            criteria_passed += 1
        feedback_parts.append(formatting_feedback)
        
        # Criterion 6: Check chronological order
        is_sorted, sort_feedback = check_chronological_order(workbook, sheet_name)
        if is_sorted:
            criteria_passed += 1
        feedback_parts.append(sort_feedback)
        
        # Criterion 7: Check data accuracy
        matching_count, accuracy_feedback = check_data_accuracy(workbook, sheet_name)
        if matching_count >= 6:
            criteria_passed += 1
        elif matching_count >= 4:
            criteria_passed += 0.5
        feedback_parts.append(accuracy_feedback)
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: {criteria_passed}/{total_criteria} criteria passed, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
