#!/usr/bin/env python3
"""Verifier for create_pivot_table task."""

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


def verify_pivot_table(traj, env_info, task_info):
    """Verify pivot table was created."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_paths = [
        "/home/ga/Documents/employee_sales.xlsx",
        "/home/ga/Documents/pivot_table.xlsx",
        "/home/ga/Documents/Pivot.xlsx",
    ]

    success = False
    wb = None
    error = None
    temp_dir = None

    for path in container_paths:
        success, wb, error, temp_dir = copy_and_parse_spreadsheet(
            path, copy_from_env, file_format='xlsx'
        )
        if success:
            break

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open file: {error}"}

    try:
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 5

        sheets = wb.sheetnames

        # Criterion 1: Multiple sheets (indicates pivot sheet created)
        has_multiple = len(sheets) > 1

        if has_multiple:
            criteria_passed += 1
            feedback_parts.append(f"Multiple sheets: {sheets}")
        else:
            feedback_parts.append("Multiple sheets: NOT found")

        # Criterion 2: VLM verification for pivot table
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Spreadsheet screenshot. Answer in JSON:
{
    "has_pivot_table": true/false,
    "has_aggregated_data": true/false,
    "has_department_summary": true/false,
    "has_grand_totals": true/false,
    "has_structured_layout": true/false
}
Does the spreadsheet show:
1. A pivot table with rows and columns?
2. Aggregated/summarized data?
3. Department-wise breakdown?
4. Grand total rows or columns?
5. A structured table layout (not raw data)?
""")

        if vlm_result is not None:
            has_pivot = vlm_result.get("has_pivot_table", False)
            has_agg = vlm_result.get("has_aggregated_data", False)
            has_dept = vlm_result.get("has_department_summary", False)
            has_totals = vlm_result.get("has_grand_totals", False)

            if has_pivot or has_agg:
                criteria_passed += 1
                feedback_parts.append("Pivot table structure: detected")
            else:
                feedback_parts.append("Pivot table structure: NOT detected")

            if has_dept:
                criteria_passed += 1
                feedback_parts.append("Department summary: detected")
            else:
                feedback_parts.append("Department summary: NOT detected")

            if has_totals:
                criteria_passed += 1
                feedback_parts.append("Grand totals: detected")
            else:
                feedback_parts.append("Grand totals: NOT detected")
        else:
            total_criteria -= 3
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
