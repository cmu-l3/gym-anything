#!/usr/bin/env python3
"""
Verifier for Carpool Rebalance task
Checks mileage updates, formula corrections, and cost reconciliation
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path for host machine execution
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_carpool_rebalance(traj, env_info, task_info):
    """
    Verify carpool rebalance task completion.
    
    Checks:
    1. Martinez family mileage updated to 5.8 (was 4.2)
    2. Formulas fixed (no #REF errors, correct references)
    3. Cost formulas use correct mileage lookup
    4. Balance reconciled (sum = $0.00 ±$0.50)
    5. Fair share calculated correctly
    6. Math validated (spot checks)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to find the result file
    container_paths = [
        "/home/ga/Documents/carpool_rebalanced.ods",
        "/home/ga/Documents/carpool_schedule.ods",
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path in container_paths:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format='ods'
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

    try:
        # Get sheet names
        sheets = workbook.get('sheets', {})
        sheet_names = list(sheets.keys())
        
        if len(sheet_names) < 3:
            return {"passed": False, "score": 0, "feedback": f"Expected 3 sheets, found {len(sheet_names)}"}
        
        # Find sheets by name (case-insensitive partial match)
        drive_log_sheet = None
        family_info_sheet = None
        cost_summary_sheet = None
        
        for name in sheet_names:
            name_lower = name.lower()
            if 'drive' in name_lower and 'log' in name_lower:
                drive_log_sheet = name
            elif 'family' in name_lower and 'info' in name_lower:
                family_info_sheet = name
            elif 'cost' in name_lower and 'summary' in name_lower:
                cost_summary_sheet = name
        
        if not all([drive_log_sheet, family_info_sheet, cost_summary_sheet]):
            return {"passed": False, "score": 0, 
                   "feedback": f"Could not find all required sheets. Found: {sheet_names}"}
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # === CRITERION 1: Mileage Updated ===
        # Find Martinez row in Family Info (should be row 5, but let's search)
        martinez_mileage = None
        martinez_row = None
        family_info_rows = sheets[family_info_sheet]
        
        for i, row in enumerate(family_info_rows[1:], start=2):  # Skip header
            if len(row) > 0:
                family_cell = row[0] if len(row) > 0 else {}
                family_name = family_cell.get('value') if isinstance(family_cell, dict) else family_cell
                if family_name and 'martinez' in str(family_name).lower():
                    martinez_row = i
                    if len(row) > 2:
                        mileage_cell = row[2]
                        martinez_mileage = mileage_cell.get('value') if isinstance(mileage_cell, dict) else mileage_cell
                    break
        
        mileage_correct = False
        if martinez_mileage is not None:
            try:
                mileage_float = float(martinez_mileage)
                if abs(mileage_float - 5.8) < 0.1:
                    criteria_passed += 1
                    mileage_correct = True
                    feedback_parts.append(f"✅ Martinez mileage updated to {mileage_float:.1f} miles")
                else:
                    feedback_parts.append(f"❌ Martinez mileage is {mileage_float:.1f}, expected 5.8")
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Martinez mileage invalid: {martinez_mileage}")
        else:
            feedback_parts.append("❌ Could not find Martinez family mileage")
        
        subscores['mileage_updated'] = mileage_correct
        
        # === CRITERION 2: Formulas Fixed (no #REF errors) ===
        # Check Cost Summary sheet for formulas in Total Miles column (column C)
        cost_summary_rows = sheets[cost_summary_sheet]
        
        # Find the data rows (after header, typically rows 5-9)
        formula_errors = []
        formula_checks = []
        formulas_fixed = True
        
        for i in range(4, min(10, len(cost_summary_rows))):  # Check rows 5-9
            if i < len(cost_summary_rows) and len(cost_summary_rows[i]) > 2:
                total_miles_cell = cost_summary_rows[i][2]  # Column C
                formula = total_miles_cell.get('formula') if isinstance(total_miles_cell, dict) else None
                value = total_miles_cell.get('value') if isinstance(total_miles_cell, dict) else total_miles_cell
                
                if formula:
                    formula_checks.append(formula)
                    # Check for #REF errors
                    if '#REF' in str(formula).upper() or '#REF' in str(value).upper():
                        formula_errors.append(f"Row {i+1} has #REF error")
                        formulas_fixed = False
        
        if formulas_fixed and len(formula_checks) >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas fixed (no #REF errors, {len(formula_checks)} formulas checked)")
        else:
            if formula_errors:
                feedback_parts.append(f"❌ Formula errors found: {'; '.join(formula_errors)}")
            else:
                feedback_parts.append(f"❌ Formulas not properly fixed or missing ({len(formula_checks)} found)")
        
        subscores['formulas_fixed'] = formulas_fixed
        
        # === CRITERION 3: Cost Formulas Correct ===
        # Check that Total Miles formulas use correct VLOOKUP pattern
        correct_formula_pattern = False
        
        for formula in formula_checks[:3]:  # Check first few formulas
            formula_upper = str(formula).upper()
            # Should contain: COUNTIF or B reference, VLOOKUP, column 3, multiplication by 2
            has_vlookup = 'VLOOKUP' in formula_upper
            has_col3 = ',3,' in formula or ', 3,' in formula or ',3)' in formula
            has_multiply_2 = '*2' in formula or '* 2' in formula
            
            if has_vlookup and has_col3 and has_multiply_2:
                correct_formula_pattern = True
                break
        
        if correct_formula_pattern:
            criteria_passed += 1
            feedback_parts.append("✅ Cost formulas use correct mileage lookup (VLOOKUP column 3)")
        else:
            feedback_parts.append("❌ Cost formulas don't use correct pattern (need VLOOKUP with column 3, *2)")
        
        subscores['cost_formula_correct'] = correct_formula_pattern
        
        # === CRITERION 4: Balance Reconciled ===
        # Sum of all balances should equal $0.00 (±$0.50)
        # Balance is in column F (index 5), rows 5-9
        balances = []
        balance_sum = None
        
        for i in range(4, min(10, len(cost_summary_rows))):
            if i < len(cost_summary_rows) and len(cost_summary_rows[i]) > 5:
                balance_cell = cost_summary_rows[i][5]  # Column F
                balance_value = balance_cell.get('value') if isinstance(balance_cell, dict) else balance_cell
                
                if balance_value is not None and balance_value != '':
                    try:
                        balance_float = float(balance_value)
                        balances.append(balance_float)
                    except (ValueError, TypeError):
                        pass
        
        balance_reconciled = False
        if len(balances) >= 3:  # At least 3 families have balances
            balance_sum = sum(balances)
            if abs(balance_sum) <= 0.50:
                criteria_passed += 1
                balance_reconciled = True
                feedback_parts.append(f"✅ Balance reconciled (sum = ${balance_sum:.2f}, within tolerance)")
            else:
                feedback_parts.append(f"❌ Balance not reconciled (sum = ${balance_sum:.2f}, should be ~$0.00)")
        else:
            # Check if there's a total row
            total_row_idx = min(9, len(cost_summary_rows) - 1)
            if total_row_idx < len(cost_summary_rows) and len(cost_summary_rows[total_row_idx]) > 5:
                total_balance_cell = cost_summary_rows[total_row_idx][5]
                total_balance = total_balance_cell.get('value') if isinstance(total_balance_cell, dict) else total_balance_cell
                if total_balance is not None:
                    try:
                        balance_sum = float(total_balance)
                        if abs(balance_sum) <= 0.50:
                            criteria_passed += 1
                            balance_reconciled = True
                            feedback_parts.append(f"✅ Balance reconciled (total row: ${balance_sum:.2f})")
                        else:
                            feedback_parts.append(f"❌ Balance not reconciled (total: ${balance_sum:.2f})")
                    except:
                        pass
            
            if not balance_reconciled:
                feedback_parts.append(f"❌ Balance calculation incomplete ({len(balances)} balances found)")
        
        subscores['balance_reconciled'] = balance_reconciled
        
        # === CRITERION 5: Fair Share Calculated ===
        # Fair share should be in column E (index 4)
        # Should be: total gas cost / 5
        fair_shares = []
        
        for i in range(4, min(10, len(cost_summary_rows))):
            if i < len(cost_summary_rows) and len(cost_summary_rows[i]) > 4:
                fair_share_cell = cost_summary_rows[i][4]  # Column E
                fair_share_value = fair_share_cell.get('value') if isinstance(fair_share_cell, dict) else fair_share_cell
                
                if fair_share_value is not None and fair_share_value != '':
                    try:
                        fs_float = float(fair_share_value)
                        fair_shares.append(fs_float)
                    except (ValueError, TypeError):
                        pass
        
        fair_share_correct = False
        if len(fair_shares) >= 3:
            # All fair shares should be the same value
            if len(set([round(fs, 2) for fs in fair_shares])) == 1:
                criteria_passed += 1
                fair_share_correct = True
                feedback_parts.append(f"✅ Fair share calculated (${fair_shares[0]:.2f} per family)")
            else:
                feedback_parts.append(f"⚠️ Fair shares vary: {[round(fs, 2) for fs in fair_shares]}")
        else:
            feedback_parts.append("❌ Fair share not calculated (column E incomplete)")
        
        subscores['fair_share_calculated'] = fair_share_correct
        
        # === CRITERION 6: Math Validated (Spot Check) ===
        # Verify one family's calculation manually
        # Garcia should have driven 7 times, 4.2 miles one-way
        garcia_drive_count = None
        garcia_mileage = None
        garcia_total_miles = None
        garcia_gas_cost = None
        
        # Get Garcia's drive count from Drive Log
        drive_count_garcia = 0
        for row in sheets[drive_log_sheet][1:]:  # Skip header
            if len(row) > 1:
                driver_cell = row[1]
                driver = driver_cell.get('value') if isinstance(driver_cell, dict) else driver_cell
                if driver and 'garcia' in str(driver).lower():
                    drive_count_garcia += 1
        
        # Get Garcia's mileage from Family Info
        for row in family_info_rows[1:]:
            if len(row) > 0:
                family_cell = row[0]
                family_name = family_cell.get('value') if isinstance(family_cell, dict) else family_cell
                if family_name and 'garcia' in str(family_name).lower():
                    if len(row) > 2:
                        mileage_cell = row[2]
                        garcia_mileage = mileage_cell.get('value') if isinstance(mileage_cell, dict) else mileage_cell
                    break
        
        # Get Garcia's values from Cost Summary
        for row in cost_summary_rows[4:10]:
            if len(row) > 0:
                family_cell = row[0]
                family_name = family_cell.get('value') if isinstance(family_cell, dict) else family_cell
                if family_name and 'garcia' in str(family_name).lower():
                    if len(row) > 2:
                        miles_cell = row[2]
                        garcia_total_miles = miles_cell.get('value') if isinstance(miles_cell, dict) else miles_cell
                    if len(row) > 3:
                        cost_cell = row[3]
                        garcia_gas_cost = cost_cell.get('value') if isinstance(cost_cell, dict) else cost_cell
                    break
        
        math_valid = False
        try:
            # Get gas price and MPG from assumptions (row 2)
            gas_price = None
            mpg = None
            if len(cost_summary_rows) > 1:
                assumption_row = cost_summary_rows[1]
                if len(assumption_row) > 1:
                    gas_price_cell = assumption_row[1]
                    gas_price = gas_price_cell.get('value') if isinstance(gas_price_cell, dict) else gas_price_cell
                if len(assumption_row) > 3:
                    mpg_cell = assumption_row[3]
                    mpg = mpg_cell.get('value') if isinstance(mpg_cell, dict) else mpg_cell
            
            if all(v is not None for v in [drive_count_garcia, garcia_mileage, garcia_total_miles, 
                                           garcia_gas_cost, gas_price, mpg]):
                # Calculate expected values
                expected_total_miles = drive_count_garcia * float(garcia_mileage) * 2
                expected_gas_cost = expected_total_miles * (float(gas_price) / float(mpg))
                
                actual_total_miles = float(garcia_total_miles)
                actual_gas_cost = float(garcia_gas_cost)
                
                miles_match = abs(actual_total_miles - expected_total_miles) < 1.0
                cost_match = abs(actual_gas_cost - expected_gas_cost) < 1.0
                
                if miles_match and cost_match:
                    criteria_passed += 1
                    math_valid = True
                    feedback_parts.append(f"✅ Math validated (Garcia: {drive_count_garcia} drives × {garcia_mileage} mi × 2 = {actual_total_miles:.1f} mi)")
                else:
                    feedback_parts.append(f"❌ Math incorrect (expected {expected_total_miles:.1f} mi, got {actual_total_miles:.1f})")
            else:
                feedback_parts.append("⚠️ Could not validate math (missing data)")
        except Exception as e:
            logger.debug(f"Math validation error: {e}")
            feedback_parts.append("⚠️ Math validation failed")
        
        subscores['math_validated'] = math_valid
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 5/6 criteria (80%)
        
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
        if temp_dir:
            cleanup_verification_temp(temp_dir)
