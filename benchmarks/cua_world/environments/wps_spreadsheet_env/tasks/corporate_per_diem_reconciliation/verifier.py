#!/usr/bin/env python3
"""
Verifier for corporate_per_diem_reconciliation task.
Checks for cross-sheet lookups, logic boundaries, mathematical operations,
conditional formatting rules, and visual state verification.
"""

import sys
import os
import json
import logging
import tempfile
import re

# Import gym_anything utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import copy_and_parse_spreadsheet, cleanup_verification_temp
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reconciliation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    # 1. Read exported result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not export_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Workbook not found. Did you delete or rename it?"}
        
    if not export_result.get("file_modified_during_task", False):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task session. Did you save (Ctrl+S)?"}

    # 2. Copy and parse the spreadsheet
    # Note: openpyxl defaults to data_only=False, meaning we get formula strings. This is perfect for verifying methodology.
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/travel_reconciliation.xlsx", copy_from_env, file_format='xlsx'
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse spreadsheet: {error}"}

    score = 0
    feedback_parts = []
    
    try:
        sheet_names = [s.lower() for s in wb.sheetnames]
        claims_ws = None
        for s in wb.sheetnames:
            if "claims" in s.lower():
                claims_ws = wb[s]
                break
                
        if not claims_ws:
            return {"passed": False, "score": 0, "feedback": "Expense_Claims sheet missing."}

        # --- Check 1: Lookup Formulas (20 pts) ---
        has_lookups = False
        lookup_pattern = re.compile(r'(VLOOKUP|XLOOKUP|INDEX|MATCH)', re.IGNORECASE)
        for row in range(2, min(10, claims_ws.max_row)): # Sample first few rows
            g_val = str(claims_ws[f'G{row}'].value)
            h_val = str(claims_ws[f'H{row}'].value)
            if lookup_pattern.search(g_val) and lookup_pattern.search(h_val):
                has_lookups = True
                break
                
        if has_lookups:
            score += 20
            feedback_parts.append("Lookups: Valid (20/20)")
        else:
            feedback_parts.append("Lookups: Missing/Invalid formulas (0/20)")

        # --- Check 2: Logic Formulas (MIN or IF) (20 pts) ---
        has_logic = False
        logic_pattern = re.compile(r'(MIN|IF)', re.IGNORECASE)
        for row in range(2, min(10, claims_ws.max_row)):
            i_val = str(claims_ws[f'I{row}'].value)
            j_val = str(claims_ws[f'J{row}'].value)
            if logic_pattern.search(i_val) or logic_pattern.search(j_val):
                has_logic = True
                break
                
        if has_logic:
            score += 20
            feedback_parts.append("Capping Logic: Valid (20/20)")
        else:
            feedback_parts.append("Capping Logic: Missing MIN/IF formulas (0/20)")
            
        # --- Check 3: Mathematical Summaries (15 pts) ---
        has_math = False
        math_pattern = re.compile(r'(\+|-|SUM)', re.IGNORECASE)
        for row in range(2, min(10, claims_ws.max_row)):
            k_val = str(claims_ws[f'K{row}'].value)
            l_val = str(claims_ws[f'L{row}'].value)
            if math_pattern.search(k_val) and math_pattern.search(l_val):
                has_math = True
                break
                
        if has_math:
            score += 15
            feedback_parts.append("Totals Math: Valid (15/15)")
        else:
            feedback_parts.append("Totals Math: Missing formulas (0/15)")

        # --- Check 4: Currency Formatting (10 pts) ---
        # Look for currency formatting strings ($ or #,##0)
        has_currency = False
        format_str = str(claims_ws['E2'].number_format) + str(claims_ws['L2'].number_format)
        if '$' in format_str or '0.00' in format_str or '##0' in format_str:
            has_currency = True
            score += 10
            feedback_parts.append("Currency format: Found (10/10)")
        else:
            feedback_parts.append("Currency format: Not applied (0/10)")

        # --- Check 5: Summary Sheet Aggregations (15 pts) ---
        has_summary = False
        summary_ws = None
        for s in wb.sheetnames:
            if s.lower() == "summary":
                summary_ws = wb[s]
                break
                
        if summary_ws:
            b1_val = str(summary_ws['B1'].value).upper()
            b2_val = str(summary_ws['B2'].value).upper()
            # Must refer back to the claims sheet or contain SUM function
            if 'SUM' in b1_val or 'CLAIMS' in b1_val or 'SUM' in b2_val:
                has_summary = True
                score += 15
                feedback_parts.append("Summary Sheet: Configured (15/15)")
            else:
                feedback_parts.append("Summary Sheet: Formulas missing in B1/B2 (0/15)")
        else:
            feedback_parts.append("Summary Sheet: Missing (0/15)")

    except Exception as e:
        logger.error(f"Error during spreadsheet inspection: {e}")
        feedback_parts.append("Spreadsheet parsing error.")
    finally:
        cleanup_verification_temp(temp_dir)

    # --- Check 6: VLM Verification for Conditional Formatting & Completeness (20 pts) ---
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """
        You are verifying a completed spreadsheet task. Look at the provided screenshots of WPS Spreadsheet.
        Task requirements included:
        1. Calculating columns for Reimbursable amounts and Overages.
        2. Adding Conditional Formatting to the 'Overage' column (highlighting numbers > 0, usually in red).
        3. A fully populated table.
        
        Respond ONLY with a JSON object:
        {
            "spreadsheet_populated": true/false,
            "conditional_formatting_visible": true/false
        }
        """
        
        vlm_result = query_vlm(images=frames + [final], prompt=prompt)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("spreadsheet_populated", False):
                vlm_score += 10
            if parsed.get("conditional_formatting_visible", False):
                vlm_score += 10
                
            score += vlm_score
            feedback_parts.append(f"VLM Visual Check: {vlm_score}/20")
        else:
            feedback_parts.append("VLM Visual Check: Failed to execute")

    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }