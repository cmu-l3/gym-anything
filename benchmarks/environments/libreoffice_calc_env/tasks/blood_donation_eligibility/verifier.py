#!/usr/bin/env python3
"""
Verifier for Blood Donation Eligibility task
"""

import sys
import os
import logging
from datetime import datetime, timedelta
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_date_flexible(date_str):
    """Parse date from various formats"""
    if not date_str:
        return None
    
    date_str = str(date_str).strip()
    
    # Common date formats
    formats = [
        '%Y-%m-%d',
        '%m/%d/%Y',
        '%d/%m/%Y',
        '%m/%d/%y',
        '%Y/%m/%d',
        '%b %d, %Y',
        '%B %d, %Y',
        '%d-%b-%Y',
        '%d-%B-%Y'
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue
    
    # Try to extract year-month-day pattern
    match = re.search(r'(\d{4})-(\d{1,2})-(\d{1,2})', date_str)
    if match:
        return datetime(int(match.group(1)), int(match.group(2)), int(match.group(3)))
    
    match = re.search(r'(\d{1,2})/(\d{1,2})/(\d{4})', date_str)
    if match:
        return datetime(int(match.group(3)), int(match.group(1)), int(match.group(2)))
    
    return None


def get_waiting_period(donation_type):
    """Get waiting period in days for donation type"""
    donation_type = str(donation_type).strip()
    
    waiting_periods = {
        'Whole Blood': 56,
        'Platelets': 7,
        'Plasma': 28,
        'Double Red Cells': 112,
        'whole blood': 56,
        'platelets': 7,
        'plasma': 28,
        'double red cells': 112
    }
    
    return waiting_periods.get(donation_type, None)


def verify_blood_donation_eligibility(traj, env_info, task_info):
    """
    Verify blood donation eligibility task completion.
    
    Checks:
    1. Required columns present (Days Since, Waiting Period, Eligible?, Next Eligible Date)
    2. Formulas use correct functions (DAYS, TODAY, IF)
    3. Sample calculations are accurate
    4. Eligibility logic is correct
    5. No formula errors
    6. Date formatting applied
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try ODS first, then fall back to CSV
    success = False
    file_info = {}
    error = ""
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/blood_donation_eligibility.ods'),
        ('csv', '/home/ga/Documents/blood_donation_history.csv'),
        ('ods', '/home/ga/Documents/blood_donation_history.ods')
    ]:
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            [file_format]
        )
        if success:
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        data = file_info['sheet_data']
        sheet_names = get_sheet_names(data)
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_rows = data['sheets'][sheet_name]
        
        if len(sheet_rows) < 2:
            return {"passed": False, "score": 0, "feedback": "Insufficient data rows"}

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}

        # Get header row (first row)
        header_row = sheet_rows[0]
        headers = [str(cell.get('value', '') if isinstance(cell, dict) else cell).lower().strip() 
                   for cell in header_row]
        
        logger.info(f"Headers found: {headers}")

        # Criterion 1: Required columns present
        required_keywords = {
            'days_since': ['days since', 'days_since', 'dayssince', 'since donation'],
            'waiting': ['waiting period', 'waiting', 'period', 'wait'],
            'eligible': ['eligible', 'eligibility', 'can donate'],
            'next_date': ['next eligible', 'next date', 'eligible date', 'nexteligible']
        }
        
        columns_found = {key: False for key in required_keywords.keys()}
        
        for key, keywords in required_keywords.items():
            for header in headers:
                if any(keyword in header for keyword in keywords):
                    columns_found[key] = True
                    break
        
        columns_found_count = sum(columns_found.values())
        
        if columns_found_count >= 3:  # At least 3 of 4 key columns
            criteria_passed += 1
            feedback_parts.append(f"✅ Required columns present ({columns_found_count}/4)")
            subscores['columns_present'] = True
        else:
            feedback_parts.append(f"❌ Missing required columns (found {columns_found_count}/4)")
            subscores['columns_present'] = False

        # Criterion 2: Formula functions present
        formulas_found = {'DAYS': False, 'TODAY': False, 'IF': False}
        
        for row in sheet_rows[1:]:  # Skip header
            for cell in row:
                if isinstance(cell, dict):
                    formula = str(cell.get('formula', '')).upper()
                    if formula:
                        if 'DAYS' in formula or 'DAY' in formula:
                            formulas_found['DAYS'] = True
                        if 'TODAY' in formula:
                            formulas_found['TODAY'] = True
                        if 'IF' in formula:
                            formulas_found['IF'] = True
        
        logger.info(f"Formulas found: {formulas_found}")
        
        if formulas_found['DAYS'] and formulas_found['IF']:
            criteria_passed += 1
            feedback_parts.append("✅ Correct formula functions used (DAYS, IF)")
            subscores['correct_formulas'] = True
        else:
            missing = [k for k, v in formulas_found.items() if not v and k in ['DAYS', 'IF']]
            feedback_parts.append(f"❌ Missing formula functions: {', '.join(missing)}")
            subscores['correct_formulas'] = False

        # Criterion 3-4: Calculation accuracy and eligibility logic
        # Find column indices
        date_col = None
        type_col = None
        days_since_col = None
        waiting_col = None
        eligible_col = None
        
        for i, header in enumerate(headers):
            if 'date' in header and 'next' not in header and 'eligible' not in header:
                date_col = i
            elif 'type' in header or 'donation type' in header:
                type_col = i
            elif any(kw in header for kw in ['days since', 'days_since', 'since donation']):
                days_since_col = i
            elif any(kw in header for kw in ['waiting period', 'waiting', 'period']):
                waiting_col = i
            elif 'eligible' in header and 'next' not in header and 'date' not in header:
                eligible_col = i
        
        logger.info(f"Column indices - Date: {date_col}, Type: {type_col}, Days Since: {days_since_col}, Waiting: {waiting_col}, Eligible: {eligible_col}")
        
        # Sample calculations
        calc_correct_count = 0
        eligibility_correct_count = 0
        sample_count = 0
        today = datetime.now()
        
        for row_idx in range(1, min(4, len(sheet_rows))):  # Check first 3 data rows
            row = sheet_rows[row_idx]
            
            if date_col is not None and date_col < len(row) and type_col is not None and type_col < len(row):
                date_cell = row[date_col].get('value') if isinstance(row[date_col], dict) else row[date_col]
                type_cell = row[type_col].get('value') if isinstance(row[type_col], dict) else row[type_col]
                
                donation_date = parse_date_flexible(date_cell)
                expected_waiting = get_waiting_period(type_cell)
                
                if donation_date and expected_waiting:
                    sample_count += 1
                    
                    # Calculate expected days since
                    expected_days_since = (today - donation_date).days
                    
                    # Check actual days since
                    if days_since_col is not None and days_since_col < len(row):
                        actual_days_cell = row[days_since_col].get('value') if isinstance(row[days_since_col], dict) else row[days_since_col]
                        try:
                            actual_days = float(actual_days_cell)
                            if abs(actual_days - expected_days_since) <= 1:  # Allow ±1 day tolerance
                                calc_correct_count += 1
                        except (ValueError, TypeError):
                            pass
                    
                    # Check waiting period
                    if waiting_col is not None and waiting_col < len(row):
                        actual_waiting_cell = row[waiting_col].get('value') if isinstance(row[waiting_col], dict) else row[waiting_col]
                        try:
                            actual_waiting = float(actual_waiting_cell)
                            if actual_waiting == expected_waiting:
                                pass  # Correct waiting period
                        except (ValueError, TypeError):
                            pass
                    
                    # Check eligibility logic
                    if eligible_col is not None and eligible_col < len(row):
                        eligible_cell = row[eligible_col].get('value') if isinstance(row[eligible_col], dict) else row[eligible_col]
                        expected_eligible = expected_days_since >= expected_waiting
                        actual_eligible = str(eligible_cell).upper() in ['YES', 'TRUE', '1', 'Y']
                        
                        if expected_eligible == actual_eligible:
                            eligibility_correct_count += 1
        
        if sample_count > 0:
            if calc_correct_count >= sample_count * 0.67:  # At least 2/3 correct
                criteria_passed += 1
                feedback_parts.append(f"✅ Calculation accuracy verified ({calc_correct_count}/{sample_count} samples)")
                subscores['calc_accuracy'] = True
            else:
                feedback_parts.append(f"❌ Calculation errors detected ({calc_correct_count}/{sample_count} correct)")
                subscores['calc_accuracy'] = False
            
            if eligibility_correct_count >= sample_count * 0.67:
                criteria_passed += 1
                feedback_parts.append(f"✅ Eligibility logic correct ({eligibility_correct_count}/{sample_count} samples)")
                subscores['eligibility_logic'] = True
            else:
                feedback_parts.append(f"❌ Eligibility logic errors ({eligibility_correct_count}/{sample_count} correct)")
                subscores['eligibility_logic'] = False
        else:
            feedback_parts.append("⚠️ Could not verify calculations (insufficient data)")
            subscores['calc_accuracy'] = False
            subscores['eligibility_logic'] = False

        # Criterion 5: No formula errors
        error_count = 0
        for row in sheet_rows[1:]:
            for cell in row:
                if isinstance(cell, dict):
                    value = str(cell.get('value', ''))
                    if value.startswith('#') and any(err in value for err in ['VALUE', 'REF', 'DIV', 'NAME', 'NUM', 'NULL']):
                        error_count += 1
        
        if error_count == 0:
            criteria_passed += 1
            feedback_parts.append("✅ No formula errors detected")
            subscores['no_errors'] = True
        else:
            feedback_parts.append(f"❌ Formula errors found ({error_count} errors)")
            subscores['no_errors'] = False

        # Criterion 6: Date formatting check
        # Check if there's a "Next Eligible Date" column with date-like values
        next_date_col = None
        for i, header in enumerate(headers):
            if any(kw in header for kw in ['next eligible', 'next date', 'eligible date']):
                next_date_col = i
                break
        
        date_formatted = False
        if next_date_col is not None:
            # Check if values look like dates
            date_like_count = 0
            for row in sheet_rows[1:4]:  # Check first few rows
                if next_date_col < len(row):
                    cell_value = str(row[next_date_col].get('value') if isinstance(row[next_date_col], dict) else row[next_date_col])
                    if parse_date_flexible(cell_value) or '/' in cell_value or '-' in cell_value:
                        date_like_count += 1
            
            if date_like_count >= 2:
                date_formatted = True
        
        if date_formatted:
            criteria_passed += 1
            feedback_parts.append("✅ Date formatting applied")
            subscores['date_formatted'] = True
        else:
            feedback_parts.append("⚠️ Date formatting may not be applied")
            subscores['date_formatted'] = False
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 70% (4/6 criteria)
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(file_info.get('temp_dir'))
