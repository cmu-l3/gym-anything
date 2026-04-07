#!/usr/bin/env python3
"""
Verifier for fleet_fuel_analysis task.
"""

import os
import sys
import json
import logging
import tempfile
import re

# Add utils directory to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from wps_verification_utils import copy_and_parse_spreadsheet, cleanup_verification_temp
except ImportError:
    # Fallback if utils not available directly during isolated testing
    def copy_and_parse_spreadsheet(*args, **kwargs): return False, None, "Import error", None
    def cleanup_verification_temp(*args, **kwargs): pass

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fleet_fuel_analysis(traj, env_info, task_info):
    """
    Verify the fleet fuel analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing."}

    # 1. Read JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_meta.get("file_modified", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "File was not modified during the task duration. (Do-nothing detected)"
        }

    # 2. Parse Spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/fleet_fuel_data.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse spreadsheet: {error}"}

    score = 0
    feedback = []
    max_score = 100
    
    try:
        sheets = [s.lower() for s in wb.sheetnames]
        
        # ----- Check Sheets -----
        if 'analysis' in sheets and 'summary' in sheets:
            score += 10
            feedback.append("Analysis and Summary sheets created.")
        else:
            feedback.append(f"Missing required sheets. Found: {wb.sheetnames}")
            # If sheets don't exist, it's impossible to pass programmatic checks
            if 'analysis' not in sheets:
                return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # ----- Check Analysis Formulas -----
        analysis_ws = wb['Analysis'] if 'Analysis' in wb.sheetnames else wb['analysis']
        
        has_vlookup = False
        has_sumif = False
        has_if = False
        
        # Check rows 2 through 16 for expected formulas
        for row in range(2, 17):
            for col in range(1, 12): # Cols A through K
                cell_val = str(analysis_ws.cell(row=row, column=col).value).upper()
                if not cell_val.startswith('='):
                    continue
                if 'VLOOKUP' in cell_val:
                    has_vlookup = True
                if 'SUMIF' in cell_val or 'SUMPRODUCT' in cell_val:
                    has_sumif = True
                if 'IF(' in cell_val:
                    has_if = True
                    
        if has_vlookup:
            score += 15
            feedback.append("VLOOKUP formulas found.")
        else:
            feedback.append("Missing VLOOKUP formulas.")
            
        if has_sumif:
            score += 15
            feedback.append("SUMIF/SUMPRODUCT formulas found.")
        else:
            feedback.append("Missing SUMIF/SUMPRODUCT formulas.")
            
        if has_if:
            score += 10
            feedback.append("IF formulas found.")
        else:
            feedback.append("Missing IF formulas.")

        # ----- Check Summary Formulas -----
        if 'Summary' in wb.sheetnames or 'summary' in sheets:
            summary_ws = wb['Summary'] if 'Summary' in wb.sheetnames else wb['summary']
            
            has_sum = False
            has_countif = False
            has_index_match = False
            
            for row in range(1, 20):
                for col in range(1, 5):
                    cell_val = str(summary_ws.cell(row=row, column=col).value).upper()
                    if not cell_val.startswith('='):
                        continue
                    if 'SUM(' in cell_val:
                        has_sum = True
                    if 'COUNTIF(' in cell_val:
                        has_countif = True
                    if 'INDEX(' in cell_val and 'MATCH(' in cell_val:
                        has_index_match = True
                        
            if has_sum:
                score += 10
                feedback.append("Summary SUM found.")
            if has_countif:
                score += 10
                feedback.append("Summary COUNTIF found.")
            if has_index_match:
                score += 10
                feedback.append("Summary INDEX/MATCH found.")

        # ----- Programmatic Chart Check -----
        has_chart = False
        if hasattr(analysis_ws, '_charts') and len(analysis_ws._charts) > 0:
            has_chart = True
            score += 5
            feedback.append("Chart object detected programmatically.")

        # ----- VLM Trajectory Verification for workflow and chart visually -----
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            
            vlm_prompt = """
            You are evaluating a user working in WPS Spreadsheet.
            Task: Create formulas and a bar chart comparing Actual vs EPA fuel efficiency.
            
            Examine the trajectory and final image. Return JSON:
            {
                "created_formulas": true/false,
                "created_chart": true/false,
                "chart_is_bar_chart": true/false
            }
            """
            vlm_result = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("created_formulas"):
                    score += 5
                    feedback.append("VLM confirmed formula interaction.")
                if parsed.get("created_chart") and parsed.get("chart_is_bar_chart"):
                    score += 10
                    has_chart = True
                    feedback.append("VLM visually confirmed bar chart presence.")
                elif not has_chart:
                    feedback.append("VLM did not detect a valid bar chart.")
            else:
                # Give partial credit if VLM fails but programmatic passed
                if has_chart:
                    score += 10
                feedback.append("VLM check unavailable or failed to parse.")
        else:
            if has_chart:
                score += 15 # Grant full chart points if VLM is entirely missing
            feedback.append("VLM check skipped (not provided).")

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        feedback.append(f"Verification script error: {e}")
    finally:
        cleanup_verification_temp(temp_dir)

    passed = score >= 60 and has_vlookup and has_sumif

    if passed:
        feedback.insert(0, "Task passed successfully.")
    else:
        feedback.insert(0, "Task failed to meet minimum passing criteria.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }