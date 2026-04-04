#!/usr/bin/env python3
"""Verifier for sort_and_filter_data task."""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sort_filter(traj, env_info, task_info):
    """Verify sort and filter operations were applied."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/customer_orders.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open file: {error}"}

    try:
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 5

        sheet = wb.active

        # Criterion 1: AutoFilter applied
        has_filter = sheet.auto_filter and sheet.auto_filter.ref

        if has_filter:
            criteria_passed += 1
            feedback_parts.append("AutoFilter: present")
        else:
            feedback_parts.append("AutoFilter: NOT found")

        # Criterion 2: Freeze panes
        has_freeze = sheet.freeze_panes is not None

        if has_freeze:
            criteria_passed += 1
            feedback_parts.append("Freeze panes: present")
        else:
            feedback_parts.append("Freeze panes: NOT found")

        # Criterion 3: Check if sorted by Amount (descending)
        amounts = []
        for row in sheet.iter_rows(min_row=2, min_col=8, max_col=8, values_only=True):
            if row[0] is not None:
                amounts.append(row[0])

        is_sorted_desc = len(amounts) > 1 and amounts == sorted(amounts, reverse=True)

        if is_sorted_desc:
            criteria_passed += 1
            feedback_parts.append("Sorted by Amount (descending): confirmed")
        else:
            feedback_parts.append("Sorted by Amount: NOT confirmed")

        # Criterion 4-5: VLM verification
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Spreadsheet screenshot. Answer in JSON:
{
    "has_filter_dropdowns": true/false,
    "has_freeze_line": true/false,
    "has_sorted_appearance": true/false,
    "has_filtered_view": true/false
}
Does the spreadsheet show:
1. Filter dropdown arrows in the header row?
2. A frozen header line that stays in place?
3. Data that appears to be sorted (largest to smallest in a column)?
4. Any indication of filtered data (fewer rows visible)?
""")

        if vlm_result is not None:
            has_filter_dd = vlm_result.get("has_filter_dropdowns", False)
            has_freeze_line = vlm_result.get("has_freeze_line", False)

            if has_filter_dd:
                criteria_passed += 1
                feedback_parts.append("Filter dropdowns: detected")
            else:
                feedback_parts.append("Filter dropdowns: NOT detected")

            if has_freeze_line:
                criteria_passed += 1
                feedback_parts.append("Freeze line: detected")
            else:
                feedback_parts.append("Freeze line: NOT detected")
        else:
            total_criteria -= 2
            feedback_parts.append("VLM: unavailable")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 55

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
