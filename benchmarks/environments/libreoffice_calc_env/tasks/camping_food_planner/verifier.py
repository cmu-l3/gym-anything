#!/usr/bin/env python3
"""
Verifier for Camping Food Planner task
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path since verification runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_camping_food_planner(traj, env_info, task_info):
    """
    Verify camping food planner task completion.
    
    Checks:
    1. Quantity formulas present (not hard-coded values)
    2. Sample calculations correct (Rice, Chicken, Pasta)
    3. Safety factor (1.1) applied in formulas
    4. Cost per person breakdown exists and sums appropriately
    5. Shopping list created with items
    6. Dietary restrictions honored (different counts for restricted items)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/camping_food_plan.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheets = list(workbook.get('sheets', {}).keys())
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheets[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Helper function to check if cell has formula
        def has_formula(cell_ref):
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            return formula is not None and formula.strip() != ""
        
        # Helper function to check if formula contains required pattern
        def formula_contains(cell_ref, pattern):
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            if not formula:
                return False
            return pattern.upper() in formula.upper()
        
        # Criterion 1: Quantity formulas present (not hard-coded)
        # Check cells F17-F24 (Total Quantity column for 8 food items)
        quantity_cells = [f"F{i}" for i in range(17, 25)]
        formulas_present = 0
        for cell in quantity_cells:
            if has_formula(cell):
                formulas_present += 1
        
        if formulas_present >= 6:  # At least 6 out of 8 items have formulas
            criteria_passed += 1
            feedback_parts.append(f"✅ Quantity formulas present ({formulas_present}/8 items)")
        else:
            feedback_parts.append(f"❌ Insufficient quantity formulas ({formulas_present}/8 items, need 6+)")
        
        # Criterion 2: Sample calculations correct
        # Rice (F17): 7 × 0.5 × 5 × 1.1 = 19.25
        # Chicken (F19): 4 × 0.4 × 5 × 1.1 = 8.8
        # Pasta (F18): 5 × 0.3 × 5 × 1.1 = 8.25
        
        expected_values = {
            'F17': (18.5, 20.0, "Rice"),      # 7 × 0.5 × 5 × 1.1 = 19.25
            'F19': (8.0, 9.5, "Chicken"),     # 4 × 0.4 × 5 × 1.1 = 8.8
            'F18': (7.5, 9.0, "Pasta")        # 5 × 0.3 × 5 × 1.1 = 8.25
        }
        
        calculations_correct = 0
        for cell_ref, (min_val, max_val, item_name) in expected_values.items():
            value = get_cell_value(workbook, sheet_name, cell_ref)
            try:
                num_value = float(value) if value is not None else 0
                if min_val <= num_value <= max_val:
                    calculations_correct += 1
                else:
                    logger.info(f"{item_name} calculation: expected {min_val}-{max_val}, got {num_value}")
            except (ValueError, TypeError):
                logger.info(f"{item_name} calculation: invalid value {value}")
        
        if calculations_correct >= 2:  # At least 2 out of 3 sample calculations correct
            criteria_passed += 1
            feedback_parts.append(f"✅ Sample calculations correct ({calculations_correct}/3)")
        else:
            feedback_parts.append(f"❌ Sample calculations incorrect ({calculations_correct}/3, need 2+)")
        
        # Criterion 3: Safety factor (1.1) applied
        # Check if at least 3 quantity formulas contain "1.1" or "*1.1" or "* 1.1"
        safety_factor_count = 0
        for cell in quantity_cells[:6]:  # Check first 6 items
            formula = get_cell_formula(workbook, sheet_name, cell)
            if formula and ('1.1' in formula or '1,1' in formula):  # Some locales use comma
                safety_factor_count += 1
        
        if safety_factor_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Safety factor applied ({safety_factor_count} formulas contain 1.1)")
        else:
            feedback_parts.append(f"❌ Safety factor missing ({safety_factor_count} formulas contain 1.1, need 3+)")
        
        # Criterion 4: Cost per person breakdown exists
        # Check rows 40-46 (Name and Amount columns)
        cost_per_person_exists = False
        cost_entries = 0
        
        for i in range(40, 47):  # Check 7 rows for 7 participants
            name_cell = get_cell_value(workbook, sheet_name, f"A{i}")
            cost_cell = get_cell_value(workbook, sheet_name, f"B{i}")
            
            if name_cell and cost_cell:
                try:
                    float(cost_cell)
                    cost_entries += 1
                except (ValueError, TypeError):
                    pass
        
        if cost_entries >= 5:  # At least 5 people have cost entries
            criteria_passed += 1
            cost_per_person_exists = True
            feedback_parts.append(f"✅ Cost per person breakdown exists ({cost_entries}/7 entries)")
        else:
            feedback_parts.append(f"❌ Cost per person incomplete ({cost_entries}/7 entries, need 5+)")
        
        # Criterion 5: Shopping list created
        # Check rows 29-36 for shopping list entries
        shopping_list_items = 0
        
        for i in range(29, 37):  # Check 8 rows for 8 food items
            item_cell = get_cell_value(workbook, sheet_name, f"A{i}")
            qty_cell = get_cell_value(workbook, sheet_name, f"B{i}")
            
            if item_cell and qty_cell:
                shopping_list_items += 1
        
        if shopping_list_items >= 5:  # At least 5 items in shopping list
            criteria_passed += 1
            feedback_parts.append(f"✅ Shopping list created ({shopping_list_items}/8 items)")
        else:
            feedback_parts.append(f"❌ Shopping list incomplete ({shopping_list_items}/8 items, need 5+)")
        
        # Criterion 6: Dietary restrictions honored
        # Check that Chicken (row 19) uses count ≤ 5 (not all 7 people)
        # Check that Pasta (row 18) uses count ≤ 6 (excluding gluten-free)
        
        dietary_correct = False
        
        # Check Chicken eaters count (E19) - should be 4 or similar (not 7)
        chicken_eaters = get_cell_value(workbook, sheet_name, 'E19')
        pasta_eaters = get_cell_value(workbook, sheet_name, 'E18')
        
        chicken_ok = False
        pasta_ok = False
        
        try:
            chicken_count = float(chicken_eaters) if chicken_eaters else 7
            if chicken_count <= 5:  # Vegetarians excluded (3 people), so max 4-5
                chicken_ok = True
        except (ValueError, TypeError):
            pass
        
        try:
            pasta_count = float(pasta_eaters) if pasta_eaters else 7
            if pasta_count <= 6:  # Gluten-free excluded (2 people), so max 5-6
                pasta_ok = True
        except (ValueError, TypeError):
            pass
        
        # Alternative: check if calculations result in different quantities
        # (implying different participant counts were used)
        rice_qty = get_cell_value(workbook, sheet_name, 'F17')
        chicken_qty = get_cell_value(workbook, sheet_name, 'F19')
        
        try:
            rice_val = float(rice_qty) if rice_qty else 0
            chicken_val = float(chicken_qty) if chicken_qty else 0
            
            # If chicken quantity is notably less than rice (accounting for different servings)
            # Rice: 7 × 0.5 = 3.5 person-servings, Chicken: 4 × 0.4 = 1.6 person-servings
            # This suggests different counts were used
            if chicken_val > 0 and rice_val > 0:
                ratio = chicken_val / rice_val
                if 0.3 < ratio < 0.7:  # Reasonable range suggesting different counts
                    dietary_correct = True
        except (ValueError, TypeError):
            pass
        
        if chicken_ok or pasta_ok or dietary_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Dietary restrictions appear to be honored")
        else:
            # Don't fail too harshly on this - it's a complex criterion
            feedback_parts.append("⚠️ Dietary restrictions handling unclear")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 5/6 criteria (80%)
        
        # Add summary
        if passed:
            feedback_parts.insert(0, "🎉 Camping food planner completed successfully!")
        else:
            feedback_parts.insert(0, "❌ Camping food planner incomplete")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "formulas_present": formulas_present >= 6,
                "calculations_correct": calculations_correct >= 2,
                "safety_factor": safety_factor_count >= 3,
                "cost_per_person": cost_per_person_exists,
                "shopping_list": shopping_list_items >= 5,
                "dietary_restrictions": chicken_ok or pasta_ok or dietary_correct
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }

    finally:
        if temp_dir:
            cleanup_verification_temp(temp_dir)
