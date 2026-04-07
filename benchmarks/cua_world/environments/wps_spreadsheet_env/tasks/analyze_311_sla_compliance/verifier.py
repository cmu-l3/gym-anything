#!/usr/bin/env python3
"""
Verifier for analyze_311_sla_compliance task.
"""

import sys
import os
import json
import logging
import tempfile

# Insert path to access wps_verification_utils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    get_cell_formula,
    get_cell_value
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Verification VLM Prompt
VLM_PROMPT = """
Analyze these trajectory frames from a user working in a spreadsheet application. 
The task was to calculate SLA compliance for 311 pothole requests and build a Ward Summary sheet.

Check for evidence of workflow progression:
1. Did the user write formulas calculating Days to Close or SLA Status?
2. Did the user create a new sheet for the Ward Summary?
3. Did the user use aggregation formulas (COUNTIF, AVERAGEIF, COUNTIFS)?

Respond with a JSON object containing:
{
    "workflow_evidence_found": true/false,
    "summary_sheet_visible": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_sla_compliance(traj, env_info, task_info):
    """Verifies the SLA analysis spreadsheet."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    # 1. Evaluate metadata export (File saved & Anti-gaming)
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    file_modified = False
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            result_meta = json.load(f)
            file_modified = result_meta.get("file_modified_during_task", False)
            if file_modified:
                score += 10
                feedback_parts.append("File was saved/modified")
            else:
                feedback_parts.append("File was NOT modified (score heavily penalized)")
    except Exception as e:
        feedback_parts.append(f"Failed to read metadata: {e}")
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    # 2. Parse the Spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/chicago_311_potholes.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success or not wb:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Failed to open spreadsheet: {error}. " + " | ".join(feedback_parts)
        }

    try:
        sheets = wb.sheetnames
        
        # --- Evaluate Pothole_Data Formulas ---
        if "Pothole_Data" in sheets:
            # Check Column G (Days_To_Close)
            col_g_formulas = 0
            col_h_formulas = 0
            
            # Sample 10 rows to check for formulas to avoid looping 100 times needlessly
            sample_rows = [2, 10, 25, 50, 75, 90]
            
            for r in sample_rows:
                g_val = str(get_cell_formula(wb, "Pothole_Data", r, 7) or "").upper()
                h_val = str(get_cell_formula(wb, "Pothole_Data", r, 8) or "").upper()
                
                # Look for subtraction, DAYS, or IF checks in Col G
                if '=' in g_val and ('-' in g_val or 'DAYS' in g_val or 'DATEDIF' in g_val):
                    col_g_formulas += 1
                
                # Look for IF, 7, MET/BREACHED in Col H
                if '=' in h_val and 'IF' in h_val and '7' in h_val:
                    col_h_formulas += 1

            if col_g_formulas >= len(sample_rows) / 2:
                score += 20
                feedback_parts.append("Days_To_Close formulas: Present")
            else:
                feedback_parts.append("Days_To_Close formulas: Missing/Incorrect")

            if col_h_formulas >= len(sample_rows) / 2:
                score += 20
                feedback_parts.append("SLA_Status nested IF formulas: Present")
            else:
                feedback_parts.append("SLA_Status formulas: Missing/Incorrect")
        else:
            feedback_parts.append("Pothole_Data sheet missing/renamed")

        # --- Evaluate Ward_Summary Sheet ---
        if "Ward_Summary" in sheets:
            score += 10
            feedback_parts.append("Ward_Summary sheet created")
            
            ws_summary = wb["Ward_Summary"]
            countif_found = False
            avgif_found = False
            countifs_found = False
            
            # Check rows 2-6 in summary sheet for the aggregation formulas
            for r in range(2, 7):
                b_form = str(ws_summary.cell(row=r, column=2).value or "").upper()
                c_form = str(ws_summary.cell(row=r, column=3).value or "").upper()
                d_form = str(ws_summary.cell(row=r, column=4).value or "").upper()
                
                if 'COUNTIF' in b_form: countif_found = True
                if 'AVERAGEIF' in c_form: avgif_found = True
                if 'COUNTIFS' in d_form: countifs_found = True
                
            if countif_found and avgif_found:
                score += 20
                feedback_parts.append("COUNTIF/AVERAGEIF aggregations: Present")
            else:
                feedback_parts.append("COUNTIF/AVERAGEIF aggregations: Missing")
                
            if countifs_found:
                score += 10
                feedback_parts.append("COUNTIFS for Breaches: Present")
            else:
                feedback_parts.append("COUNTIFS for Breaches: Missing")
        else:
            feedback_parts.append("Ward_Summary sheet NOT found")

    except Exception as e:
        logger.error(f"Spreadsheet evaluation error: {e}", exc_info=True)
        feedback_parts.append(f"Evaluation error: {str(e)}")
    finally:
        cleanup_verification_temp(temp_dir)

    # 3. VLM Trajectory Verification
    try:
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            all_frames = frames + [final_frame] if final_frame else frames
            
            if all_frames:
                vlm_res = query_vlm(images=all_frames, prompt=VLM_PROMPT)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("workflow_evidence_found"):
                        score += 10
                        feedback_parts.append("VLM: Workflow evidence confirmed")
                    else:
                        feedback_parts.append("VLM: No clear workflow evidence")
    except Exception as e:
        logger.warning(f"VLM Verification failed: {e}")
        feedback_parts.append("VLM Verification unavailable")

    # Determine Pass/Fail (Requires 75 points and the file to be modified)
    passed = score >= 75 and file_modified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }