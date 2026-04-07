#!/usr/bin/env python3
"""Verifier for apply_data_validation task."""

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


def verify_data_validation(traj, env_info, task_info):
    """Verify data validation was applied."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/project_tracker.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open file: {error}"}

    try:
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 5

        sheet = wb.active

        # Criterion 1: Has data validation rules (25 points)
        has_dv = False
        dv_count = 0
        dv_types = set()

        if hasattr(sheet, 'data_validations') and sheet.data_validations:
            dv = sheet.data_validations
            dv_count = len(dv.dataValidation) if dv.dataValidation else 0
            has_dv = dv_count > 0
            for rule in (dv.dataValidation or []):
                if rule.type:
                    dv_types.add(rule.type)

        if has_dv:
            criteria_passed += 1
            feedback_parts.append(f"Data validation: present ({dv_count} rules, types: {dv_types})")
        else:
            feedback_parts.append("Data validation: NOT found")

        # Criterion 2: Has list validation (for Status/Priority dropdowns)
        has_list = 'list' in dv_types
        if has_list:
            criteria_passed += 1
            feedback_parts.append("List validation (dropdowns): found")
        else:
            feedback_parts.append("List validation (dropdowns): NOT found")

        # Criterion 3: Has whole number or decimal validation (for Budget)
        has_number = 'whole' in dv_types or 'decimal' in dv_types
        if has_number:
            criteria_passed += 1
            feedback_parts.append("Number validation (Budget): found")
        else:
            feedback_parts.append("Number validation (Budget): NOT found")

        # Criterion 4: Has date validation (for Start Date)
        has_date = 'date' in dv_types
        if has_date:
            criteria_passed += 1
            feedback_parts.append("Date validation (Start Date): found")
        else:
            feedback_parts.append("Date validation (Start Date): NOT found")

        # Criterion 5: VLM visual verification
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Spreadsheet screenshot. Answer in JSON:
{
    "has_dropdown_indicators": true/false,
    "data_visible": true/false,
    "spreadsheet_formatted": true/false
}
Does the spreadsheet show:
1. Dropdown indicators or data validation markers on cells?
2. Is the project data visible and formatted?
3. Are there any validation error indicators?
""")

        if vlm_result is not None:
            if vlm_result.get("has_dropdown_indicators", False) or vlm_result.get("data_visible", False):
                criteria_passed += 1
                feedback_parts.append("VLM: validation indicators detected")
            else:
                feedback_parts.append("VLM: no validation indicators detected")
        else:
            total_criteria -= 1
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
