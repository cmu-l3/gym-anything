#!/usr/bin/env python3
"""Verifier for faa_wildlife_strike_analysis task."""

import sys
import os
import json
import logging
import tempfile
import re

# Add utils directory to path to import wps_verification_utils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import copy_and_parse_spreadsheet

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_wildlife_strike_analysis(traj, env_info, task_info):
    """Verify WPS Spreadsheet wildlife strike analysis."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Check basic file state from export_result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result_meta.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Spreadsheet file not found."}

    file_modified = result_meta.get("file_modified_during_task", False)

    # 2. Parse the spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/wildlife_strikes.xlsx", 
        copy_from_env, 
        file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse spreadsheet: {error}"}

    score = 0
    feedback_parts = []
    
    if file_modified:
        score += 5
        feedback_parts.append("File saved successfully (5/5)")
    else:
        feedback_parts.append("File was NOT saved/modified (0/5)")

    try:
        # Check if sheets exist
        sheet_names = wb.sheetnames
        if 'Strikes' not in sheet_names or 'Summary' not in sheet_names:
            return {"passed": False, "score": score, "feedback": "Missing required 'Strikes' or 'Summary' sheets."}
            
        ws_strikes = wb['Strikes']
        ws_summary = wb['Summary']

        # Function to clean and extract formula
        def get_formula(cell):
            if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                return cell.value.upper()
            return ""

        # --- EVALUATE 'STRIKES' SHEET ---
        # State Lookup (Col H)
        h2_formula = get_formula(ws_strikes['H2'])
        if any(func in h2_formula for func in ['VLOOKUP', 'XLOOKUP', 'INDEX']):
            score += 15
            feedback_parts.append("State Lookup formula correct (15/15)")
        elif h2_formula != "":
            score += 5
            feedback_parts.append("State Lookup formula present but might be incorrect (5/15)")
        else:
            feedback_parts.append("State Lookup formula missing (0/15)")

        # Total Cost (Col I)
        i2_formula = get_formula(ws_strikes['I2'])
        if ('F' in i2_formula and 'G' in i2_formula) or 'SUM(' in i2_formula:
            score += 10
            feedback_parts.append("Total Cost formula correct (10/10)")
        elif i2_formula != "":
            score += 5
            feedback_parts.append("Total Cost formula present but structure unusual (5/10)")
        else:
            feedback_parts.append("Total Cost formula missing (0/10)")

        # Major Incident Logic (Col J)
        j2_formula = get_formula(ws_strikes['J2'])
        if 'IF' in j2_formula and 'OR' in j2_formula and '50000' in j2_formula and 'SUBSTANTIAL' in j2_formula:
            score += 20
            feedback_parts.append("Major Incident IF/OR logic correct (20/20)")
        elif 'IF' in j2_formula:
            score += 10
            feedback_parts.append("Major Incident IF present, but criteria might be incomplete (10/20)")
        else:
            feedback_parts.append("Major Incident logic missing (0/20)")

        # --- EVALUATE 'SUMMARY' SHEET ---
        # Total Strikes (Col B)
        b2_formula = get_formula(ws_summary['B2'])
        if 'COUNTIF' in b2_formula:
            score += 15
            feedback_parts.append("Summary Total Strikes COUNTIF correct (15/15)")
        else:
            feedback_parts.append("Summary Total Strikes formula missing or incorrect (0/15)")

        # Total Cost (Col C)
        c2_formula = get_formula(ws_summary['C2'])
        if 'SUMIF' in c2_formula:
            score += 15
            feedback_parts.append("Summary Total Cost SUMIF correct (15/15)")
        else:
            feedback_parts.append("Summary Total Cost formula missing or incorrect (0/15)")

        # Major Incidents (Col D)
        d2_formula = get_formula(ws_summary['D2'])
        if 'COUNTIFS' in d2_formula:
            score += 15
            feedback_parts.append("Summary Major Incidents COUNTIFS correct (15/15)")
        else:
            feedback_parts.append("Summary Major Incidents formula missing or incorrect (0/15)")

        # --- EVALUATE FORMATTING ---
        # Currency Formatting check on Strikes column I and Summary column C
        currency_found = False
        i2_format = ws_strikes['I2'].number_format if ws_strikes['I2'].number_format else ""
        c2_format = ws_summary['C2'].number_format if ws_summary['C2'].number_format else ""
        
        if ('$' in i2_format or 'USD' in i2_format) and ('$' in c2_format or 'USD' in c2_format):
            currency_found = True
            
        if currency_found:
            score += 5
            feedback_parts.append("Currency formatting applied (5/5)")
        else:
            feedback_parts.append("Currency formatting missing or incomplete (0/5)")

    except Exception as e:
        logger.error(f"Error evaluating workbook: {e}")
        feedback_parts.append(f"Error during workbook analysis: {e}")
    finally:
        # Cleanup temp directory
        if temp_dir and os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)

    # VLM Anti-Gaming Check (Ensure UI usage)
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            if frames:
                vlm_prompt = """Look at these frames from a screen recording. 
Does it show a user/agent interacting with the WPS Spreadsheet UI? 
Answer purely with JSON: {"used_spreadsheet_ui": true/false}"""
                vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
                if vlm_res and vlm_res.get("parsed", {}).get("used_spreadsheet_ui", False):
                    pass # Valid UI interaction
                else:
                    feedback_parts.append("Warning: VLM did not detect spreadsheet UI usage (Possible python scripting used)")
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")

    # Pass threshold: 70 points with Major Incident Logic AND at least two Summary aggregations correct
    # Checking if Major incident logic > 0 and at least two summary logic > 0
    major_logic = 'IF/OR logic correct' in " ".join(feedback_parts) or 'IF present' in " ".join(feedback_parts)
    
    summary_correct = sum([
        1 for f in feedback_parts if 'Summary Total Strikes COUNTIF correct' in f or 
                                     'Summary Total Cost SUMIF correct' in f or 
                                     'Summary Major Incidents COUNTIFS correct' in f
    ])
    
    passed = score >= 70 and major_logic and summary_correct >= 2 and file_modified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }