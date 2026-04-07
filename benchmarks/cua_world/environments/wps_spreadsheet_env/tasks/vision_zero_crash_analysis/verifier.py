#!/usr/bin/env python3
"""Verifier for vision_zero_crash_analysis task."""

import sys
import os
import json
import logging
import tempfile

# Use provided verification utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vision_zero_crash_analysis(traj, env_info, task_info):
    """
    Verify that the time extraction, pivot aggregations, format applications, and charting are implemented.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read exported metadata JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic file presence evaluation (Anti-gaming check)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Spreadsheet file not found."}
        
    if not result.get('file_modified_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task. Did the agent forget to save?"}

    # Extract Excel content for verification using utility
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/nyc_collisions.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        score = 0
        feedback_parts = []
        
        # 1. Hour Column Creation Check (10 pts)
        crashes_sheet = wb['Crashes'] if 'Crashes' in wb.sheetnames else wb.active
        hour_formula_found = False
        
        # Verify P2 contains the HOUR function logically
        p2_val = str(crashes_sheet['P2'].value).upper()
        if 'HOUR(' in p2_val:
            hour_formula_found = True
        else:
            # Fallback checking first few rows or adjacent columns
            for col in range(15, 20):
                cell_val = str(crashes_sheet.cell(row=2, column=col).value).upper()
                if 'HOUR(' in cell_val:
                    hour_formula_found = True
                    break

        if hour_formula_found:
            score += 10
            feedback_parts.append("Hour formula: correct")
        else:
            feedback_parts.append("Hour formula: missing")

        # 2. Hourly_Analysis Summary Sheet Checklist (10 pts)
        if 'Hourly_Analysis' in wb.sheetnames:
            score += 10
            feedback_parts.append("Summary sheet: found")
            analysis_sheet = wb['Hourly_Analysis']
            
            # 3. Total Crashes COUNTIF Logic (20 pts)
            b2_val = str(analysis_sheet['B2'].value).upper()
            if 'COUNTIF' in b2_val:
                score += 20
                feedback_parts.append("Total Crashes COUNTIF formula: correct")
            else:
                feedback_parts.append("Total Crashes formula: missing COUNTIF")
                
            # 4. Injury SUMIF Logic (20 pts)
            c2_val = str(analysis_sheet['C2'].value).upper()
            d2_val = str(analysis_sheet['D2'].value).upper()
            if 'SUMIF' in c2_val and 'SUMIF' in d2_val:
                score += 20
                feedback_parts.append("Injury Sum SUMIF formulas: correct")
            else:
                feedback_parts.append("Injury Sum formulas: missing SUMIF")
                
            # 5. Injury Rate Calc (10 pts)
            e2_val = str(analysis_sheet['E2'].value).upper()
            if '/' in e2_val and '=' in e2_val:
                score += 10
                feedback_parts.append("Injury Rate formula: correct")
            else:
                feedback_parts.append("Injury Rate formula: missing division")
                
            # 6 & 7: VLM Multi-Modality Checks for Visuals (30 pts Total)
            # Try to grab references programmatically if openpyxl successfully parses them natively 
            has_chart_obj = len(analysis_sheet._charts) > 0 if hasattr(analysis_sheet, '_charts') else False
            has_cf_obj = len(analysis_sheet.conditional_formatting._cf_rules) > 0 if hasattr(analysis_sheet, 'conditional_formatting') else False
            
            # Use Trajectory Validation visually due to WPS Office discrepancies with standard XML parsing
            vlm_prompt = '''
            Analyze this WPS Spreadsheet screenshot. Answer in JSON format:
            {
                "has_trend_chart": true/false,
                "has_color_scale_formatting": true/false
            }
            Does the spreadsheet show:
            1. A trend chart (like a line or column chart) visualizing the hourly data?
            2. Color scale conditional formatting (e.g., gradient colors like red/yellow/green applied to a column of numbers)?
            '''
            vlm_result = vlm_verify_screenshot(env_info, traj, vlm_prompt)
            
            has_chart_vlm = False
            has_cf_vlm = False
            
            if vlm_result:
                has_chart_vlm = vlm_result.get("has_trend_chart", False)
                has_cf_vlm = vlm_result.get("has_color_scale_formatting", False)
                
            if has_chart_obj or has_chart_vlm:
                score += 15
                feedback_parts.append("Trend Chart: confirmed")
            else:
                feedback_parts.append("Trend Chart: not found")
                
            if has_cf_obj or has_cf_vlm:
                score += 15
                feedback_parts.append("Conditional Formatting: confirmed")
            else:
                feedback_parts.append("Conditional Formatting: not found")
                
        else:
            feedback_parts.append("Summary sheet 'Hourly_Analysis': NOT found")

        # Final Verification Determination Check
        # Pass Threshold: 70 points AND core functional requirements hit to prevent hallucination
        crashes_ok = any("Total Crashes COUNTIF formula: correct" in f for f in feedback_parts)
        injury_ok = any("Injury Sum SUMIF formulas: correct" in f for f in feedback_parts)
        
        passed = score >= 70 and crashes_ok and injury_ok

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)