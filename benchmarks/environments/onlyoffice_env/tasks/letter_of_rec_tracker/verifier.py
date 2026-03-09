#!/usr/bin/env python3
"""
Verifier for Letter of Recommendation Tracker task

Verifies that a multi-dimensional LoR tracking spreadsheet was created with:
- Structured headers for programs, deadlines, recommenders, status
- Multiple program entries (6+)
- Deadline information with variety
- Recommender tracking across programs
- Status/progress tracking
"""

import sys
import os
import logging
import tempfile
import re
from typing import List, Set, Optional, Any, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_by_header(header_row: Tuple, keywords: List[str]) -> int:
    """
    Find column index that contains any of the keywords in header.
    Returns -1 if not found.
    """
    if not header_row:
        return -1
    
    for col_idx, cell in enumerate(header_row):
        if cell and isinstance(cell, str):
            cell_lower = cell.lower()
            for keyword in keywords:
                if keyword.lower() in cell_lower:
                    return col_idx
    return -1


def count_date_like_cells(rows: List[Tuple], col_idx: int) -> int:
    """
    Count cells in a column that look like dates or deadline information.
    Handles formats like: "Dec 1", "12/1", "December 1", date objects
    """
    if col_idx < 0:
        return 0
    
    date_patterns = [
        r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)',  # Month names
        r'\d{1,2}/\d{1,2}',  # Date format like 12/1
        r'\d{1,2}-\d{1,2}',  # Date format like 12-1
        r'(january|february|march|april|may|june|july|august|september|october|november|december)'
    ]
    
    count = 0
    for row in rows:
        if col_idx < len(row):
            cell = row[col_idx]
            if cell:
                # Check if it's a date object
                if hasattr(cell, 'date') or hasattr(cell, 'day'):
                    count += 1
                    continue
                
                # Check if it's a string with date-like content
                if isinstance(cell, str):
                    cell_lower = cell.lower()
                    for pattern in date_patterns:
                        if re.search(pattern, cell_lower):
                            count += 1
                            break
    return count


def count_pattern_in_data(data: List[Tuple], patterns: List[str]) -> int:
    """
    Count occurrences of patterns (case-insensitive) across all cells.
    Used for finding recommender names or status keywords.
    """
    count = 0
    for row in data:
        for cell in row:
            if cell and isinstance(cell, str):
                cell_lower = cell.lower()
                for pattern in patterns:
                    if pattern.lower() in cell_lower:
                        count += 1
                        break  # Count each cell only once
    return count


def count_pattern_in_column(rows: List[Tuple], col_idx: int, patterns: List[str]) -> int:
    """
    Count occurrences of patterns in a specific column.
    """
    if col_idx < 0:
        return 0
    
    count = 0
    for row in rows:
        if col_idx < len(row):
            cell = row[col_idx]
            if cell and isinstance(cell, str):
                cell_lower = cell.lower()
                for pattern in patterns:
                    if pattern.lower() in cell_lower:
                        count += 1
                        break
    return count


def count_matching_headers(header_row: Tuple, keywords: List[str]) -> int:
    """
    Count how many headers contain any of the keywords.
    """
    if not header_row:
        return 0
    
    count = 0
    for cell in header_row:
        if cell and isinstance(cell, str):
            cell_lower = cell.lower()
            for keyword in keywords:
                if keyword.lower() in cell_lower:
                    count += 1
                    break
    return count


def count_unique_values_in_column(rows: List[Tuple], col_idx: int) -> int:
    """
    Count unique non-empty values in a column.
    """
    if col_idx < 0:
        return 0
    
    unique_values = set()
    for row in rows:
        if col_idx < len(row):
            cell = row[col_idx]
            if cell and str(cell).strip():
                # Normalize to string for comparison
                unique_values.add(str(cell).strip().lower())
    
    return len(unique_values)


def extract_unique_recommender_names(data: List[Tuple]) -> Set[str]:
    """
    Extract likely recommender names from the data.
    Looks for common professor name patterns and common test names.
    """
    common_names = ['chen', 'park', 'rodriguez', 'kim', 'smith', 'johnson', 
                    'williams', 'brown', 'jones', 'garcia', 'miller', 'davis']
    
    found_names = set()
    for row in data:
        for cell in row:
            if cell and isinstance(cell, str):
                cell_lower = cell.lower()
                # Check for "Dr. X" pattern
                if 'dr.' in cell_lower or 'prof.' in cell_lower:
                    found_names.add(cell.strip())
                # Check for common last names
                for name in common_names:
                    if name in cell_lower:
                        found_names.add(name)
    
    return found_names


def check_row_has_bold(sheet: Any, row_num: int) -> bool:
    """
    Check if any cells in the specified row have bold formatting.
    Row_num is 1-indexed.
    """
    try:
        for cell in sheet[row_num]:
            if cell.font and cell.font.bold:
                return True
    except:
        pass
    return False


def count_rows_with_min_fields(rows: List[Tuple], min_fields: int = 4) -> int:
    """
    Count rows that have at least min_fields non-empty cells.
    """
    count = 0
    for row in rows:
        non_empty = sum(1 for cell in row if cell and str(cell).strip())
        if non_empty >= min_fields:
            count += 1
    return count


def verify_letter_of_rec_tracker(traj, env_info, task_info):
    """
    Verify that letter of recommendation tracking spreadsheet was created correctly.

    Required Criteria (must pass 6/6 for minimum pass):
    1. File exists and is valid XLSX
    2. Header row with 5+ columns
    3. At least 6 program entries
    4. Deadline column with temporal data
    5. Recommender tracking (names or columns)
    6. Status/notes tracking

    Quality Criteria (bonus points):
    7. Multiple programs (6+) tracked
    8. Deadline variety (3+ different dates)
    9. Multiple recommenders (2+ names)

    Usability Bonus:
    10. Header row is bold
    11. Complete data structure (4+ fields per row)
    12. Material tracking evidence
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/lor_tracker.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_lor_')

    try:
        # Copy file from container to temp location
        temp_file_path = os.path.join(temp_dir, 'lor_tracker.xlsx')
        
        try:
            copy_from_env(container_path, temp_file_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy file: {str(e)}"}

        if not os.path.exists(temp_file_path) or os.path.getsize(temp_file_path) == 0:
            return {"passed": False, "score": 0, "feedback": "File not found or empty"}

        # Parse the spreadsheet
        wb = parse_xlsx_file(temp_file_path)
        if not wb:
            return {"passed": False, "score": 0, "feedback": "Failed to parse XLSX file"}

        sheet = wb.active
        
        # Extract data as list of tuples
        data = list(sheet.iter_rows(values_only=True, max_row=50, max_col=20))
        
        if not data or len(data) < 2:
            return {"passed": False, "score": 0, "feedback": "Spreadsheet is empty or has insufficient data"}

        criteria_met = []
        feedback_parts = []

        # ===== REQUIRED CRITERIA =====

        # 1. Header row exists (5+ columns with content)
        header_row = data[0]
        header_count = sum(1 for cell in header_row if cell and str(cell).strip())
        
        if header_count >= 5:
            criteria_met.append("header_row")
            feedback_parts.append(f"✅ Header row with {header_count} columns")
        else:
            feedback_parts.append(f"❌ Insufficient header columns ({header_count}/5)")

        # 2. At least 6 program entries (rows with non-empty first column)
        program_rows = [row for row in data[1:] if row and row[0] and str(row[0]).strip()]
        program_count = len(program_rows)
        
        if program_count >= 6:
            criteria_met.append("program_entries")
            feedback_parts.append(f"✅ {program_count} programs tracked")
        else:
            feedback_parts.append(f"❌ Only {program_count} programs (need 6+)")

        # 3. Deadline column with dates
        deadline_col = find_column_by_header(header_row, ["deadline", "due", "date"])
        
        # If no deadline header found, search all columns for date patterns
        if deadline_col < 0:
            # Try to find column with most date-like values
            max_dates = 0
            for col_idx in range(min(10, len(header_row))):
                date_count = count_date_like_cells(program_rows, col_idx)
                if date_count > max_dates:
                    max_dates = date_count
                    deadline_col = col_idx
        
        date_count = count_date_like_cells(program_rows, deadline_col) if deadline_col >= 0 else 0
        
        if date_count >= 5:
            criteria_met.append("deadlines")
            feedback_parts.append(f"✅ Deadline tracking ({date_count} dates found)")
        else:
            feedback_parts.append(f"❌ Insufficient deadline data ({date_count}/5 dates)")

        # 4. Recommender tracking
        # Look for recommender columns in header
        recommender_cols = count_matching_headers(header_row, 
            ["recommender", "rec", "professor", "prof", "advisor", "writer"])
        
        # Look for recommender names in data
        recommender_mentions = count_pattern_in_data(data, 
            ["chen", "park", "rodriguez", "kim", "dr.", "prof.", "smith", "johnson"])
        
        if recommender_mentions >= 10 or recommender_cols >= 2:
            criteria_met.append("recommenders")
            if recommender_cols >= 2:
                feedback_parts.append(f"✅ Recommender tracking ({recommender_cols} columns)")
            else:
                feedback_parts.append(f"✅ Recommender tracking ({recommender_mentions} name mentions)")
        else:
            feedback_parts.append(f"❌ Insufficient recommender tracking (cols:{recommender_cols}, mentions:{recommender_mentions})")

        # 5. Status/notes tracking
        status_col = find_column_by_header(header_row, 
            ["status", "notes", "progress", "submitted", "state", "materials"])
        
        status_terms = count_pattern_in_data(data[1:],
            ["submitted", "pending", "waiting", "sent", "complete", "received", 
             "all", "2/3", "3/3", "ready", "materials"])
        
        if status_col >= 0 or status_terms >= 4:
            criteria_met.append("status")
            feedback_parts.append("✅ Status/progress tracking present")
        else:
            feedback_parts.append("❌ No status tracking found")

        # 6. File was actually modified (has content beyond headers)
        if program_count >= 1:
            criteria_met.append("file_modified")
        else:
            feedback_parts.append("❌ File not properly modified")

        # ===== QUALITY CRITERIA =====

        # 7. Deadline variety (at least 3 different deadlines)
        unique_deadlines = count_unique_values_in_column(program_rows, deadline_col)
        if unique_deadlines >= 3:
            criteria_met.append("deadline_variety")
            feedback_parts.append(f"✅ Deadline variety ({unique_deadlines} unique dates)")

        # 8. Multiple recommenders (at least 2 different names)
        unique_recommenders = extract_unique_recommender_names(data)
        if len(unique_recommenders) >= 2:
            criteria_met.append("multiple_recommenders")
            feedback_parts.append(f"✅ Multiple recommenders ({len(unique_recommenders)} unique)")

        # ===== USABILITY BONUSES =====

        # 9. Bold headers
        if check_row_has_bold(sheet, 1):
            criteria_met.append("formatted_headers")
            feedback_parts.append("⭐ Headers are formatted (bold)")

        # 10. Complete rows (at least 6 rows with 4+ fields)
        complete_rows = count_rows_with_min_fields(program_rows, min_fields=4)
        if complete_rows >= 6:
            criteria_met.append("complete_structure")
            feedback_parts.append(f"⭐ Complete structure ({complete_rows} rows with 4+ fields)")

        # 11. Material tracking evidence
        material_keywords = count_pattern_in_data(data,
            ["cv", "resume", "statement", "materials", "sent", "provided", "package"])
        if material_keywords >= 3:
            criteria_met.append("material_tracking")
            feedback_parts.append("⭐ Material tracking evidence found")

        # Calculate score
        required_count = sum(1 for c in criteria_met if c in 
            ["header_row", "program_entries", "deadlines", "recommenders", "status", "file_modified"])
        quality_count = sum(1 for c in criteria_met if c in 
            ["deadline_variety", "multiple_recommenders"])
        bonus_count = sum(1 for c in criteria_met if c in 
            ["formatted_headers", "complete_structure", "material_tracking"])

        total_criteria = len(criteria_met)

        # Scoring logic
        if required_count == 6 and quality_count == 2 and bonus_count >= 2:
            score = 100
        elif required_count == 6 and quality_count == 2:
            score = 90
        elif required_count == 6 and quality_count >= 1:
            score = 80
        elif required_count == 6:
            score = 60
        else:
            # Partial credit based on required criteria met
            score = int((required_count / 6) * 50)

        passed = score >= 60

        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: {total_criteria} criteria met, score={score}")

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)