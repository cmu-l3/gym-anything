#!/usr/bin/env python3
"""
Verifier for Eldercare Medication Reconciliation task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_numeric_value(cell_value):
    """Extract numeric value from cell, handling $ signs and text"""
    if cell_value is None:
        return None
    if isinstance(cell_value, (int, float)):
        return float(cell_value)
    # Try to extract number from string
    if isinstance(cell_value, str):
        # Remove $ and other non-numeric characters except . and -
        cleaned = re.sub(r'[^\d.\-]', '', cell_value)
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def verify_med_reconciliation(traj, env_info, task_info):
    """
    Verify eldercare medication reconciliation spreadsheet.

    Checks:
    1. All 8 medications are entered in data table
    2. Key medications are correctly extracted (Metformin, Amlodipine, Atorvastatin, Lisinopril)
    3. Total cost calculation is correct (~$335.00)
    4. Equal 3-way split is calculated (~$111.67)
    5. Individual payment totals are calculated
    6. Balance calculations exist and are mathematically consistent
    7. High-cost items (>$75) are flagged
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/november_med_reconciliation.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_med_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Get the active sheet
        sheet = wb.active
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []

        # Get all data for analysis
        sheet_data = get_sheet_data(wb, sheet.title, max_rows=25, max_cols=10)

        # --- Criterion 1: Check data completeness (8 medication entries) ---
        # Look for data rows (should have dates, names, costs)
        data_rows = 0
        cost_cells = []
        
        for row_idx in range(1, 15):  # Check rows 2-14 for data
            # Check if row has date-like and cost-like content
            row_has_data = False
            for col_idx in range(0, 6):  # Check first 6 columns
                cell_val = sheet.cell(row=row_idx, column=col_idx+1).value
                if cell_val and str(cell_val).strip():
                    row_has_data = True
                    # Track costs in column E (5th column)
                    if col_idx == 4:  # Cost column
                        numeric_val = extract_numeric_value(cell_val)
                        if numeric_val and numeric_val > 5:  # Reasonable cost
                            cost_cells.append(numeric_val)
                            data_rows += 1
                            break
            
        if data_rows >= 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Data completeness: {data_rows} medication entries found")
        elif data_rows >= 6:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Partial data: {data_rows}/8 medications entered")
        else:
            feedback_parts.append(f"❌ Insufficient data: only {data_rows}/8 medications found")

        # --- Criterion 2: Verify key medications are present ---
        # Search all cells for medication names
        all_text = []
        for row in sheet_data[:15]:
            for cell in row:
                if cell:
                    all_text.append(str(cell).lower())
        
        all_text_combined = ' '.join(all_text)
        
        key_meds = {
            'metformin': False,
            'amlodipine': False,
            'atorvastatin': False,
            'lisinopril': False
        }
        
        for med in key_meds:
            if med in all_text_combined:
                key_meds[med] = True
        
        meds_found = sum(key_meds.values())
        if meds_found >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Key medications: All 4 found correctly")
        elif meds_found >= 3:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Key medications: {meds_found}/4 found")
        else:
            feedback_parts.append(f"❌ Key medications: Only {meds_found}/4 found")

        # --- Criterion 3: Verify total cost calculation (~$335.00) ---
        # Search for total cost in various locations
        total_cost_value = None
        expected_total = 335.00
        
        # Expected costs: 47.82 + 89.50 + 15.00 + 18.99 + 12.00 + 72.30 + 55.40 + 23.99 = 335.00
        
        # Search common locations and formulas
        for row_idx in range(1, 25):
            for col_idx in range(1, 10):
                cell_val = sheet.cell(row=row_idx, column=col_idx).value
                numeric_val = extract_numeric_value(cell_val)
                if numeric_val and abs(numeric_val - expected_total) < 2.0:
                    total_cost_value = numeric_val
                    break
            if total_cost_value:
                break
        
        if total_cost_value and abs(total_cost_value - expected_total) < 2.0:
            criteria_passed += 1
            feedback_parts.append(f"✅ Total cost correct: ${total_cost_value:.2f}")
        else:
            # Alternative: sum the cost_cells we found
            if cost_cells and len(cost_cells) >= 6:
                actual_sum = sum(cost_cells)
                if abs(actual_sum - expected_total) < 2.0:
                    criteria_passed += 0.7
                    feedback_parts.append(f"⚠️ Total cost approx: ${actual_sum:.2f} (calculation may be missing)")
                else:
                    feedback_parts.append(f"❌ Total cost incorrect (expected ${expected_total:.2f})")
            else:
                feedback_parts.append(f"❌ Total cost not found or incorrect")

        # --- Criterion 4: Verify equal split calculation (~$111.67) ---
        cost_per_person = None
        expected_per_person = 111.67
        
        for row_idx in range(1, 25):
            for col_idx in range(1, 10):
                cell_val = sheet.cell(row=row_idx, column=col_idx).value
                numeric_val = extract_numeric_value(cell_val)
                if numeric_val and abs(numeric_val - expected_per_person) < 2.0:
                    cost_per_person = numeric_val
                    break
            if cost_per_person:
                break
        
        if cost_per_person and abs(cost_per_person - expected_per_person) < 2.0:
            criteria_passed += 1
            feedback_parts.append(f"✅ Equal split calculated: ${cost_per_person:.2f} per person")
        else:
            feedback_parts.append(f"❌ Equal split not found (expected ~${expected_per_person:.2f})")

        # --- Criterion 5: Verify individual payment totals ---
        # Expected: Mike: 122.21, Sarah: 125.49, You: 87.30
        expected_payments = {
            'mike': 122.21,
            'sarah': 125.49,
            'you': 87.30
        }
        
        # Search for these values and associated text
        payment_values_found = []
        for row_idx in range(1, 25):
            row_text = []
            for col_idx in range(1, 5):
                cell_val = sheet.cell(row=row_idx, column=col_idx).value
                if cell_val:
                    row_text.append(str(cell_val).lower())
            
            row_text_combined = ' '.join(row_text)
            
            # Check if this row has a person's name and their payment
            for person, expected_amt in expected_payments.items():
                if person in row_text_combined or (person == 'you' and ('me' in row_text_combined or 'i' in row_text_combined)):
                    # Look for the payment amount in this row
                    for col_idx in range(1, 10):
                        cell_val = sheet.cell(row=row_idx, column=col_idx).value
                        numeric_val = extract_numeric_value(cell_val)
                        if numeric_val and abs(numeric_val - expected_amt) < 5.0:
                            payment_values_found.append(person)
                            break
        
        if len(payment_values_found) >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Individual payment totals calculated for all 3 people")
        elif len(payment_values_found) >= 2:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Individual payments: {len(payment_values_found)}/3 found")
        else:
            feedback_parts.append(f"❌ Individual payment totals missing or incorrect")

        # --- Criterion 6: Verify balance calculations ---
        # Balances: Mike: +10.54, Sarah: +13.82, You: -24.37
        # They should sum to approximately 0
        balance_values = []
        
        for row_idx in range(10, 25):
            for col_idx in range(1, 10):
                cell_val = sheet.cell(row=row_idx, column=col_idx).value
                numeric_val = extract_numeric_value(cell_val)
                if numeric_val and abs(numeric_val) < 50:  # Balance values are small
                    # Check if previous column or same row mentions "balance"
                    row_has_balance = False
                    for check_col in range(1, 5):
                        check_val = sheet.cell(row=row_idx, column=check_col).value
                        if check_val and 'balance' in str(check_val).lower():
                            row_has_balance = True
                            break
                    
                    if row_has_balance:
                        balance_values.append(numeric_val)
        
        if len(balance_values) >= 3:
            # Check if they sum to approximately zero
            balance_sum = sum(balance_values)
            if abs(balance_sum) < 2.0:
                criteria_passed += 1
                feedback_parts.append(f"✅ Balance calculations correct (sum: ${balance_sum:.2f})")
            else:
                criteria_passed += 0.5
                feedback_parts.append(f"⚠️ Balances found but don't sum to zero: ${balance_sum:.2f}")
        else:
            feedback_parts.append(f"❌ Balance calculations missing ({len(balance_values)}/3 found)")

        # --- Criterion 7: Verify high-cost flagging (>$75) ---
        # Items over $75: Amlodipine ($89.50) and possibly Lisinopril ($72.30, but that's under)
        # Actually only Amlodipine should be flagged
        high_cost_flags = 0
        
        for row_idx in range(1, 15):
            # Check if row has a cost over $75
            cost_val = None
            flag_val = None
            
            for col_idx in range(4, 7):  # Cost likely in columns 5-6
                cell_val = sheet.cell(row=row_idx, column=col_idx).value
                numeric_val = extract_numeric_value(cell_val)
                if numeric_val and numeric_val > 75:
                    cost_val = numeric_val
                    # Check next column or same row for flag
                    for flag_col in range(col_idx, col_idx+3):
                        flag_cell = sheet.cell(row=row_idx, column=flag_col).value
                        if flag_cell and ('high' in str(flag_cell).lower() or 'discuss' in str(flag_cell).lower()):
                            high_cost_flags += 1
                            flag_val = flag_cell
                            break
                    break
        
        if high_cost_flags >= 1:
            criteria_passed += 1
            feedback_parts.append(f"✅ High-cost items flagged correctly ({high_cost_flags} found)")
        else:
            feedback_parts.append(f"❌ High-cost flagging missing (expected at least 1 item >$75)")

        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

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
