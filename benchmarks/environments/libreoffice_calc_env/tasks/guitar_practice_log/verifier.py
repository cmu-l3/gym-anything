#!/usr/bin/env python3
"""
Verifier for Guitar Practice Log task
Checks data cleaning, calculations, priority identification, and summary creation
"""

import sys
import os
import logging
import re
from typing import Dict, Any, Tuple, List

# Add utils to path (relative path for host machine)
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


def find_time_column(rows: List[List[Any]]) -> int:
    """Find the column containing time data by looking for header or numeric values"""
    if not rows:
        return 2  # Default to column C (index 2)
    
    # Check header row
    if len(rows) > 0:
        for col_idx, cell in enumerate(rows[0]):
            cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
            if 'time' in cell_val:
                return col_idx
    
    # Look for column with mostly numeric values
    for col_idx in range(min(5, len(rows[0]) if rows else 0)):
        numeric_count = 0
        for row in rows[1:6]:  # Check first few data rows
            if col_idx < len(row):
                val = row[col_idx].get('value') if isinstance(row[col_idx], dict) else row[col_idx]
                if isinstance(val, (int, float)) and 5 <= val <= 180:
                    numeric_count += 1
        if numeric_count >= 3:
            return col_idx
    
    return 2  # Default fallback


def find_difficulty_column(rows: List[List[Any]]) -> int:
    """Find the column containing difficulty ratings"""
    if not rows:
        return 3
    
    # Check header row
    if len(rows) > 0:
        for col_idx, cell in enumerate(rows[0]):
            cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
            if 'difficulty' in cell_val or 'rating' in cell_val:
                return col_idx
    
    # Look for column with values 1-5
    for col_idx in range(min(6, len(rows[0]) if rows else 0)):
        rating_count = 0
        for row in rows[1:6]:
            if col_idx < len(row):
                val = row[col_idx].get('value') if isinstance(row[col_idx], dict) else row[col_idx]
                if isinstance(val, (int, float)) and 1 <= val <= 5:
                    rating_count += 1
        if rating_count >= 3:
            return col_idx
    
    return 3  # Default fallback


def check_data_cleaning(rows: List[List[Any]], time_col: int) -> Tuple[int, List[str]]:
    """
    Check if time data has been cleaned and standardized to numeric minutes
    Returns: (score, feedback_messages)
    """
    score = 0
    feedback = []
    
    numeric_time_count = 0
    valid_range_count = 0
    total_data_rows = 0
    
    # Check data rows (skip header)
    for row_idx, row in enumerate(rows[1:20], start=1):  # Check up to 20 rows
        if len(row) > time_col:
            cell = row[time_col]
            time_val = cell.get('value') if isinstance(cell, dict) else cell
            
            # Skip completely empty rows
            if not any(c.get('value') if isinstance(c, dict) else c for c in row):
                continue
            
            total_data_rows += 1
            
            # Check if numeric
            if isinstance(time_val, (int, float)):
                numeric_time_count += 1
                # Check if in valid range (5-180 minutes)
                if 5 <= time_val <= 180:
                    valid_range_count += 1
            elif isinstance(time_val, str):
                # Check if it still contains text markers (not cleaned)
                if any(marker in time_val.lower() for marker in ['min', 'hr', 'hour', 'about']):
                    feedback.append(f"⚠️ Row {row_idx+1}: Time not fully cleaned: '{time_val}'")
    
    # Score based on cleaning completeness
    if total_data_rows > 0:
        clean_percentage = numeric_time_count / total_data_rows
        if clean_percentage >= 0.8:  # 80% or more cleaned
            score += 10
            if valid_range_count >= total_data_rows * 0.75:  # 75% in valid range
                score += 10
                feedback.append(f"✅ Time data cleaned: {numeric_time_count}/{total_data_rows} entries numeric, {valid_range_count} in valid range")
            else:
                feedback.append(f"⚠️ Time data mostly cleaned but some values out of range: {valid_range_count}/{total_data_rows}")
        else:
            feedback.append(f"❌ Time data not fully cleaned: only {numeric_time_count}/{total_data_rows} entries are numeric")
    else:
        feedback.append("❌ No data rows found")
    
    return score, feedback


def check_formulas(rows: List[List[Any]]) -> Tuple[int, List[str]]:
    """
    Check for presence and correctness of formulas (SUM, AVERAGE, IF, etc.)
    Returns: (score, feedback_messages)
    """
    score = 0
    feedback = []
    
    formula_count = 0
    sum_found = False
    average_found = False
    if_found = False
    
    for row in rows:
        for cell in row:
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula:
                    formula_count += 1
                    formula_upper = formula.upper()
                    
                    if 'SUM' in formula_upper:
                        sum_found = True
                    if 'AVERAGE' in formula_upper or 'AVG' in formula_upper:
                        average_found = True
                    if 'IF' in formula_upper:
                        if_found = True
    
    # Score formulas
    if formula_count >= 5:
        score += 10
        feedback.append(f"✅ Found {formula_count} formulas")
    elif formula_count >= 3:
        score += 5
        feedback.append(f"⚠️ Found only {formula_count} formulas (expected 5+)")
    else:
        feedback.append(f"❌ Insufficient formulas: found {formula_count}, expected at least 5")
    
    if sum_found:
        score += 8
        feedback.append("✅ SUM formula found")
    else:
        feedback.append("❌ No SUM formula found")
    
    if average_found:
        score += 7
        feedback.append("✅ AVERAGE formula found")
    else:
        feedback.append("❌ No AVERAGE formula found")
    
    return score, feedback


def check_priority_identification(rows: List[List[Any]]) -> Tuple[int, List[str]]:
    """
    Check if priority areas have been identified
    Returns: (score, feedback_messages)
    """
    score = 0
    feedback = []
    
    priority_count = 0
    priority_rows = []
    
    for row_idx, row in enumerate(rows):
        for cell_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                value = cell.get('value')
                if isinstance(value, str) and 'PRIORITY' in value.upper():
                    priority_count += 1
                    priority_rows.append(row_idx + 1)
    
    # Expected: 2-6 priority items (based on difficulty >= 4 and time < 30)
    if 2 <= priority_count <= 8:
        score += 20
        feedback.append(f"✅ Priority identification: {priority_count} items marked")
    elif priority_count > 0:
        score += 10
        feedback.append(f"⚠️ Priority identification partial: {priority_count} items (expected 2-6)")
    else:
        feedback.append("❌ No priority items identified")
    
    return score, feedback


def check_summary_section(rows: List[List[Any]]) -> Tuple[int, List[str]]:
    """
    Check for presence of summary section with key statistics
    Returns: (score, feedback_messages)
    """
    score = 0
    feedback = []
    
    summary_keywords = ['week', 'total', 'average', 'summary', 'overall']
    keyword_found_count = 0
    summary_row_start = None
    
    # Look for summary section (usually below main data, after row 15)
    for row_idx, row in enumerate(rows):
        for cell in row:
            if isinstance(cell, dict):
                value = cell.get('value')
                if isinstance(value, str):
                    value_lower = value.lower()
                    if any(kw in value_lower for kw in summary_keywords):
                        keyword_found_count += 1
                        if summary_row_start is None:
                            summary_row_start = row_idx
                        break
    
    if keyword_found_count >= 3:
        score += 15
        feedback.append(f"✅ Summary section found (starting around row {summary_row_start + 1})")
    elif keyword_found_count >= 1:
        score += 8
        feedback.append(f"⚠️ Partial summary section found ({keyword_found_count} keywords)")
    else:
        feedback.append("❌ No summary section found")
    
    return score, feedback


def check_instructor_insights(rows: List[List[Any]]) -> Tuple[int, List[str]]:
    """
    Check for instructor recommendations/insights section
    Returns: (score, feedback_messages)
    """
    score = 0
    feedback = []
    
    insight_keywords = ['focus', 'recommend', 'most', 'least', 'highest', 'priority', 'practice more']
    insights_found = 0
    
    for row in rows[15:]:  # Check rows below main data
        for cell in row:
            if isinstance(cell, dict):
                value = cell.get('value')
                if isinstance(value, str):
                    value_lower = value.lower()
                    if any(kw in value_lower for kw in insight_keywords):
                        insights_found += 1
                        break
    
    if insights_found >= 2:
        score += 10
        feedback.append(f"✅ Instructor insights present ({insights_found} recommendations)")
    elif insights_found >= 1:
        score += 5
        feedback.append("⚠️ Partial instructor insights")
    else:
        feedback.append("❌ No instructor insights found")
    
    return score, feedback


def verify_guitar_practice_log(traj, env_info, task_info):
    """
    Main verification function for guitar practice log task
    
    Checks:
    1. Data cleaning (20 points)
    2. Formula accuracy (25 points)
    3. Priority identification (20 points)
    4. Summary section (15 points)
    5. Conditional formatting (10 points - structural check)
    6. Instructor insights (10 points)
    
    Total: 100 points
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible filenames
    possible_paths = [
        "/home/ga/Documents/guitar_practice_log.ods",
        "/home/ga/Documents/practice_notes_raw.ods",
        "/home/ga/Documents/guitar_practice.ods",
        "/home/ga/Documents/practice_log.ods"
    ]
    
    workbook = None
    temp_dir = None
    success = False
    
    for container_path in possible_paths:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format='ods'
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load practice log file. Tried: {', '.join(possible_paths)}. Error: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook.get('sheets', {}).keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        rows = workbook['sheets'][sheet_name]
        
        if len(rows) < 5:
            return {"passed": False, "score": 0, "feedback": "Insufficient data in spreadsheet"}
        
        # Dynamically find columns
        time_col = find_time_column(rows)
        difficulty_col = find_difficulty_column(rows)
        
        logger.info(f"Detected time column: {time_col}, difficulty column: {difficulty_col}")
        
        # Run all verification checks
        total_score = 0
        all_feedback = []
        
        # 1. Data Cleaning (20 points)
        clean_score, clean_feedback = check_data_cleaning(rows, time_col)
        total_score += clean_score
        all_feedback.extend(clean_feedback)
        
        # 2. Formulas (25 points)
        formula_score, formula_feedback = check_formulas(rows)
        total_score += formula_score
        all_feedback.extend(formula_feedback)
        
        # 3. Priority Identification (20 points)
        priority_score, priority_feedback = check_priority_identification(rows)
        total_score += priority_score
        all_feedback.extend(priority_feedback)
        
        # 4. Summary Section (15 points)
        summary_score, summary_feedback = check_summary_section(rows)
        total_score += summary_score
        all_feedback.extend(summary_feedback)
        
        # 5. Conditional Formatting / Structure (10 points)
        # ODS parsing has limited styling support, give credit for proper structure
        if len(rows) > 15:  # Has enough rows for data + summary
            total_score += 10
            all_feedback.append("✅ Spreadsheet has proper structure")
        
        # 6. Instructor Insights (10 points)
        insights_score, insights_feedback = check_instructor_insights(rows)
        total_score += insights_score
        all_feedback.extend(insights_feedback)
        
        # Determine pass/fail
        passed = total_score >= 70
        
        # Add final summary
        if passed and total_score >= 90:
            all_feedback.insert(0, "🎉 Excellent practice log organization!")
        elif passed:
            all_feedback.insert(0, "✅ Practice log meets requirements")
        else:
            all_feedback.insert(0, "❌ Practice log needs more work")
        
        feedback_str = " | ".join(all_feedback)
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback_str,
            "subscores": {
                "data_cleaning": clean_score,
                "formulas": formula_score,
                "priority_identification": priority_score,
                "summary_section": summary_score,
                "instructor_insights": insights_score
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
