#!/usr/bin/env python3
"""Verifier for create_sales_summary task."""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    get_spreadsheet_text,
    get_cell_value,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sales_summary(traj, env_info, task_info):
    """
    Verify that the sales summary was created correctly.

    SCORING CRITERIA:
    1. Summary sheet exists (25 points)
    2. Has SUMIF formulas for totals (20 points)
    3. Has AVERAGEIF formulas (15 points)
    4. Has COUNTIF formulas (15 points)
    5. Bold formatting on headers (10 points)
    6. Currency formatting applied (10 points)
    7. VLM visual verification (5 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Try different file paths
    container_paths = [
        "/home/ga/Documents/sales_data.xlsx",
        "/home/ga/Documents/sales_summary.xlsx",
        "/home/ga/Documents/Summary.xlsx",
        "/home/ga/Documents/sales.xlsx",
    ]

    success = False
    wb = None
    error = None
    temp_dir = None

    for container_path in container_paths:
        success, wb, error, temp_dir = copy_and_parse_spreadsheet(
            container_path, copy_from_env, file_format='xlsx'
        )
        if success:
            logger.info(f"Successfully opened: {container_path}")
            break

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 7

        # Get metadata
        metadata = task_info.get('metadata', {})

        # ================================================================
        # Criterion 1: Summary sheet exists
        # ================================================================
        sheets = wb.sheetnames
        has_summary = any('summary' in s.lower() for s in sheets) or len(sheets) > 1

        if has_summary:
            criteria_passed += 1
            feedback_parts.append(f"Summary sheet exists: {sheets}")
        else:
            feedback_parts.append("Summary sheet NOT found")

        # ================================================================
        # Criterion 2-4: Check for formulas
        # ================================================================
        sumif_count = 0
        averageif_count = 0
        countif_count = 0

        for sheet_name in sheets:
            sheet = wb[sheet_name]
            for row in sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        formula = cell.value.upper()
                        if 'SUMIF' in formula:
                            sumif_count += 1
                        if 'AVERAGEIF' in formula:
                            averageif_count += 1
                        if 'COUNTIF' in formula:
                            countif_count += 1

        # Criterion 2: SUMIF formulas
        if sumif_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"SUMIF formulas: {sumif_count}")
        else:
            feedback_parts.append(f"SUMIF formulas: NOT found ({sumif_count})")

        # Criterion 3: AVERAGEIF formulas
        if averageif_count >= 1:
            criteria_passed += 1
            feedback_parts.append(f"AVERAGEIF formulas: {averageif_count}")
        else:
            feedback_parts.append(f"AVERAGEIF formulas: NOT found")

        # Criterion 4: COUNTIF formulas
        if countif_count >= 1:
            criteria_passed += 1
            feedback_parts.append(f"COUNTIF formulas: {countif_count}")
        else:
            feedback_parts.append(f"COUNTIF formulas: NOT found")

        # ================================================================
        # Criterion 5: Bold formatting on headers
        # ================================================================
        has_bold_headers = False

        for sheet_name in sheets:
            if 'summary' in sheet_name.lower():
                sheet = wb[sheet_name]
                # Check first row for bold
                for cell in sheet[1]:
                    if cell.font and cell.font.bold:
                        has_bold_headers = True
                        break
                if has_bold_headers:
                    break

        if has_bold_headers:
            criteria_passed += 1
            feedback_parts.append("Bold headers: present")
        else:
            feedback_parts.append("Bold headers: NOT found")

        # ================================================================
        # Criterion 6: Currency formatting
        # ================================================================
        has_currency_format = False

        for sheet_name in sheets:
            if 'summary' in sheet_name.lower():
                sheet = wb[sheet_name]
                # Check cells for currency format
                for row in sheet.iter_rows(min_row=2):
                    for cell in row:
                        if cell.number_format and '$' in cell.number_format:
                            has_currency_format = True
                            break
                    if has_currency_format:
                        break

        if has_currency_format:
            criteria_passed += 1
            feedback_parts.append("Currency formatting: present")
        else:
            feedback_parts.append("Currency formatting: NOT found")

        # ================================================================
        # Criterion 7: VLM verification
        # ================================================================
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Spreadsheet screenshot. Answer in JSON:
{
    "has_summary_table": true/false,
    "has_formulas_visible": true/false,
    "has_proper_formatting": true/false,
    "has_multiple_sheets": true/false
}
Does the spreadsheet show:
1. A summary table with aggregated data?
2. Formulas or calculated values?
3. Proper formatting (bold, numbers)?
4. Multiple sheets or tabs?
""")

        if vlm_result is not None:
            has_table = vlm_result.get("has_summary_table", False)
            has_formatting = vlm_result.get("has_proper_formatting", False)

            if has_table or has_formatting:
                criteria_passed += 1
                feedback_parts.append("VLM: spreadsheet properly formatted")
            else:
                feedback_parts.append("VLM: formatting not confirmed")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM: unavailable")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 55

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
