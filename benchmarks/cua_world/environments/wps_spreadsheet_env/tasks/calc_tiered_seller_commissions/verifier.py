#!/usr/bin/env python3
"""Verifier for calc_tiered_seller_commissions task."""

import sys
import os
import json
import tempfile
import logging

# Import utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_commissions(traj, env_info, task_info):
    """
    Verify the calculations and formulas for the tiered commission task.
    
    SCORING CRITERIA:
    1. File was modified during task (anti-gaming) (10 pts)
    2. SUMIF formulas present in Total_Sales column (20 pts)
    3. VLOOKUP formulas present in Commission_Rate column (25 pts)
    4. Arithmetic formulas present for Commission_Amount and Net (20 pts)
    5. Grand Total row (47) present with SUM formulas (15 pts)
    6. VLM Verification that Payouts sheet is visually populated (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    target_file = "/home/ga/Documents/seller_commissions.xlsx"
    
    # Check export json for file modification
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not export_result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Target file not found."}

    # Open spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        target_file, copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        score = 0
        feedback_parts = []
        
        # Criterion 1: File Modified
        if export_result.get("file_modified"):
            score += 10
            feedback_parts.append("File modified during task")
        else:
            feedback_parts.append("File NOT modified during task (possible anti-gaming flag)")
        
        if 'Payouts' not in wb.sheetnames:
            return {"passed": False, "score": score, "feedback": "Payouts sheet missing."}
            
        sheet = wb['Payouts']
        
        # Analyze Rows 2-46 for formulas
        sumif_count = 0
        vlookup_count = 0
        multiply_count = 0
        subtract_count = 0
        
        for row in range(2, 47):
            b_val = str(sheet.cell(row=row, column=2).value).upper()
            c_val = str(sheet.cell(row=row, column=3).value).upper()
            d_val = str(sheet.cell(row=row, column=4).value).upper()
            e_val = str(sheet.cell(row=row, column=5).value).upper()
            
            if b_val.startswith('=') and 'SUMIF' in b_val:
                sumif_count += 1
            if c_val.startswith('=') and ('VLOOKUP' in c_val or 'LOOKUP' in c_val or 'INDEX' in c_val):
                vlookup_count += 1
            if d_val.startswith('=') and '*' in d_val:
                multiply_count += 1
            if e_val.startswith('=') and '-' in e_val:
                subtract_count += 1

        # Criterion 2: SUMIF (Max 45)
        if sumif_count >= 40:
            score += 20
            feedback_parts.append("SUMIF formulas correctly applied")
        elif sumif_count > 0:
            score += int(20 * (sumif_count / 45))
            feedback_parts.append(f"SUMIF formulas partially applied ({sumif_count}/45)")
        else:
            feedback_parts.append("SUMIF formulas MISSING")

        # Criterion 3: VLOOKUP (Max 45)
        if vlookup_count >= 40:
            score += 25
            feedback_parts.append("VLOOKUP formulas correctly applied")
        elif vlookup_count > 0:
            score += int(25 * (vlookup_count / 45))
            feedback_parts.append(f"VLOOKUP formulas partially applied ({vlookup_count}/45)")
        else:
            feedback_parts.append("VLOOKUP formulas MISSING")

        # Criterion 4: Arithmetic (Max 45 each)
        if multiply_count >= 40 and subtract_count >= 40:
            score += 20
            feedback_parts.append("Arithmetic payouts formulas correctly applied")
        elif multiply_count > 0 or subtract_count > 0:
            score += 10
            feedback_parts.append("Arithmetic formulas partially applied")
        else:
            feedback_parts.append("Arithmetic formulas MISSING")

        # Criterion 5: Grand Totals (Row 47)
        a47_val = str(sheet.cell(row=47, column=1).value).lower()
        b47_val = str(sheet.cell(row=47, column=2).value).upper()
        d47_val = str(sheet.cell(row=47, column=4).value).upper()
        e47_val = str(sheet.cell(row=47, column=5).value).upper()
        
        totals_found = 0
        if 'total' in a47_val:
            totals_found += 1
        if b47_val.startswith('=') and 'SUM' in b47_val:
            totals_found += 1
        if d47_val.startswith('=') and 'SUM' in d47_val:
            totals_found += 1
        if e47_val.startswith('=') and 'SUM' in e47_val:
            totals_found += 1
            
        if totals_found == 4:
            score += 15
            feedback_parts.append("Grand Total row correctly implemented")
        elif totals_found > 0:
            score += 5
            feedback_parts.append("Grand Total row partially implemented")
        else:
            feedback_parts.append("Grand Total row MISSING")

        # Criterion 6: VLM Verification
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Spreadsheet screenshot. Answer in JSON:
{
    "shows_payouts_sheet": true/false,
    "shows_calculated_numbers": true/false,
    "shows_grand_total_row": true/false
}
Does the spreadsheet currently show:
1. The 'Payouts' sheet as the active tab?
2. Calculated numerical values (like currency/percentages) rather than empty cells or exposed formula text?
3. A Grand Total row at the bottom?
""")
        if vlm_result:
            if vlm_result.get("shows_calculated_numbers", False):
                score += 10
                feedback_parts.append("VLM visual verification passed")
            else:
                feedback_parts.append("VLM visual verification: data not populated properly")
        else:
            feedback_parts.append("VLM visual verification unavailable")

        # Determine pass/fail
        key_criteria = (sumif_count > 0 and vlookup_count > 0 and export_result.get("file_modified"))
        passed = (score >= 70) and key_criteria

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