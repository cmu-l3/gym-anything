#!/usr/bin/env python3
"""Verifier for farm_soil_nutrient_analysis task."""

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

def verify_farm_soil(traj, env_info, task_info):
    """Verify farm soil nutrient analysis was completed correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "soil_test_results.xlsx not found."}

    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/soil_test_results.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open file: {error}"}

    try:
        feedback_parts = []
        score = 0
        
        # Criterion 1: Anti-gaming / Action verification (10 pts)
        if result.get("file_modified"):
            score += 10
            feedback_parts.append("File saved")
        else:
            feedback_parts.append("File NOT modified")

        sheets = wb.sheetnames
        
        if 'Soil_Data' not in sheets:
            return {"passed": False, "score": score, "feedback": "Soil_Data sheet missing."}
            
        soil_ws = wb['Soil_Data']
        
        # Safe value extraction
        def get_f(cell):
            val = soil_ws[cell].value
            return str(val).upper() if val else ""

        target_n_f = get_f('H2')
        deficit_n_f = get_f('K2')
        lime_f = get_f('N2')
        total_n_f = get_f('O2')

        # Criterion 2: Lookups used for Targets (20 pts)
        if target_n_f.startswith('=') and any(f in target_n_f for f in ['VLOOKUP', 'INDEX', 'MATCH', 'XLOOKUP']):
            score += 20
            feedback_parts.append("Lookup formulas used")
        else:
            feedback_parts.append(f"Lookup formulas missing (found: {target_n_f})")

        # Criterion 3: Deficits use MAX/IF logic (10 pts)
        if deficit_n_f.startswith('=') and any(f in deficit_n_f for f in ['MAX', 'IF']):
            score += 10
            feedback_parts.append("Deficit logic correct")
        else:
            feedback_parts.append(f"Deficit logic missing (found: {deficit_n_f})")
            
        # Criterion 4: Lime IF logic (10 pts)
        if lime_f.startswith('=') and 'IF' in lime_f and '<' in lime_f:
            score += 10
            feedback_parts.append("Lime IF logic correct")
        else:
            feedback_parts.append(f"Lime IF logic missing (found: {lime_f})")

        # Criterion 5: Total Pounds Arithmetic (15 pts)
        if total_n_f.startswith('=') and '2' in total_n_f and '*' in total_n_f:
            score += 15
            feedback_parts.append("Total pounds arithmetic correct")
        else:
            feedback_parts.append(f"Total pounds arithmetic missing (found: {total_n_f})")

        # Criterion 6 & 7: Summary Sheet Validation (25 pts total)
        summary_found = False
        for s in sheets:
            if s.lower() == 'summary':
                summary_found = True
                summary_ws = wb[s]
                
                has_sum = False
                has_sumif = False
                for row in summary_ws.iter_rows(max_row=30, max_col=10):
                    for cell in row:
                        if cell.value and isinstance(cell.value, str):
                            val = cell.value.upper()
                            if val.startswith('='):
                                if 'SUMIF' in val:
                                    has_sumif = True
                                    has_sum = True
                                elif 'SUM' in val:
                                    has_sum = True
                                
                if has_sum:
                    score += 10
                    feedback_parts.append("Summary aggregations present")
                else:
                    feedback_parts.append("Summary aggregations missing")
                    
                if has_sumif:
                    score += 15
                    feedback_parts.append("Summary SUMIFs present")
                else:
                    feedback_parts.append("Summary SUMIFs missing")
                break
                
        if not summary_found:
            feedback_parts.append("Summary sheet NOT found")

        # Criterion 8: VLM Visual Verification (10 pts)
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Spreadsheet screenshot. Answer in JSON:
{
    "shows_soil_data_or_summary": true/false,
    "shows_calculated_columns": true/false
}
Does the screenshot show:
1. The farm soil analysis data or the summary sheet?
2. Calculated columns for deficits, totals, or lime requirements (populated with data, not empty)?
""")
        if vlm_result:
            if vlm_result.get("shows_soil_data_or_summary") and vlm_result.get("shows_calculated_columns"):
                score += 10
                feedback_parts.append("VLM visual verification passed")
            else:
                feedback_parts.append("VLM visual verification failed")
        else:
            feedback_parts.append("VLM visual verification unavailable")

        # 75 points represents missing only visual verification or minor rule structure deviations
        passed = score >= 75

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