#!/usr/bin/env python3
"""
Verifier for Energy Payback Calculator task

Verifies that the energy upgrade payback calculator spreadsheet was created correctly
with proper data, formulas, and calculations.
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_energy_payback(traj, env_info, task_info):
    """
    Verify that energy payback calculator spreadsheet was created correctly.

    Checks:
    1. File exists and is valid XLSX
    2. Given input values entered correctly:
       - B1 = 185 (current monthly bill)
       - B2 = 0.30 or 30 (reduction percentage)
       - B5 = 8500 (upgrade cost)
    3. Calculated values are correct:
       - B3: New monthly bill (~129.5) = 185 * 0.7
       - B4: Monthly savings (~55.5) = 185 - 129.5
       - B6: Payback period (~153) = 8500 / 55.5
    4. Mathematical consistency (B1 = B3 + B4)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/energy_upgrade_analysis.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_energy_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False, 
                "score": 0.0, 
                "feedback": f"Failed to load spreadsheet: {error}"
            }

        score = 0.0
        feedback_parts = []

        # Get the active sheet (first sheet in workbook)
        try:
            sheet = wb.active
            if sheet is None:
                # Try to get first sheet by name
                sheet_names = wb.sheetnames
                if sheet_names:
                    sheet = wb[sheet_names[0]]
                else:
                    return {
                        "passed": False, 
                        "score": 0.0, 
                        "feedback": "No worksheets found in workbook"
                    }
        except Exception as e:
            return {
                "passed": False, 
                "score": 0.0, 
                "feedback": f"Could not access worksheet: {str(e)}"
            }

        # Helper function to safely get cell value
        def safe_get_cell_value(cell_ref):
            try:
                cell = sheet[cell_ref]
                return cell.value
            except Exception as e:
                logger.warning(f"Error getting cell {cell_ref}: {e}")
                return None

        # ===================================================================
        # CHECK INPUT VALUES (30 points)
        # ===================================================================
        
        # B1: Current monthly bill should be 185 (10 points)
        b1 = safe_get_cell_value('B1')
        if b1 is not None and isinstance(b1, (int, float)):
            b1_val = float(b1)
            if abs(b1_val - 185) < 1:
                score += 10
                feedback_parts.append(f"✅ Current bill correctly entered: ${b1_val:.2f}")
            else:
                feedback_parts.append(f"❌ Current bill incorrect (expected $185, got ${b1_val:.2f})")
        else:
            feedback_parts.append(f"❌ Current bill missing or invalid in B1: {b1}")

        # B2: Reduction percentage should be 0.30 or 30 (10 points)
        b2 = safe_get_cell_value('B2')
        if b2 is not None and isinstance(b2, (int, float)):
            b2_val = float(b2)
            # Accept both 0.30 (decimal) and 30 (whole number percentage)
            if abs(b2_val - 0.30) < 0.01 or abs(b2_val - 30) < 1:
                score += 10
                feedback_parts.append(f"✅ Reduction percentage correctly entered: {b2_val}")
            else:
                feedback_parts.append(f"❌ Reduction percentage incorrect (expected 0.30 or 30, got {b2_val})")
        else:
            feedback_parts.append(f"❌ Reduction percentage missing or invalid in B2: {b2}")

        # B5: Upgrade cost should be 8500 (10 points)
        b5 = safe_get_cell_value('B5')
        if b5 is not None and isinstance(b5, (int, float)):
            b5_val = float(b5)
            if abs(b5_val - 8500) < 1:
                score += 10
                feedback_parts.append(f"✅ Upgrade cost correctly entered: ${b5_val:.2f}")
            else:
                feedback_parts.append(f"❌ Upgrade cost incorrect (expected $8,500, got ${b5_val:.2f})")
        else:
            feedback_parts.append(f"❌ Upgrade cost missing or invalid in B5: {b5}")

        # ===================================================================
        # CHECK CALCULATED VALUES (70 points)
        # ===================================================================

        b3 = safe_get_cell_value('B3')  # New monthly bill
        b4 = safe_get_cell_value('B4')  # Monthly savings
        b6 = safe_get_cell_value('B6')  # Payback period

        # B3: New monthly bill should be ~129.5 (25 points)
        expected_b3 = 129.5  # 185 * (1 - 0.30) = 185 * 0.7
        if b3 is not None and isinstance(b3, (int, float)):
            b3_val = float(b3)
            error_margin = abs(b3_val - expected_b3)
            
            if error_margin < 5:  # Within $5
                if error_margin < 1:  # Very accurate
                    score += 25
                    feedback_parts.append(f"✅ New monthly bill calculated correctly: ${b3_val:.2f} (expected ~${expected_b3:.2f})")
                else:  # Close but not exact
                    partial_score = max(15, 25 - (error_margin * 2))
                    score += partial_score
                    feedback_parts.append(f"⚠️ New monthly bill close: ${b3_val:.2f} (expected ~${expected_b3:.2f})")
            else:
                feedback_parts.append(f"❌ New monthly bill incorrect: ${b3_val:.2f} (expected ~${expected_b3:.2f})")
        else:
            feedback_parts.append(f"❌ New monthly bill not calculated in B3: {b3}")

        # B4: Monthly savings should be ~55.5 (25 points)
        expected_b4 = 55.5  # 185 - 129.5
        if b4 is not None and isinstance(b4, (int, float)):
            b4_val = float(b4)
            error_margin = abs(b4_val - expected_b4)
            
            if error_margin < 5:  # Within $5
                if error_margin < 1:  # Very accurate
                    score += 25
                    feedback_parts.append(f"✅ Monthly savings calculated correctly: ${b4_val:.2f} (expected ~${expected_b4:.2f})")
                else:  # Close but not exact
                    partial_score = max(15, 25 - (error_margin * 2))
                    score += partial_score
                    feedback_parts.append(f"⚠️ Monthly savings close: ${b4_val:.2f} (expected ~${expected_b4:.2f})")
            else:
                feedback_parts.append(f"❌ Monthly savings incorrect: ${b4_val:.2f} (expected ~${expected_b4:.2f})")
        else:
            feedback_parts.append(f"❌ Monthly savings not calculated in B4: {b4}")

        # B6: Payback period should be ~153 months (20 points)
        expected_b6 = 153.15  # 8500 / 55.5
        if b6 is not None and isinstance(b6, (int, float)):
            b6_val = float(b6)
            error_margin = abs(b6_val - expected_b6)
            
            if error_margin < 10:  # Within 10 months
                if error_margin < 2:  # Very accurate
                    score += 20
                    feedback_parts.append(f"✅ Payback period calculated correctly: {b6_val:.1f} months (expected ~{expected_b6:.1f})")
                else:  # Close but not exact
                    partial_score = max(10, 20 - error_margin)
                    score += partial_score
                    feedback_parts.append(f"⚠️ Payback period close: {b6_val:.1f} months (expected ~{expected_b6:.1f})")
            else:
                feedback_parts.append(f"❌ Payback period incorrect: {b6_val:.1f} months (expected ~{expected_b6:.1f})")
        else:
            feedback_parts.append(f"❌ Payback period not calculated in B6: {b6}")

        # ===================================================================
        # ADDITIONAL CHECKS
        # ===================================================================

        # Mathematical consistency check (bonus validation)
        if all(x is not None and isinstance(x, (int, float)) for x in [b1, b3, b4]):
            b1_float = float(b1)
            b3_float = float(b3)
            b4_float = float(b4)
            
            # Check if original bill = new bill + savings (within $2 tolerance)
            if abs((b3_float + b4_float) - b1_float) < 2:
                feedback_parts.append("✅ Mathematical consistency verified (new bill + savings ≈ original bill)")
            else:
                feedback_parts.append(f"⚠️ Inconsistency: B3({b3_float:.2f}) + B4({b4_float:.2f}) ≠ B1({b1_float:.2f})")

        # Sanity checks for reasonable values
        if b3 is not None and isinstance(b3, (int, float)) and float(b3) < 0:
            feedback_parts.append("⚠️ Warning: New monthly bill is negative (check formula)")
        
        if b4 is not None and isinstance(b4, (int, float)) and float(b4) < 0:
            feedback_parts.append("⚠️ Warning: Monthly savings is negative (check formula)")
        
        if b6 is not None and isinstance(b6, (int, float)):
            b6_val = float(b6)
            if b6_val < 0 or b6_val > 1000:
                feedback_parts.append(f"⚠️ Warning: Payback period ({b6_val:.1f} months) seems unreasonable")

        # ===================================================================
        # FINAL SCORING
        # ===================================================================

        passed = score >= 75
        normalized_score = score / 100.0
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0.0, 
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
