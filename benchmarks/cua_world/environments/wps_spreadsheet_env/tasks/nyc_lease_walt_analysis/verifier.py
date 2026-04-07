#!/usr/bin/env python3
"""Verifier for nyc_lease_walt_analysis task."""

import sys
import os
import json
import logging
import tempfile
import math
from datetime import datetime

# Add the utils directory to the path to import wps utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from wps_verification_utils import copy_and_parse_spreadsheet, cleanup_verification_temp
except ImportError:
    logger.warning("wps_verification_utils not found, continuing with basic openpyxl check")

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_walt_analysis(traj, env_info, task_info):
    """
    Verify the commercial lease WALT analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Read base result from export script
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)
            
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Target spreadsheet not found. Task failed."}
        
    if not result_data.get("file_modified_during_task", False):
        feedback_parts.append("Warning: File does not appear to have been modified during task.")

    # Copy and parse spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/nyc_brooklyn_leases.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success or not wb:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse workbook: {error}"}

    try:
        sheets = wb.sheetnames
        if 'Lease Data' not in sheets:
            return {"passed": False, "score": 0, "feedback": "'Lease Data' sheet missing."}
            
        lease_sheet = wb['Lease Data']
        
        # Determine Ground Truth based on the loaded Lease Data
        # We read cols D (SqFt), F (Lease_End), G (Annual_Rent) to dynamically calculate expected results
        gt_sqft_sum = 0
        gt_rent_sum = 0
        gt_walt_weight_sum = 0
        
        analysis_date = datetime(2026, 1, 1)
        
        for row in range(2, lease_sheet.max_row + 1):
            sqft = lease_sheet.cell(row=row, column=4).value
            end_date = lease_sheet.cell(row=row, column=6).value
            rent = lease_sheet.cell(row=row, column=7).value
            
            if sqft is not None and rent is not None:
                gt_sqft_sum += sqft
                gt_rent_sum += rent
                
                # Calculate remaining months correctly
                if isinstance(end_date, datetime) and end_date > analysis_date:
                    months = (end_date.year - analysis_date.year) * 12 + end_date.month - analysis_date.month
                    # WALT Weight = Rent * Months
                    gt_walt_weight_sum += rent * months
                    
        gt_avg_psf = gt_rent_sum / gt_sqft_sum if gt_sqft_sum > 0 else 0
        gt_walt_months = gt_walt_weight_sum / gt_rent_sum if gt_rent_sum > 0 else 0
        gt_walt_years = gt_walt_months / 12

        # =========================================================
        # CRITERION 1: Rent Per SqFt Column (10 pts)
        # =========================================================
        h_header = str(lease_sheet.cell(row=1, column=8).value).strip()
        h2_val = lease_sheet.cell(row=2, column=8).value
        h2_formula = lease_sheet.cell(row=2, column=8).data_type == 'f'
        
        if "Rent" in h_header and "SqFt" in h_header and h2_val is not None:
            score += 10
            feedback_parts.append("Rent PSF column verified")
        else:
            feedback_parts.append("Rent PSF column missing or invalid")

        # =========================================================
        # CRITERION 2: Remaining Months Logic (25 pts)
        # =========================================================
        i_header = str(lease_sheet.cell(row=1, column=9).value).strip()
        i2_val = lease_sheet.cell(row=2, column=9).value # Row 2 is expired in our dataset -> should be 0
        i3_val = lease_sheet.cell(row=3, column=9).value # Row 3 is 5 months
        
        if "Remaining" in i_header or "Months" in i_header:
            if str(i2_val) == "0":
                score += 25
                feedback_parts.append("Remaining Months correct (handles expired leases)")
            elif str(i2_val).startswith("-"):
                score += 10
                feedback_parts.append("Remaining Months computed, but failed to floor expired to 0")
            else:
                score += 5
                feedback_parts.append("Remaining Months column found, logic unclear")
        else:
            feedback_parts.append("Remaining Months column missing")

        # =========================================================
        # CRITERION 3: WALT Weight Column (10 pts)
        # =========================================================
        j_header = str(lease_sheet.cell(row=1, column=10).value).strip()
        j3_val = lease_sheet.cell(row=3, column=10).value # Should be Annual Rent * Months
        
        if "WALT" in j_header or "Weight" in j_header:
            score += 10
            feedback_parts.append("WALT Weight column verified")
        else:
            feedback_parts.append("WALT Weight column missing")

        # =========================================================
        # CRITERION 4: Summary Sheet Exists & Structure (10 pts)
        # =========================================================
        if 'Portfolio Summary' in sheets:
            summary_sheet = wb['Portfolio Summary']
            labels_found = 0
            # Just scan column A for required text
            for row in range(1, 10):
                val = str(summary_sheet.cell(row=row, column=1).value).lower()
                if "sqft" in val or "rent" in val or "walt" in val:
                    labels_found += 1
            if labels_found >= 4:
                score += 10
                feedback_parts.append("Summary sheet structure good")
            else:
                score += 5
                feedback_parts.append("Summary sheet created but labels incomplete")
                
            # =========================================================
            # CRITERION 5: Summary Aggregations (20 pts)
            # =========================================================
            # Find the values in Column B
            b_vals = []
            for row in range(1, 10):
                cell = summary_sheet.cell(row=row, column=2)
                if cell.value is not None:
                    try:
                        b_vals.append(float(cell.value))
                    except:
                        pass
                        
            agg_points = 0
            if any(math.isclose(v, gt_sqft_sum, rel_tol=0.01) for v in b_vals):
                agg_points += 10
            if any(math.isclose(v, gt_rent_sum, rel_tol=0.01) for v in b_vals):
                agg_points += 10
                
            score += agg_points
            if agg_points == 20:
                feedback_parts.append("Aggregations (SqFt/Rent) correct")

            # =========================================================
            # CRITERION 6: WALT Calculation (10 pts)
            # =========================================================
            walt_pts = 0
            if any(math.isclose(v, gt_walt_months, rel_tol=0.05) for v in b_vals):
                walt_pts += 5
            if any(math.isclose(v, gt_walt_years, rel_tol=0.05) for v in b_vals):
                walt_pts += 5
                
            score += walt_pts
            if walt_pts > 0:
                feedback_parts.append("WALT Calculation correct")
            else:
                feedback_parts.append("WALT Calculation incorrect or missing")
                
        else:
            feedback_parts.append("Portfolio Summary sheet missing")

        # =========================================================
        # CRITERION 7: Conditional Formatting (VLM) (15 pts)
        # =========================================================
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            try:
                frames = sample_trajectory_frames(traj, n=4)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                vlm_resp = query_vlm(
                    prompt="""Analyze these spreadsheet screenshots. 
                    Has the user applied a conditional formatting rule to highlight cells in RED? 
                    Look specifically for the 'Remaining_Months' column containing numbers like 5, 16, 8 that are highlighted with a red or light red background, while 0 and numbers above 24 remain unhighlighted.
                    Answer in JSON: {"has_red_conditional_formatting": true/false}""",
                    images=images
                )
                
                if vlm_resp and vlm_resp.get("parsed", {}).get("has_red_conditional_formatting", False):
                    score += 15
                    feedback_parts.append("Conditional formatting verified visually")
                else:
                    feedback_parts.append("Conditional formatting NOT visible visually")
            except Exception as e:
                logger.error(f"VLM check failed: {e}")
                feedback_parts.append("VLM visual verification skipped/failed")
        else:
            # Fallback if VLM unavailable, check if openpyxl sees any conditional formatting rules on Lease Data
            if hasattr(lease_sheet, 'conditional_formatting') and len(lease_sheet.conditional_formatting._cf_rules) > 0:
                score += 15
                feedback_parts.append("Conditional formatting rules detected programmatically")
            else:
                feedback_parts.append("No Conditional formatting detected")

        # Compile final result
        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification encountered error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Execution error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)