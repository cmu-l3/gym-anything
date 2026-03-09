#!/usr/bin/env python3
"""
Verifier for VLOOKUP Formula task.
Checks that VLOOKUP formulas are present and produce correct results.
"""

import logging
import sys
import os

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula
)

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)


def check_vlookup_formula(traj, env_info, task_info):
    """
    Verify VLOOKUP formula task:
    1. Price cells contain formulas with VLOOKUP
    2. Formula results match expected prices
    3. Formulas use correct references
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/Documents/vlookup_result.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])

    if not success:
        container_path = "/home/ga/Documents/vlookup_exercise.csv"
        success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
        if not success:
            container_path = "/home/ga/Documents/vlookup_exercise.ods"
            success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
            if not success:
                return {"passed": False, "score": 0, "feedback": f"Setup failed: {error}"}
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Setup failed: {error}"}
    
    try:
        feedback_parts = []
        criteria_met = 0
        total_criteria = 3

        # Get sheet data
        data = file_info['sheet_data']

        # Find Orders sheet (might be sheet 1 or 0 depending on setup)
        sheet_names = list(data.get('sheets', {}).keys())
        orders_sheet_name = None

        for name in sheet_names:
            if 'Orders' in name or 'orders' in name.lower():
                orders_sheet_name = name
                break

        # If not found, try second sheet (index 1) or fallback to first sheet
        if not orders_sheet_name:
            if len(sheet_names) > 1:
                orders_sheet_name = sheet_names[1]  # Assume second sheet
            elif sheet_names:
                orders_sheet_name = sheet_names[0]  # Fallback to first sheet

        if not orders_sheet_name:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}

        # Expected prices for product IDs in order
        # O001->P002->49.99, O002->P001->29.99, O003->P004->89.99, O004->P003->15.99, O005->P005->12.50
        expected_prices = [49.99, 29.99, 89.99, 15.99, 12.50]

        # 1. Check formulas present
        formulas_found = 0
        for row_idx in range(2, 7):  # Rows 2-6 (Excel-style 1-indexed)
            cell_ref = f"C{row_idx}"
            formula = get_cell_formula(data, orders_sheet_name, cell_ref)
            if formula and 'VLOOKUP' in str(formula).upper():
                formulas_found += 1

        if formulas_found >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ VLOOKUP formulas found ({formulas_found}/5)")
        else:
            feedback_parts.append(f"❌ Insufficient VLOOKUP formulas ({formulas_found}/5)")

        # 2. Check formula results
        prices_correct = 0
        for row_offset, expected_price in enumerate(expected_prices):
            row_idx = row_offset + 2  # Start from row 2
            cell_ref = f"C{row_idx}"
            actual = get_cell_value(data, orders_sheet_name, cell_ref)
            try:
                actual_num = float(actual)
                if abs(actual_num - expected_price) < 0.01:
                    prices_correct += 1
            except (ValueError, TypeError):
                pass

        if prices_correct >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ Prices correct ({prices_correct}/5)")
        else:
            feedback_parts.append(f"❌ Prices incorrect ({prices_correct}/5)")

        # 3. Check at least one formula has correct syntax
        correct_syntax = False
        for row_idx in range(2, 7):
            cell_ref = f"C{row_idx}"
            formula = get_cell_formula(data, orders_sheet_name, cell_ref)
            if formula and 'VLOOKUP' in str(formula).upper():
                # Check for key components
                formula_upper = str(formula).upper()
                if 'PRODUCTS' in formula_upper or 'A:B' in formula_upper or '.A' in formula_upper:
                    correct_syntax = True
                    break

        if correct_syntax:
            criteria_met += 1
            feedback_parts.append("✅ Formula uses correct sheet reference")
        else:
            feedback_parts.append("⚠️ Formula syntax may be incorrect")
        
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 66  # Need 2/3 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent VLOOKUP implementation!")
        elif passed:
            feedback_parts.append("✅ VLOOKUP task completed.")
        else:
            feedback_parts.append("❌ VLOOKUP task incomplete.")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_temp(file_info.get('temp_dir'))
