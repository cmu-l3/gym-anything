#!/usr/bin/env python3
"""Verifier for Menu Engineering Analysis task."""

import json
import os
import sys
import logging
import tempfile

# Add WPS utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    vlm_verify_screenshot
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_menu_engineering(traj, env_info, task_info):
    """
    Verify the menu engineering analysis.
    Checks for:
    1. Proper file modification (Anti-gaming).
    2. Formulas used for calculations (data_only=False check).
    3. Correct evaluation of Unit_CM, Total_Revenue, Total_CM.
    4. Correct Benchmarks in J2 and K2.
    5. Correct Classification logic (Star, Plowhorse, Puzzle, Dog).
    6. Summary sheet with counts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve evaluated data JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            eval_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read evaluated data: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Validate file exist and modified
    if not eval_data.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "File /home/ga/Documents/menu_sales_data.xlsx not found"}
        
    mtime = eval_data.get("file_mtime", 0)
    start_time = eval_data.get("task_start", 0)
    if mtime < start_time:
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task."}

    # Retrieve workbook to check FORMULAS (data_only=False)
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/menu_sales_data.xlsx", copy_from_env, file_format='xlsx'
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse spreadsheet for formulas: {error}"}

    try:
        feedback = []
        score = 0
        
        # 1. Base Modification (10 points)
        score += 10
        feedback.append("File modified correctly.")
        
        pos_data = eval_data.get("pos_data", [])
        if not pos_data:
            return {"passed": False, "score": score, "feedback": "No data found in POS_Export"}

        ws = wb["POS_Export"]
        
        # 2. Check Financial Columns F, G, H (20 points)
        f_formulas = 0
        calculations_correct = True
        
        total_qty = 0
        total_cm = 0
        count = len(pos_data)
        
        for i, row in enumerate(pos_data):
            row_idx = i + 2
            qty = row.get("qty", 0) or 0
            cost = row.get("cost", 0) or 0
            price = row.get("price", 0) or 0
            
            # Ground truths
            expected_unit_cm = price - cost
            expected_total_rev = qty * price
            expected_total_cm = qty * expected_unit_cm
            
            total_qty += qty
            total_cm += expected_unit_cm
            
            # Check formulas exist in workbook
            f_val = ws.cell(row=row_idx, column=6).value
            if isinstance(f_val, str) and f_val.startswith('='):
                f_formulas += 1
                
            # Check accuracy of evaluated values (tolerance for float precision)
            if abs((row.get("unit_cm") or 0) - expected_unit_cm) > 0.05: calculations_correct = False
            if abs((row.get("total_rev") or 0) - expected_total_rev) > 0.05: calculations_correct = False
            if abs((row.get("total_cm") or 0) - expected_total_cm) > 0.05: calculations_correct = False

        if f_formulas > 0 and calculations_correct:
            score += 20
            feedback.append("Financial calculation formulas applied correctly.")
        else:
            feedback.append(f"Financial calculations missing or incorrect (Formulas used: {f_formulas}/{count}).")

        # 3. Check Benchmarks J2, K2 (15 points)
        expected_avg_qty = total_qty / count if count > 0 else 0
        expected_avg_cm = total_cm / count if count > 0 else 0
        
        j2_val = eval_data.get("j2_value")
        k2_val = eval_data.get("k2_value")
        
        j2_formula = str(ws['J2'].value).upper()
        k2_formula = str(ws['K2'].value).upper()
        
        benchmarks_correct = False
        if j2_val is not None and k2_val is not None:
            if abs(float(j2_val) - expected_avg_qty) < 0.5 and abs(float(k2_val) - expected_avg_cm) < 0.5:
                if 'AVERAGE' in j2_formula and 'AVERAGE' in k2_formula:
                    benchmarks_correct = True
                    
        if benchmarks_correct:
            score += 15
            feedback.append("Benchmark averages calculated correctly.")
        else:
            feedback.append("Benchmarks J2/K2 incorrect or not using AVERAGE formula.")

        # 4. Check Classification Logic Column I (35 points)
        # We check both the logic accuracy and if a formula was used
        logic_correct = True
        i_formulas = 0
        
        gt_counts = {"Star": 0, "Plowhorse": 0, "Puzzle": 0, "Dog": 0}
        
        for i, row in enumerate(pos_data):
            qty = row.get("qty", 0) or 0
            unit_cm = row.get("unit_cm", 0) or 0
            agent_class = str(row.get("classification", "")).strip().lower()
            
            # Determine GT class
            if qty >= expected_avg_qty and unit_cm >= expected_avg_cm:
                gt_class = "star"
            elif qty >= expected_avg_qty and unit_cm < expected_avg_cm:
                gt_class = "plowhorse"
            elif qty < expected_avg_qty and unit_cm >= expected_avg_cm:
                gt_class = "puzzle"
            else:
                gt_class = "dog"
                
            gt_counts[gt_class.capitalize()] += 1
            
            if agent_class != gt_class:
                logic_correct = False
                
            # Check if formula used
            i_val = ws.cell(row=i+2, column=9).value
            if isinstance(i_val, str) and i_val.startswith('='):
                i_formulas += 1
                
        if logic_correct and i_formulas > (count * 0.5):
            score += 35
            feedback.append("Classification logic (IF/AND/IFS) applied correctly.")
        else:
            feedback.append(f"Classification logic failed or hardcoded (Formulas used: {i_formulas}/{count}).")

        # 5. Check Summary Sheet (20 points)
        summary_found = False
        summary_correct = True
        
        summary_data = eval_data.get("summary_data", [])
        if summary_data:
            summary_found = True
            agent_counts = {}
            for row in summary_data:
                # Normalize keys for comparison
                cat = str(row.get("category", "")).strip().capitalize()
                val = row.get("count", 0)
                try:
                    val = int(val) if val is not None else 0
                except:
                    val = 0
                agent_counts[cat] = val
                
            for cat in ["Star", "Plowhorse", "Puzzle", "Dog"]:
                if agent_counts.get(cat, 0) != gt_counts[cat]:
                    summary_correct = False
                    
        if summary_found and summary_correct:
            score += 20
            feedback.append("Summary sheet created with correct counts.")
        elif summary_found:
            feedback.append("Summary sheet exists but counts are incorrect.")
        else:
            feedback.append("Summary sheet missing.")
            
        # Optional: VLM verification for trajectory visual confirmation 
        # (This is extra validation to ensure they actually used the GUI properly, though formulas prove strong compliance)
        vlm_res = vlm_verify_screenshot(env_info, traj, 
            "Look at the spreadsheet. Does it contain a column with words like 'Star', 'Plowhorse', 'Dog', 'Puzzle' and basic financial data?"
        )
        if vlm_res:
            feedback.append("VLM visual verification confirmed.")
        
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)