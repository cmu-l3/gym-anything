#!/usr/bin/env python3
"""
Verifier for Create Formula task
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    verify_formula,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_spreadsheet_formulas(traj, env_info, task_info):
    """
    Verify that spreadsheet formulas were created correctly.

    Checks:
    1. B8 (Total Sales) has SUM formula with correct result (~11720)
    2. B9 (Average Sales) has AVERAGE formula with correct result (~586)
    3. B10 (Max Quarter) has MAX formula with correct result (1500)
    4. Spreadsheet was saved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/sales_data.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_sheet_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        criteria_passed = 0
        feedback_parts = []

        sheet_name = "Sales"

        # Criterion 1: Check B8 has SUM formula with result ~11720
        total_value = get_cell_value(wb, sheet_name, 'B8')
        if total_value is not None and isinstance(total_value, (int, float)):
            if abs(total_value - 11720) <= 10:
                criteria_passed += 1
                feedback_parts.append(f"✅ Total Sales correct: {total_value}")
            else:
                feedback_parts.append(f"❌ Total Sales incorrect: {total_value} (expected ~11720)")
        else:
            feedback_parts.append(f"❌ Total Sales missing or invalid: {total_value}")

        # Criterion 2: Check B9 has AVERAGE formula with result ~586
        avg_value = get_cell_value(wb, sheet_name, 'B9')
        if avg_value is not None and isinstance(avg_value, (int, float)):
            if abs(avg_value - 586) <= 10:
                criteria_passed += 1
                feedback_parts.append(f"✅ Average Sales correct: {avg_value}")
            else:
                feedback_parts.append(f"❌ Average Sales incorrect: {avg_value} (expected ~586)")
        else:
            feedback_parts.append(f"❌ Average Sales missing or invalid: {avg_value}")

        # Criterion 3: Check B10 has MAX formula with result 1500
        max_value = get_cell_value(wb, sheet_name, 'B10')
        if max_value is not None and isinstance(max_value, (int, float)):
            if abs(max_value - 1500) <= 1:
                criteria_passed += 1
                feedback_parts.append(f"✅ Max Quarter correct: {max_value}")
            else:
                feedback_parts.append(f"❌ Max Quarter incorrect: {max_value} (expected 1500)")
        else:
            feedback_parts.append(f"❌ Max Quarter missing or invalid: {max_value}")

        # Criterion 4: Verify original data is intact
        product_a2 = get_cell_value(wb, sheet_name, 'A2')
        if product_a2 == "Laptop":
            criteria_passed += 1
            feedback_parts.append("✅ Original data preserved")
        else:
            feedback_parts.append(f"❌ Original data corrupted: A2={product_a2}")

        score = int((criteria_passed / 4) * 100)
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
