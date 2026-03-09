#!/usr/bin/env python3
"""
Verifier for Emergency Supply Rotation task.

Checks:
1. Formulas in "Days Until Expiration" column
2. Formulas in "Status" column with correct IF logic
3. Accuracy of calculations
4. Conditional formatting applied
5. All expiration dates filled
6. No formula errors
7. Data sorted by priority
"""

import sys
import os
import logging
import re
from datetime import datetime, timedelta
import zipfile
from xml.etree import ElementTree as ET

# Add utils to path - use relative path for host machine
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    parse_ods_file
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_conditional_formatting_in_ods(filepath, sheet_name="Sheet1"):
    """
    Check if conditional formatting exists in ODS file.
    Returns dict with formatting info.
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return {'has_formatting': False, 'details': []}
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for conditional formatting in ODS
            # ODS uses calcext:conditional-formats or similar
            formatting_found = False
            details = []
            
            # Check for style:conditional-format or calcext:conditional-formats
            ns = {
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'calcext': 'urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0'
            }
            
            # Look for conditional formatting elements
            for prefix in ['calcext', 'style']:
                cf_elements = root.findall(f'.//{prefix}:conditional-format', ns)
                if cf_elements:
                    formatting_found = True
                    details.append(f"Found {len(cf_elements)} conditional format elements")
                    break
            
            # Alternative: check for data-style or value-type changes indicating formatting
            if not formatting_found:
                # Check if cells have varying styles (could indicate conditional formatting)
                cells = root.findall('.//table:table-cell', ns)
                style_attrs = set()
                for cell in cells[:50]:  # Check first 50 cells
                    style = cell.get(f'{{{ns["table"]}}}style-name')
                    if style:
                        style_attrs.add(style)
                
                if len(style_attrs) > 5:  # Multiple styles suggest formatting
                    formatting_found = True
                    details.append(f"Multiple cell styles detected ({len(style_attrs)} styles)")
            
            return {
                'has_formatting': formatting_found,
                'details': details
            }
    
    except Exception as e:
        logger.debug(f"Error checking conditional formatting: {e}")
        return {'has_formatting': False, 'details': [str(e)]}


def verify_days_formula(formula, expiration_col='D'):
    """
    Verify that the days formula uses date arithmetic with TODAY().
    
    Expected patterns:
    - =DAYS(D2,TODAY())
    - =D2-TODAY()
    - =DATEDIF(TODAY(),D2,"D")
    """
    if not formula:
        return False, "No formula found"
    
    formula_upper = formula.upper().replace(' ', '')
    
    # Check for TODAY() function
    if 'TODAY()' not in formula_upper:
        return False, "Formula doesn't use TODAY()"
    
    # Check for reference to expiration date column
    has_col_ref = expiration_col.upper() in formula_upper
    
    # Check for date calculation method
    has_days_func = 'DAYS(' in formula_upper
    has_subtraction = '-' in formula_upper
    has_datedif = 'DATEDIF(' in formula_upper
    
    has_calculation = has_days_func or has_subtraction or has_datedif
    
    if has_col_ref and has_calculation:
        return True, "Valid date formula"
    
    return False, f"Invalid formula structure: {formula}"


def verify_status_formula(formula, days_col='G'):
    """
    Verify that status formula uses nested IFs with correct thresholds.
    
    Expected logic:
    - IF days < 0: "EXPIRED"
    - IF days <= 30: "IMMEDIATE"  
    - IF days <= 90: "SOON"
    - ELSE: "OK"
    """
    if not formula:
        return False, "No formula found", {}
    
    formula_upper = formula.upper().replace(' ', '').replace('"', '')
    
    checks = {
        'has_if': formula_upper.count('IF(') >= 3,  # Nested IFs
        'has_days_ref': days_col.upper() in formula_upper,
        'has_expired': 'EXPIRED' in formula_upper,
        'has_immediate': 'IMMEDIATE' in formula_upper,
        'has_soon': 'SOON' in formula_upper,
        'has_ok': 'OK' in formula_upper,
        'has_30_threshold': '30' in formula_upper,
        'has_90_threshold': '90' in formula_upper,
        'has_zero_check': '<0' in formula_upper or '<=0' in formula_upper
    }
    
    critical_checks = ['has_if', 'has_days_ref', 'has_expired', 'has_immediate', 'has_30_threshold']
    passed = all(checks[key] for key in critical_checks)
    
    if passed:
        return True, "Valid status formula", checks
    
    missing = [key for key in critical_checks if not checks[key]]
    return False, f"Missing elements: {missing}", checks


def verify_emergency_supply_rotation(traj, env_info, task_info):
    """
    Verify emergency supply rotation task completion.
    
    Checks 9 criteria:
    1. Days formula present
    2. Days calculation accurate
    3. Status formula present
    4. Status categories correct
    5. Days column has conditional formatting
    6. Status column has conditional formatting
    7. All expiration dates filled
    8. No formula errors
    9. Data sorted by priority
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    possible_paths = [
        "/home/ga/Documents/emergency_supplies.ods",
        "/home/ga/Documents/emergency_supplies_partial.ods",
        "/home/ga/Documents/emergency_supplies_partial.csv"
    ]
    
    success = False
    file_info = None
    
    for path in possible_paths:
        file_format = 'ods' if path.endswith('.ods') else 'csv'
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            path, 
            [file_format]
        )
        if success:
            logger.info(f"Successfully loaded file from: {path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load file: {error}. Tried paths: {possible_paths}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = data['sheets'][sheet_name]
        
        # Initialize scoring
        criteria_met = 0
        total_criteria = 9
        feedback_parts = []
        subscores = {}
        
        # Find header row and column indices
        header_row = sheet_data[0] if sheet_data else []
        headers = [cell.get('value', '') if isinstance(cell, dict) else cell for cell in header_row]
        
        # Identify columns
        try:
            days_col_idx = next(i for i, h in enumerate(headers) if 'Days' in str(h) and 'Expiration' in str(h))
            status_col_idx = next(i for i, h in enumerate(headers) if 'Status' in str(h))
            exp_date_col_idx = next(i for i, h in enumerate(headers) if 'Expiration' in str(h) and 'Days' not in str(h))
        except StopIteration:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not find required columns. Found headers: {headers}"
            }
        
        # Convert indices to column letters
        def col_idx_to_letter(idx):
            letter = ''
            idx += 1  # Convert to 1-based
            while idx > 0:
                idx -= 1
                letter = chr(ord('A') + (idx % 26)) + letter
                idx //= 26
            return letter
        
        days_col_letter = col_idx_to_letter(days_col_idx)
        status_col_letter = col_idx_to_letter(status_col_idx)
        exp_col_letter = col_idx_to_letter(exp_date_col_idx)
        
        # CRITERION 1: Days formula present
        days_formula_row2 = get_cell_formula(data, sheet_name, f'{days_col_letter}2')
        days_formula_valid, days_msg = verify_days_formula(days_formula_row2, exp_col_letter)
        
        if days_formula_valid:
            criteria_met += 1
            feedback_parts.append(f"✅ Days formula valid: {days_formula_row2}")
            subscores['days_formula_present'] = True
        else:
            feedback_parts.append(f"❌ Days formula issue: {days_msg}")
            subscores['days_formula_present'] = False
        
        # CRITERION 2: Days calculation accurate
        # Spot check 3 rows with known expiration dates
        accurate_calculations = 0
        total_checks = 0
        
        for row_idx in range(1, min(len(sheet_data), 8)):  # Check first 7 data rows
            exp_date_cell = sheet_data[row_idx][exp_date_col_idx] if len(sheet_data[row_idx]) > exp_date_col_idx else None
            days_cell = sheet_data[row_idx][days_col_idx] if len(sheet_data[row_idx]) > days_col_idx else None
            
            if not exp_date_cell or not days_cell:
                continue
            
            exp_date_val = exp_date_cell.get('value') if isinstance(exp_date_cell, dict) else exp_date_cell
            days_val = days_cell.get('value') if isinstance(days_cell, dict) else days_cell
            
            # Skip if expiration date is empty
            if not exp_date_val or exp_date_val == '':
                continue
            
            # Try to parse expiration date and calculate expected days
            try:
                if isinstance(exp_date_val, str):
                    exp_date = datetime.strptime(exp_date_val.split()[0], "%Y-%m-%d")
                else:
                    # Might be already parsed
                    continue
                
                expected_days = (exp_date - datetime.now()).days
                actual_days = float(days_val) if days_val not in [None, ''] else None
                
                if actual_days is not None:
                    total_checks += 1
                    if abs(actual_days - expected_days) <= 1:  # ±1 day tolerance
                        accurate_calculations += 1
            except:
                continue
        
        if total_checks > 0 and accurate_calculations / total_checks >= 0.7:
            criteria_met += 1
            feedback_parts.append(f"✅ Days calculations accurate ({accurate_calculations}/{total_checks} correct)")
            subscores['days_calculation_accurate'] = True
        elif total_checks > 0:
            feedback_parts.append(f"⚠️ Days calculations may be incorrect ({accurate_calculations}/{total_checks} correct)")
            subscores['days_calculation_accurate'] = False
        else:
            feedback_parts.append("⚠️ Could not verify days calculations")
            subscores['days_calculation_accurate'] = False
        
        # CRITERION 3: Status formula present
        status_formula_row2 = get_cell_formula(data, sheet_name, f'{status_col_letter}2')
        status_formula_valid, status_msg, status_checks = verify_status_formula(status_formula_row2, days_col_letter)
        
        if status_formula_valid:
            criteria_met += 1
            feedback_parts.append(f"✅ Status formula valid with correct thresholds")
            subscores['status_formula_present'] = True
        else:
            feedback_parts.append(f"❌ Status formula issue: {status_msg}")
            subscores['status_formula_present'] = False
        
        # CRITERION 4: Status categories correct
        # Check that status values match expected categories based on days
        correct_status = 0
        total_status = 0
        
        for row_idx in range(1, min(len(sheet_data), 13)):
            days_cell = sheet_data[row_idx][days_col_idx] if len(sheet_data[row_idx]) > days_col_idx else None
            status_cell = sheet_data[row_idx][status_col_idx] if len(sheet_data[row_idx]) > status_col_idx else None
            
            if not days_cell or not status_cell:
                continue
            
            days_val = days_cell.get('value') if isinstance(days_cell, dict) else days_cell
            status_val = status_cell.get('value') if isinstance(status_cell, dict) else status_cell
            
            if days_val in [None, ''] or status_val in [None, '']:
                continue
            
            try:
                days_num = float(days_val)
                status_str = str(status_val).upper()
                
                total_status += 1
                
                # Check if status matches threshold logic
                if days_num < 0 and 'EXPIRED' in status_str:
                    correct_status += 1
                elif 0 <= days_num <= 30 and 'IMMEDIATE' in status_str:
                    correct_status += 1
                elif 30 < days_num <= 90 and 'SOON' in status_str:
                    correct_status += 1
                elif days_num > 90 and 'OK' in status_str:
                    correct_status += 1
            except:
                continue
        
        if total_status > 0 and correct_status / total_status >= 0.8:
            criteria_met += 1
            feedback_parts.append(f"✅ Status categories correct ({correct_status}/{total_status})")
            subscores['status_categories_correct'] = True
        elif total_status > 0:
            feedback_parts.append(f"⚠️ Status categories may be incorrect ({correct_status}/{total_status})")
            subscores['status_categories_correct'] = False
        else:
            feedback_parts.append("⚠️ Could not verify status categories")
            subscores['status_categories_correct'] = False
        
        # CRITERION 5 & 6: Conditional formatting
        # Check if conditional formatting exists (ODS only)
        if file_info['format'] == 'ods':
            cf_info = check_conditional_formatting_in_ods(file_info['file_path'], sheet_name)
            
            if cf_info['has_formatting']:
                criteria_met += 2  # Give credit for both columns
                feedback_parts.append(f"✅ Conditional formatting detected: {', '.join(cf_info['details'])}")
                subscores['days_formatting_applied'] = True
                subscores['status_formatting_applied'] = True
            else:
                feedback_parts.append("⚠️ Conditional formatting not detected (may need manual verification)")
                subscores['days_formatting_applied'] = False
                subscores['status_formatting_applied'] = False
        else:
            feedback_parts.append("⚠️ Cannot verify formatting in CSV format")
            subscores['days_formatting_applied'] = False
            subscores['status_formatting_applied'] = False
        
        # CRITERION 7: All expiration dates filled
        missing_dates = 0
        for row_idx in range(1, min(len(sheet_data), 13)):
            if len(sheet_data[row_idx]) > exp_date_col_idx:
                exp_cell = sheet_data[row_idx][exp_date_col_idx]
                exp_val = exp_cell.get('value') if isinstance(exp_cell, dict) else exp_cell
                if not exp_val or exp_val == '':
                    missing_dates += 1
        
        if missing_dates == 0:
            criteria_met += 1
            feedback_parts.append("✅ All expiration dates filled")
            subscores['all_dates_complete'] = True
        else:
            feedback_parts.append(f"❌ {missing_dates} missing expiration dates")
            subscores['all_dates_complete'] = False
        
        # CRITERION 8: No formula errors
        error_count = 0
        for row_idx in range(1, min(len(sheet_data), 13)):
            for cell in sheet_data[row_idx]:
                cell_val = cell.get('value') if isinstance(cell, dict) else cell
                if cell_val and isinstance(cell_val, str) and '#' in cell_val:
                    if any(err in cell_val for err in ['#REF!', '#VALUE!', '#NAME?', '#DIV/0!', '#N/A']):
                        error_count += 1
        
        if error_count == 0:
            criteria_met += 1
            feedback_parts.append("✅ No formula errors detected")
            subscores['no_formula_errors'] = True
        else:
            feedback_parts.append(f"❌ {error_count} formula errors found")
            subscores['no_formula_errors'] = False
        
        # CRITERION 9: Data sorted by priority (days ascending)
        # Check if days column is in ascending order
        days_values = []
        for row_idx in range(1, min(len(sheet_data), 13)):
            if len(sheet_data[row_idx]) > days_col_idx:
                days_cell = sheet_data[row_idx][days_col_idx]
                days_val = days_cell.get('value') if isinstance(days_cell, dict) else days_cell
                if days_val not in [None, '']:
                    try:
                        days_values.append(float(days_val))
                    except:
                        pass
        
        is_sorted = all(days_values[i] <= days_values[i+1] for i in range(len(days_values)-1)) if len(days_values) > 1 else False
        
        if is_sorted:
            criteria_met += 1
            feedback_parts.append("✅ Data sorted by priority (days ascending)")
            subscores['data_sorted'] = True
        else:
            feedback_parts.append("⚠️ Data not sorted by priority")
            subscores['data_sorted'] = False
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 70% (5/9 criteria)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent emergency supply organization!")
        elif passed:
            feedback_parts.insert(0, "✅ Emergency supply rotation task completed")
        else:
            feedback_parts.insert(0, f"❌ Task incomplete ({criteria_met}/{total_criteria} criteria met)")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "criteria_met": f"{criteria_met}/{total_criteria}"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_temp(file_info.get('temp_dir') if file_info else None)
