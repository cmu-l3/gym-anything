#!/usr/bin/env python3
"""
Verifier for Basic Formulas task
"""

import sys
import os
import logging

# Add utils to path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    verify_cell_value,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_basic_formulas(traj, env_info, task_info):
    """
    Verify basic formulas task completion.
    
    Checks:
    1. Cells A1-A5 contain values 10, 20, 30, 40, 50
    2. Cell B1 contains SUM formula with result 150
    3. Cell B2 contains AVERAGE formula with result 30
    4. Formulas are actual formulas, not hardcoded values
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/basic_formulas.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]

        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []

        # Criterion 1: Data entry correct (A1-A5)
        expected_values = [10, 20, 30, 40, 50]
        data_correct = True
        for i, expected in enumerate(expected_values, start=1):
            cell_address = f"A{i}"
            actual = get_cell_value(workbook, sheet_name, cell_address)
            if actual != expected:
                data_correct = False
                feedback_parts.append(f"❌ Cell {cell_address}: expected {expected}, got {actual}")
                break

        if data_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Data entry correct (A1-A5)")
        else:
            if not feedback_parts:
                feedback_parts.append("❌ Data entry incorrect in A1-A5")

        # Criterion 2: SUM formula in B1
        b1_value = get_cell_value(workbook, sheet_name, 'B1')
        b1_formula = get_cell_formula(workbook, sheet_name, 'B1')

        sum_correct = False
        if b1_formula and 'SUM' in b1_formula.upper():
            if abs(float(b1_value) - 150) < 0.01:
                criteria_passed += 1
                sum_correct = True
                feedback_parts.append(f"✅ SUM formula correct: {b1_formula} = {b1_value}")
            else:
                feedback_parts.append(f"❌ SUM result incorrect: expected 150, got {b1_value}")
        else:
            feedback_parts.append(f"❌ B1 missing SUM formula (got: {b1_formula or 'no formula'})")

        # Criterion 3: AVERAGE formula in B2
        b2_value = get_cell_value(workbook, sheet_name, 'B2')
        b2_formula = get_cell_formula(workbook, sheet_name, 'B2')
        
        avg_correct = False
        if b2_formula and 'AVERAGE' in b2_formula.upper():
            if abs(float(b2_value) - 30) < 0.01:
                criteria_passed += 1
                avg_correct = True
                feedback_parts.append(f"✅ AVERAGE formula correct: {b2_formula} = {b2_value}")
            else:
                feedback_parts.append(f"❌ AVERAGE result incorrect: expected 30, got {b2_value}")
        else:
            feedback_parts.append(f"❌ B2 missing AVERAGE formula (got: {b2_formula or 'no formula'})")
        
        # Criterion 4: Formulas not hardcoded
        formulas_used = (b1_formula is not None) and (b2_formula is not None)
        if formulas_used:
            criteria_passed += 1
            feedback_parts.append("✅ Formulas used (not hardcoded values)")
        else:
            feedback_parts.append("❌ Values appear hardcoded (no formulas detected)")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "data_entry": data_correct,
                "sum_formula": sum_correct,
                "average_formula": avg_correct,
                "formulas_used": formulas_used
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
