#!/usr/bin/env python3
"""
Verifier for Sort Data task.
Checks that data is sorted by Score column in ascending order.
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
    verify_data_sorted,
    get_sheet_names
)

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)


def check_sort_data(traj, env_info, task_info):
    """
    Verify sort data task:
    1. Score column is sorted in ascending order
    2. Name-Score pairs are maintained
    3. No data loss
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Setup verification
    container_path = "/home/ga/Documents/sort_data_result.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods', 'xlsx'])
    if not success:
        container_path = "/home/ga/Documents/sort_data_input.csv"
        success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods', 'xlsx'])
        if not success:
            container_path = "/home/ga/Documents/sort_data_input.ods"
            success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods', 'xlsx'])
            if not success:
                return {"passed": False, "score": 0, "feedback": f"Setup failed: {error}"}
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())

        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}

        sheet_name = sheet_names[0]
        sheet_rows = data['sheets'][sheet_name]

        # Convert to format expected by verify_data_sorted
        sheet_data_for_sort = {'rows': sheet_rows}

        feedback_parts = []
        criteria_met = 0
        total_criteria = 3

        # 1. Check if Score column (column B, index 1) is sorted
        is_sorted, sort_error = verify_data_sorted(sheet_data_for_sort, column=1, order='asc', start_row=1, end_row=6)

        if is_sorted:
            criteria_met += 1
            feedback_parts.append("✅ Score column sorted in ascending order")
        else:
            feedback_parts.append(f"❌ Score column not sorted: {sort_error}")

        # 2. Check expected order (David, Bob, Alice, Eve, Charlie)
        expected_order = [
            ("David", 63),
            ("Bob", 72),
            ("Alice", 85),
            ("Eve", 88),
            ("Charlie", 95)
        ]

        order_correct = True
        for i, (exp_name, exp_score) in enumerate(expected_order):
            row_idx = i + 2  # Skip header (row 1), start from row 2
            actual_name = str(get_cell_value(data, sheet_name, f"A{row_idx}")).strip()
            actual_score = get_cell_value(data, sheet_name, f"B{row_idx}")

            try:
                actual_score_num = float(actual_score)
                if actual_name != exp_name or abs(actual_score_num - exp_score) > 0.01:
                    order_correct = False
                    feedback_parts.append(f"Row {row_idx}: expected ({exp_name}, {exp_score}), got ({actual_name}, {actual_score})")
            except (ValueError, TypeError):
                order_correct = False
                feedback_parts.append(f"Row {row_idx}: invalid score value: {actual_score}")

        if order_correct:
            criteria_met += 1
            feedback_parts.append("✅ Name-Score pairs correctly maintained")
        else:
            feedback_parts.append("❌ Name-Score pairs incorrect after sorting")

        # 3. Check no data loss (5 data rows + 1 header)
        row_count = 0
        for row in sheet_rows:
            if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
                row_count += 1

        if row_count >= 6:
            criteria_met += 1
            feedback_parts.append("✅ All data preserved")
        else:
            feedback_parts.append(f"❌ Data loss detected: only {row_count} rows found")
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 66  # Need 2/3 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect sort!")
        elif passed:
            feedback_parts.append("✅ Sort task completed.")
        else:
            feedback_parts.append("❌ Sort task failed.")
        
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
