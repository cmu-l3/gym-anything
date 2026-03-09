#!/usr/bin/env python3
"""
Verifier for Medical Billing Reconciliation task

This verifies that the agent created a proper medical billing dispute
reconciliation spreadsheet with correct calculations and formatting.
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_cell_with_text(sheet, text_pattern, max_rows=30, max_cols=10):
    """
    Find a cell containing specific text pattern
    
    Returns: (row, col) tuple or None
    """
    text_lower = text_pattern.lower()
    for row in range(1, max_rows + 1):
        for col in range(1, max_cols + 1):
            cell = sheet.cell(row=row, column=col)
            if cell.value and text_lower in str(cell.value).lower():
                return (row, col)
    return None


def get_numeric_value(value, allow_none=False):
    """
    Extract numeric value from cell, handling various formats
    
    Returns: float or None
    """
    if value is None:
        return None if allow_none else 0.0
    
    if isinstance(value, (int, float)):
        return float(value)
    
    # Handle string values with currency symbols, commas, etc.
    if isinstance(value, str):
        # Remove currency symbols, commas, spaces
        cleaned = re.sub(r'[\$,\s]', '', value)
        try:
            return float(cleaned)
        except ValueError:
            return None if allow_none else 0.0
    
    return None if allow_none else 0.0


def check_cell_formatting(cell, bold=False, color_check=None):
    """
    Check if cell has specific formatting
    
    Args:
        cell: openpyxl cell object
        bold: whether to check for bold
        color_check: 'red' to check for red text
    
    Returns: tuple (has_bold, has_red_color)
    """
    has_bold = False
    has_red = False
    
    if cell.font:
        has_bold = cell.font.bold is True
        
        if cell.font.color and color_check == 'red':
            # Check if color is reddish (R > 200, G < 100, B < 100)
            try:
                if hasattr(cell.font.color, 'rgb'):
                    rgb = cell.font.color.rgb
                    if rgb and len(rgb) >= 6:
                        # RGB format can be AARRGGBB or RRGGBB
                        if len(rgb) == 8:  # AARRGGBB
                            r = int(rgb[2:4], 16)
                            g = int(rgb[4:6], 16)
                            b = int(rgb[6:8], 16)
                        else:  # RRGGBB
                            r = int(rgb[0:2], 16)
                            g = int(rgb[2:4], 16)
                            b = int(rgb[4:6], 16)
                        
                        has_red = (r > 200 and g < 100 and b < 100)
                elif hasattr(cell.font.color, 'theme'):
                    # Theme colors - harder to check, accept if theme is 1 (red-ish)
                    has_red = cell.font.color.theme in [1, 2]
            except Exception as e:
                logger.debug(f"Error checking color: {e}")
    
    return has_bold, has_red


def verify_medical_billing_reconciliation(traj, env_info, task_info):
    """
    Verify that medical billing reconciliation spreadsheet was created correctly.

    Checks:
    1. File exists and is saved
    2. Has proper structure with calculations
    3. Section 1 (Provider Charges): Total Billed ≈ $3,497, Total Allowed ≈ $1,976.30
    4. Section 2 (Payments): Total Paid ≈ $1,730-$1,732
    5. Section 3 (Reconciliation): Actual Owed ≈ $244-$246, Discrepancy ≈ $954-$956
    6. Formatting: Key amounts are bold, discrepancy is red
    7. Uses formulas for calculations
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/medical_billing_dispute.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_billing_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        sheet = wb.active
        
        criteria_passed = 0
        total_criteria = 10
        feedback_parts = []
        
        # Strategy: Look for key text markers and check nearby cells for values
        # This is more robust than assuming specific cell locations
        
        # ============================================================
        # Criterion 1: Check for Provider Charges section structure
        # ============================================================
        # Look for "total" related to provider charges
        total_billed = None
        total_allowed = None
        
        # Scan for likely total rows (look for "total" in column A, values in B and C)
        for row in range(1, 25):
            cell_a = sheet.cell(row=row, column=1)
            if cell_a.value and 'total' in str(cell_a.value).lower():
                val_b = get_numeric_value(sheet.cell(row=row, column=2).value, allow_none=True)
                val_c = get_numeric_value(sheet.cell(row=row, column=3).value, allow_none=True)
                
                # First total we find with reasonable values is likely provider charges total
                if val_b is not None and val_c is not None:
                    if 3000 < val_b < 4000 and 1800 < val_c < 2200:
                        total_billed = val_b
                        total_allowed = val_c
                        break
        
        if total_billed and total_allowed:
            if abs(total_billed - 3497) < 50:
                criteria_passed += 1
                feedback_parts.append(f"✅ Total Billed correct: ${total_billed:.2f}")
            else:
                feedback_parts.append(f"⚠️ Total Billed off: ${total_billed:.2f} (expected ~$3,497)")
            
            if abs(total_allowed - 1976.30) < 50:
                criteria_passed += 1
                feedback_parts.append(f"✅ Total Allowed correct: ${total_allowed:.2f}")
            else:
                feedback_parts.append(f"⚠️ Total Allowed off: ${total_allowed:.2f} (expected ~$1,976.30)")
        else:
            feedback_parts.append("❌ Provider Charges section not found or incomplete")
        
        # ============================================================
        # Criterion 2: Check for Payment Breakdown section
        # ============================================================
        total_paid = None
        
        # Look for total paid (scan for "total" with value around 1730)
        for row in range(1, 30):
            cell_a = sheet.cell(row=row, column=1)
            if cell_a.value and 'total' in str(cell_a.value).lower():
                val_b = get_numeric_value(sheet.cell(row=row, column=2).value, allow_none=True)
                
                # Look for total paid amount
                if val_b is not None and 1500 < val_b < 1900:
                    # Make sure this isn't the provider charges total we already found
                    if not (total_billed and abs(val_b - total_billed) < 100):
                        total_paid = val_b
                        break
        
        if total_paid:
            # Allow range 1580-1732 (insurance paid varies slightly in interpretation)
            if 1580 <= total_paid <= 1800:
                criteria_passed += 1
                feedback_parts.append(f"✅ Total Paid found: ${total_paid:.2f}")
            else:
                feedback_parts.append(f"⚠️ Total Paid seems off: ${total_paid:.2f} (expected ~$1,580-$1,732)")
        else:
            feedback_parts.append("❌ Payment Breakdown section not found or incomplete")
        
        # ============================================================
        # Criterion 3 & 4: Check for Reconciliation section
        # ============================================================
        actual_owed = None
        discrepancy = None
        actual_owed_cell = None
        discrepancy_cell = None
        
        # Look for "actual" and "owe" or "discrepancy" and "dispute"
        for row in range(1, 35):
            cell_a = sheet.cell(row=row, column=1)
            cell_b = sheet.cell(row=row, column=2)
            
            if cell_a.value:
                text = str(cell_a.value).lower()
                val_b = get_numeric_value(cell_b.value, allow_none=True)
                
                # Look for actual amount owed
                if ('actual' in text and 'owe' in text) or ('you owe' in text):
                    if val_b is not None and 200 < val_b < 500:
                        actual_owed = val_b
                        actual_owed_cell = cell_b
                
                # Look for discrepancy
                if ('discrepancy' in text or 'dispute' in text or 'difference' in text):
                    if val_b is not None and 800 < val_b < 1200:
                        discrepancy = val_b
                        discrepancy_cell = cell_b
        
        if actual_owed:
            # Expected range: $243.92 to $396.06 (depends on interpretation)
            if 240 <= actual_owed <= 400:
                criteria_passed += 1
                feedback_parts.append(f"✅ Actual Amount Owed calculated: ${actual_owed:.2f}")
            else:
                feedback_parts.append(f"⚠️ Actual Amount Owed seems off: ${actual_owed:.2f} (expected ~$244-$396)")
        else:
            feedback_parts.append("❌ Actual Amount Owed not found in reconciliation")
        
        if discrepancy:
            # Expected: around $953-$956
            if 900 <= discrepancy <= 1000:
                criteria_passed += 1
                feedback_parts.append(f"✅ Discrepancy calculated: ${discrepancy:.2f}")
            else:
                feedback_parts.append(f"⚠️ Discrepancy seems off: ${discrepancy:.2f} (expected ~$954-$956)")
        else:
            feedback_parts.append("❌ Discrepancy amount not found in reconciliation")
        
        # ============================================================
        # Criterion 5 & 6: Check formatting
        # ============================================================
        formatting_score = 0
        
        if actual_owed_cell:
            is_bold, _ = check_cell_formatting(actual_owed_cell, bold=True)
            if is_bold:
                criteria_passed += 1
                formatting_score += 1
                feedback_parts.append("✅ Actual Amount Owed is bold")
            else:
                feedback_parts.append("⚠️ Actual Amount Owed should be bold")
        
        if discrepancy_cell:
            is_bold, is_red = check_cell_formatting(discrepancy_cell, bold=True, color_check='red')
            
            if is_bold:
                formatting_score += 1
            if is_red:
                formatting_score += 1
            
            if is_bold and is_red:
                criteria_passed += 2
                feedback_parts.append("✅ Discrepancy is bold and red")
            elif is_bold:
                criteria_passed += 1
                feedback_parts.append("⚠️ Discrepancy is bold but not red")
            elif is_red:
                criteria_passed += 1
                feedback_parts.append("⚠️ Discrepancy is red but not bold")
            else:
                feedback_parts.append("❌ Discrepancy should be bold and red")
        
        # ============================================================
        # Criterion 7: Check for formula usage (bonus)
        # ============================================================
        formula_count = 0
        for row in range(1, 35):
            for col in range(1, 6):
                cell = sheet.cell(row=row, column=col)
                if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                    formula_count += 1
        
        if formula_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Uses formulas ({formula_count} found)")
        elif formula_count >= 1:
            feedback_parts.append(f"⚠️ Limited formula use ({formula_count} found, expected 3+)")
        else:
            feedback_parts.append("❌ No formulas detected - should use SUM and cell references")
        
        # ============================================================
        # Calculate final score
        # ============================================================
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 60  # Need at least 6/10 criteria
        
        feedback = " | ".join(feedback_parts)
        
        # Add summary
        summary = f"Score: {criteria_passed}/{total_criteria} criteria passed."
        if passed:
            summary += " Task completed successfully!"
        else:
            summary += " Need more work on reconciliation structure and calculations."
        
        return {
            "passed": passed,
            "score": score,
            "feedback": f"{summary} | {feedback}"
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
