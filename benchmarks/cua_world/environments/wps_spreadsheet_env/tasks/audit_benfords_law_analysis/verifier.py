#!/usr/bin/env python3
"""Verifier for audit_benfords_law_analysis task."""

import sys
import os
import json
import tempfile
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_benfords_law_analysis(traj, env_info, task_info):
    """
    Verify the agent correctly applied Benford's law analysis.
    Uses multi-criteria verification focusing on correct formula usage,
    spreadsheet structure, and trajectory VLM visual checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Evaluate task metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Workbook not found."}

    # Open the spreadsheet
    target_file = "/home/ga/Documents/vendor_payments_FY23.xlsx"
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        target_file, copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        feedback_parts = []
        score = 0
        
        # 1. Check Anti-Gaming File Modifications (10 points)
        if export_result.get("file_modified_during_task", False):
            score += 10
            feedback_parts.append("File modified during task")
        else:
            feedback_parts.append("File was NOT modified (did you save?)")

        sheets = wb.sheetnames
        has_payments = "Payments" in sheets
        
        # Determine exact name for analysis sheet (case-insensitivity tolerance)
        analysis_sheet_name = next((s for s in sheets if "benford" in s.lower()), None)

        # 2. Structure & Leading Digit Checks (20 points)
        if has_payments and analysis_sheet_name:
            score += 10
            feedback_parts.append(f"Required sheets found")
            
            # Check for leading digit formula extraction in Payments sheet
            payment_ws = wb["Payments"]
            has_leading_digit_formula = False
            
            # Scan the 6th column (F) or header row for "Leading_Digit"
            for row in payment_ws.iter_rows(min_row=1, max_row=10, values_only=False):
                for cell in row:
                    val = str(cell.value).upper()
                    if "LEFT" in val and "VALUE" in val:
                        has_leading_digit_formula = True
                        break
                if has_leading_digit_formula:
                    break
            
            if has_leading_digit_formula:
                score += 10
                feedback_parts.append("Leading digit formula detected")
            else:
                feedback_parts.append("No standard text extraction formula found in Payments")
        else:
            feedback_parts.append("Required sheets NOT found")

        # 3. Benford Formula Checks (30 points)
        has_countif = False
        has_log10 = False
        has_variance = False
        has_if_flag = False
        has_charts = False

        if analysis_sheet_name:
            analysis_ws = wb[analysis_sheet_name]
            
            # Check for chart presence
            if hasattr(analysis_ws, '_charts') and len(analysis_ws._charts) > 0:
                has_charts = True

            # Scan formulas in the analysis sheet
            for row in analysis_ws.iter_rows(values_only=False):
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula = cell.value.upper()
                        if "COUNTIF" in formula:
                            has_countif = True
                        if "LOG10" in formula:
                            has_log10 = True
                        if "ABS" in formula or "-" in formula:
                            has_variance = True
                        if "IF" in formula and ("0.02" in formula or "2%" in formula):
                            has_if_flag = True

            if has_countif:
                score += 5
                feedback_parts.append("COUNTIF logic found")
            if has_log10:
                score += 10
                feedback_parts.append("LOG10 Benford formula found")
            if has_variance:
                score += 5
                feedback_parts.append("Variance logic found")
            if has_if_flag:
                score += 10
                feedback_parts.append("Anomaly IF flag found")
        
        # 4. Chart Structure (15 points)
        if has_charts:
            score += 15
            feedback_parts.append("Chart element found in spreadsheet")
        else:
            feedback_parts.append("Chart object NOT found in sheet")

        # 5. VLM Visual Trajectory Verification (25 points)
        # Trajectory verifies the user actually built the chart and formatted it
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            vlm_prompt = """
            Analyze these WPS Spreadsheet trajectory screenshots. Answer in JSON:
            {
                "has_benford_table": true/false,
                "has_analysis_chart": true/false,
                "shows_investigate_flag": true/false
            }
            Look for:
            1. A summary table indicating Digits 1-9 and Expected/Actual distributions.
            2. A Bar/Column or Line chart comparing actual vs expected distributions.
            3. A column with conditional flags like "Investigate" or "OK".
            """
            vlm_result = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("has_benford_table"):
                    score += 10
                    feedback_parts.append("VLM: Table visible")
                if parsed.get("has_analysis_chart"):
                    score += 10
                    feedback_parts.append("VLM: Chart visible")
                if parsed.get("shows_investigate_flag"):
                    score += 5
                    feedback_parts.append("VLM: Flag visible")
            else:
                feedback_parts.append("VLM verification failed")
                # Deduct from maximum possible since VLM couldn't run
        else:
            feedback_parts.append("VLM unavailable - skipping visual check")
            # Pro-rate score if VLM is offline
            score = min(100, int((score / 75.0) * 100))

        # Check thresholds
        key_criteria_met = has_log10 and has_countif and (has_charts or (vlm_result and vlm_result.get("parsed", {}).get("has_analysis_chart")))
        passed = score >= 65 and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)