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

        # Criterion 1: Data validation exists
        has_dv = False
        dv_count = 0

        if hasattr(sheet, 'data_validations') and sheet.data_validations:
            dv = sheet.data_validations
            dv_count = len(dv.dataValidation) if dv.dataValidation else 0
            has_dv = dv_count > 0

        if has_dv:
            criteria_passed += 1
            feedback_parts.append(f"Data validation: present ({dv_count} rules)")
        else:
            feedback_parts.append("Data validation: NOT found")

        # Criterion 2: Freeze panes
        has_freeze = sheet.freeze_panes is not None

        if has_freeze:
            criteria_passed += 1
            feedback_parts.append("Freeze panes: present")
        else:
            feedback_parts.append("Freeze panes: NOT found")

        # Criterion 3-5: VLM checks
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Spreadsheet screenshot. Answer in JSON:
{
    "has_dropdown_menus": true/false,
    "has_freeze_effect": true/false,
    "has_validation_indicators": true/false,
    "has_proper_layout": true/false
}
Does the spreadsheet show:
1. Dropdown menus or arrows indicating data validation?
2. Frozen header row (stays in place when scrolling)?
3. Visual indicators of validation rules?
4. Well-organized table structure?
""")

        if vlm_result is not None:
            has_dropdown = vlm_result.get("has_dropdown_menus", False)
            has_freeze_effect = vlm_result.get("has_freeze_effect", False)
            has_indicators = vlm_result.get("has_validation_indicators", False)

            if has_dropdown or has_indicators:
                criteria_passed += 1
                feedback_parts.append("Dropdown menus: detected")
            else:
                feedback_parts.append("Dropdown menus: NOT detected")

            if has_freeze_effect:
                criteria_passed += 1
                feedback_parts.append("Freeze effect: detected")
            else:
                feedback_parts.append("Freeze effect: NOT detected")

            if has_indicators:
                criteria_passed += 1
                feedback_parts.append("Validation indicators: detected")
            else:
                feedback_parts.append("Validation indicators: NOT detected")
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
