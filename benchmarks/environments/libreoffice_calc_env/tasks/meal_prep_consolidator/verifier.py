#!/usr/bin/env python3
"""
Verifier for Meal Prep Ingredient Consolidation task

Checks:
1. Ingredient aggregation (spot checks for common ingredients)
2. Pantry subtraction logic applied
3. Formula-driven (not hard-coded values)
4. Proper filtering (only items with quantity > 0)
5. Reasonable completeness
"""

import sys
import os
import logging
import re

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_ingredient(ingredient):
    """Normalize ingredient name for comparison"""
    if not ingredient:
        return ""
    ingredient = str(ingredient).lower().strip()
    # Remove plural 's' for comparison
    if ingredient.endswith('s') and len(ingredient) > 3:
        ingredient = ingredient[:-1]
    return ingredient


def find_ingredient_in_shopping_list(shopping_data, target_ingredient):
    """
    Find ingredient in shopping list data.
    Returns (found, quantity, row_index) tuple
    """
    target_norm = normalize_ingredient(target_ingredient)
    
    for i, row in enumerate(shopping_data):
        if len(row) < 2:
            continue
        
        cell_value = row[0].get('value') if isinstance(row[0], dict) else row[0]
        if not cell_value:
            continue
        
        ingredient_norm = normalize_ingredient(cell_value)
        
        # Check for match
        if target_norm in ingredient_norm or ingredient_norm in target_norm:
            qty_cell = row[1] if len(row) > 1 else None
            quantity = qty_cell.get('value') if isinstance(qty_cell, dict) else qty_cell
            try:
                quantity = float(quantity) if quantity else 0
            except (ValueError, TypeError):
                quantity = 0
            return True, quantity, i
    
    return False, 0, -1


def check_for_formulas_in_sheet(sheet_data, min_formulas=2):
    """Check if sheet contains formulas (not just values)"""
    formula_count = 0
    
    for row in sheet_data[:30]:  # Check first 30 rows
        for cell in row:
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula:
                    formula_upper = formula.upper()
                    # Look for common aggregation/lookup formulas
                    if any(func in formula_upper for func in ['SUMIF', 'VLOOKUP', 'INDEX', 'MATCH', 'IF', 'MAX']):
                        formula_count += 1
                        logger.info(f"Found formula: {formula}")
                        if formula_count >= min_formulas:
                            return True
    
    return formula_count >= min_formulas


def verify_meal_prep_consolidation(traj, env_info, task_info):
    """
    Verify meal prep ingredient consolidation task.
    
    Returns:
        Dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/meal_prep_shopping.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        sheets = workbook.get('sheets', {})
        
        # Verify required sheets exist
        if 'Shopping List' not in sheets:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Shopping List sheet not found in workbook"
            }
        
        shopping_data = sheets['Shopping List']
        
        criteria_met = 0
        total_criteria = 5
        feedback_parts = []
        
        # ===== Criterion 1: Aggregation Correct (spot check: chicken breast) =====
        # Expected: 2+2 = 4 lbs needed, 0 on hand → Buy 4 lbs
        chicken_found, chicken_qty, _ = find_ingredient_in_shopping_list(shopping_data, "chicken breast")
        
        if chicken_found and 3.5 <= chicken_qty <= 4.5:
            criteria_met += 1
            feedback_parts.append(f"✅ Chicken aggregation correct (~4 lbs)")
        elif chicken_found:
            feedback_parts.append(f"❌ Chicken quantity incorrect (found {chicken_qty}, expected ~4)")
        else:
            feedback_parts.append("❌ Chicken breast not found in shopping list")
        
        # ===== Criterion 2: Pantry Subtraction (spot check: onion) =====
        # Expected: 1+1+2+1+2 = 7 needed, 5 on hand → Buy 2
        onion_found, onion_qty, _ = find_ingredient_in_shopping_list(shopping_data, "onion")
        
        if onion_found and 1.5 <= onion_qty <= 2.5:
            criteria_met += 1
            feedback_parts.append(f"✅ Onion pantry subtraction correct (~2 needed)")
        elif onion_found:
            feedback_parts.append(f"⚠️ Onion quantity unexpected (found {onion_qty}, expected ~2)")
            # Partial credit if at least found
            criteria_met += 0.3
        else:
            feedback_parts.append("❌ Onion not found (or incorrectly excluded)")
        
        # ===== Criterion 3: Formula-Driven =====
        has_formulas = check_for_formulas_in_sheet(shopping_data, min_formulas=2)
        
        if has_formulas:
            criteria_met += 1
            feedback_parts.append("✅ Formula-driven (SUMIF/VLOOKUP/IF detected)")
        else:
            feedback_parts.append("❌ No formulas detected (values appear hard-coded)")
        
        # ===== Criterion 4: Proper Filtering (olive oil should NOT be in list) =====
        # Expected: 4 tbsp needed, 4 on hand → Buy 0 (should be filtered out)
        olive_found, olive_qty, _ = find_ingredient_in_shopping_list(shopping_data, "olive oil")
        
        if not olive_found:
            criteria_met += 1
            feedback_parts.append("✅ Properly filtered (olive oil not in list, already stocked)")
        elif olive_qty == 0:
            # Present but with 0 quantity - acceptable
            criteria_met += 0.7
            feedback_parts.append("⚠️ Olive oil present but with 0 qty (acceptable)")
        else:
            feedback_parts.append(f"❌ Olive oil incorrectly included (qty: {olive_qty}, should be 0)")
        
        # ===== Criterion 5: Completeness =====
        # Count non-empty rows in shopping list (excluding header)
        item_count = 0
        for i, row in enumerate(shopping_data):
            if i == 0:  # Skip header
                continue
            if len(row) >= 1:
                cell_value = row[0].get('value') if isinstance(row[0], dict) else row[0]
                if cell_value and str(cell_value).strip():
                    item_count += 1
        
        # Expected: ~10-15 items (out of ~20 unique ingredients, some are fully stocked)
        # Unique ingredients in recipes: chicken breast, olive oil, onion, garlic, bell pepper,
        # pasta, black beans, rice, eggs, cheese, carrots, celery, vegetable broth
        # That's ~13 unique. With pantry (olive oil, onion, garlic, salt, pepper, rice partially covered),
        # expect ~8-12 items to buy
        if 6 <= item_count <= 15:
            criteria_met += 1
            feedback_parts.append(f"✅ Reasonable coverage ({item_count} items in shopping list)")
        else:
            feedback_parts.append(f"⚠️ Shopping list length unexpected ({item_count} items, expected 6-15)")
        
        # ===== Additional spot check: garlic (should be in list) =====
        # Expected: 2+2+2 = 6 cloves needed, 1 on hand → Buy 5 cloves
        garlic_found, garlic_qty, _ = find_ingredient_in_shopping_list(shopping_data, "garlic")
        
        if garlic_found and 4 <= garlic_qty <= 6:
            logger.info(f"✅ Bonus: Garlic calculation correct (~5 cloves)")
        elif garlic_found:
            logger.info(f"Garlic found with qty {garlic_qty} (expected ~5)")
        else:
            logger.info("Garlic not found in shopping list")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need 4/5 criteria (allowing some partial credit)
        
        # Summary feedback
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent meal prep consolidation!")
        elif passed:
            feedback_parts.append("✅ Meal prep task completed")
        else:
            feedback_parts.append("❌ Consolidation incomplete or incorrect")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "aggregation_correct": chicken_found and 3.5 <= chicken_qty <= 4.5,
                "pantry_subtracted": onion_found and 1.5 <= onion_qty <= 2.5,
                "formula_driven": has_formulas,
                "filtered_properly": not olive_found or olive_qty == 0,
                "reasonable_completeness": 6 <= item_count <= 15
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
