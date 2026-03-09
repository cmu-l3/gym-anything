#!/usr/bin/env python3
"""
Verifier for Food Reintroduction Protocol task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_data_start_row(sheet, max_search_rows=50):
    """
    Find the row where the actual data table starts (header row with Period, Food_Introduced, etc.)
    Returns the row number (1-indexed) or None if not found
    """
    for row_idx in range(1, max_search_rows + 1):
        cell_val = sheet.cell(row=row_idx, column=1).value
        if cell_val and isinstance(cell_val, str):
            # Check if this looks like a header row
            if 'period' in cell_val.lower() or (
                'date' in cell_val.lower() and 
                sheet.cell(row=row_idx, column=2).value and 
                'food' in str(sheet.cell(row=row_idx, column=2).value).lower()
            ):
                return row_idx
    return None


def find_summary_start_row(sheet, data_start_row, max_data_rows=20):
    """
    Find the row where the summary section starts
    Returns the row number (1-indexed) or None if not found
    """
    search_start = data_start_row + 1 if data_start_row else 1
    search_end = min(search_start + max_data_rows + 10, sheet.max_row + 1)
    
    for row_idx in range(search_start, search_end):
        cell_val = sheet.cell(row=row_idx, column=1).value
        if cell_val and isinstance(cell_val, str):
            if 'summary' in cell_val.lower():
                return row_idx
    return None


def find_row_by_food(sheet, food_keyword, data_start_row, max_rows=20):
    """
    Find the row containing a specific food in column B (Food_Introduced)
    Returns row number or None
    """
    search_start = data_start_row + 1 if data_start_row else 1
    search_end = min(search_start + max_rows, sheet.max_row + 1)
    
    for row_idx in range(search_start, search_end):
        food_val = sheet.cell(row=row_idx, column=2).value
        if food_val and isinstance(food_val, str):
            if food_keyword.lower() in food_val.lower():
                return row_idx
    return None


def verify_food_reintroduction_protocol(traj, env_info, task_info):
    """
    Verify that the food reintroduction analysis spreadsheet was created correctly.

    Checks:
    1. Correct structure (sheet name, columns, data rows)
    2. Accurate data entry (baseline, eggs, dairy, soy values)
    3. Formula correctness (avg severity calculations)
    4. Trigger status categorization
    5. Summary section with formulas
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/reintroduction_analysis.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_reintro_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Check sheet name
        if "Reintroduction_Analysis" not in wb.sheetnames:
            # Try to find any sheet that might have the data
            if len(wb.sheetnames) > 0:
                sheet = wb.active
                feedback = f"⚠️ Sheet not named 'Reintroduction_Analysis' (found: {wb.sheetnames[0]}), using active sheet"
            else:
                return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        else:
            sheet = wb["Reintroduction_Analysis"]
            feedback = ""

        score = 0
        feedback_parts = []
        if feedback:
            feedback_parts.append(feedback)

        # Find where the data table starts
        data_start_row = find_data_start_row(sheet)
        if not data_start_row:
            return {
                "passed": False, 
                "score": 10, 
                "feedback": "❌ Could not find data table header row (Period, Food_Introduced, etc.)"
            }

        feedback_parts.append(f"✅ Found data table starting at row {data_start_row}")
        score += 5

        # Criterion 1: Check structure (20 points)
        # Should have at least 7 columns and at least 10 data rows (header + 9 food periods)
        min_expected_rows = data_start_row + 10  # header + 9 data rows minimum
        
        if sheet.max_column >= 7:
            score += 8
            feedback_parts.append(f"✅ Structure: {sheet.max_column} columns (expected ≥7)")
        else:
            feedback_parts.append(f"❌ Structure: only {sheet.max_column} columns (expected ≥7)")

        if sheet.max_row >= min_expected_rows:
            score += 7
            feedback_parts.append(f"✅ Structure: {sheet.max_row} rows (expected ≥{min_expected_rows})")
        else:
            feedback_parts.append(f"⚠️ Structure: only {sheet.max_row} rows (expected ≥{min_expected_rows})")
            score += 3

        # Criterion 2: Check data accuracy for key foods (25 points)
        # Expected values from the source data:
        # Baseline: Skin=3, Digestive=2, Energy=8
        # Eggs: Skin=7, Digestive=6, Energy=5
        # Dairy: Skin=8, Digestive=8, Energy=4
        # Soy: Skin=6, Digestive=7, Energy=5
        
        def check_food_data(food_name, expected_skin, expected_digestive, expected_energy, points):
            """Helper to check data for a specific food"""
            row = find_row_by_food(sheet, food_name, data_start_row)
            if not row:
                feedback_parts.append(f"⚠️ {food_name} data not found")
                return 0
            
            # Columns: A=Period, B=Food, C=Skin, D=Digestive, E=Energy
            skin = sheet.cell(row=row, column=3).value
            digestive = sheet.cell(row=row, column=4).value
            energy = sheet.cell(row=row, column=5).value
            
            if skin == expected_skin and digestive == expected_digestive and energy == expected_energy:
                feedback_parts.append(f"✅ {food_name} data correct: Skin={skin}, Digestive={digestive}, Energy={energy}")
                return points
            else:
                feedback_parts.append(
                    f"❌ {food_name} data incorrect: got ({skin}, {digestive}, {energy}), "
                    f"expected ({expected_skin}, {expected_digestive}, {expected_energy})"
                )
                # Partial credit if some values are correct
                correct_count = sum([
                    skin == expected_skin,
                    digestive == expected_digestive,
                    energy == expected_energy
                ])
                return int(points * correct_count / 3)
        
        score += check_food_data("baseline", 3, 2, 8, 7)
        score += check_food_data("eggs", 7, 6, 5, 6)
        score += check_food_data("dairy", 8, 8, 4, 6)
        score += check_food_data("soy", 6, 7, 5, 6)

        # Criterion 3: Check formula calculations (30 points)
        # Formula: (Skin + Digestive + (10 - Energy)) / 3
        # Expected values:
        # Baseline: (3 + 2 + (10-8)) / 3 = 2.33
        # Eggs: (7 + 6 + (10-5)) / 3 = 6.0
        # Dairy: (8 + 8 + (10-4)) / 3 = 7.33
        # Soy: (6 + 7 + (10-5)) / 3 = 6.0
        
        def check_formula_result(food_name, expected_avg, tolerance, points):
            """Helper to check calculated average severity"""
            row = find_row_by_food(sheet, food_name, data_start_row)
            if not row:
                return 0
            
            # Column F should have the calculated average
            avg_val = sheet.cell(row=row, column=6).value
            
            if avg_val is not None and isinstance(avg_val, (int, float)):
                if abs(avg_val - expected_avg) <= tolerance:
                    feedback_parts.append(f"✅ {food_name} avg severity correct: {avg_val:.2f}")
                    return points
                else:
                    feedback_parts.append(
                        f"❌ {food_name} avg severity incorrect: {avg_val:.2f} "
                        f"(expected {expected_avg:.2f})"
                    )
                    return 0
            else:
                feedback_parts.append(f"❌ {food_name} avg severity missing or invalid: {avg_val}")
                return 0
        
        score += check_formula_result("baseline", 2.33, 0.1, 7)
        score += check_formula_result("eggs", 6.0, 0.1, 8)
        score += check_formula_result("dairy", 7.33, 0.1, 8)
        score += check_formula_result("soy", 6.0, 0.1, 7)

        # Criterion 4: Check trigger status categorization (15 points)
        # Should identify Eggs, Dairy, and Soy as triggers (avg > 5)
        
        def check_trigger_status(food_name, expected_status, points):
            """Helper to check trigger status"""
            row = find_row_by_food(sheet, food_name, data_start_row)
            if not row:
                return 0
            
            # Column G should have the trigger status
            status_val = sheet.cell(row=row, column=7).value
            
            if status_val and isinstance(status_val, str):
                status_lower = status_val.lower()
                
                if expected_status == "trigger":
                    if "trigger" in status_lower or "⚠" in status_val:
                        feedback_parts.append(f"✅ {food_name} correctly identified as TRIGGER")
                        return points
                    else:
                        feedback_parts.append(f"❌ {food_name} should be TRIGGER, got: {status_val}")
                        return 0
                elif expected_status == "safe":
                    if "safe" in status_lower or "✓" in status_val:
                        feedback_parts.append(f"✅ {food_name} correctly identified as Safe")
                        return points
                    else:
                        feedback_parts.append(f"⚠️ {food_name} should be Safe, got: {status_val}")
                        return int(points * 0.5)
            else:
                feedback_parts.append(f"❌ {food_name} trigger status missing: {status_val}")
                return 0
        
        score += check_trigger_status("eggs", "trigger", 5)
        score += check_trigger_status("dairy", "trigger", 5)
        score += check_trigger_status("soy", "trigger", 5)

        # Criterion 5: Check summary section (20 points)
        summary_row = find_summary_start_row(sheet, data_start_row)
        
        if summary_row:
            feedback_parts.append(f"✅ Summary section found at row {summary_row}")
            score += 4
            
            # Look for trigger count in the next few rows after SUMMARY
            # It could be in column A (label) and B (value)
            trigger_count_found = False
            safe_count_found = False
            highest_food_found = False
            
            for offset in range(1, 6):  # Check 5 rows after SUMMARY
                check_row = summary_row + offset
                label = sheet.cell(row=check_row, column=1).value
                value = sheet.cell(row=check_row, column=2).value
                
                if label and isinstance(label, str):
                    label_lower = label.lower()
                    
                    # Check for trigger count
                    if "trigger" in label_lower and not trigger_count_found:
                        if value == 3:  # Eggs, Dairy, Soy
                            feedback_parts.append(f"✅ Trigger count correct: {value}")
                            score += 6
                        elif value == 2:  # Partial credit if they missed one
                            feedback_parts.append(f"⚠️ Trigger count close: {value} (expected 3)")
                            score += 3
                        else:
                            feedback_parts.append(f"❌ Trigger count incorrect: {value} (expected 3)")
                            score += 1
                        trigger_count_found = True
                    
                    # Check for safe count
                    if "safe" in label_lower and not safe_count_found:
                        # Safe foods (avg ≤ 3): Baseline (2.33), White Rice (1.33), Chicken (2.33), 
                        # Gluten (3.33 - borderline), Peanuts (2.33), Tree Nuts (2.67)
                        # So around 5-6 safe foods
                        if value >= 4 and value <= 7:
                            feedback_parts.append(f"✅ Safe count reasonable: {value}")
                            score += 4
                        else:
                            feedback_parts.append(f"⚠️ Safe count seems off: {value}")
                            score += 2
                        safe_count_found = True
                    
                    # Check for highest severity food
                    if ("highest" in label_lower or "max" in label_lower) and not highest_food_found:
                        if value and isinstance(value, str):
                            if "dairy" in value.lower() or "milk" in value.lower():
                                feedback_parts.append(f"✅ Highest severity food correct: {value}")
                                score += 6
                            else:
                                feedback_parts.append(f"❌ Highest severity food incorrect: {value} (expected Dairy)")
                                score += 2
                        else:
                            feedback_parts.append(f"❌ Highest severity food missing or invalid: {value}")
                            score += 1
                        highest_food_found = True
            
            if not trigger_count_found:
                feedback_parts.append("❌ Trigger count not found in summary")
            if not safe_count_found:
                feedback_parts.append("⚠️ Safe count not found in summary")
            if not highest_food_found:
                feedback_parts.append("❌ Highest severity food not found in summary")
                
        else:
            feedback_parts.append("❌ Summary section not found")

        # Cap score at 100
        score = min(score, 100)
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
