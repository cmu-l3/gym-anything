#!/usr/bin/env python3
"""
Verifier for telco_churn_mrr_analysis task.
Uses copy_from_env to safely extract files and trajectory frames for VLM scoring.
"""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import copy_and_parse_spreadsheet, cleanup_verification_temp
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_churn_analysis(traj, env_info, task_info):
    """Verify customer churn MRR analysis operations."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100
    
    # ---------------------------------------------------------
    # 1. Read task_result.json (Anti-gaming & Basic Checks)
    # ---------------------------------------------------------
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)
            
    if not result_meta.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Target file churn_analysis.xlsx was not saved."}
        
    if result_meta.get("file_created_during_task", False):
        score += 15
        feedback_parts.append("File created during session (+15)")
    else:
        feedback_parts.append("Warning: File timestamp invalid.")

    # ---------------------------------------------------------
    # 2. Extract and Parse Spreadsheet
    # ---------------------------------------------------------
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/churn_analysis.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": score, "feedback": f"Failed to parse XLSX: {error}"}

    try:
        sheets = wb.sheetnames
        has_data = "Data" in sheets
        has_dash = "Dashboard" in sheets
        
        if has_data and has_dash:
            score += 10
            feedback_parts.append("Required sheets found (+10)")
        else:
            feedback_parts.append(f"Missing sheets (Found: {sheets})")
            
        # ---------------------------------------------------------
        # 3. Verify 'Data' Sheet formulas
        # ---------------------------------------------------------
        formulas_v = False
        formulas_w = False
        
        if has_data:
            data_sheet = wb["Data"]
            # Scan top rows of col V and W (indices 22 and 23 in 1-based openpyxl)
            for row in range(2, min(20, data_sheet.max_row + 1)):
                cell_v = data_sheet.cell(row=row, column=22).value
                cell_w = data_sheet.cell(row=row, column=23).value
                
                if isinstance(cell_v, str) and cell_v.startswith("="):
                    if "IF" in cell_v.upper():
                        formulas_v = True
                if isinstance(cell_w, str) and cell_w.startswith("="):
                    if "IF" in cell_w.upper() and ("AND" in cell_w.upper() or "*" in cell_w):
                        formulas_w = True
                        
            if formulas_v:
                score += 10
                feedback_parts.append("Lost_MRR logic found (+10)")
            if formulas_w:
                score += 10
                feedback_parts.append("High_Value_Churn logic found (+10)")

        # ---------------------------------------------------------
        # 4. Verify 'Dashboard' Sheet formulas & aggregations
        # ---------------------------------------------------------
        found_countif = False
        found_sumifs = False
        found_averageif = False
        
        if has_dash:
            dash_sheet = wb["Dashboard"]
            for row in dash_sheet.iter_rows():
                for cell in row:
                    val = str(cell.value).upper() if cell.value else ""
                    if val.startswith("="):
                        if "COUNTIF" in val:
                            found_countif = True
                        if "SUMIFS" in val or "SUMIF" in val:
                            found_sumifs = True
                        if "AVERAGEIF" in val:
                            found_averageif = True
                            
            if found_countif:
                score += 15
                feedback_parts.append("Dashboard COUNTIFs found (+15)")
            if found_sumifs:
                score += 15
                feedback_parts.append("Dashboard SUMIFS found (+15)")
            if found_averageif:
                score += 10
                feedback_parts.append("Dashboard AVERAGEIF found (+10)")

        # ---------------------------------------------------------
        # 5. VLM Verification (Trajectory frames)
        # ---------------------------------------------------------
        if query_vlm and traj:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)
                
            vlm_prompt = """
            Analyze these frames from a WPS Spreadsheet session. The user is tasked with building a Telco Churn Dashboard.
            Answer in JSON format:
            {
                "worked_on_csv_data": true/false,
                "created_summary_tables": true/false,
                "wrote_formulas_in_formula_bar": true/false
            }
            Did the agent:
            1. Have the raw Telco customer data open?
            2. Build dashboard summary tables (Contract Type, Internet Service)?
            3. Actively write or edit spreadsheet formulas?
            """
            
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("worked_on_csv_data") and parsed.get("created_summary_tables"):
                    score += 15
                    feedback_parts.append("VLM confirmed dashboard workflow (+15)")
                else:
                    feedback_parts.append("VLM did not observe full dashboard creation.")
            else:
                feedback_parts.append("VLM query failed or unsupported.")
        else:
            feedback_parts.append("VLM skipped (no frames or query available).")

        passed = score >= 70
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