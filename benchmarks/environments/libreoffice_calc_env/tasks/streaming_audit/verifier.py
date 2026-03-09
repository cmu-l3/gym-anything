#!/usr/bin/env python3
"""
Verifier for Streaming Service Subscription Audit task
"""

import sys
import os
import logging
import re
from datetime import datetime, timedelta

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
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


def normalize_formula(formula):
    """Normalize formula for comparison (remove spaces, uppercase)"""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def check_monthly_cost_formula(formula, row_idx):
    """
    Check if Monthly Cost formula correctly handles Annual vs Monthly billing.
    Expected pattern: IF(C{row}="Annual", B{row}/12, B{row})
    """
    if not formula:
        return False, "No formula found"
    
    norm = normalize_formula(formula)
    
    # Check for IF statement
    if 'IF' not in norm:
        return False, "Missing IF statement"
    
    # Check for reference to billing cycle column (C)
    if f'C{row_idx}' not in norm:
        return False, f"Missing reference to billing cycle (C{row_idx})"
    
    # Check for "Annual" condition
    if 'ANNUAL' not in norm:
        return False, "Missing 'Annual' condition"
    
    # Check for division by 12
    if '/12' not in norm and '÷12' not in norm:
        return False, "Missing division by 12 for annual subscriptions"
    
    # Check for reference to cost column (B)
    if f'B{row_idx}' not in norm:
        return False, f"Missing reference to cost (B{row_idx})"
    
    return True, "Formula correct"


def check_days_to_renewal_formula(formula, row_idx):
    """
    Check if Days to Renewal uses TODAY() function.
    Expected pattern: D{row}-TODAY()
    """
    if not formula:
        return False, "No formula found"
    
    norm = normalize_formula(formula)
    
    # Check for TODAY function
    if 'TODAY()' not in norm:
        return False, "Missing TODAY() function"
    
    # Check for reference to renewal date column (D)
    if f'D{row_idx}' not in norm:
        return False, f"Missing reference to renewal date (D{row_idx})"
    
    # Check for subtraction
    if '-' not in norm and '−' not in norm:
        return False, "Missing subtraction operation"
    
    return True, "Formula correct"


def check_renewal_alert_formula(formula, days_col_ref, row_idx):
    """
    Check if Renewal Alert flags subscriptions renewing within 30 days.
    Expected pattern: IF({days_col}<=30, "RENEWING SOON", "")
    """
    if not formula:
        return False, "No formula found"
    
    norm = normalize_formula(formula)
    
    # Check for IF statement
    if 'IF' not in norm:
        return False, "Missing IF statement"
    
    # Check for <=30 or similar threshold
    if '<=30' not in norm and '=<30' not in norm and '<30' not in norm and '≤30' not in norm:
        return False, "Missing threshold check (<=30)"
    
    # Check for some text output (RENEWING, SOON, ALERT, etc.)
    if not any(word in norm for word in ['RENEW', 'SOON', 'ALERT', 'DUE']):
        return False, "Missing alert text"
    
    return True, "Formula correct"


def check_cost_per_hour_formula(formula, row_idx, monthly_cost_col):
    """
    Check if Cost/Hour handles division by zero.
    Expected pattern: IF(F{row}=0, "Not Used", {monthly_cost}/F{row})
    """
    if not formula:
        return False, "No formula found"
    
    norm = normalize_formula(formula)
    
    # Check for IF statement (for zero handling)
    if 'IF' not in norm and 'IFERROR' not in norm:
        return False, "Missing IF/IFERROR for zero handling"
    
    # Check for reference to hours column (F)
    if f'F{row_idx}' not in norm:
        return False, f"Missing reference to hours (F{row_idx})"
    
    # Check for division
    if '/' not in norm and '÷' not in norm:
        return False, "Missing division operation"
    
    # Check for zero check (=0, >0, <>"", etc.)
    if '=0' not in norm and '>0' not in norm and '<>0' not in norm and '0=' not in norm:
        # Maybe uses IFERROR instead
        if 'IFERROR' not in norm:
            return False, "Missing zero check"
    
    return True, "Formula correct"


def check_amount_owed_formula(formula, row_idx, monthly_cost_col):
    """
    Check if Amount Owed calculates 50% split for shared subscriptions.
    Expected pattern: IF(E{row}<>"", {monthly_cost}/2, 0)
    """
    if not formula:
        return False, "No formula found"
    
    norm = normalize_formula(formula)
    
    # Check for IF statement
    if 'IF' not in norm:
        return False, "Missing IF statement"
    
    # Check for reference to shared column (E)
    if f'E{row_idx}' not in norm:
        return False, f"Missing reference to Shared With column (E{row_idx})"
    
    # Check for empty/non-empty check
    if '<>""' not in norm and '=""' not in norm and '>""' not in norm:
        # Alternative: ISBLANK check
        if 'ISBLANK' not in norm and 'LEN' not in norm:
            return False, "Missing empty cell check"
    
    # Check for division by 2 (50% split)
    if '/2' not in norm and '÷2' not in norm and '*0.5' not in norm:
        return False, "Missing division by 2 (50% split)"
    
    return True, "Formula correct"


def verify_streaming_audit(traj, env_info, task_info):
    """
    Verify streaming subscription audit task completion.
    
    Checks:
    1. Required columns present (Monthly Cost, Days to Renewal, Renewal Alert, Cost/Hour, Amount Owed)
    2. Monthly Cost formula normalizes annual subscriptions correctly
    3. Renewal Alert flags subscriptions renewing within 30 days
    4. Cost/Hour formula handles division by zero
    5. Total Cost calculation is accurate
    6. Formulas are applied to all data rows
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/streaming_subscriptions.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        sheet_data = workbook['sheets'][sheet_name]

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}

        # Get header row to find column positions
        if len(sheet_data) < 2:
            return {"passed": False, "score": 0, "feedback": "Spreadsheet has insufficient data"}
        
        header_row = sheet_data[0]
        headers = []
        for cell in header_row:
            value = cell.get('value') if isinstance(cell, dict) else cell
            headers.append(str(value).lower() if value else "")
        
        logger.info(f"Headers found: {headers}")
        
        # Find column indices for required columns
        def find_column(keywords):
            for i, h in enumerate(headers):
                if any(kw in h for kw in keywords):
                    return i
            return -1
        
        monthly_cost_col = find_column(['monthly', 'month cost'])
        days_to_renewal_col = find_column(['days', 'renewal', 'days to'])
        renewal_alert_col = find_column(['alert', 'renew', 'flag'])
        cost_per_hour_col = find_column(['cost/hour', 'per hour', 'cost per'])
        amount_owed_col = find_column(['owed', 'amount owed', 'due'])
        
        # Original data columns
        service_col = 0  # A
        cost_col = 1  # B
        billing_col = 2  # C
        renewal_date_col = 3  # D
        shared_col = 4  # E
        hours_col = 5  # F
        
        logger.info(f"Column positions - Monthly Cost: {monthly_cost_col}, Days: {days_to_renewal_col}, "
                   f"Alert: {renewal_alert_col}, Cost/Hour: {cost_per_hour_col}, Amount Owed: {amount_owed_col}")
        
        # Criterion 1: Required columns present
        required_cols = {
            'Monthly Cost': monthly_cost_col >= 0,
            'Days to Renewal': days_to_renewal_col >= 0,
            'Renewal Alert': renewal_alert_col >= 0,
            'Cost/Hour': cost_per_hour_col >= 0,
            'Amount Owed': amount_owed_col >= 0
        }
        
        missing_cols = [name for name, present in required_cols.items() if not present]
        
        if not missing_cols:
            criteria_passed += 1
            feedback_parts.append("✅ All required columns present")
            subscores['columns_present'] = True
        else:
            feedback_parts.append(f"❌ Missing columns: {', '.join(missing_cols)}")
            subscores['columns_present'] = False
        
        # Get data rows (skip header, process rows 2-9 which are indices 1-8)
        data_rows = sheet_data[1:9] if len(sheet_data) >= 9 else sheet_data[1:]
        num_data_rows = len(data_rows)
        
        if num_data_rows < 6:
            feedback_parts.append(f"⚠️ Warning: Only {num_data_rows} data rows found (expected 8)")
        
        # Criterion 2: Monthly Cost formula normalizes correctly
        if monthly_cost_col >= 0 and num_data_rows > 0:
            # Check formula in first data row (row 2, index 1)
            row_idx = 2
            cell_ref = f"{chr(65 + monthly_cost_col)}{row_idx}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            
            formula_ok, msg = check_monthly_cost_formula(formula, row_idx)
            
            # Also verify calculation correctness
            calculation_ok = False
            if formula_ok:
                # Check a few rows to verify calculations
                correct_calcs = 0
                for i, row in enumerate(data_rows[:min(4, num_data_rows)]):
                    r_idx = i + 2
                    
                    if len(row) <= monthly_cost_col or len(row) <= billing_col or len(row) <= cost_col:
                        continue
                    
                    cost_cell = row[cost_col]
                    billing_cell = row[billing_col]
                    monthly_cell = row[monthly_cost_col]
                    
                    cost_val = cost_cell.get('value') if isinstance(cost_cell, dict) else cost_cell
                    billing_val = billing_cell.get('value') if isinstance(billing_cell, dict) else billing_cell
                    monthly_val = monthly_cell.get('value') if isinstance(monthly_cell, dict) else monthly_cell
                    
                    if not cost_val or not billing_val or not monthly_val:
                        continue
                    
                    try:
                        cost_num = float(cost_val)
                        monthly_num = float(monthly_val)
                        
                        if 'annual' in str(billing_val).lower():
                            expected = cost_num / 12
                            if abs(monthly_num - expected) < 0.01:
                                correct_calcs += 1
                        elif 'monthly' in str(billing_val).lower():
                            if abs(monthly_num - cost_num) < 0.01:
                                correct_calcs += 1
                    except (ValueError, TypeError):
                        pass
                
                calculation_ok = correct_calcs >= 2  # At least 2 correct calculations
            
            if formula_ok and calculation_ok:
                criteria_passed += 1
                feedback_parts.append(f"✅ Monthly Cost normalization correct")
                subscores['monthly_cost_correct'] = True
            else:
                if not formula_ok:
                    feedback_parts.append(f"❌ Monthly Cost formula issue: {msg}")
                else:
                    feedback_parts.append(f"❌ Monthly Cost calculations incorrect")
                subscores['monthly_cost_correct'] = False
        else:
            feedback_parts.append("❌ Monthly Cost column not found")
            subscores['monthly_cost_correct'] = False
        
        # Criterion 3: Renewal Alert flags subscriptions renewing soon
        if renewal_alert_col >= 0 and days_to_renewal_col >= 0 and num_data_rows > 0:
            row_idx = 2
            cell_ref = f"{chr(65 + renewal_alert_col)}{row_idx}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            days_col_letter = chr(65 + days_to_renewal_col)
            
            formula_ok, msg = check_renewal_alert_formula(formula, days_col_letter, row_idx)
            
            # Verify that at least one subscription has alert (based on setup, we have some within 30 days)
            has_alert = False
            for row in data_rows:
                if len(row) <= renewal_alert_col:
                    continue
                alert_cell = row[renewal_alert_col]
                alert_val = alert_cell.get('value') if isinstance(alert_cell, dict) else alert_cell
                if alert_val and str(alert_val).strip():
                    has_alert = True
                    break
            
            if formula_ok and has_alert:
                criteria_passed += 1
                feedback_parts.append("✅ Renewal alerts working correctly")
                subscores['renewal_alerts_correct'] = True
            else:
                if not formula_ok:
                    feedback_parts.append(f"❌ Renewal Alert formula issue: {msg}")
                elif not has_alert:
                    feedback_parts.append("❌ No renewal alerts found (expected some within 30 days)")
                subscores['renewal_alerts_correct'] = False
        else:
            feedback_parts.append("❌ Renewal Alert or Days to Renewal column not found")
            subscores['renewal_alerts_correct'] = False
        
        # Criterion 4: Cost/Hour handles division by zero
        if cost_per_hour_col >= 0 and monthly_cost_col >= 0 and num_data_rows > 0:
            row_idx = 2
            cell_ref = f"{chr(65 + cost_per_hour_col)}{row_idx}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            monthly_col_letter = chr(65 + monthly_cost_col)
            
            formula_ok, msg = check_cost_per_hour_formula(formula, row_idx, monthly_col_letter)
            
            # Check that zero hours is handled (should show text like "Not Used" or similar)
            zero_handled = False
            for row in data_rows:
                if len(row) <= hours_col or len(row) <= cost_per_hour_col:
                    continue
                hours_cell = row[hours_col]
                cph_cell = row[cost_per_hour_col]
                
                hours_val = hours_cell.get('value') if isinstance(hours_cell, dict) else hours_cell
                cph_val = cph_cell.get('value') if isinstance(cph_cell, dict) else cph_cell
                
                # If hours is 0, cost/hour should be text (not number/error)
                if hours_val == 0 or hours_val == '0':
                    if isinstance(cph_val, str) and cph_val:
                        zero_handled = True
                        break
            
            if formula_ok and (zero_handled or num_data_rows < 6):  # zero_handled or no zero case found
                criteria_passed += 1
                feedback_parts.append("✅ Cost/Hour calculation with zero handling correct")
                subscores['cost_per_hour_correct'] = True
            else:
                if not formula_ok:
                    feedback_parts.append(f"❌ Cost/Hour formula issue: {msg}")
                else:
                    feedback_parts.append("❌ Cost/Hour doesn't handle zero hours properly")
                subscores['cost_per_hour_correct'] = False
        else:
            feedback_parts.append("❌ Cost/Hour column not found")
            subscores['cost_per_hour_correct'] = False
        
        # Criterion 5: Total Cost calculation (optional but check if present)
        # Look for SUM formula in any cell
        total_found = False
        total_correct = False
        
        # Calculate expected total from monthly costs
        expected_total = 0
        if monthly_cost_col >= 0:
            for row in data_rows:
                if len(row) <= monthly_cost_col:
                    continue
                monthly_cell = row[monthly_cost_col]
                monthly_val = monthly_cell.get('value') if isinstance(monthly_cell, dict) else monthly_cell
                if monthly_val:
                    try:
                        expected_total += float(monthly_val)
                    except (ValueError, TypeError):
                        pass
        
        # Search for SUM formulas in likely locations (bottom of Monthly Cost column or separate area)
        if monthly_cost_col >= 0:
            monthly_col_letter = chr(65 + monthly_cost_col)
            # Check rows 10-15 for totals
            for check_row in range(10, 16):
                cell_ref = f"{monthly_col_letter}{check_row}"
                formula = get_cell_formula(workbook, sheet_name, cell_ref)
                if formula and 'SUM' in normalize_formula(formula):
                    total_found = True
                    value = get_cell_value(workbook, sheet_name, cell_ref)
                    if value:
                        try:
                            if abs(float(value) - expected_total) < 1.0:  # Within $1
                                total_correct = True
                                break
                        except (ValueError, TypeError):
                            pass
        
        if total_correct:
            criteria_passed += 1
            feedback_parts.append(f"✅ Total monthly cost calculated correctly (${expected_total:.2f})")
            subscores['total_cost_correct'] = True
        elif total_found:
            feedback_parts.append(f"⚠️ Total found but value may be incorrect")
            subscores['total_cost_correct'] = False
        else:
            feedback_parts.append(f"⚠️ Total monthly cost not found (optional but recommended)")
            subscores['total_cost_correct'] = False
        
        # Criterion 6: Formulas applied consistently to all rows
        formulas_consistent = True
        if monthly_cost_col >= 0 and num_data_rows >= 6:
            # Check that at least rows 2-7 have formulas in monthly cost column
            rows_with_formulas = 0
            for i in range(2, min(8, num_data_rows + 2)):
                cell_ref = f"{chr(65 + monthly_cost_col)}{i}"
                formula = get_cell_formula(workbook, sheet_name, cell_ref)
                if formula:
                    rows_with_formulas += 1
            
            formulas_consistent = rows_with_formulas >= min(6, num_data_rows)
        
        if formulas_consistent:
            criteria_passed += 1
            feedback_parts.append("✅ Formulas applied consistently to all data rows")
            subscores['formulas_consistent'] = True
        else:
            feedback_parts.append(f"❌ Formulas not applied to all rows (found {rows_with_formulas}/{num_data_rows})")
            subscores['formulas_consistent'] = False
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 5/6 criteria
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: {criteria_passed}/{total_criteria} criteria passed, score={score}")
        
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
        cleanup_verification_temp(temp_dir)
