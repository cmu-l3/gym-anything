#!/usr/bin/env python3
"""Verifier for add_conditional_formatting task."""

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


def verify_conditional_formatting(traj, env_info, task_info):
    """Verify conditional formatting was applied."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/inventory.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open file: {error}"}

    try:
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 5

        sheet = wb.active

        # Criterion 1: Has conditional formatting
        has_cf = False
        cf_count = 0

        if hasattr(sheet, 'conditional_formatting') and sheet.conditional_formatting:
            cf = sheet.conditional_formatting
            cf_count = len(cf._cf_rules) if cf._cf_rules else 0
            has_cf = cf_count > 0

        if has_cf:
            criteria_passed += 1
            feedback_parts.append(f"Conditional formatting: present ({cf_count} rules)")
        else:
            feedback_parts.append("Conditional formatting: NOT found")

        # Criterion 2-4: VLM checks (main criteria since openpyxl CF support is limited)
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Spreadsheet screenshot. Answer in JSON:
{
    "has_color_highlighting": true/false,
    "has_data_bars": true/false,
    "has_color_scale": true/false,
    "has_visual_formatting": true/false
}
Does the spreadsheet show:
1. Color highlighting (red/green) on cells?
2. Data bars for visual comparison?
3. Color gradients or scales?
4. Any visual conditional formatting?
""")

        if vlm_result is not None:
            has_colors = vlm_result.get("has_color_highlighting", False)
            has_bars = vlm_result.get("has_data_bars", False)
            has_scale = vlm_result.get("has_color_scale", False)

            if has_colors:
                criteria_passed += 1
                feedback_parts.append("Color highlighting: detected")
            else:
                feedback_parts.append("Color highlighting: NOT detected")

            if has_bars:
                criteria_passed += 1
                feedback_parts.append("Data bars: detected")
            else:
                feedback_parts.append("Data bars: NOT detected")

            if has_scale:
                criteria_passed += 1
                feedback_parts.append("Color scale: detected")
            else:
                feedback_parts.append("Color scale: NOT detected")
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
