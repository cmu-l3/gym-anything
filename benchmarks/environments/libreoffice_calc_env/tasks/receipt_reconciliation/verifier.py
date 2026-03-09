#!/usr/bin/env python3
"""
Verifier for Receipt Reconciliation task.
Checks that agent correctly imported CSV, calculated totals with formulas,
and identified the discrepancy.
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    parse_csv_file,
    parse_ods_file
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_sum_formula_cell(workbook, sheet_name):
    """
    Search for a cell containing a SUM formula.
    Returns (row_idx, col_idx, formula, value) or None if not found.
    """
    sheet_data = workbook['sheets'][sheet_name]
    
    for row_idx, row in enumerate(sheet_data):
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                formula = cell.get('formula', '')
                value = cell.get('value')
                if formula and 'SUM' in formula.upper():
                    return (row_idx, col_idx, formula, value)
    
    return None


def extract_sum_range(formula):
    """
    Extract the range from a SUM formula.
    E.g., "=SUM(B2:B21)" -> (2, 21) for rows
    Returns (start_row, end_row) or None
    """
    # Match patterns like SUM(B2:B21) or SUM(B2:B50)
    pattern = r'SUM\s*\(\s*[A-Z]+(\d+)\s*:\s*[A-Z]+(\d+)\s*\)'
    match = re.search(pattern, formula.upper())
    
    if match:
        start_row = int(match.group(1))
        end_row = int(match.group(2))
        return (start_row, end_row)
    
    return None


def calculate_actual_receipt_total(workbook, sheet_name):
    """
    Calculate the actual total by summing all price values in column B.
    Assumes column B contains prices starting from row 2.
    """
    sheet_data = workbook['sheets'][sheet_name]
    total = 0.0
    count = 0
    
    # Start from row 1 (index 1, since row 0 is header)
    for row_idx in range(1, len(sheet_data)):
        if row_idx < len(sheet_data) and 1 < len(sheet_data[row_idx]):  # Column B is index 1
            cell = sheet_data[row_idx][1]  # Column B
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if value is not None and value != '':
                try:
                    price = float(value)
                    total += price
                    count += 1
                except (ValueError, TypeError):
                    pass
    
    logger.info(f"Calculated actual total from {count} items: ${total:.2f}")
    return total, count


def find_discrepancy_value(workbook, sheet_name, expected_discrepancy, tolerance=0.50):
    """
    Search for a cell that likely contains the discrepancy value.
    Looks for values close to the expected discrepancy.
    """
    sheet_data = workbook['sheets'][sheet_name]
    
    candidates = []
    
    for row_idx, row in enumerate(sheet_data):
        for col_idx, cell in enumerate(row):
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if isinstance(value, (int, float)):
                # Check if value is close to expected discrepancy
                if abs(value - expected_discrepancy) < tolerance:
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    candidates.append((row_idx, col_idx, value, formula))
    
    return candidates


def verify_receipt_reconciliation(traj, env_info, task_info):
    """
    Verify receipt reconciliation task completion.
    
    Checks:
    1. CSV data imported with all items
    2. SUM formula exists for calculating total
    3. SUM formula covers appropriate range of items
    4. Calculated total is correct (~$119.67)
    5. Discrepancy calculation exists
    6. Discrepancy value is correct (~$7.76)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Expected values
    EXPECTED_ITEM_COUNT = 20
    EXPECTED_ACTUAL_TOTAL = 119.67
    EXPECTED_CHARGED_TOTAL = 127.43
    EXPECTED_DISCREPANCY = 7.76
    
    # Try multiple possible file paths
    possible_paths = [
        ("/home/ga/Documents/reconciled_receipt.ods", 'ods'),
        ("/home/ga/Documents/grocery_receipt.ods", 'ods'),
        ("/home/ga/Documents/grocery_receipt.csv", 'csv'),
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path, file_format in possible_paths:
        logger.info(f"Trying to load: {container_path} as {file_format}")
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load receipt file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = workbook['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: CSV data imported (check item count)
        row_count = 0
        for row in sheet_data:
            # Check if row has any non-empty cells
            if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
                row_count += 1
        
        data_imported = row_count >= (EXPECTED_ITEM_COUNT + 1)  # +1 for header
        if data_imported:
            criteria_passed += 1
            feedback_parts.append(f"✅ CSV data imported ({row_count} rows including header)")
        else:
            feedback_parts.append(f"❌ CSV data incomplete ({row_count} rows, expected {EXPECTED_ITEM_COUNT + 1})")
        
        # Criterion 2: SUM formula present
        sum_formula_result = find_sum_formula_cell(workbook, sheet_name)
        
        if sum_formula_result:
            row_idx, col_idx, formula, formula_value = sum_formula_result
            criteria_passed += 1
            feedback_parts.append(f"✅ SUM formula found: {formula}")
            
            # Criterion 3: SUM formula covers appropriate range
            sum_range = extract_sum_range(formula)
            if sum_range:
                start_row, end_row = sum_range
                range_size = end_row - start_row + 1
                
                # Should cover most/all items (at least 15 items)
                if range_size >= 15:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Formula range appropriate ({range_size} rows)")
                else:
                    feedback_parts.append(f"⚠️ Formula range may be too small ({range_size} rows)")
            else:
                feedback_parts.append("⚠️ Could not parse formula range")
            
            # Criterion 4: Calculated total is correct
            if formula_value is not None:
                try:
                    calculated_total = float(formula_value)
                    if abs(calculated_total - EXPECTED_ACTUAL_TOTAL) < 0.50:
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Calculated total correct: ${calculated_total:.2f}")
                    else:
                        feedback_parts.append(
                            f"❌ Calculated total incorrect: ${calculated_total:.2f} "
                            f"(expected ~${EXPECTED_ACTUAL_TOTAL:.2f})"
                        )
                except (ValueError, TypeError):
                    feedback_parts.append(f"❌ Formula result invalid: {formula_value}")
            else:
                feedback_parts.append("❌ Formula has no calculated value")
        else:
            feedback_parts.append("❌ No SUM formula found")
        
        # Criterion 5 & 6: Find discrepancy calculation
        discrepancy_candidates = find_discrepancy_value(
            workbook, sheet_name, EXPECTED_DISCREPANCY, tolerance=0.50
        )
        
        if discrepancy_candidates:
            # Use the first candidate
            disc_row, disc_col, disc_value, disc_formula = discrepancy_candidates[0]
            
            # Criterion 5: Discrepancy calculation exists
            if disc_formula and ('-' in disc_formula or '=' in disc_formula):
                criteria_passed += 1
                feedback_parts.append(f"✅ Discrepancy formula found: {disc_formula}")
            else:
                criteria_passed += 1
                feedback_parts.append(f"✅ Discrepancy value found: ${disc_value:.2f}")
            
            # Criterion 6: Discrepancy value is correct
            if abs(disc_value - EXPECTED_DISCREPANCY) < 0.20:
                criteria_passed += 1
                feedback_parts.append(
                    f"✅ Discrepancy correct: ${disc_value:.2f} overcharge detected"
                )
            else:
                feedback_parts.append(
                    f"⚠️ Discrepancy value: ${disc_value:.2f} "
                    f"(expected ~${EXPECTED_DISCREPANCY:.2f})"
                )
        else:
            feedback_parts.append(
                f"❌ Discrepancy calculation not found (expected ~${EXPECTED_DISCREPANCY:.2f})"
            )
        
        # Also verify charged amount is present somewhere
        charged_found = False
        for row in sheet_data:
            for cell in row:
                value = cell.get('value') if isinstance(cell, dict) else cell
                if isinstance(value, (int, float)):
                    if abs(value - EXPECTED_CHARGED_TOTAL) < 0.10:
                        charged_found = True
                        break
            if charged_found:
                break
        
        if charged_found:
            feedback_parts.append(f"✅ Store charged amount (${EXPECTED_CHARGED_TOTAL:.2f}) present")
        else:
            feedback_parts.append(f"⚠️ Store charged amount not clearly identified")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (need 4-5 out of 6 criteria)
        
        # Add summary feedback
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Receipt reconciliation completed successfully!")
        elif passed:
            feedback_parts.insert(0, "✅ Receipt reconciliation task completed")
        else:
            feedback_parts.insert(0, "❌ Receipt reconciliation incomplete")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "data_imported": data_imported,
                "sum_formula_present": sum_formula_result is not None,
                "discrepancy_found": len(discrepancy_candidates) > 0,
                "criteria_met": criteria_passed,
                "total_criteria": total_criteria
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
