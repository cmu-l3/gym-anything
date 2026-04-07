#!/usr/bin/env python3
"""Verifier for college_roi_analysis task."""

import sys
import os
import json
import logging
import tempfile
import math

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp
)

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_cell_highlighting(sheet, row, col):
    """Check if a cell has a non-white/non-transparent background fill."""
    try:
        cell = sheet.cell(row=row, column=col)
        if cell.fill and cell.fill.fgColor:
            actual = str(cell.fill.fgColor.rgb).upper()
            # FFFFFF is white, 00000000 is transparent
            if actual not in ['00000000', 'FFFFFFFF', '00FFFFFF', 'FFFFFF00']: 
                # Specifically matching typical yellow 'FFFF00' or similar
                if "FF00" in actual or "FFFF" in actual:
                    return True
                # Accept any deliberate highlighting as attempt
                return True
        return False
    except:
        return False


def verify_college_roi(traj, env_info, task_info):
    """
    Verify the College ROI task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # ================================================================
    # Read basic task completion info
    # ================================================================
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

    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Target file PA_College_ROI.xlsx not saved."}

    if not result.get("file_created_during_task"):
        feedback_parts.append("WARNING: File not created during task (potential anti-gaming flag).")
    else:
        score += 10
        feedback_parts.append("File created correctly.")

    # ================================================================
    # Extract Spreadsheet and Parse
    # ================================================================
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/PA_College_ROI.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": score, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        # Check sheet
        if 'PA_Analysis' in wb.sheetnames:
            score += 10
            feedback_parts.append("Sheet 'PA_Analysis' found.")
            sheet = wb['PA_Analysis']
        else:
            feedback_parts.append("Sheet 'PA_Analysis' NOT found. Halting evaluation.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Locate Columns
        headers = [str(cell.value).strip().lower() if cell.value else "" for cell in sheet[1]]
        
        try:
            col_instnm = headers.index('instnm') + 1
            col_stabbr = headers.index('stabbr') + 1
            col_preddeg = headers.index('preddeg') + 1
            col_debt = headers.index('grad_debt_mdn') + 1
            col_earn = headers.index('md_earn_wne_p10') + 1
            col_ratio = headers.index('debt_to_earnings') + 1
        except ValueError as e:
            feedback_parts.append(f"Missing required column headers: {e}")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Analyze Rows
        row_count = 0
        filtering_correct = True
        sorting_correct = True
        ratio_correct = True
        previous_earn = float('inf')
        top_5_highlighted = 0
        
        for row_idx in range(2, sheet.max_row + 1):
            stabbr = str(sheet.cell(row=row_idx, column=col_stabbr).value).strip()
            preddeg = str(sheet.cell(row=row_idx, column=col_preddeg).value).strip()
            debt = str(sheet.cell(row=row_idx, column=col_debt).value).strip()
            earn = str(sheet.cell(row=row_idx, column=col_earn).value).strip()
            ratio_val = sheet.cell(row=row_idx, column=col_ratio).value
            
            # Skip empty rows that might just be formatting
            if not stabbr or stabbr == 'None':
                continue
                
            row_count += 1
            
            # Check Filtering
            if stabbr != 'PA' or preddeg != '3' or debt in ['PrivacySuppressed', 'NULL'] or earn in ['PrivacySuppressed', 'NULL']:
                filtering_correct = False
                
            # Check Sorting
            try:
                earn_val = float(earn)
                if earn_val > previous_earn:
                    sorting_correct = False
                previous_earn = earn_val
            except ValueError:
                sorting_correct = False

            # Check Ratio
            try:
                expected_ratio = float(debt) / float(earn)
                # Parse ratio if it's a formula string "=D2/E2" or direct float
                if isinstance(ratio_val, str) and ratio_val.startswith('='):
                    # We accept the presence of a formula as correct intent since openpyxl can't evaluate it
                    pass 
                else:
                    actual_ratio = float(ratio_val)
                    if not math.isclose(expected_ratio, actual_ratio, rel_tol=0.01):
                        ratio_correct = False
            except (ValueError, TypeError):
                ratio_correct = False

            # Check Highlighting for Top 5
            if row_count <= 5:
                if check_cell_highlighting(sheet, row_idx, col_instnm):
                    top_5_highlighted += 1

        # Evaluate Criteria
        expected_valid_rows = task_info.get("metadata", {}).get("expected_valid_rows", 24)
        if filtering_correct and row_count == expected_valid_rows:
            score += 30
            feedback_parts.append("Filtering perfect.")
        else:
            feedback_parts.append(f"Filtering incorrect (Found {row_count} rows, expected {expected_valid_rows}, all valid? {filtering_correct}).")

        if ratio_correct and row_count > 0:
            score += 20
            feedback_parts.append("Ratio calculation correct.")
        else:
            feedback_parts.append("Ratio calculation incorrect.")

        if sorting_correct and row_count > 1:
            score += 20
            feedback_parts.append("Sorting descending correct.")
        else:
            feedback_parts.append("Sorting incorrect.")

        if top_5_highlighted >= 4:  # Allowance for 1 mistake
            score += 10
            feedback_parts.append("Top 5 formatting correct.")
        else:
            feedback_parts.append(f"Top 5 formatting incomplete (Found {top_5_highlighted}/5).")

        # ================================================================
        # VLM Trajectory Verification
        # ================================================================
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            images = frames + [final_img] if final_img else frames

            if images:
                vlm_res = query_vlm(
                    images=images,
                    prompt="Does this sequence show a user working in WPS Spreadsheet filtering columns, writing a division formula, sorting data, and filling cell backgrounds with yellow? Reply 'Yes' or 'No'."
                )
                if "yes" in str(vlm_res).lower():
                    feedback_parts.append("VLM visual trajectory verified.")
                else:
                    feedback_parts.append("VLM visual verification ambiguous/failed.")
        
        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": score, "feedback": f"Error during verification: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)