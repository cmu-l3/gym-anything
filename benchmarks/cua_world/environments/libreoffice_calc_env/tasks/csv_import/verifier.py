#!/usr/bin/env python3
"""Verifier for CSV Import task"""

import sys
import os

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import copy_and_parse_spreadsheet, get_cell_value, cleanup_verification_temp
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_csv_import(traj, env_info, task_info):
    """Verify CSV import and formatting"""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Try ODS first, fall back to CSV
    temp_dir = None
    success = False
    for fmt, path in [('ods', '/home/ga/Documents/employees.ods'),
                       ('csv', '/home/ga/Documents/employees.csv')]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(path, copy_from_env, file_format=fmt)
        if success:
            break

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        sheet_name = list(workbook['sheets'].keys())[0]

        criteria_passed = 0
        feedback_parts = []

        # Check data imported
        name_cell = get_cell_value(workbook, sheet_name, 'B2')
        if name_cell == "Alice Smith":
            criteria_passed += 1
            feedback_parts.append("✅ Data imported correctly")
        else:
            feedback_parts.append(f"❌ Data import issue (B2 expected 'Alice Smith', got '{name_cell}')")

        # Check salary value
        salary_cell = get_cell_value(workbook, sheet_name, 'D2')
        if salary_cell == 85000 or salary_cell == "85000" or str(salary_cell) == "85000":
            criteria_passed += 1
            feedback_parts.append("✅ Salary data correct")
        else:
            feedback_parts.append(f"❌ Salary incorrect (expected 85000, got {salary_cell})")

        # Check date
        date_cell = get_cell_value(workbook, sheet_name, 'E2')
        if date_cell and '2020' in str(date_cell):
            criteria_passed += 1
            feedback_parts.append("✅ Date data present")
        else:
            feedback_parts.append(f"❌ Date issue (got {date_cell})")

        # Check row count
        sheet_rows = workbook['sheets'][sheet_name]
        row_count = 0
        for row in sheet_rows:
            if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
                row_count += 1

        if row_count >= 5:  # Header + 4 data rows
            criteria_passed += 1
            feedback_parts.append("✅ All rows present")
        else:
            feedback_parts.append(f"❌ Missing rows (found {row_count}, expected 5)")
        
        score = int((criteria_passed / 4) * 100)
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
