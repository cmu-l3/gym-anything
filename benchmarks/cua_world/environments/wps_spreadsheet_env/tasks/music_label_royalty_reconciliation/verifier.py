#!/usr/bin/env python3
"""Verifier for music_label_royalty_reconciliation task."""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_column_formulas(sheet, col_idx, expected_keywords):
    """Checks if a column contains formulas with specific keywords."""
    match_count = 0
    # Check top rows of the column for the formula
    for row in range(2, min(sheet.max_row, 20) + 1):
        cell = sheet.cell(row=row, column=col_idx)
        val = str(cell.value).upper()
        if val.startswith('='):
            if any(kw in val for kw in expected_keywords):
                match_count += 1
    return match_count > 0

def verify_royalty_reconciliation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load the execution stats
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            stats = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not stats.get('file_modified_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File was not modified. Did you save your work?"}

    # Load spreadsheet WITH formulas
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/royalty_statement_Q3.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        score = 0
        feedback_parts = []
        sheets = wb.sheetnames

        # CRITERION 1: Sheets Structure (15 pts)
        has_summary = 'Payout_Summary' in sheets
        if has_summary:
            score += 15
            feedback_parts.append("Payout_Summary sheet exists")
        else:
            feedback_parts.append("Payout_Summary sheet NOT found")

        # Inspect Streaming_Data
        stream_ws = wb['Streaming_Data'] if 'Streaming_Data' in sheets else None
        
        # CRITERION 2: Streaming_Data calculations (25 pts)
        has_rate_formula = False
        has_gross_formula = False
        
        if stream_ws:
            # Check Column G (7) for lookups
            has_rate_formula = check_column_formulas(stream_ws, 7, ['VLOOKUP', 'XLOOKUP', 'INDEX', 'LOOKUP'])
            # Check Column H (8) for arithmetic
            has_gross_formula = check_column_formulas(stream_ws, 8, ['*', 'PRODUCT'])
            
            if has_rate_formula:
                score += 15
                feedback_parts.append("Dynamic Rate Lookup found")
            else:
                feedback_parts.append("Dynamic Rate Lookup NOT found in Streaming_Data")
                
            if has_gross_formula:
                score += 10
                feedback_parts.append("Gross Royalty calculation found")
            else:
                feedback_parts.append("Gross Royalty calculation NOT found")

        # CRITERION 3: Payout_Summary Aggregations and Financial Logic (45 pts)
        has_sumif = False
        has_financial_bounds = False
        has_advance_lookup = False
        
        if has_summary:
            sum_ws = wb['Payout_Summary']
            
            # Check Column B (2) for SUMIF
            has_sumif = check_column_formulas(sum_ws, 2, ['SUMIF'])
            if has_sumif:
                score += 15
                feedback_parts.append("SUMIF aggregation found")
            else:
                feedback_parts.append("SUMIF aggregation NOT found")
                
            # Check Column C (3) for Advance Lookups
            has_advance_lookup = check_column_formulas(sum_ws, 3, ['VLOOKUP', 'XLOOKUP', 'INDEX'])
            if has_advance_lookup:
                score += 10
                feedback_parts.append("Advance Lookups found")
                
            # Check Column D (4) and E (5) for Financial Bounds (MAX/IF)
            net_payable_bounds = check_column_formulas(sum_ws, 4, ['MAX', 'IF'])
            remaining_bounds = check_column_formulas(sum_ws, 5, ['MAX', 'IF'])
            
            if net_payable_bounds and remaining_bounds:
                has_financial_bounds = True
                score += 20
                feedback_parts.append("Proper Financial bounds (MAX/IF) applied")
            elif net_payable_bounds or remaining_bounds:
                score += 10
                feedback_parts.append("Partial Financial bounds applied")
            else:
                feedback_parts.append("Financial bounds (no negative payouts) NOT implemented correctly")

        # CRITERION 4: VLM visual/formatting check (15 pts)
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Spreadsheet screenshot showing a Payout Summary or Streaming Data sheet. Answer in JSON:
{
    "has_currency_formatting": true/false,
    "has_structured_payout_table": true/false
}
Does the spreadsheet show:
1. Currency formatting ($ symbols) on financial values?
2. A structured payout table with columns like Artist, Total_Gross_Royalty, Net_Payable?
""")

        if vlm_result is not None:
            if vlm_result.get("has_currency_formatting", False):
                score += 10
                feedback_parts.append("Currency formatting visually confirmed")
            if vlm_result.get("has_structured_payout_table", False):
                score += 5
                feedback_parts.append("Table structure visually confirmed")
        else:
            feedback_parts.append("VLM visual verification unavailable")

        # Final Evaluation
        # Must hit a threshold AND implement the core task (SUMIF + Bounds)
        passed = score >= 75 and has_sumif and has_rate_formula
        
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