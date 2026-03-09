#!/usr/bin/env python3
"""
Verifier for Noise Violation Log task
"""

import sys
import os
import logging
import tempfile
import re
from datetime import datetime
from typing import List, Tuple, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_index(header_row: List, keywords: List[str]) -> Optional[int]:
    """Find column index by searching for keywords in header"""
    if not header_row:
        return None
    
    for idx, cell in enumerate(header_row):
        if cell is None:
            continue
        cell_text = str(cell).lower()
        for keyword in keywords:
            if keyword.lower() in cell_text:
                return idx
    return None


def is_valid_date(cell_value) -> bool:
    """Check if cell contains a valid date"""
    if cell_value is None:
        return False
    
    # Check if it's a datetime object
    if isinstance(cell_value, datetime):
        return True
    
    # Check if it's a string that looks like a date
    if isinstance(cell_value, str):
        date_patterns = [
            r'\d{1,2}/\d{1,2}/\d{2,4}',
            r'\d{1,2}-\d{1,2}-\d{2,4}',
            r'\w{3,}\s+\d{1,2}',
        ]
        for pattern in date_patterns:
            if re.search(pattern, cell_value):
                return True
    
    return False


def is_valid_time(cell_value) -> bool:
    """Check if cell contains a valid time"""
    if cell_value is None:
        return False
    
    cell_str = str(cell_value).strip()
    
    # Check for time patterns
    time_patterns = [
        r'\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)',
        r'\d{1,2}:\d{2}',
        r'\d{1,2}\s*(?:AM|PM|am|pm)',
    ]
    
    for pattern in time_patterns:
        if re.search(pattern, cell_str):
            return True
    
    return False


def count_data_rows(sheet_data: List[List], start_row: int = 1) -> int:
    """Count rows with data (non-empty date column)"""
    count = 0
    for row_idx in range(start_row, len(sheet_data)):
        row = sheet_data[row_idx]
        if row and len(row) > 0 and row[0] is not None:
            # Check if first cell has content
            if str(row[0]).strip() and str(row[0]).strip().lower() not in ['date', 'total', 'summary']:
                count += 1
    return count


def check_for_formulas(sheet, start_row: int, end_row: int, col_idx: int) -> int:
    """Check if cells contain formulas (by checking if value is numeric and reasonable for duration)"""
    formula_count = 0
    for row_idx in range(start_row, min(end_row + 1, sheet.max_row + 1)):
        cell = sheet.cell(row=row_idx, column=col_idx + 1)
        if cell.value and isinstance(cell.value, (int, float)):
            if 0 < cell.value < 24:  # Reasonable duration in hours
                formula_count += 1
    return formula_count


def check_for_summary_section(sheet_data: List[List]) -> Tuple[bool, int]:
    """Check if there's a summary statistics section"""
    summary_keywords = ['total', 'summary', 'statistics', 'average', 'count']
    summary_found = False
    summary_count = 0
    
    for row in sheet_data:
        if not row:
            continue
        
        row_text = ' '.join([str(cell).lower() for cell in row if cell is not None])
        
        for keyword in summary_keywords:
            if keyword in row_text:
                summary_found = True
                summary_count += 1
                break
    
    return summary_found, summary_count


def assess_formatting_quality(sheet) -> int:
    """Assess overall formatting quality (returns score 0-15)"""
    score = 0
    
    # Check if header row (row 1) has bold formatting
    try:
        header_bold_count = 0
        for col in range(1, min(10, sheet.max_column + 1)):
            cell = sheet.cell(row=1, column=col)
            if cell.font and cell.font.bold:
                header_bold_count += 1
        
        if header_bold_count >= 5:
            score += 5
        elif header_bold_count >= 3:
            score += 3
    except:
        pass
    
    # Check for borders
    try:
        border_count = 0
        for row in range(1, min(15, sheet.max_row + 1)):
            for col in range(1, min(10, sheet.max_column + 1)):
                cell = sheet.cell(row=row, column=col)
                if cell.border and (cell.border.left.style or cell.border.top.style):
                    border_count += 1
                    if border_count >= 10:
                        score += 5
                        break
            if border_count >= 10:
                break
    except:
        pass
    
    # Check for reasonable column widths (not default)
    try:
        custom_width_count = 0
        for col_letter in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I']:
            try:
                if sheet.column_dimensions[col_letter].width != 8.43:  # Default width
                    custom_width_count += 1
            except:
                pass
        
        if custom_width_count >= 4:
            score += 5
        elif custom_width_count >= 2:
            score += 3
    except:
        pass
    
    return score


def verify_noise_violation_log(traj, env_info, task_info):
    """
    Verify that noise violation log was created correctly.

    Checks:
    1. Proper structure with required columns (20 pts)
    2. Sufficient data - at least 12 incidents (25 pts)
    3. Formulas for duration calculations (15 pts)
    4. Professional formatting (15 pts)
    5. Summary statistics section (15 pts)
    6. Valid dates, times, and categorization (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Noise_Violation_Log.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_noise_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0.0, "feedback": f"Failed to load spreadsheet: {error}"}

        sheet = wb.active
        sheet_data = get_sheet_data(wb, sheet.title, max_rows=100, max_cols=20)
        
        if not sheet_data or len(sheet_data) < 2:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Spreadsheet is empty or has insufficient data"
            }
        
        score = 0.0
        feedback_parts = []
        
        # Get header row
        header_row = sheet_data[0] if sheet_data else []
        
        # === CRITERION 1: Structure Check (20 points) ===
        required_columns = {
            'date': ['date'],
            'day': ['day', 'weekday', 'dow'],
            'start': ['start', 'begin', 'time'],
            'end': ['end', 'finish'],
            'duration': ['duration', 'hours', 'length'],
            'type': ['type', 'violation', 'category'],
            'quiet': ['quiet', 'hours'],
            'description': ['description', 'details', 'notes'],
        }
        
        columns_found = {}
        for col_name, keywords in required_columns.items():
            idx = find_column_index(header_row, keywords)
            if idx is not None:
                columns_found[col_name] = idx
        
        structure_score = (len(columns_found) / len(required_columns)) * 20
        score += structure_score
        
        if len(columns_found) >= 6:
            feedback_parts.append(f"✅ Structure: {len(columns_found)}/8 required columns found")
        else:
            feedback_parts.append(f"❌ Structure: Only {len(columns_found)}/8 required columns found")
        
        # === CRITERION 2: Data Completeness (25 points) ===
        incident_count = count_data_rows(sheet_data, start_row=1)
        
        if incident_count >= 12:
            score += 25
            feedback_parts.append(f"✅ Data: {incident_count} incidents logged (sufficient)")
        elif incident_count >= 8:
            score += 15
            feedback_parts.append(f"⚠️ Data: {incident_count} incidents (adequate, but ≥12 recommended)")
        elif incident_count >= 5:
            score += 8
            feedback_parts.append(f"⚠️ Data: {incident_count} incidents (insufficient, need ≥12)")
        else:
            feedback_parts.append(f"❌ Data: Only {incident_count} incidents logged")
        
        # === CRITERION 3: Formula Check (15 points) ===
        formula_score = 0
        if 'duration' in columns_found and incident_count >= 3:
            duration_col = columns_found['duration']
            formulas_found = check_for_formulas(sheet, 2, min(incident_count + 5, 25), duration_col)
            
            if formulas_found >= 3:
                formula_score = 15
                feedback_parts.append(f"✅ Formulas: Duration calculations present ({formulas_found} found)")
            elif formulas_found >= 1:
                formula_score = 8
                feedback_parts.append(f"⚠️ Formulas: Some calculations present ({formulas_found} found)")
            else:
                feedback_parts.append("❌ Formulas: No duration calculations detected")
        else:
            feedback_parts.append("❌ Formulas: Cannot verify (duration column missing)")
        
        score += formula_score
        
        # === CRITERION 4: Professional Formatting (15 points) ===
        formatting_score = assess_formatting_quality(sheet)
        score += formatting_score
        
        if formatting_score >= 12:
            feedback_parts.append("✅ Formatting: Professional appearance")
        elif formatting_score >= 8:
            feedback_parts.append("⚠️ Formatting: Basic formatting applied")
        else:
            feedback_parts.append("❌ Formatting: Needs improvement")
        
        # === CRITERION 5: Summary Statistics (15 points) ===
        has_summary, summary_count = check_for_summary_section(sheet_data)
        
        if has_summary and summary_count >= 2:
            score += 15
            feedback_parts.append("✅ Summary: Statistics section present")
        elif has_summary:
            score += 8
            feedback_parts.append("⚠️ Summary: Minimal statistics present")
        else:
            feedback_parts.append("❌ Summary: No summary statistics found")
        
        # === CRITERION 6: Data Quality (10 points) ===
        data_quality_score = 0
        
        # Check for valid dates
        if 'date' in columns_found:
            date_col = columns_found['date']
            valid_dates = sum(1 for row in sheet_data[1:min(incident_count + 5, len(sheet_data))]
                            if len(row) > date_col and is_valid_date(row[date_col]))
            
            if valid_dates >= incident_count * 0.8:
                data_quality_score += 5
        
        # Check for valid times
        if 'start' in columns_found:
            start_col = columns_found['start']
            valid_times = sum(1 for row in sheet_data[1:min(incident_count + 5, len(sheet_data))]
                            if len(row) > start_col and is_valid_time(row[start_col]))
            
            if valid_times >= incident_count * 0.7:
                data_quality_score += 5
        
        score += data_quality_score
        
        if data_quality_score >= 8:
            feedback_parts.append("✅ Data Quality: Valid dates and times")
        elif data_quality_score >= 5:
            feedback_parts.append("⚠️ Data Quality: Mostly valid entries")
        else:
            feedback_parts.append("❌ Data Quality: Invalid or missing dates/times")
        
        # Normalize score to 0-1 range
        final_score = min(100, score) / 100.0
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0.0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
