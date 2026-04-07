#!/usr/bin/env python3
"""Verifier for calc_medicare_readmission_penalties task."""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_readmission_penalties(traj, env_info, task_info):
    """
    Verify the medicare readmission penalties task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ====================================================================
    # Step 1: Check basic metadata export
    # ====================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result_meta.get("file_modified_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The spreadsheet file was not saved/modified during the task."
        }

    # ====================================================================
    # Step 2: Open and parse the spreadsheet formulas
    # ====================================================================
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/cms_readmissions.xlsx", 
        copy_from_env, 
        file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        score = 5  # Start with 5 pts for saving the file
        feedback_parts = ["File saved (+5)"]
        
        sheets = wb.sheetnames
        has_summary = any("summary" in s.lower() for s in sheets)
        
        if has_summary:
            score += 5
            feedback_parts.append("Summary sheet created (+5)")
        else:
            feedback_parts.append("Summary sheet NOT found")

        # Check Readmissions Sheet formulas
        if "Readmissions" in wb:
            ws_data = wb["Readmissions"]
            
            # Analyze Column G (Status) and Column H (Penalty)
            has_no_data_logic = False
            has_excessive_logic = False
            has_penalty_math = False
            
            # Sample first few rows to evaluate formulas
            for row in range(2, min(10, ws_data.max_row + 1)):
                g_cell = ws_data.cell(row=row, column=7).value
                h_cell = ws_data.cell(row=row, column=8).value
                
                if isinstance(g_cell, str) and "=" in g_cell:
                    g_formula = g_cell.upper()
                    if "NOT AVAILABLE" in g_formula or "ISNUMBER" in g_formula or "ISTEXT" in g_formula or "IFERROR" in g_formula:
                        has_no_data_logic = True
                    if ">1" in g_formula or "EXCESSIVE" in g_formula:
                        has_excessive_logic = True
                
                if isinstance(h_cell, str) and "=" in h_cell:
                    h_formula = h_cell.upper()
                    # Check for basic arithmetic expected: (F-1)*E*1000
                    if "*" in h_formula and ("1000" in h_formula or "1E3" in h_formula):
                        has_penalty_math = True
            
            if has_no_data_logic:
                score += 20
                feedback_parts.append("Text handling logic detected (+20)")
            else:
                feedback_parts.append("Text handling logic ('No Data') NOT detected")
                
            if has_excessive_logic:
                score += 15
                feedback_parts.append("Numerical logic ('Excessive') detected (+15)")
            else:
                feedback_parts.append("Numerical logic NOT detected")
                
            if has_penalty_math:
                score += 15
                feedback_parts.append("Penalty arithmetic detected (+15)")
            else:
                feedback_parts.append("Penalty arithmetic NOT detected")

        # Check Measure_Summary Sheet formulas
        has_countifs = False
        has_sumifs = False
        has_data_bars = False
        
        for sheet_name in sheets:
            if "summary" in sheet_name.lower():
                ws_sum = wb[sheet_name]
                
                # Check Conditional Formatting
                if hasattr(ws_sum, 'conditional_formatting') and ws_sum.conditional_formatting:
                    cf = ws_sum.conditional_formatting
                    if cf._cf_rules:
                        for cell_range, rules in cf._cf_rules.items():
                            for rule in rules:
                                if rule.type == 'dataBar':
                                    has_data_bars = True
                
                # Check for COUNTIFS / SUMIFS
                for row in ws_sum.iter_rows():
                    for cell in row:
                        if isinstance(cell.value, str) and "=" in cell.value:
                            formula = cell.value.upper()
                            if "COUNTIF" in formula:
                                has_countifs = True
                            if "SUMIF" in formula:
                                has_sumifs = True
        
        if has_countifs:
            score += 15
            feedback_parts.append("Hospital counts (COUNTIFS) detected (+15)")
        else:
            feedback_parts.append("Hospital counts NOT detected")
            
        if has_sumifs:
            score += 15
            feedback_parts.append("Financial totals (SUMIFS) detected (+15)")
        else:
            feedback_parts.append("Financial totals NOT detected")

        # ====================================================================
        # Step 3: VLM Verification for formatting/layout
        # ====================================================================
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            
            vlm_prompt = """
            Analyze these screenshots from a spreadsheet task. Some are trajectory frames, the last is the final screenshot.
            Answer strictly in JSON:
            {
                "currency_formatting_applied": true/false,
                "summary_table_visible": true/false,
                "data_bars_visible": true/false
            }
            1. Are the Estimated_Penalty amounts formatted as Currency ($)?
            2. Is there a Measure Summary table visible summarizing by measure?
            3. Are Data Bars (colored gradient bars inside cells) visually present in the summary table?
            """
            
            vlm_res = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
            if vlm_res and vlm_res.get("parsed"):
                parsed = vlm_res["parsed"]
                # We use VLM to verify data bars if openpyxl failed to detect them properly
                if parsed.get("data_bars_visible", False) and not has_data_bars:
                    has_data_bars = True
                
                if parsed.get("currency_formatting_applied", False):
                    feedback_parts.append("Currency formatting visually confirmed")
        
        if has_data_bars:
            score += 10
            feedback_parts.append("Data Bars conditional formatting detected (+10)")
        else:
            feedback_parts.append("Data Bars NOT detected")

        # Pass condition: 75 points, must have text handling logic and financial totals
        key_criteria_met = has_no_data_logic and has_sumifs
        passed = (score >= 75) and key_criteria_met

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