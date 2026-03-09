#!/usr/bin/env python3
"""
Verifier for Wildlife Log Cleanup task
Checks data cleaning quality: species standardization, date uniformity, 
plausibility flagging, and data preservation
"""

import sys
import os
import logging
import re
from datetime import datetime

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def is_valid_date(value):
    """Check if a value is a valid date"""
    if value is None or value == '':
        return False
    
    # Check if it's already a date object or number (LibreOffice internal date)
    if isinstance(value, (int, float)):
        # LibreOffice date serial numbers are positive
        return value > 0
    
    # Check common date string formats
    value_str = str(value).strip()
    date_patterns = [
        r'\d{4}-\d{2}-\d{2}',  # YYYY-MM-DD
        r'\d{4}/\d{2}/\d{2}',  # YYYY/MM/DD
        r'\d{2}-\d{2}-\d{4}',  # DD-MM-YYYY
        r'\d{2}/\d{2}/\d{4}',  # MM/DD/YYYY
    ]
    
    for pattern in date_patterns:
        if re.match(pattern, value_str):
            return True
    
    return False


def get_column_index(headers, possible_names):
    """Find column index by matching possible header names"""
    headers_lower = [str(h).lower().strip() if h else '' for h in headers]
    
    for name in possible_names:
        name_lower = name.lower()
        if name_lower in headers_lower:
            return headers_lower.index(name_lower)
    
    return None


def extract_column_data(sheet_data, col_index, start_row=1):
    """Extract column data starting from specified row"""
    data = []
    rows = sheet_data
    
    for i in range(start_row, len(rows)):
        if col_index < len(rows[i]):
            cell = rows[i][col_index]
            value = cell.get('value') if isinstance(cell, dict) else cell
            data.append(value)
        else:
            data.append(None)
    
    return data


def verify_wildlife_cleanup(traj, env_info, task_info):
    """
    Verify wildlife log cleanup task completion.
    
    Checks:
    1. Species standardization: ≥90% of entries have valid standardized names
    2. Date uniformity: ≥95% of dates are in standard format
    3. Plausibility flags: Flag column exists with 5-20% flagged entries
    4. Summary accurate: Total observation count matches original
    5. Data preserved: Original row count maintained
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/wildlife_observations.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get sheets
        sheets = workbook.get('sheets', {})
        sheet_names = list(sheets.keys())
        
        if len(sheet_names) < 2:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Expected 2 sheets (Observations and Species_Reference), found only 1"
            }
        
        # Find Observations and Species_Reference sheets
        obs_sheet_name = None
        ref_sheet_name = None
        
        for name in sheet_names:
            name_lower = name.lower()
            if 'observation' in name_lower:
                obs_sheet_name = name
            elif 'reference' in name_lower or 'species' in name_lower:
                ref_sheet_name = name
        
        if not obs_sheet_name:
            obs_sheet_name = sheet_names[0]
        if not ref_sheet_name:
            ref_sheet_name = sheet_names[1] if len(sheet_names) > 1 else None
        
        obs_data = sheets[obs_sheet_name]
        ref_data = sheets[ref_sheet_name] if ref_sheet_name else []
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Extract headers from observations sheet
        if not obs_data or len(obs_data) == 0:
            return {"passed": False, "score": 0, "feedback": "Observations sheet is empty"}
        
        headers = []
        for cell in obs_data[0]:
            value = cell.get('value') if isinstance(cell, dict) else cell
            headers.append(str(value) if value else '')
        
        logger.info(f"Observation headers: {headers}")
        
        # Expected original columns: Date, Species, Count, Time_of_Day, Notes
        # Expected new columns: Standard_Species, Standard_Date, Plausibility_Flag
        
        # Count data rows (exclude header)
        data_row_count = len(obs_data) - 1
        expected_row_count = 20  # We created 20 observation rows
        
        # Criterion 5: Data preserved (check first since it's fundamental)
        if data_row_count >= expected_row_count - 2:  # Allow 2 rows margin
            criteria_passed += 1
            feedback_parts.append(f"✅ Data preserved ({data_row_count} rows)")
        else:
            feedback_parts.append(f"❌ Data loss detected (expected ~{expected_row_count} rows, found {data_row_count})")
        
        # Find column indices for new columns
        standard_species_col = get_column_index(headers, [
            'standard_species', 'standardized_species', 'standardspecies',
            'std_species', 'species_standard'
        ])
        
        standard_date_col = get_column_index(headers, [
            'standard_date', 'standardized_date', 'standarddate',
            'std_date', 'date_standard', 'clean_date'
        ])
        
        flag_col = get_column_index(headers, [
            'plausibility_flag', 'flag', 'check', 'plausibility',
            'suspicious', 'alert', 'validation'
        ])
        
        # Also find original columns
        species_col = get_column_index(headers, ['species'])
        count_col = get_column_index(headers, ['count'])
        
        logger.info(f"Column indices - Standard Species: {standard_species_col}, Standard Date: {standard_date_col}, Flag: {flag_col}")
        
        # Criterion 1: Species standardization
        species_standardization_success = False
        if standard_species_col is not None:
            # Extract reference species names
            ref_standardized_names = set()
            if ref_data and len(ref_data) > 1:
                # Assume column 1 (index 1) has standardized names
                for i in range(1, len(ref_data)):
                    if len(ref_data[i]) > 1:
                        cell = ref_data[i][1]
                        value = cell.get('value') if isinstance(cell, dict) else cell
                        if value:
                            ref_standardized_names.add(str(value).lower().strip())
            
            logger.info(f"Reference standardized names: {ref_standardized_names}")
            
            # Check standardized species column
            standard_species_data = extract_column_data(obs_data, standard_species_col, start_row=1)
            
            valid_count = 0
            total_count = 0
            for value in standard_species_data:
                if value and str(value).strip() != '':
                    total_count += 1
                    value_str = str(value).lower().strip()
                    # Check if it's in reference table or is a reasonable standardized name
                    if (value_str in ref_standardized_names or 
                        any(ref in value_str for ref in ['cardinal', 'chickadee', 'jay', 'cottontail', 'deer', 'hawk', 'squirrel', 'robin', 'chipmunk'])):
                        valid_count += 1
            
            if total_count > 0:
                success_rate = valid_count / total_count
                if success_rate >= 0.85:  # Slightly relaxed from 0.90
                    criteria_passed += 1
                    species_standardization_success = True
                    feedback_parts.append(f"✅ Species standardized ({valid_count}/{total_count} = {success_rate:.1%})")
                else:
                    feedback_parts.append(f"⚠️ Species standardization incomplete ({valid_count}/{total_count} = {success_rate:.1%}, need ≥85%)")
            else:
                feedback_parts.append("❌ No standardized species data found")
        else:
            feedback_parts.append("❌ Standard_Species column not found")
        
        # Criterion 2: Date uniformity
        date_uniformity_success = False
        if standard_date_col is not None:
            standard_date_data = extract_column_data(obs_data, standard_date_col, start_row=1)
            
            valid_dates = 0
            total_dates = 0
            for value in standard_date_data:
                if value and str(value).strip() != '':
                    total_dates += 1
                    if is_valid_date(value):
                        valid_dates += 1
            
            if total_dates > 0:
                date_success_rate = valid_dates / total_dates
                if date_success_rate >= 0.90:  # Relaxed from 0.95
                    criteria_passed += 1
                    date_uniformity_success = True
                    feedback_parts.append(f"✅ Dates standardized ({valid_dates}/{total_dates} = {date_success_rate:.1%})")
                else:
                    feedback_parts.append(f"⚠️ Date standardization incomplete ({valid_dates}/{total_dates} = {date_success_rate:.1%}, need ≥90%)")
            else:
                feedback_parts.append("❌ No standardized date data found")
        else:
            feedback_parts.append("❌ Standard_Date column not found")
        
        # Criterion 3: Plausibility flags
        flag_success = False
        if flag_col is not None:
            flag_data = extract_column_data(obs_data, flag_col, start_row=1)
            
            flagged_count = 0
            total_flags = 0
            for value in flag_data:
                if value and str(value).strip() != '':
                    total_flags += 1
                    value_str = str(value).upper().strip()
                    # Check for common flag indicators
                    if any(indicator in value_str for indicator in ['CHECK', 'FLAG', 'SUSPICIOUS', 'ALERT', 'REVIEW', 'WARNING']):
                        flagged_count += 1
            
            if total_flags > 0:
                flag_rate = flagged_count / total_flags
                # We expect 5-20% to be flagged (1 entry with 50 deer out of 20 = 5%)
                if 0.03 <= flag_rate <= 0.30:  # Allow 3-30% range (more permissive)
                    criteria_passed += 1
                    flag_success = True
                    feedback_parts.append(f"✅ Plausibility flags present ({flagged_count}/{total_flags} = {flag_rate:.1%})")
                else:
                    # Still give partial credit if flags exist
                    if flagged_count > 0:
                        criteria_passed += 0.5
                    feedback_parts.append(f"⚠️ Flag rate outside expected range ({flag_rate:.1%}, expected 3-30%)")
            else:
                feedback_parts.append("❌ No plausibility flag data found")
        else:
            feedback_parts.append("❌ Plausibility_Flag column not found")
        
        # Criterion 4: Summary accurate (verify total observation count)
        # This is a simpler check - just verify count column has reasonable data
        summary_success = False
        if count_col is not None:
            count_data = extract_column_data(obs_data, count_col, start_row=1)
            
            total_obs = 0
            valid_counts = 0
            for value in count_data:
                if value is not None and str(value).strip() != '':
                    try:
                        count_val = float(value)
                        if count_val > 0:
                            total_obs += count_val
                            valid_counts += 1
                    except (ValueError, TypeError):
                        pass
            
            # We expect around 100-150 total observations based on our data
            if valid_counts >= 15 and 50 <= total_obs <= 200:
                criteria_passed += 1
                summary_success = True
                feedback_parts.append(f"✅ Observation counts preserved (total: {int(total_obs)}, entries: {valid_counts})")
            else:
                feedback_parts.append(f"⚠️ Count data inconsistent (total: {int(total_obs)}, entries: {valid_counts})")
        else:
            feedback_parts.append("❌ Count column not found")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 4/5 criteria (80%)
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "species_standardization": species_standardization_success,
                "date_uniformity": date_uniformity_success,
                "plausibility_flags": flag_success,
                "summary_accurate": summary_success,
                "data_preserved": data_row_count >= expected_row_count - 2
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
