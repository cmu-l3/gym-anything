#!/usr/bin/env python3
"""
Verifier for Macro Nutrition Tracker task
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


def fuzzy_match_food(cell_text, food_keywords):
    """Check if cell contains any of the food keywords (case-insensitive, fuzzy)"""
    if not cell_text or not isinstance(cell_text, str):
        return False
    cell_lower = cell_text.lower()
    return any(keyword.lower() in cell_lower for keyword in food_keywords)


def is_formula(cell):
    """Check if a cell contains a formula"""
    try:
        # In openpyxl, formulas start with '='
        if hasattr(cell, 'value') and isinstance(cell.value, str) and cell.value.startswith('='):
            return True
        # Check if cell has a formula attribute
        if hasattr(cell, 'data_type') and cell.data_type == 'f':
            return True
        return False
    except:
        return False


def is_reasonable_macro_value(value, macro_type):
    """Check if a macro value is in a reasonable range"""
    if not isinstance(value, (int, float)):
        return False
    
    # Basic sanity checks: values should be positive and not absurdly large
    if value < 0 or value > 500:
        return False
    
    # More specific checks based on macro type
    if macro_type == 'protein' and value > 100:  # Single food item unlikely > 100g protein
        return False
    if macro_type == 'carbs' and value > 150:  # Single food item unlikely > 150g carbs
        return False
    if macro_type == 'fat' and value > 100:  # Single food item unlikely > 100g fat
        return False
    
    return True


def verify_macro_tracker(traj, env_info, task_info):
    """
    Verify that macro nutrition tracker was created correctly.

    Scoring breakdown (100 points):
    - File creation: 15 points
    - Structure (columns): 15 points
    - Food items present (8+ of 11): 20 points
    - Reasonable macro values: 15 points
    - SUM formulas present: 15 points
    - Correct totals: 10 points
    - Targets present: 5 points
    - Differences shown: 5 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/macro_log.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_macro_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Get the active sheet
        sheet = wb.active
        sheet_name = sheet.title

        score = 0
        feedback_parts = []

        # Criterion 1: File creation and basic validity (15 points)
        score += 15
        feedback_parts.append("✅ File created and parseable")

        # Get all data from the sheet
        data = get_sheet_data(wb, sheet_name, max_rows=50, max_cols=10)
        
        if len(data) < 5:
            return {
                "passed": False,
                "score": score,
                "feedback": "❌ Spreadsheet is nearly empty (fewer than 5 rows)"
            }

        # Criterion 2: Check for proper column structure (15 points)
        # Look for headers containing "food", "protein", "carb", "fat"
        header_row = None
        food_col = protein_col = carbs_col = fat_col = None
        
        for row_idx, row in enumerate(data[:5]):  # Check first 5 rows for headers
            row_lower = [str(cell).lower() if cell else "" for cell in row]
            
            # Check if this row has header-like content
            has_food = any("food" in cell or "item" in cell for cell in row_lower)
            has_protein = any("protein" in cell for cell in row_lower)
            has_carbs = any("carb" in cell for cell in row_lower)
            has_fat = any("fat" in cell for cell in row_lower)
            
            if has_food and has_protein and (has_carbs or has_fat):
                header_row = row_idx
                # Find column indices
                for col_idx, cell in enumerate(row_lower):
                    if "food" in cell or "item" in cell:
                        food_col = col_idx
                    if "protein" in cell:
                        protein_col = col_idx
                    if "carb" in cell:
                        carbs_col = col_idx
                    if "fat" in cell:
                        fat_col = col_idx
                break
        
        if header_row is not None and food_col is not None:
            score += 15
            feedback_parts.append(f"✅ Proper column structure found (Food, Protein, Carbs, Fat)")
        else:
            feedback_parts.append("❌ Missing proper column headers")

        # Criterion 3: Check for expected food items (20 points)
        expected_foods = {
            'yogurt': ['yogurt', 'greek'],
            'banana': ['banana'],
            'granola': ['granola'],
            'chicken': ['chicken', 'breast'],
            'rice': ['rice', 'brown'],
            'broccoli': ['broccoli'],
            'shake': ['shake', 'protein shake'],
            'almond': ['almond', 'butter'],
            'salmon': ['salmon'],
            'potato': ['potato', 'sweet'],
            'beans': ['beans', 'green']
        }
        
        foods_found = set()
        food_rows = []
        
        if food_col is not None:
            for row_idx, row in enumerate(data[header_row+1:], start=header_row+1):
                if row_idx >= len(data):
                    break
                cell_value = row[food_col] if food_col < len(row) else None
                
                if cell_value and isinstance(cell_value, str):
                    cell_lower = cell_value.lower()
                    # Skip instruction text and total/target rows
                    if any(skip in cell_lower for skip in ['enter', 'total', 'target', 'difference', '[', ']']):
                        continue
                    
                    for food_name, keywords in expected_foods.items():
                        if any(kw in cell_lower for kw in keywords):
                            foods_found.add(food_name)
                            food_rows.append(row_idx)
                            break
        
        foods_count = len(foods_found)
        if foods_count >= 8:
            score += 20
            feedback_parts.append(f"✅ Found {foods_count}/11 expected foods")
        elif foods_count >= 5:
            partial_score = int((foods_count / 11) * 20)
            score += partial_score
            feedback_parts.append(f"⚠️ Found only {foods_count}/11 expected foods (partial credit)")
        else:
            feedback_parts.append(f"❌ Found only {foods_count}/11 expected foods")

        # Criterion 4: Check for reasonable macro values (15 points)
        reasonable_values = 0
        total_values_checked = 0
        
        if protein_col is not None and food_rows:
            for row_idx in food_rows[:11]:  # Check up to 11 food rows
                if row_idx >= len(data):
                    continue
                row = data[row_idx]
                
                # Check protein
                if protein_col < len(row):
                    protein_val = row[protein_col]
                    if is_reasonable_macro_value(protein_val, 'protein'):
                        reasonable_values += 1
                    total_values_checked += 1
                
                # Check carbs
                if carbs_col is not None and carbs_col < len(row):
                    carbs_val = row[carbs_col]
                    if is_reasonable_macro_value(carbs_val, 'carbs'):
                        reasonable_values += 1
                    total_values_checked += 1
                
                # Check fat
                if fat_col is not None and fat_col < len(row):
                    fat_val = row[fat_col]
                    if is_reasonable_macro_value(fat_val, 'fat'):
                        reasonable_values += 1
                    total_values_checked += 1
        
        if total_values_checked > 0:
            reasonable_ratio = reasonable_values / total_values_checked
            if reasonable_ratio >= 0.7:
                score += 15
                feedback_parts.append(f"✅ Macro values are reasonable ({reasonable_values}/{total_values_checked})")
            elif reasonable_ratio >= 0.5:
                partial_score = int(reasonable_ratio * 15)
                score += partial_score
                feedback_parts.append(f"⚠️ Some macro values seem off ({reasonable_values}/{total_values_checked})")
            else:
                feedback_parts.append(f"❌ Many macro values are unreasonable ({reasonable_values}/{total_values_checked})")
        
        # Criterion 5: Check for SUM formulas (15 points)
        has_formulas = False
        formula_count = 0
        
        # Look for cells with SUM formulas (typically in rows after food items)
        for row in sheet.iter_rows(min_row=header_row+2 if header_row else 2, max_row=50, max_col=10):
            for cell in row:
                if is_formula(cell):
                    cell_val = str(cell.value) if cell.value else ""
                    if 'SUM' in cell_val.upper():
                        formula_count += 1
                        has_formulas = True
        
        if formula_count >= 3:  # Expecting at least 3 SUM formulas (protein, carbs, fat)
            score += 15
            feedback_parts.append(f"✅ Found {formula_count} SUM formulas")
        elif formula_count >= 1:
            partial_score = int((formula_count / 3) * 15)
            score += partial_score
            feedback_parts.append(f"⚠️ Found only {formula_count} SUM formulas (expected 3)")
        else:
            feedback_parts.append("❌ No SUM formulas found (totals should use formulas)")
        
        # Criterion 6: Check if totals are approximately correct (10 points)
        # Expected totals: Protein ~156g, Carbs ~157g, Fat ~49g (with ±15% tolerance)
        expected_totals = {'protein': 156, 'carbs': 157, 'fat': 49}
        tolerance = 0.15  # 15% tolerance
        
        totals_correct = 0
        found_totals = {}
        
        # Look for "total" row
        for row_idx, row in enumerate(data):
            cell_text = str(row[0]).lower() if row and row[0] else ""
            if "total" in cell_text:
                # Extract values from this row
                if protein_col and protein_col < len(row):
                    protein_total = row[protein_col]
                    if isinstance(protein_total, (int, float)):
                        found_totals['protein'] = protein_total
                        if abs(protein_total - expected_totals['protein']) <= expected_totals['protein'] * tolerance:
                            totals_correct += 1
                
                if carbs_col and carbs_col < len(row):
                    carbs_total = row[carbs_col]
                    if isinstance(carbs_total, (int, float)):
                        found_totals['carbs'] = carbs_total
                        if abs(carbs_total - expected_totals['carbs']) <= expected_totals['carbs'] * tolerance:
                            totals_correct += 1
                
                if fat_col and fat_col < len(row):
                    fat_total = row[fat_col]
                    if isinstance(fat_total, (int, float)):
                        found_totals['fat'] = fat_total
                        if abs(fat_total - expected_totals['fat']) <= expected_totals['fat'] * tolerance:
                            totals_correct += 1
                break
        
        if totals_correct >= 2:
            partial_score = int((totals_correct / 3) * 10)
            score += partial_score
            if totals_correct == 3:
                feedback_parts.append(f"✅ All totals approximately correct")
            else:
                feedback_parts.append(f"⚠️ {totals_correct}/3 totals approximately correct")
        elif found_totals:
            feedback_parts.append(f"❌ Totals found but values seem off: {found_totals}")
        else:
            feedback_parts.append("❌ No total row found")
        
        # Criterion 7: Check for target values (5 points)
        has_targets = False
        for row in data:
            cell_text = str(row[0]).lower() if row and row[0] else ""
            if "target" in cell_text or "goal" in cell_text:
                has_targets = True
                # Check if target values are present (150, 200, 60)
                target_values = [cell for cell in row[1:] if isinstance(cell, (int, float))]
                if any(abs(v - 150) <= 5 for v in target_values) or \
                   any(abs(v - 200) <= 5 for v in target_values) or \
                   any(abs(v - 60) <= 5 for v in target_values):
                    score += 5
                    feedback_parts.append("✅ Target values present")
                    break
        
        if not has_targets:
            feedback_parts.append("❌ Target row not found")
        
        # Criterion 8: Check for difference calculation (5 points)
        has_difference = False
        for row in data:
            cell_text = str(row[0]).lower() if row and row[0] else ""
            if "difference" in cell_text or "diff" in cell_text or "over" in cell_text or "under" in cell_text:
                has_difference = True
                score += 5
                feedback_parts.append("✅ Difference row present")
                break
        
        if not has_difference:
            feedback_parts.append("❌ Difference row not found")

        # Determine pass/fail
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