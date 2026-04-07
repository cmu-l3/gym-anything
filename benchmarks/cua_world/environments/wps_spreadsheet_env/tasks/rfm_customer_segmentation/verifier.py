#!/usr/bin/env python3
"""
Verifier for rfm_customer_segmentation task.
Evaluates accurate calculation of RFM metrics via Excel/WPS logic and final aggregations.
"""

import json
import os
import sys
import tempfile
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rfm_segmentation(traj, env_info, task_info):
    """
    Verify that RFM Customer Segmentation was calculated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Read Environment Task Data
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export meta: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result_meta.get("file_modified_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Anti-Gaming: The file was not modified during the task. Did you save your work?"}

    # ================================================================
    # 2. Parse Spreadsheet Values
    # ================================================================
    success, wb_vals, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/rfm_analysis.xlsx", copy_from_env, file_format='xlsx'
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    score = 0
    feedback_parts = []
    
    try:
        sheets = wb_vals.sheetnames
        if "Customer_Data" not in sheets:
            return {"passed": False, "score": 0, "feedback": "Customer_Data sheet missing"}
            
        ws_data = wb_vals["Customer_Data"]
        
        # Verify Headers
        headers = [str(cell.value).strip().lower() for cell in ws_data[1] if cell.value is not None]
        
        expected_cols = {
            'recency': 'recency_days',
            'r_score': 'r_score',
            'f_score': 'f_score',
            'm_score': 'm_score',
            'rfm_score': 'rfm_score',
            'segment': 'customer_segment'
        }
        
        # Find column indices (1-based)
        col_indices = {}
        for key, exp_name in expected_cols.items():
            for idx, h in enumerate(headers):
                if exp_name in h:
                    col_indices[key] = idx + 1
                    break

        # Check Recency Calculation (Target row 2 -> 12346 '2011-01-18')
        # Ref date: 2011-12-10. Days diff: 326
        if 'recency' in col_indices:
            val = ws_data.cell(row=2, column=col_indices['recency']).value
            if isinstance(val, (int, float)) and 320 <= val <= 330:
                score += 15
                feedback_parts.append("Recency correctly calculated")
            else:
                feedback_parts.append(f"Recency incorrect/missing (found {val})")
        else:
            feedback_parts.append("Recency_Days column missing")

        # Check Scores Lookups
        if all(k in col_indices for k in ['r_score', 'f_score', 'm_score']):
            # For 12346: Recency 326 -> R=1, Freq 1 -> F=1, Mon 77183 -> M=4
            r_val = ws_data.cell(row=2, column=col_indices['r_score']).value
            f_val = ws_data.cell(row=2, column=col_indices['f_score']).value
            m_val = ws_data.cell(row=2, column=col_indices['m_score']).value
            
            if r_val == 1 and f_val == 1 and m_val == 4:
                score += 25
                feedback_parts.append("R/F/M VLOOKUP scores correct")
            else:
                feedback_parts.append(f"R/F/M VLOOKUP scores incorrect (Found R{r_val}/F{f_val}/M{m_val})")
        else:
            feedback_parts.append("Score columns missing")
            
        # Check RFM string and Segment
        if 'rfm_score' in col_indices and 'segment' in col_indices:
            rfm_val = ws_data.cell(row=2, column=col_indices['rfm_score']).value
            seg_val = ws_data.cell(row=2, column=col_indices['segment']).value
            
            # Allow integer 114 or string "114"
            if str(rfm_val) == "114" and str(seg_val).lower() == "hibernating":
                score += 20
                feedback_parts.append("RFM combo and Segment exact match correct")
            else:
                feedback_parts.append(f"RFM/Segment mismatch (Found {rfm_val} -> {seg_val})")
        else:
            feedback_parts.append("RFM/Segment columns missing")

        # Check Summary Sheet
        summary_found = False
        summary_calcs_correct = False
        if "Segment_Summary" in sheets:
            summary_found = True
            ws_sum = wb_vals["Segment_Summary"]
            score += 10
            feedback_parts.append("Summary sheet created")
            
            # Search for COUNTIF/SUMIF values
            has_count = False
            has_rev = False
            for row in ws_sum.iter_rows(min_row=2, max_row=20, values_only=True):
                # We expect counts like 1, 2, 10, etc., and revenues in thousands
                # E.g., Hibernating has a few users
                if row[0] is not None and len(row) >= 3:
                    if isinstance(row[1], (int, float)) and row[1] > 0:
                        has_count = True
                    if isinstance(row[2], (int, float)) and row[2] > 0:
                        has_rev = True
            
            if has_count and has_rev:
                score += 10
                summary_calcs_correct = True
                feedback_parts.append("Aggregations (Count/Revenue) populated")
            else:
                feedback_parts.append("Aggregations missing on Summary sheet")
        else:
            feedback_parts.append("Summary sheet NOT found")

        # ================================================================
        # 3. VLM Verification (Anti-Gaming / Process Check)
        # ================================================================
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            vlm_prompt = """
            Look at these screenshots of a user working in a spreadsheet.
            Did the user actually construct formulas (e.g. VLOOKUP, SUMIF, COUNTIF, date arithmetic) in the formula bar to calculate the Recency, Scores, and Segments?
            Ensure they didn't just type in static raw numbers or copy-paste external results.
            Reply ONLY in JSON format:
            {"used_formulas": true/false}
            """
            
            vlm_result = query_vlm(
                images=frames + [final_frame],
                prompt=vlm_prompt
            )
            
            if vlm_result and vlm_result.get("parsed", {}).get("used_formulas", False):
                score += 20
                feedback_parts.append("VLM confirmed formula usage")
            else:
                feedback_parts.append("VLM did not detect active formula usage (may be static data)")
                
        passed = score >= 70 and summary_found

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