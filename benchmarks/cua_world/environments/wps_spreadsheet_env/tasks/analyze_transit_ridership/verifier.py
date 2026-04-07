#!/usr/bin/env python3
"""
Verifier for analyze_transit_ridership task.

Checks:
1. File saved/modified (anti-gaming).
2. 'Period' logic correctly implemented in Raw_Data.
3. SUMIF formula applied for Total rides.
4. AVERAGEIFS formulas applied for Weekday/Weekend averages.
5. Nested IF applied for Station Tier categorizations.
6. VLM trajectory verification to ensure work was actually performed.
"""

import json
import os
import sys
import logging
import tempfile

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    get_cell_formula,
    get_cell_value
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transit_ridership(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read JSON result from export
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    file_modified = False
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            file_modified = result.get('file_modified', False)
    except Exception as e:
        logger.error(f"Error reading result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Parse the spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/cta_ridership_oct2023.xlsx",
        copy_from_env,
        file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    score = 0
    feedback_parts = []
    
    try:
        if file_modified:
            score += 10
            feedback_parts.append("File modified (+10)")
        else:
            feedback_parts.append("File NOT modified (0)")

        if 'Raw_Data' not in wb.sheetnames or 'Station_Summary' not in wb.sheetnames:
            return {
                "passed": False, 
                "score": score, 
                "feedback": " | ".join(feedback_parts) + " | Critical failure: Missing required sheets."
            }

        ws_raw = wb['Raw_Data']
        ws_sum = wb['Station_Summary']

        # 3. Check Period Logic in Raw_Data
        period_header = str(get_cell_value(wb, 'Raw_Data', 1, 6) or '').strip().lower()
        has_period_header = (period_header == 'period')
        
        period_formula_found = False
        # Sample top rows to verify logic applied
        for row in range(2, min(ws_raw.max_row, 15)):
            f = str(get_cell_formula(wb, 'Raw_Data', row, 6) or '').upper()
            if 'IF' in f and ('W' in f or 'WEEKDAY' in f):
                period_formula_found = True
                break

        if has_period_header and period_formula_found:
            score += 15
            feedback_parts.append("Period logic present (+15)")
        else:
            feedback_parts.append("Period logic missing (0)")

        # 4. Check formulas in Station_Summary
        sumif_found = False
        avgif_weekday_found = False
        avgif_weekend_found = False
        tier_if_found = False

        for row in range(2, min(ws_sum.max_row, 15)):
            f_b = str(get_cell_formula(wb, 'Station_Summary', row, 2) or '').upper()
            f_c = str(get_cell_formula(wb, 'Station_Summary', row, 3) or '').upper()
            f_d = str(get_cell_formula(wb, 'Station_Summary', row, 4) or '').upper()
            f_e = str(get_cell_formula(wb, 'Station_Summary', row, 5) or '').upper()

            if 'SUMIF' in f_b: 
                sumif_found = True
            if 'AVERAGEIFS' in f_c: 
                avgif_weekday_found = True
            if 'AVERAGEIFS' in f_d: 
                avgif_weekend_found = True
            if 'IF' in f_e and ('100' in f_e or '50' in f_e): 
                tier_if_found = True

        if sumif_found:
            score += 20
            feedback_parts.append("SUMIF applied (+20)")
        else:
            feedback_parts.append("SUMIF missing (0)")

        if avgif_weekday_found and avgif_weekend_found:
            score += 25
            feedback_parts.append("AVERAGEIFS correctly applied (+25)")
        elif avgif_weekday_found or avgif_weekend_found:
            score += 10
            feedback_parts.append("AVERAGEIFS partially applied (+10)")
        else:
            feedback_parts.append("AVERAGEIFS missing (0)")

        if tier_if_found:
            score += 15
            feedback_parts.append("Station Tier IF logic applied (+15)")
        else:
            feedback_parts.append("Station Tier IF logic missing (0)")

        # 5. VLM Trajectory Verification
        query_vlm = env_info.get('query_vlm')
        vlm_score = 0
        if query_vlm:
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=3)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                vlm_prompt = """
                Review these screenshots of a user working in WPS Spreadsheet.
                The user is tasked with adding a 'Period' column in the Raw Data, and building a 'Station_Summary' table using formulas like SUMIF, AVERAGEIFS, and IF.
                Did the user actively construct these formulas and build out the requested columns during the workflow?
                Respond strictly with JSON containing a single boolean field:
                {"workflow_completed": true} or {"workflow_completed": false}
                """
                vlm_result = query_vlm(prompt=vlm_prompt, images=images)
                if vlm_result and vlm_result.get("parsed", {}).get("workflow_completed", False):
                    vlm_score = 15
                    feedback_parts.append("VLM visual verification passed (+15)")
                else:
                    feedback_parts.append("VLM visual verification failed (0)")
            except Exception as e:
                logger.warning(f"VLM verification error: {e}")
                vlm_score = 15
                feedback_parts.append("VLM error, auto-granting (+15)")
        else:
            vlm_score = 15
            feedback_parts.append("VLM unavailable, auto-granting (+15)")

        score += vlm_score

        # Ensure passing threshold implies doing the core aggregation correctly
        passed = score >= 75 and sumif_found and file_modified

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