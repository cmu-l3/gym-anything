#!/usr/bin/env python3
"""
Verifier for Scholarship Format Rescue task.

Comprehensive validation of financial data formatting compliance:
1. File structure (9 columns, exact names, correct order)
2. Data type validation (dates in YYYY-MM-DD, numbers not text)
3. Content validation (categories match taxonomy, no empty fields)
4. Calculation verification (monthly, semester, needs-based logic)
5. Format precision (date format strict, decimal places, text cleanliness)
"""

import sys
import os
import logging
import csv
import re
from datetime import datetime
from typing import Dict, List, Tuple, Any

# Add utils to path (relative path for host execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Required specification constants
REQUIRED_COLUMNS = [
    'Transaction_ID',
    'Date', 
    'Category',
    'Description',
    'Amount',
    'Monthly_Amount',
    'Semester_Total',
    'Needs_Based',
    'Source'
]

ALLOWED_CATEGORIES = [
    'Tuition',
    'Housing',
    'Educational Materials',
    'Transportation',
    'Healthcare',
    'Miscellaneous'
]

ALLOWED_SOURCES = [
    'Loan',
    'Grant',
    'Scholarship',
    'Work-Study',
    'Personal'
]

ACADEMIC_YEAR_START = datetime(2023, 8, 1)
ACADEMIC_YEAR_END = datetime(2024, 7, 31)


def parse_csv_file(filepath: str) -> Tuple[bool, List[Dict[str, str]], str]:
    """
    Parse CSV file and return rows as list of dicts.
    
    Returns:
        (success, rows, error_message)
    """
    try:
        rows = []
        with open(filepath, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                rows.append(row)
        
        if not rows:
            return False, [], "CSV file is empty (no data rows)"
        
        return True, rows, ""
    
    except Exception as e:
        logger.error(f"Error parsing CSV: {e}", exc_info=True)
        return False, [], f"Failed to parse CSV: {str(e)}"


def verify_column_structure(headers: List[str]) -> Tuple[int, List[str]]:
    """
    Verify column structure matches requirements.
    
    Returns:
        (points_earned, feedback_list)
    """
    feedback = []
    points = 0
    max_points = 15
    
    # Check column count
    if len(headers) != len(REQUIRED_COLUMNS):
        feedback.append(f"❌ Wrong column count: expected {len(REQUIRED_COLUMNS)}, got {len(headers)}")
        return 0, feedback
    
    # Check column names (case-sensitive)
    all_correct = True
    for i, (expected, actual) in enumerate(zip(REQUIRED_COLUMNS, headers)):
        if expected != actual:
            feedback.append(f"❌ Column {i+1} name incorrect: expected '{expected}', got '{actual}'")
            all_correct = False
    
    if all_correct:
        points = max_points
        feedback.append(f"✅ Column structure correct ({len(REQUIRED_COLUMNS)} columns in order)")
    else:
        # Partial credit if names exist but wrong order
        if set(headers) == set(REQUIRED_COLUMNS):
            points = max_points // 2
            feedback.append("⚠️ Columns exist but wrong order")
        else:
            points = 0
    
    return points, feedback


def verify_date_format(date_str: str) -> Tuple[bool, bool, str]:
    """
    Verify date format and range.
    
    Returns:
        (format_correct, in_range, error_message)
    """
    # Check format with regex
    pattern = r'^\d{4}-\d{2}-\d{2}$'
    if not re.match(pattern, date_str):
        return False, False, f"Date format incorrect: '{date_str}' (expected YYYY-MM-DD)"
    
    # Check if valid date and in range
    try:
        date_obj = datetime.strptime(date_str, '%Y-%m-%d')
        in_range = ACADEMIC_YEAR_START <= date_obj <= ACADEMIC_YEAR_END
        if not in_range:
            return True, False, f"Date {date_str} outside academic year (2023-08-01 to 2024-07-31)"
        return True, True, ""
    except ValueError:
        return False, False, f"Invalid date: '{date_str}'"


def verify_numeric_value(value_str: str, field_name: str) -> Tuple[bool, float, str]:
    """
    Verify a value is a valid number (not text).
    
    Returns:
        (is_valid, numeric_value, error_message)
    """
    try:
        # Check if it looks like text (leading zeros, quotes, etc.)
        if isinstance(value_str, str):
            # Remove whitespace
            value_str = value_str.strip()
            
            # Check for parentheses (old negative format)
            if '(' in value_str or ')' in value_str:
                return False, 0, f"{field_name} has parentheses (use minus sign for negatives)"
            
            # Check for non-numeric characters (except minus, period, comma)
            if re.search(r"[^\d\.\-,]", value_str):
                return False, 0, f"{field_name} contains non-numeric characters"
        
        # Try to convert to float
        numeric_val = float(str(value_str).replace(',', ''))
        return True, numeric_val, ""
    
    except (ValueError, TypeError):
        return False, 0, f"{field_name} is not a valid number: '{value_str}'"


def verify_dates(rows: List[Dict]) -> Tuple[int, List[str]]:
    """Verify all dates are in correct format and range."""
    feedback = []
    points = 0
    max_points = 20
    
    if not rows:
        return 0, ["❌ No data rows to verify"]
    
    valid_count = 0
    errors = []
    
    for i, row in enumerate(rows, start=2):  # Start at 2 (row 1 is header)
        date_str = row.get('Date', '').strip()
        
        if not date_str:
            errors.append(f"Row {i}: Empty date")
            continue
        
        format_ok, range_ok, error = verify_date_format(date_str)
        
        if format_ok and range_ok:
            valid_count += 1
        elif not format_ok:
            errors.append(f"Row {i}: {error}")
        elif not range_ok:
            errors.append(f"Row {i}: {error}")
    
    success_rate = valid_count / len(rows) if rows else 0
    points = int(max_points * success_rate)
    
    if success_rate == 1.0:
        feedback.append(f"✅ All {len(rows)} dates valid (YYYY-MM-DD, within academic year)")
    elif success_rate >= 0.8:
        feedback.append(f"⚠️ Most dates valid ({valid_count}/{len(rows)})")
        feedback.extend(errors[:3])  # Show first 3 errors
    else:
        feedback.append(f"❌ Many date errors ({valid_count}/{len(rows)} valid)")
        feedback.extend(errors[:5])  # Show first 5 errors
    
    return points, feedback


def verify_numbers(rows: List[Dict]) -> Tuple[int, List[str]]:
    """Verify numeric columns are properly formatted."""
    feedback = []
    points = 0
    max_points = 20
    
    numeric_fields = ['Amount', 'Monthly_Amount', 'Semester_Total']
    
    valid_count = 0
    total_checks = len(rows) * len(numeric_fields)
    errors = []
    
    for i, row in enumerate(rows, start=2):
        for field in numeric_fields:
            value = row.get(field, '').strip()
            
            if not value:
                errors.append(f"Row {i}, {field}: Empty")
                continue
            
            is_valid, _, error = verify_numeric_value(value, field)
            
            if is_valid:
                valid_count += 1
            else:
                errors.append(f"Row {i}, {field}: {error}")
    
    success_rate = valid_count / total_checks if total_checks > 0 else 0
    points = int(max_points * success_rate)
    
    if success_rate == 1.0:
        feedback.append(f"✅ All numeric fields properly formatted ({total_checks} values)")
    elif success_rate >= 0.8:
        feedback.append(f"⚠️ Most numbers valid ({valid_count}/{total_checks})")
        feedback.extend(errors[:3])
    else:
        feedback.append(f"❌ Many numeric errors ({valid_count}/{total_checks} valid)")
        feedback.extend(errors[:5])
    
    return points, feedback


def verify_categories(rows: List[Dict]) -> Tuple[int, List[str]]:
    """Verify categories match required taxonomy."""
    feedback = []
    points = 0
    max_points = 15
    
    valid_count = 0
    invalid_categories = []
    
    for i, row in enumerate(rows, start=2):
        category = row.get('Category', '').strip()
        
        if category in ALLOWED_CATEGORIES:
            valid_count += 1
        else:
            invalid_categories.append(f"Row {i}: '{category}'")
    
    success_rate = valid_count / len(rows) if rows else 0
    points = int(max_points * success_rate)
    
    if success_rate == 1.0:
        feedback.append(f"✅ All categories valid (matched to taxonomy)")
    elif success_rate >= 0.8:
        feedback.append(f"⚠️ Most categories valid ({valid_count}/{len(rows)})")
        feedback.append(f"Invalid: {', '.join(invalid_categories[:3])}")
    else:
        feedback.append(f"❌ Many invalid categories ({valid_count}/{len(rows)} valid)")
        feedback.append(f"Examples: {', '.join(invalid_categories[:5])}")
    
    return points, feedback


def verify_calculations(rows: List[Dict]) -> Tuple[int, List[str]]:
    """Verify derived field calculations are correct."""
    feedback = []
    points = 0
    max_points = 20
    
    calculation_errors = 0
    monthly_errors = []
    semester_errors = []
    needs_based_errors = []
    
    tolerance = 0.02  # Allow small floating point differences
    
    for i, row in enumerate(rows, start=2):
        # Get values
        try:
            amount = float(row.get('Amount', '0').replace(',', ''))
            monthly = float(row.get('Monthly_Amount', '0').replace(',', ''))
            semester = float(row.get('Semester_Total', '0').replace(',', ''))
            source = row.get('Source', '').strip()
            needs_based = row.get('Needs_Based', '').strip()
            
            # Check Monthly_Amount = Amount / 12
            expected_monthly = amount / 12
            if abs(monthly - expected_monthly) > tolerance:
                calculation_errors += 1
                monthly_errors.append(f"Row {i}: {monthly:.2f} ≠ {expected_monthly:.2f}")
            
            # Check Semester_Total = Monthly_Amount * 4
            expected_semester = monthly * 4
            if abs(semester - expected_semester) > tolerance:
                calculation_errors += 1
                semester_errors.append(f"Row {i}: {semester:.2f} ≠ {expected_semester:.2f}")
            
            # Check Needs_Based logic
            should_be_yes = source in ['Grant', 'Scholarship']
            is_yes = needs_based.lower() == 'yes'
            
            if should_be_yes != is_yes:
                calculation_errors += 1
                expected = 'Yes' if should_be_yes else 'No'
                needs_based_errors.append(f"Row {i}: '{needs_based}' ≠ '{expected}' (Source: {source})")
        
        except (ValueError, KeyError) as e:
            calculation_errors += 1
            continue
    
    total_checks = len(rows) * 3  # 3 calculations per row
    correct_count = total_checks - calculation_errors
    success_rate = correct_count / total_checks if total_checks > 0 else 0
    points = int(max_points * success_rate)
    
    if success_rate == 1.0:
        feedback.append(f"✅ All calculations correct ({total_checks} checks)")
    elif success_rate >= 0.9:
        feedback.append(f"⚠️ Most calculations correct ({correct_count}/{total_checks})")
        if monthly_errors:
            feedback.append(f"Monthly errors: {monthly_errors[0]}")
        if semester_errors:
            feedback.append(f"Semester errors: {semester_errors[0]}")
        if needs_based_errors:
            feedback.append(f"Needs-based errors: {needs_based_errors[0]}")
    else:
        feedback.append(f"❌ Many calculation errors ({correct_count}/{total_checks} correct)")
        feedback.extend((monthly_errors + semester_errors + needs_based_errors)[:5])
    
    return points, feedback


def verify_completeness(rows: List[Dict]) -> Tuple[int, List[str]]:
    """Verify no missing data in required fields."""
    feedback = []
    points = 0
    max_points = 10
    
    empty_cells = []
    
    for i, row in enumerate(rows, start=2):
        for col in REQUIRED_COLUMNS:
            value = row.get(col, '').strip()
            if not value:
                empty_cells.append(f"Row {i}, Column '{col}'")
    
    if not empty_cells:
        points = max_points
        feedback.append(f"✅ No missing data ({len(rows)} rows complete)")
    else:
        # Deduct points proportionally
        total_cells = len(rows) * len(REQUIRED_COLUMNS)
        filled_rate = (total_cells - len(empty_cells)) / total_cells
        points = int(max_points * filled_rate)
        
        feedback.append(f"❌ {len(empty_cells)} empty required fields")
        feedback.extend(empty_cells[:5])  # Show first 5
    
    return points, feedback


def verify_scholarship_format(traj, env_info, task_info):
    """
    Main verifier for scholarship format rescue task.
    
    Comprehensive validation with point-based scoring:
    - Structure: 15 points (column names, order, count)
    - Dates: 20 points (YYYY-MM-DD format, within range)
    - Numbers: 20 points (proper numeric types, no text)
    - Categories: 15 points (match taxonomy)
    - Calculations: 20 points (monthly, semester, needs-based)
    - Completeness: 10 points (no empty required fields)
    
    Total: 100 points
    Pass threshold: 85 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to find the output CSV file
    container_path = "/home/ga/Documents/financial_data_submission.csv"
    
    success, result = setup_verification_environment(
        copy_from_env,
        container_path,
        expected_formats=['csv']
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load CSV file: {result.get('error', 'File not found')}"
        }
    
    temp_dir = result.get('temp_dir')
    
    try:
        # Parse CSV
        filepath = result.get('filepath')
        success, rows, error = parse_csv_file(filepath)
        
        if not success:
            return {"passed": False, "score": 0, "feedback": error}
        
        if not rows:
            return {"passed": False, "score": 0, "feedback": "CSV file contains no data rows"}
        
        # Get headers
        headers = list(rows[0].keys()) if rows else []
        
        # Run all verification checks
        total_score = 0
        all_feedback = []
        subscores = {}
        
        # 1. Column structure (15 points)
        struct_points, struct_feedback = verify_column_structure(headers)
        total_score += struct_points
        all_feedback.extend(struct_feedback)
        subscores['structure'] = struct_points
        
        # If structure is completely wrong, can't proceed with other checks
        if struct_points == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(all_feedback),
                "subscores": subscores
            }
        
        # 2. Date validation (20 points)
        date_points, date_feedback = verify_dates(rows)
        total_score += date_points
        all_feedback.extend(date_feedback)
        subscores['dates'] = date_points
        
        # 3. Number validation (20 points)
        number_points, number_feedback = verify_numbers(rows)
        total_score += number_points
        all_feedback.extend(number_feedback)
        subscores['numbers'] = number_points
        
        # 4. Category validation (15 points)
        category_points, category_feedback = verify_categories(rows)
        total_score += category_points
        all_feedback.extend(category_feedback)
        subscores['categories'] = category_points
        
        # 5. Calculation validation (20 points)
        calc_points, calc_feedback = verify_calculations(rows)
        total_score += calc_points
        all_feedback.extend(calc_feedback)
        subscores['calculations'] = calc_points
        
        # 6. Completeness validation (10 points)
        complete_points, complete_feedback = verify_completeness(rows)
        total_score += complete_points
        all_feedback.extend(complete_feedback)
        subscores['completeness'] = complete_points
        
        # Determine pass/fail
        passed = total_score >= 85
        
        # Add overall summary
        if passed and total_score >= 95:
            all_feedback.insert(0, "🎉 EXCELLENT: Perfect format compliance!")
        elif passed:
            all_feedback.insert(0, "✅ PASSED: Format meets scholarship requirements")
        else:
            all_feedback.insert(0, f"❌ FAILED: Score {total_score}/100 (need 85+)")
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": " | ".join(all_feedback),
            "subscores": subscores,
            "details": {
                "row_count": len(rows),
                "structure_points": struct_points,
                "date_points": date_points,
                "number_points": number_points,
                "category_points": category_points,
                "calculation_points": calc_points,
                "completeness_points": complete_points
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
        cleanup_verification_environment(temp_dir)
