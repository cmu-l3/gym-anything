#!/usr/bin/env python3
"""Verifier for supply_chain_otif_analysis task."""

import sys
import os
import json
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


def verify_otif_analysis(traj, env_info, task_info):
    """Verify that OTIF analysis formulas, summary table, and formatting were applied."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read the export JSON metadata for anti-gaming checks
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not export_data.get("file_modified_during_task", False):
        return {"passed": False, "score": 0, "feedback": "File was not saved/modified during task."}

    # 2. Extract and Parse the Spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/supply_chain_orders.xlsx", copy_from_env, file_format='xlsx'
    )
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        feedback_parts = []
        score = 0
        
        # Track presence of logic formulas
        has_variance_math = False
        has_if_logic = False
        has_and_logic = False
        
        # Track summary logic
        has_summary_sheet = False
        has_countif_logic = False
        
        # Evaluate Data Sheet (Order_Data)
        if 'Order_Data' in wb.sheetnames:
            ws_data = wb['Order_Data']
            # Search formulas in the new columns G, H, I, J
            for row in ws_data.iter_rows(min_row=2, max_row=10, min_col=7, max_col=10):
                for cell in row:
                    val = str(cell.value).upper() if cell.value else ""
                    if "=" in val:
                        if "-" in val: # Variance subtraction
                            has_variance_math = True
                        if "IF" in val:
                            has_if_logic = True
                        if "AND" in val:
                            has_and_logic = True

        if has_variance_math and has_if_logic and has_and_logic:
            score += 35
            feedback_parts.append("OTIF logic formulas (IF/AND/Variance) present")
        else:
            feedback_parts.append("Incomplete OTIF logic formulas in Order_Data")

        # Evaluate Summary Sheet
        if 'Department_Summary' in wb.sheetnames:
            has_summary_sheet = True
            score += 15
            feedback_parts.append("Department_Summary sheet created")
            
            ws_summary = wb['Department_Summary']
            # Check for aggregation logic
            for row in ws_summary.iter_rows(min_row=2, max_row=10, min_col=2, max_col=3):
                for cell in row:
                    val = str(cell.value).upper() if cell.value else ""
                    if "COUNTIF" in val:
                        has_countif_logic = True
                        
            if has_countif_logic:
                score += 20
                feedback_parts.append("COUNTIF aggregation formulas present")
            else:
                feedback_parts.append("Missing COUNTIF logic for summary table")
        else:
            feedback_parts.append("Department_Summary sheet NOT found")

        # 3. Trajectory-based VLM verification for Formatting & Sorting
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            frames.append(get_final_screenshot(traj))
            
            vlm_prompt = """
            Analyze these screenshots of a WPS Spreadsheet task. Respond in JSON format only:
            {
                "has_summary_table": true/false,
                "is_sorted_descending": true/false,
                "has_red_conditional_formatting": true/false,
                "has_percentage_formatting": true/false
            }
            1. Is there a summary table showing Departments and Order counts?
            2. Is the 'Total Orders' column visually sorted in descending order (highest numbers at top)?
            3. Are there cells highlighted with a RED background (Conditional Formatting for values < 90%)?
            4. Are the OTIF percentages formatted with a % symbol?
            """
            
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("is_sorted_descending"):
                    score += 15
                    feedback_parts.append("Table is sorted descending")
                else:
                    feedback_parts.append("Sorting missing or incorrect")
                    
                if parsed.get("has_red_conditional_formatting") and parsed.get("has_percentage_formatting"):
                    score += 15
                    feedback_parts.append("Conditional and percentage formatting applied")
                else:
                    feedback_parts.append("Visual formatting incomplete")
            else:
                feedback_parts.append("VLM visual verification failed")
        else:
            feedback_parts.append("VLM not available for formatting checks")

        passed = score >= 70 and has_if_logic and has_summary_sheet
        
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