#!/usr/bin/env python3
"""Verifier for calculate_manufacturing_oee task."""

import sys
import os
import json
import tempfile
import logging

# Add utils directory to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_manufacturing_oee(traj, env_info, task_info):
    """Verify OEE calculations and summary sheet."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read exported JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check basic file modification
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "File /home/ga/Documents/production_logs.xlsx not found."}
    
    if not result.get('file_modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "File was not saved/modified during the task."}

    # Fetch spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/production_logs.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse spreadsheet: {error}"}

    try:
        feedback_parts = []
        score = 0
        
        # Check Shift Logs Sheet (Max 60 points)
        if 'Shift Logs' not in wb.sheetnames:
            return {"passed": False, "score": 0, "feedback": "'Shift Logs' sheet is missing or renamed."}
            
        shift_sheet = wb['Shift Logs']
        
        # Verification functions
        def is_formula(cell):
            return cell.value is not None and str(cell.value).startswith('=')
            
        def has_percent_format(cell):
            return cell.number_format is not None and '%' in cell.number_format

        # Sample row 2 to check formulas
        i2 = shift_sheet['I2'] # Operating Time: D2 - E2
        j2 = shift_sheet['J2'] # Availability: I2 / D2
        k2 = shift_sheet['K2'] # Performance: (G2 * (F2 / 60)) / I2
        l2 = shift_sheet['L2'] # Quality: (G2 - H2) / G2
        m2 = shift_sheet['M2'] # OEE: J2 * K2 * L2

        # 1. Check Operating Time and Availability (15 pts)
        if is_formula(i2) and is_formula(j2):
            score += 15
            feedback_parts.append("Time/Avail formulas found")
        else:
            feedback_parts.append("Missing Time/Avail formulas")

        # 2. Check Performance and Quality (20 pts)
        if is_formula(k2) and is_formula(l2) and '/' in str(k2.value) and '60' in str(k2.value):
            score += 20
            feedback_parts.append("Perf/Qual formulas found")
        else:
            feedback_parts.append("Missing or incorrect Perf/Qual formulas")

        # 3. Check OEE (15 pts)
        if is_formula(m2) and '*' in str(m2.value):
            score += 15
            feedback_parts.append("OEE formula found")
        else:
            feedback_parts.append("Missing OEE formula")

        # 4. Check formatting (10 pts)
        if has_percent_format(j2) and has_percent_format(m2):
            score += 10
            feedback_parts.append("Percentage formatting applied")
        else:
            feedback_parts.append("Missing percentage formatting")

        # Check Machine Summary Sheet (Max 40 points)
        summary_found = False
        for s in wb.sheetnames:
            if 'summary' in s.lower():
                summary_found = True
                summary_sheet = wb[s]
                break

        if summary_found:
            score += 10
            feedback_parts.append("Summary sheet found")
            
            # Check row 2 formulas in summary
            b2_sum = str(summary_sheet['B2'].value).upper() if summary_sheet['B2'].value else ""
            c2_sum = str(summary_sheet['C2'].value).upper() if summary_sheet['C2'].value else ""
            
            # Average logic (15 pts)
            if b2_sum.startswith('=') and ('AVERAGE' in b2_sum or 'SUM' in b2_sum):
                score += 15
                feedback_parts.append("Average OEE formula found")
            else:
                feedback_parts.append("Missing Average OEE formula")

            # Status logic (15 pts)
            if c2_sum.startswith('=') and 'IF' in c2_sum and ('75' in c2_sum or '0.75' in c2_sum):
                score += 15
                feedback_parts.append("Status IF formula found")
            else:
                feedback_parts.append("Missing Status IF formula")
        else:
            feedback_parts.append("Summary sheet NOT found")

        # VLM Trajectory check to ensure agent actually worked in the UI
        vlm_result = vlm_verify_screenshot(env_info, traj, """
        Analyze this WPS Spreadsheet screenshot.
        Is there evidence of OEE calculation (columns for Availability, Performance, Quality, OEE) or a Machine Summary sheet with 'Good' or 'Needs Review' status?
        Answer as JSON: {"shows_oee_work": true/false}
        """)
        
        vlm_worked = False
        if vlm_result and vlm_result.get("shows_oee_work", False):
            vlm_worked = True
        
        passed = score >= 75 and vlm_worked

        if not vlm_worked:
            feedback_parts.append("VLM did not verify visual OEE work")

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