#!/usr/bin/env python3
"""
Verifier for Diabetic Patient Nutrition Analysis task.

Evaluates the agent's ability to cross-reference the food diary with USDA nutrients,
calculate daily/meal totals, identify ADA target violations, and format professionally.
Uses ground truth file exported natively by the setup task inside the container.
"""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_all_text(wb):
    all_text = []
    for sheet_name in wb.sheetnames:
        sheet = wb[sheet_name]
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 500),
                                    max_col=min(sheet.max_column, 50)):
            for cell in row:
                if cell.value is not None:
                    all_text.append(str(cell.value).lower())
    return " ".join(all_text)

def extract_all_numbers(wb):
    numbers = []
    for sn in wb.sheetnames:
        sheet = wb[sn]
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 500),
                                    max_col=min(sheet.max_column, 50)):
            for cell in row:
                if isinstance(cell.value, (int, float)):
                    numbers.append(float(cell.value))
    return numbers

def is_number_close_to_any(target, num_list, tol=5.0):
    for n in num_list:
        if abs(target - n) <= tol:
            return True
    return False

def verify_nutrition_analysis(traj, env_info, task_info):
    """
    Verify the nutrition analysis workbook.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/nutrition_analysis.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_nutrition_')

    try:
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Wrong-target gate: Failed to load nutrition_analysis.xlsx: {error}"
            }

        feedback_parts = []
        score = 0.0

        all_text = extract_all_text(wb)
        all_numbers = extract_all_numbers(wb)
        num_sheets = len(wb.sheetnames)

        # Count total filled cells
        total_cells = 0
        for sn in wb.sheetnames:
            sheet = wb[sn]
            for row in sheet.iter_rows(max_row=min(sheet.max_row, 500), max_col=min(sheet.max_column, 50)):
                for cell in row:
                    if cell.value is not None:
                        total_cells += 1

        if total_cells < 20:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Wrong-target gate: File has insufficient content"
            }

        # Retrieve ground truth calculated dynamically during setup_task.sh
        gt_temp = os.path.join(temp_dir, "gt.json")
        try:
            copy_from_env("/tmp/nutrition_ground_truth.json", gt_temp)
            with open(gt_temp, "r") as f:
                gt = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load ground truth: {e}")
            gt = {"daily_cals": [], "weekly_cals": 0, "high_carb_meals": []}

        # CHECK 1: Daily Calorie Totals (2.0 pts)
        daily_cals = gt.get("daily_cals", [])
        found_cals = sum(1 for c in daily_cals if is_number_close_to_any(c, all_numbers, 2.0))
        if found_cals >= 5:
            score += 2.0
            feedback_parts.append(f"Daily calorie totals found ({found_cals}/7 days)")
        elif found_cals >= 3:
            score += 1.0
            feedback_parts.append(f"Some daily calorie totals found ({found_cals}/7 days)")
        else:
            feedback_parts.append("Daily calorie totals missing or incorrect")

        # CHECK 2: Macronutrient breakdown (2.0 pts)
        macro_terms = ["protein", "carb", "fat", "fiber", "sodium"]
        found_macros = sum(1 for m in macro_terms if m in all_text)
        if found_macros >= 4:
            score += 2.0
            feedback_parts.append("Macronutrient breakdown present")
        elif found_macros >= 2:
            score += 1.0
            feedback_parts.append("Partial macronutrient breakdown")
        else:
            feedback_parts.append("Macronutrient breakdown missing")

        # CHECK 3: Meal-level carb threshold flagging (1.5 pts)
        carb_flag_terms = ["exceed", "> 60", ">60", "high carb", "warning", "flag", "over 60"]
        has_flagging = any(t in all_text for t in carb_flag_terms)
        
        high_carb_vals = [m["carbs"] for m in gt.get("high_carb_meals", [])]
        found_hc_vals = sum(1 for v in high_carb_vals if is_number_close_to_any(v, all_numbers, 1.0))
        
        if has_flagging and found_hc_vals >= 2:
            score += 1.5
            feedback_parts.append("Meal-level carb flagging present")
        elif has_flagging or found_hc_vals >= 2:
            score += 0.75
            feedback_parts.append("Partial meal-level carb analysis")
        else:
            feedback_parts.append("Meal-level carb flagging missing")

        # CHECK 4: ADA target comparison (1.5 pts)
        ada_targets = [1800, 2200, 2300, 200, 275, 70, 25, 60]
        found_targets = sum(1 for t in ada_targets if is_number_close_to_any(t, all_numbers, 0.1) or str(t) in all_text)
        
        target_terms = ["target", "goal", "ada", "guideline", "limit"]
        has_target_terms = any(t in all_text for t in target_terms)

        if found_targets >= 4 and has_target_terms:
            score += 1.5
            feedback_parts.append("ADA target comparison present")
        elif found_targets >= 2:
            score += 0.75
            feedback_parts.append("Partial ADA target comparison")
        else:
            feedback_parts.append("ADA target comparison missing")

        # CHECK 5: Weekly summary statistics (1.5 pts)
        summary_terms = ["average", "mean", "min", "max", "weekly", "total"]
        has_summary_terms = sum(1 for t in summary_terms if t in all_text) >= 2
        
        weekly_cals = gt.get("weekly_cals", 0)
        has_weekly_cals = is_number_close_to_any(weekly_cals, all_numbers, 10.0)

        if has_summary_terms and has_weekly_cals:
            score += 1.5
            feedback_parts.append("Weekly summary statistics present")
        elif has_summary_terms or has_weekly_cals:
            score += 0.75
            feedback_parts.append("Partial weekly summary")
        else:
            feedback_parts.append("Weekly summary missing")

        # CHECK 6: Professional structure (1.5 pts)
        if num_sheets >= 3:
            score += 1.5
            feedback_parts.append(f"Professional multi-sheet structure ({num_sheets} sheets)")
        elif num_sheets >= 2:
            score += 0.75
            feedback_parts.append(f"Basic multi-sheet structure ({num_sheets} sheets)")
        else:
            feedback_parts.append("Single sheet structure")

        # Normalize score to 10.0 points
        passed = score >= 5.0

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    except Exception as e:
        logger.error(f"Error verifying nutrition analysis: {e}")
        return {"passed": False, "score": 0.0, "feedback": f"Error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)