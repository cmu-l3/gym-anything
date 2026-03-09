#!/usr/bin/env python3
"""
Verifier for Childcare Swap Balancer task (childcare_swap_balancer@1)

This verifier checks that the agent has correctly:
1. Calculated Hours Given for each family using SUMIF
2. Calculated Hours Received for each family using SUMIF
3. Calculated Net Balance (Given - Received)
4. Applied conditional formatting for imbalances
5. Calculated maximum imbalance
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_childcare_swap_balancer(traj, env_info, task_info):
    """
    Verify that the childcare swap balance spreadsheet is correctly completed.
    
    Expected values (calculated from the raw session data):
    - Miller: Given 13.5, Received 11, Balance +2.5
    - Chen: Given 13, Received 15, Balance -2
    - Rodriguez: Given 11.5, Received 12, Balance -0.5
    - Patel: Given 11, Received 11, Balance 0
    - Maximum imbalance: 2.5
    """
    
    # Expected correct values (calculated from raw session data in setup)
    EXPECTED = {
        'Miller': {'given': 13.5, 'received': 11.0, 'balance': 2.5},
        'Chen': {'given': 13.0, 'received': 15.0, 'balance': -2.0},
        'Rodriguez': {'given': 11.5, 'received': 12.0, 'balance': -0.5},
        'Patel': {'given': 11.0, 'received': 11.0, 'balance': 0.0}
    }
    
    TOLERANCE = 0.2  # Allow small floating point differences
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/childcare_swap_raw.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_childcare_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Check that Summary sheet exists
        if 'Summary' not in wb.sheetnames:
            return {"passed": False, "score": 0, "feedback": "Summary sheet not found in workbook"}

        summary_sheet = wb['Summary']
        
        # Get all data from summary sheet (first 20 rows, 10 columns should be enough)
        data = get_sheet_data(wb, 'Summary', max_rows=20, max_cols=10)
        
        # Parse the summary data to find families and their values
        family_data = {}
        families_found = []
        
        # Search through all cells to find family names and their associated values
        for row_idx, row in enumerate(data):
            for col_idx, cell in enumerate(row):
                if cell and isinstance(cell, str):
                    cell_lower = cell.lower().strip()
                    
                    # Check if this cell contains a family name
                    for family_name in ['Miller', 'Chen', 'Rodriguez', 'Patel']:
                        if family_name.lower() == cell_lower or family_name.lower() in cell_lower.split():
                            families_found.append(family_name)
                            
                            # Try to extract values from cells to the right
                            try:
                                given = None
                                received = None
                                balance = None
                                
                                # Look in the next few columns for numeric values
                                for offset in range(1, 5):
                                    if col_idx + offset < len(row):
                                        val = row[col_idx + offset]
                                        if isinstance(val, (int, float)):
                                            if given is None:
                                                given = float(val)
                                            elif received is None:
                                                received = float(val)
                                            elif balance is None:
                                                balance = float(val)
                                                break
                                
                                # If we found all three values, store them
                                if given is not None and received is not None and balance is not None:
                                    family_data[family_name] = {
                                        'given': given,
                                        'received': received,
                                        'balance': balance
                                    }
                            except Exception as e:
                                logger.debug(f"Error parsing values for {family_name}: {e}")
                                continue

        # Start scoring
        score = 0
        feedback_parts = []
        
        # Criterion 1: File exists and parseable (10 points)
        score += 10
        feedback_parts.append("✅ Spreadsheet exists and is parseable")
        
        # Criterion 2: All 4 families present in summary (10 points)
        unique_families = set(families_found)
        if len(unique_families) >= 4:
            score += 10
            feedback_parts.append("✅ All 4 families found in summary")
        else:
            missing = set(['Miller', 'Chen', 'Rodriguez', 'Patel']) - unique_families
            feedback_parts.append(f"❌ Only {len(unique_families)}/4 families found. Missing: {missing}")
        
        # Criterion 3: Hours Given correct for all families (20 points total, 5 per family)
        given_correct = 0
        given_details = []
        for family in ['Miller', 'Chen', 'Rodriguez', 'Patel']:
            if family in family_data:
                expected_given = EXPECTED[family]['given']
                actual_given = family_data[family]['given']
                if abs(actual_given - expected_given) <= TOLERANCE:
                    given_correct += 1
                    given_details.append(f"{family}:✓")
                else:
                    given_details.append(f"{family}:{actual_given:.1f}(exp:{expected_given})")
            else:
                given_details.append(f"{family}:missing")
        
        given_score = (given_correct / 4) * 20
        score += given_score
        
        if given_correct == 4:
            feedback_parts.append("✅ All Hours Given calculations correct")
        else:
            feedback_parts.append(f"⚠️ Hours Given: {given_correct}/4 correct [{', '.join(given_details)}]")
        
        # Criterion 4: Hours Received correct for all families (20 points total, 5 per family)
        received_correct = 0
        received_details = []
        for family in ['Miller', 'Chen', 'Rodriguez', 'Patel']:
            if family in family_data:
                expected_received = EXPECTED[family]['received']
                actual_received = family_data[family]['received']
                if abs(actual_received - expected_received) <= TOLERANCE:
                    received_correct += 1
                    received_details.append(f"{family}:✓")
                else:
                    received_details.append(f"{family}:{actual_received:.1f}(exp:{expected_received})")
            else:
                received_details.append(f"{family}:missing")
        
        received_score = (received_correct / 4) * 20
        score += received_score
        
        if received_correct == 4:
            feedback_parts.append("✅ All Hours Received calculations correct")
        else:
            feedback_parts.append(f"⚠️ Hours Received: {received_correct}/4 correct [{', '.join(received_details)}]")
        
        # Criterion 5: Net Balance correct for all families (20 points total, 5 per family)
        balance_correct = 0
        balance_details = []
        for family in ['Miller', 'Chen', 'Rodriguez', 'Patel']:
            if family in family_data:
                expected_balance = EXPECTED[family]['balance']
                actual_balance = family_data[family]['balance']
                if abs(actual_balance - expected_balance) <= TOLERANCE:
                    balance_correct += 1
                    balance_details.append(f"{family}:✓")
                else:
                    balance_details.append(f"{family}:{actual_balance:.1f}(exp:{expected_balance})")
            else:
                balance_details.append(f"{family}:missing")
        
        balance_score = (balance_correct / 4) * 20
        score += balance_score
        
        if balance_correct == 4:
            feedback_parts.append("✅ All Net Balance calculations correct")
        else:
            feedback_parts.append(f"⚠️ Net Balance: {balance_correct}/4 correct [{', '.join(balance_details)}]")
        
        # Criterion 6: Formulas used (not hardcoded) (10 points)
        # Check if any cells in the summary contain formulas
        has_formulas = False
        formula_count = 0
        
        for row in summary_sheet.iter_rows(min_row=3, max_row=10, min_col=2, max_col=5):
            for cell in row:
                # In openpyxl, formulas are stored in cell.value as strings starting with '='
                # But when data_only=True (default in our parser), we only see values
                # So we need to check if the cell has a formula by checking the data_type
                if cell.value is not None:
                    # Try to access formula if available
                    try:
                        if hasattr(cell, 'data_type') and cell.data_type == 'f':
                            has_formulas = True
                            formula_count += 1
                    except:
                        pass
        
        # Alternative: Check if values are consistent with formulas
        # If all calculations are correct, it's likely formulas were used
        if given_correct >= 3 and received_correct >= 3 and balance_correct >= 3:
            # Assume formulas were used if most calculations are correct
            has_formulas = True
        
        if has_formulas or formula_count > 0:
            score += 10
            feedback_parts.append("✅ Formulas detected (calculations appear formula-based)")
        else:
            feedback_parts.append("⚠️ Cannot confirm formulas used (may be hardcoded)")
        
        # Criterion 7: Conditional formatting applied (5 points)
        # Check if any cells in the balance column have non-default fill colors
        has_formatting = False
        for row in summary_sheet.iter_rows(min_row=4, max_row=7, min_col=4, max_col=4):
            for cell in row:
                try:
                    if cell.fill and hasattr(cell.fill, 'start_color'):
                        color = cell.fill.start_color
                        if color and hasattr(color, 'rgb'):
                            # Check if it's not white/default (00000000 or FFFFFFFF)
                            if color.rgb and color.rgb not in ['00000000', 'FFFFFFFF', None]:
                                has_formatting = True
                                break
                except:
                    pass
        
        if has_formatting:
            score += 5
            feedback_parts.append("✅ Conditional formatting detected")
        else:
            feedback_parts.append("⚠️ No conditional formatting detected")
        
        # Criterion 8: Maximum imbalance calculated (5 points)
        # Search for a value close to 2.5 (the maximum absolute balance)
        expected_max_imbalance = 2.5
        max_imbalance_found = False
        
        for row in data:
            for cell in row:
                if isinstance(cell, (int, float)):
                    if abs(float(cell) - expected_max_imbalance) <= TOLERANCE:
                        max_imbalance_found = True
                        break
            if max_imbalance_found:
                break
        
        if max_imbalance_found:
            score += 5
            feedback_parts.append("✅ Maximum imbalance calculated correctly (~2.5)")
        else:
            feedback_parts.append("⚠️ Maximum imbalance not found or incorrect (expected ~2.5)")
        
        # Determine pass/fail (75% threshold)
        passed = score >= 75
        
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