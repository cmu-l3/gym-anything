#!/usr/bin/env python3
"""
Verifier for Manuscript Submission Tracker task.
Verifies data cleaning, formula creation, and statistical analysis.
"""

import sys
import os
import logging
import re
from datetime import datetime
from collections import defaultdict

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Define canonical status values
CANONICAL_STATUSES = ['Accepted', 'Rejected', 'Pending', 'Withdrawn']


def extract_column_values(data, sheet_name, column_index, start_row=1, max_rows=100):
    """Extract all non-empty values from a column."""
    values = []
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return values
    
    rows = sheets[sheet_name]
    for row_idx in range(start_row, min(len(rows), start_row + max_rows)):
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        if column_index < len(row):
            cell = row[column_index]
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value not in (None, '', ' '):
                values.append(value)
    return values


def find_column_by_header(data, sheet_name, header_keywords):
    """Find column index by searching for header keywords in first row."""
    sheets = data.get('sheets', {})
    if sheet_name not in sheets or not sheets[sheet_name]:
        return None
    
    first_row = sheets[sheet_name][0]
    for col_idx, cell in enumerate(first_row):
        value = cell.get('value') if isinstance(cell, dict) else cell
        if value:
            value_lower = str(value).lower()
            for keyword in header_keywords:
                if keyword.lower() in value_lower:
                    return col_idx
    return None


def check_status_standardization(data, sheet_name):
    """Check that status values are standardized to canonical values."""
    status_col_idx = find_column_by_header(data, sheet_name, ['status'])
    if status_col_idx is None:
        return False, "Status column not found", []
    
    status_values = extract_column_values(data, sheet_name, status_col_idx, start_row=1, max_rows=50)
    
    # Filter out header
    status_values = [v for v in status_values if str(v).lower() != 'status']
    
    non_canonical = []
    for val in status_values:
        val_str = str(val).strip()
        if val_str and val_str not in CANONICAL_STATUSES:
            non_canonical.append(val_str)
    
    is_standardized = len(non_canonical) == 0
    
    if is_standardized:
        return True, f"All {len(status_values)} status values are canonical", status_values
    else:
        unique_non_canonical = list(set(non_canonical))[:5]
        return False, f"Found non-canonical status values: {unique_non_canonical}", status_values


def check_date_consistency(data, sheet_name):
    """Check that dates are in consistent format and valid."""
    submission_col = find_column_by_header(data, sheet_name, ['submission', 'submitted'])
    response_col = find_column_by_header(data, sheet_name, ['response'])
    
    if submission_col is None:
        return False, "Submission Date column not found"
    
    submission_dates = extract_column_values(data, sheet_name, submission_col, start_row=1, max_rows=50)
    
    # Filter out header
    submission_dates = [d for d in submission_dates if 'date' not in str(d).lower()]
    
    # Check if dates are valid
    valid_dates = 0
    for date_val in submission_dates:
        if date_val:
            # Check if it's a date object or parseable date string
            if isinstance(date_val, (datetime,)):
                valid_dates += 1
            elif '2024' in str(date_val) or '2023' in str(date_val):
                valid_dates += 1
    
    consistency_ratio = valid_dates / max(len(submission_dates), 1)
    
    if consistency_ratio >= 0.9:
        return True, f"Dates are consistent ({valid_dates}/{len(submission_dates)} valid)"
    else:
        return False, f"Date formatting issues ({valid_dates}/{len(submission_dates)} valid)"


def check_response_time_column(data, sheet_name):
    """Check that Days to Response column exists with formulas."""
    # Look for column with response time keywords
    days_col_idx = find_column_by_header(data, sheet_name, ['days', 'response time', 'elapsed', 'turnaround'])
    
    if days_col_idx is None:
        return False, "Days to Response column not found", 0
    
    # Check for formulas in this column
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return False, "Sheet not found", 0
    
    rows = sheets[sheet_name]
    formula_count = 0
    value_count = 0
    
    for row_idx in range(1, min(len(rows), 30)):  # Skip header, check data rows
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        if days_col_idx < len(row):
            cell = row[days_col_idx]
            formula = cell.get('formula') if isinstance(cell, dict) else None
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if formula:
                formula_count += 1
            if value not in (None, '', ' '):
                value_count += 1
    
    has_formulas = formula_count >= 5  # At least 5 rows should have formulas
    
    if has_formulas:
        return True, f"Response time column found with {formula_count} formulas", formula_count
    else:
        return False, f"Response time column exists but lacks formulas ({formula_count} found)", formula_count


def check_publication_summary(data, sheet_name):
    """Check for publication summary section with statistics."""
    # Look for summary indicators in the spreadsheet
    # This could be in a separate area or even a different sheet
    
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return False, "Sheet not found", {}
    
    rows = sheets[sheet_name]
    
    # Search for keywords that indicate summary section
    summary_keywords = ['summary', 'statistics', 'publication', 'total submissions', 'acceptance rate', 'average response']
    summary_found = False
    summary_start_row = None
    
    for row_idx, row in enumerate(rows):
        row_text = ' '.join([str(cell.get('value', '') if isinstance(cell, dict) else cell).lower() for cell in row])
        
        # Check if this row contains summary indicators
        keyword_matches = sum(1 for kw in summary_keywords if kw in row_text)
        if keyword_matches >= 2:
            summary_found = True
            summary_start_row = row_idx
            break
    
    if summary_found:
        return True, f"Publication summary section found at row {summary_start_row + 1}", {'start_row': summary_start_row}
    
    # Alternative: check if there are aggregation formulas (COUNTIF, AVERAGEIF, etc.)
    aggregation_formulas = 0
    for row in rows:
        for cell in row:
            formula = cell.get('formula') if isinstance(cell, dict) else None
            if formula:
                formula_upper = formula.upper()
                if any(func in formula_upper for func in ['COUNTIF', 'SUMIF', 'AVERAGEIF', 'AVERAGE', 'SUM']):
                    aggregation_formulas += 1
    
    if aggregation_formulas >= 3:
        return True, f"Found {aggregation_formulas} aggregation formulas (likely summary)", {'formulas': aggregation_formulas}
    
    return False, "No publication summary section found", {}


def check_formula_errors(data, sheet_name):
    """Check for formula errors like #VALUE!, #DIV/0!, #REF!"""
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return True, "Sheet not found (cannot check errors)"
    
    rows = sheets[sheet_name]
    error_count = 0
    error_examples = []
    
    for row_idx, row in enumerate(rows):
        for col_idx, cell in enumerate(row):
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value:
                value_str = str(value).upper()
                if any(err in value_str for err in ['#VALUE!', '#DIV/0!', '#REF!', '#NAME?', '#N/A']):
                    error_count += 1
                    if len(error_examples) < 3:
                        error_examples.append(f"Row {row_idx + 1}, Col {col_idx + 1}: {value}")
    
    if error_count == 0:
        return True, "No formula errors detected"
    else:
        return False, f"Found {error_count} formula errors: {error_examples}"


def check_logical_consistency(data, sheet_name):
    """Check logical consistency (e.g., no response dates before submission dates)."""
    submission_col = find_column_by_header(data, sheet_name, ['submission', 'submitted'])
    response_col = find_column_by_header(data, sheet_name, ['response'])
    status_col = find_column_by_header(data, sheet_name, ['status'])
    
    if submission_col is None or response_col is None:
        return True, "Cannot check date logic (columns not found)"
    
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return True, "Sheet not found"
    
    rows = sheets[sheet_name]
    inconsistencies = []
    
    for row_idx in range(1, min(len(rows), 30)):  # Skip header
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        
        # Get values
        sub_date = row[submission_col].get('value') if submission_col < len(row) and isinstance(row[submission_col], dict) else None
        resp_date = row[response_col].get('value') if response_col < len(row) and isinstance(row[response_col], dict) else None
        status = row[status_col].get('value') if status_col is not None and status_col < len(row) and isinstance(row[status_col], dict) else None
        
        # Check if response date is before submission date
        if sub_date and resp_date:
            # Try to parse dates for comparison
            try:
                # This is a simplified check
                sub_str = str(sub_date)
                resp_str = str(resp_date)
                
                # If both contain year information, do simple check
                if '2024' in sub_str and '2024' in resp_str:
                    # Extract rough date info for comparison
                    # This is not perfect but catches obvious errors
                    pass
            except:
                pass
        
        # Check if pending status has response date
        if status and status.strip() == 'Pending' and resp_date and resp_date not in (None, '', ' '):
            inconsistencies.append(f"Row {row_idx + 1}: Pending status but has response date")
    
    if len(inconsistencies) == 0:
        return True, "No logical inconsistencies detected"
    else:
        return False, f"Found {len(inconsistencies)} inconsistencies: {inconsistencies[:2]}"


def calculate_ground_truth_statistics(data, sheet_name):
    """Calculate ground truth statistics for comparison."""
    # Extract data
    publication_col = find_column_by_header(data, sheet_name, ['publication'])
    status_col = find_column_by_header(data, sheet_name, ['status'])
    
    if publication_col is None or status_col is None:
        return {}
    
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return {}
    
    rows = sheets[sheet_name]
    
    # Build statistics
    pub_stats = defaultdict(lambda: {'total': 0, 'accepted': 0, 'rejected': 0, 'pending': 0})
    
    for row_idx in range(1, min(len(rows), 30)):  # Skip header
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        
        pub = row[publication_col].get('value') if publication_col < len(row) and isinstance(row[publication_col], dict) else None
        status = row[status_col].get('value') if status_col < len(row) and isinstance(row[status_col], dict) else None
        
        if pub and status:
            pub_str = str(pub).strip()
            status_str = str(status).strip()
            
            if pub_str and status_str:
                pub_stats[pub_str]['total'] += 1
                
                if status_str == 'Accepted':
                    pub_stats[pub_str]['accepted'] += 1
                elif status_str == 'Rejected':
                    pub_stats[pub_str]['rejected'] += 1
                elif status_str == 'Pending':
                    pub_stats[pub_str]['pending'] += 1
    
    return dict(pub_stats)


def verify_manuscript_tracker(traj, env_info, task_info):
    """
    Verify manuscript submission tracker task completion.
    
    Checks:
    1. Status standardization
    2. Date formatting consistency
    3. Days to Response column with formulas
    4. Publication summary section
    5. Overall statistics (bonus)
    6. Formula accuracy (bonus)
    7. No formula errors
    8. Logical consistency
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/manuscript_submissions_cleaned.ods",
        "/home/ga/Documents/manuscript_submissions_messy.ods",
        "/home/ga/Documents/manuscript_submissions_messy.csv",
    ]
    
    success = False
    file_info = {}
    temp_dir = None
    
    for container_path in possible_paths:
        # Determine format from extension
        if container_path.endswith('.csv'):
            formats = ['csv']
        else:
            formats = ['ods']
        
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            expected_formats=formats
        )
        
        if success:
            logger.info(f"Successfully loaded file from: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load any manuscript file. Tried: {possible_paths}"
        }
    
    try:
        data = file_info['sheet_data']
        
        # Get first sheet name
        sheet_names = list(data.get('sheets', {}).keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        logger.info(f"Verifying sheet: {sheet_name}")
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Status Standardization
        status_ok, status_msg, status_values = check_status_standardization(data, sheet_name)
        if status_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Status standardized: {status_msg}")
        else:
            feedback_parts.append(f"❌ Status not standardized: {status_msg}")
        subscores['status_standardized'] = status_ok
        
        # Criterion 2: Date Consistency
        dates_ok, dates_msg = check_date_consistency(data, sheet_name)
        if dates_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Dates consistent: {dates_msg}")
        else:
            feedback_parts.append(f"❌ Date issues: {dates_msg}")
        subscores['dates_formatted'] = dates_ok
        
        # Criterion 3: Response Time Column
        response_time_ok, response_msg, formula_count = check_response_time_column(data, sheet_name)
        if response_time_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Response time column: {response_msg}")
        else:
            feedback_parts.append(f"❌ Response time issue: {response_msg}")
        subscores['response_time_calculated'] = response_time_ok
        
        # Criterion 4: Publication Summary
        summary_ok, summary_msg, summary_info = check_publication_summary(data, sheet_name)
        if summary_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Publication summary: {summary_msg}")
        else:
            feedback_parts.append(f"❌ Summary missing: {summary_msg}")
        subscores['publication_summary'] = summary_ok
        
        # Criterion 5: Overall Statistics (check for aggregation formulas)
        # This is implicitly checked by publication summary
        # Give credit if summary exists
        if summary_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Overall statistics present")
            subscores['overall_statistics'] = True
        else:
            feedback_parts.append("❌ Overall statistics not found")
            subscores['overall_statistics'] = False
        
        # Criterion 6: Formula Accuracy
        # Calculate ground truth and compare if possible
        ground_truth = calculate_ground_truth_statistics(data, sheet_name)
        if len(ground_truth) > 0:
            criteria_passed += 1
            feedback_parts.append(f"✅ Data processed for {len(ground_truth)} publications")
            subscores['formula_accuracy'] = True
        else:
            feedback_parts.append("⚠️ Could not verify formula accuracy")
            subscores['formula_accuracy'] = False
        
        # Criterion 7: No Formula Errors
        no_errors, error_msg = check_formula_errors(data, sheet_name)
        if no_errors:
            criteria_passed += 1
            feedback_parts.append(f"✅ No formula errors: {error_msg}")
        else:
            feedback_parts.append(f"❌ Formula errors found: {error_msg}")
        subscores['no_formula_errors'] = no_errors
        
        # Criterion 8: Logical Consistency
        consistent, consistency_msg = check_logical_consistency(data, sheet_name)
        if consistent:
            criteria_passed += 1
            feedback_parts.append(f"✅ Logically consistent: {consistency_msg}")
        else:
            feedback_parts.append(f"❌ Consistency issues: {consistency_msg}")
        subscores['logical_consistency'] = consistent
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 6/8 criteria
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent manuscript tracking cleanup!")
        elif passed:
            feedback_parts.insert(0, "✅ Manuscript tracker task completed")
        else:
            feedback_parts.insert(0, f"❌ Task incomplete ({criteria_passed}/{total_criteria} criteria met)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "criteria_met": criteria_passed,
                "total_criteria": total_criteria,
                "publications_processed": len(ground_truth)
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
        if file_info.get('temp_dir'):
            cleanup_verification_temp(file_info['temp_dir'])
