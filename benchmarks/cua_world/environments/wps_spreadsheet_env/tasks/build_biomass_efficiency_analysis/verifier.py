#!/usr/bin/env python3
"""
Verifier for Biomass Plant Efficiency and Heat Rate Analysis.
Evaluates both formula construction (programmatic) and visual trajectory (VLM).
"""

import os
import json
import logging
import tempfile

# Adjust path to import utility functions
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from wps_verification_utils import copy_and_parse_spreadsheet
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_biomass_efficiency(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Read task execution export
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check file modification to prevent gaming
    if not export_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Target file does not exist."}
    if not export_data.get('file_modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "Target file was NOT modified during the task (Anti-gaming)."}
    else:
        score += 5
        feedback_parts.append("File saved successfully (5/5)")

    # 2. Copy and parse the spreadsheet
    target_path = "/home/ga/Documents/eia923_biomass_data.xlsx"
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(target_path, copy_from_env, file_format='xlsx')

    if not success or wb is None:
        return {"passed": False, "score": score, "feedback": f"Failed to parse workbook: {error}"}

    try:
        sheets = wb.sheetnames
        plant_ws = wb["Plant_Data"] if "Plant_Data" in sheets else wb.active
        summary_ws = wb["State_Summary"] if "State_Summary" in sheets else None

        # -------------------------------------------------------------
        # Criterion A: Heat Rate Calculation (Col G) - 20 pts
        # -------------------------------------------------------------
        heat_rate_pts = 0
        g1_val = str(plant_ws["G1"].value).strip().lower()
        if "heat" in g1_val and "rate" in g1_val:
            heat_rate_pts += 5

        # Check formulas in G2:G5
        valid_hr_formulas = 0
        for i in range(2, min(plant_ws.max_row, 10)):
            cell_val = str(plant_ws[f"G{i}"].value).upper()
            if cell_val.startswith("="):
                if "IF" in cell_val and "NO GEN" in cell_val and "/" in cell_val:
                    valid_hr_formulas += 1
        
        if valid_hr_formulas > 0:
            heat_rate_pts += 15
            feedback_parts.append(f"Heat Rate formulas correct (20/20)")
        else:
            feedback_parts.append(f"Heat Rate formulas missing/incorrect ({heat_rate_pts}/20)")
            
        score += heat_rate_pts

        # -------------------------------------------------------------
        # Criterion B: Status Logic (Col H) - 25 pts
        # -------------------------------------------------------------
        status_pts = 0
        h1_val = str(plant_ws["H1"].value).strip().lower()
        if "efficiency" in h1_val or "status" in h1_val:
            status_pts += 5

        valid_status_formulas = 0
        for i in range(2, min(plant_ws.max_row, 10)):
            cell_val = str(plant_ws[f"H{i}"].value).upper()
            if cell_val.startswith("="):
                # Verify nested IF and key status strings
                if "IF" in cell_val and "OFFLINE" in cell_val and "OPTIMAL" in cell_val and "NORMAL" in cell_val and "REVIEW" in cell_val:
                    valid_status_formulas += 1
        
        if valid_status_formulas > 0:
            status_pts += 20
            feedback_parts.append("Status nested IF logic correct (25/25)")
        else:
            feedback_parts.append(f"Status logic missing key components ({status_pts}/25)")
            
        score += status_pts

        # -------------------------------------------------------------
        # Criterion C: Summary Sheet Structure - 10 pts
        # -------------------------------------------------------------
        struct_pts = 0
        if summary_ws:
            struct_pts += 5
            states = [str(summary_ws[f"A{i}"].value).strip().upper() for i in range(2, 8)]
            expected_states = ["CA", "FL", "GA", "ME", "MI", "WA"]
            
            # Allow any order as long as they are all present
            if all(st in states for st in expected_states):
                struct_pts += 5
                feedback_parts.append("Summary sheet structure correct (10/10)")
            else:
                feedback_parts.append("Summary sheet missing required states (5/10)")
        else:
            feedback_parts.append("Summary sheet NOT found (0/10)")
        
        score += struct_pts

        # -------------------------------------------------------------
        # Criterion D: SUMIF Aggregations - 25 pts
        # -------------------------------------------------------------
        sumif_pts = 0
        if summary_ws:
            gen_sumifs = 0
            fuel_sumifs = 0
            for i in range(2, 8):
                b_val = str(summary_ws[f"B{i}"].value).upper()
                c_val = str(summary_ws[f"C{i}"].value).upper()
                if b_val.startswith("=") and ("SUMIF" in b_val or "SUMPRODUCT" in b_val):
                    gen_sumifs += 1
                if c_val.startswith("=") and ("SUMIF" in c_val or "SUMPRODUCT" in c_val):
                    fuel_sumifs += 1
            
            if gen_sumifs >= 6: sumif_pts += 12.5
            elif gen_sumifs > 0: sumif_pts += 6
            
            if fuel_sumifs >= 6: sumif_pts += 12.5
            elif fuel_sumifs > 0: sumif_pts += 6

            feedback_parts.append(f"SUMIF formulas: {gen_sumifs} gen, {fuel_sumifs} fuel ({sumif_pts}/25)")
        score += sumif_pts

        # -------------------------------------------------------------
        # Criterion E: Aggregate Heat Rate - 15 pts
        # -------------------------------------------------------------
        agg_hr_pts = 0
        if summary_ws:
            valid_divisions = 0
            for i in range(2, 8):
                d_val = str(summary_ws[f"D{i}"].value).upper()
                # Check for division e.g., =C2/B2
                if d_val.startswith("=") and "/" in d_val:
                    valid_divisions += 1
            
            if valid_divisions >= 6:
                agg_hr_pts += 15
            elif valid_divisions > 0:
                agg_hr_pts += 7

            feedback_parts.append(f"Aggregate Heat Rate divisions: {valid_divisions} ({agg_hr_pts}/15)")
        score += agg_hr_pts

        # -------------------------------------------------------------
        # Trajectory VLM Check (Anti-gaming fallback)
        # -------------------------------------------------------------
        if query_vlm:
            try:
                frames = sample_trajectory_frames(traj, n=3)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                vlm_prompt = """
                Look at these frames from a user working in a spreadsheet application.
                Verify:
                1. Did they actively work in the spreadsheet (typing, highlighting, navigating)?
                2. Do you see them writing/working with formulas (like IF or SUMIF) or navigating between tabs (Plant_Data, State_Summary)?
                
                Respond ONLY with JSON:
                {"active_work": true/false, "formula_interaction": true/false}
                """
                vlm_resp = query_vlm(prompt=vlm_prompt, images=images)
                if vlm_resp and vlm_resp.get("parsed"):
                    parsed = vlm_resp["parsed"]
                    if not parsed.get("active_work"):
                        feedback_parts.append("VLM Penalty: No active spreadsheet work detected in trajectory.")
                        score -= 20
            except Exception as e:
                logger.warning(f"VLM trajectory check failed: {e}")

        # Final determination
        # Pass threshold is 75 points, and they must have used SOME SUMIF logic
        passed = score >= 75 and sumif_pts > 0 and heat_rate_pts >= 15

        return {
            "passed": passed,
            "score": int(score),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if temp_dir and os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)