#!/usr/bin/env python3
"""
Verifier for Meal Prep Macro Calculator task.

Checks:
1. Structure complete (columns, rows present)
2. Formulas implemented (VLOOKUP/INDEX, calculations)
3. Protein target met (175-185g)
4. Carbs target met (215-225g)
5. Fats target met (55-65g)
6. Conditional formatting applied
7. Realistic portions (0.5-3.0x)
8. Meal variety (at least 3 different meals)
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Optional

# Use relative path to the utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_meal_plan_structure(sheet_data: Dict, sheet_name: str) -> Optional[Dict]:
    """
    Scan the sheet to find the meal plan structure.
    
    Returns dict with:
    - start_row: First row of meal plan data
    - meal_col: Column index for meal names
    - portion_col: Column index for portion sizes
    - protein_col: Column index for protein values
    - carbs_col: Column index for carbs values
    - fats_col: Column index for fats values
    - cost_col: Column index for costs
    - total_row: Row index where totals are calculated
    """
    rows = sheet_data['sheets'][sheet_name]
    
    # Look for header keywords
    keywords = {
        'meal': ['meal', 'name'],
        'portion': ['portion', 'size', 'serving'],
        'protein': ['protein'],
        'carbs': ['carb', 'carbohydrate'],
        'fats': ['fat'],
        'cost': ['cost', 'price']
    }
    
    structure = {
        'start_row': None,
        'meal_col': None,
        'portion_col': None,
        'protein_col': None,
        'carbs_col': None,
        'fats_col': None,
        'cost_col': None,
        'total_row': None,
        'num_meals': 0
    }
    
    # Scan first 20 rows for headers
    for row_idx in range(min(20, len(rows))):
        row = rows[row_idx]
        row_values = []
        
        for cell in row:
            val = cell.get('value') if isinstance(cell, dict) else cell
            row_values.append(str(val).lower() if val else '')
        
        # Check if this row contains column headers
        found_headers = 0
        for col_idx, cell_val in enumerate(row_values):
            if any(kw in cell_val for kw in keywords['meal']):
                structure['meal_col'] = col_idx
                found_headers += 1
            elif any(kw in cell_val for kw in keywords['portion']):
                structure['portion_col'] = col_idx
                found_headers += 1
            elif any(kw in cell_val for kw in keywords['protein']):
                structure['protein_col'] = col_idx
                found_headers += 1
            elif any(kw in cell_val for kw in keywords['carbs']):
                structure['carbs_col'] = col_idx
                found_headers += 1
            elif any(kw in cell_val for kw in keywords['fats']):
                structure['fats_col'] = col_idx
                found_headers += 1
        
        # If we found at least 4 headers, this is likely our header row
        if found_headers >= 4:
            structure['start_row'] = row_idx + 1
            break
    
    if structure['start_row'] is None:
        return None
    
    # Count meal rows (look for 5 consecutive rows with meal names)
    meal_count = 0
    for offset in range(10):  # Check up to 10 rows after header
        row_idx = structure['start_row'] + offset
        if row_idx >= len(rows):
            break
        
        row = rows[row_idx]
        if structure['meal_col'] is not None and structure['meal_col'] < len(row):
            cell = row[structure['meal_col']]
            val = cell.get('value') if isinstance(cell, dict) else cell
            
            # Check if this looks like a meal name (non-empty string)
            if val and isinstance(val, str) and len(val) > 2:
                meal_count += 1
            else:
                # If we've found meals and hit an empty row, might be totals
                if meal_count > 0:
                    structure['total_row'] = row_idx
                    break
    
    structure['num_meals'] = meal_count
    
    # Verify we have minimum required columns
    if (structure['meal_col'] is not None and 
        structure['protein_col'] is not None and 
        structure['carbs_col'] is not None and 
        structure['fats_col'] is not None):
        return structure
    
    return None


def extract_macro_totals(sheet_data: Dict, sheet_name: str, structure: Dict) -> Tuple[float, float, float]:
    """
    Extract the total macros from the meal plan.
    """
    rows = sheet_data['sheets'][sheet_name]
    
    protein_total = 0.0
    carbs_total = 0.0
    fats_total = 0.0
    
    # Look for totals row or calculate from individual meals
    if structure['total_row'] is not None and structure['total_row'] < len(rows):
        row = rows[structure['total_row']]
        
        if structure['protein_col'] < len(row):
            val = row[structure['protein_col']].get('value') if isinstance(row[structure['protein_col']], dict) else row[structure['protein_col']]
            if val:
                try:
                    protein_total = float(val)
                except (ValueError, TypeError):
                    pass
        
        if structure['carbs_col'] < len(row):
            val = row[structure['carbs_col']].get('value') if isinstance(row[structure['carbs_col']], dict) else row[structure['carbs_col']]
            if val:
                try:
                    carbs_total = float(val)
                except (ValueError, TypeError):
                    pass
        
        if structure['fats_col'] < len(row):
            val = row[structure['fats_col']].get('value') if isinstance(row[structure['fats_col']], dict) else row[structure['fats_col']]
            if val:
                try:
                    fats_total = float(val)
                except (ValueError, TypeError):
                    pass
    
    # If totals row didn't work, sum individual meals
    if protein_total == 0.0:
        for offset in range(structure['num_meals']):
            row_idx = structure['start_row'] + offset
            if row_idx >= len(rows):
                break
            row = rows[row_idx]
            
            for col, total_var in [(structure['protein_col'], 'protein'),
                                    (structure['carbs_col'], 'carbs'),
                                    (structure['fats_col'], 'fats')]:
                if col is not None and col < len(row):
                    val = row[col].get('value') if isinstance(row[col], dict) else row[col]
                    if val:
                        try:
                            if total_var == 'protein':
                                protein_total += float(val)
                            elif total_var == 'carbs':
                                carbs_total += float(val)
                            elif total_var == 'fats':
                                fats_total += float(val)
                        except (ValueError, TypeError):
                            pass
    
    return protein_total, carbs_total, fats_total


def check_formulas_present(sheet_data: Dict, sheet_name: str, structure: Dict) -> Tuple[bool, bool]:
    """
    Check if formulas are used (VLOOKUP/INDEX and calculations).
    
    Returns: (has_lookup_formulas, has_sum_formulas)
    """
    rows = sheet_data['sheets'][sheet_name]
    
    has_lookup = False
    has_sum = False
    
    # Check meal rows for lookup formulas
    for offset in range(min(structure['num_meals'], 5)):
        row_idx = structure['start_row'] + offset
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        
        # Check protein, carbs, fats columns for formulas
        for col in [structure['protein_col'], structure['carbs_col'], structure['fats_col']]:
            if col is not None and col < len(row):
                cell = row[col]
                formula = cell.get('formula') if isinstance(cell, dict) else None
                
                if formula:
                    formula_upper = formula.upper()
                    if 'VLOOKUP' in formula_upper or 'INDEX' in formula_upper or 'MATCH' in formula_upper:
                        has_lookup = True
                    # Also accept multiplication formulas (even without VLOOKUP)
                    if '*' in formula:
                        has_lookup = True
    
    # Check total row for SUM formulas
    if structure['total_row'] is not None and structure['total_row'] < len(rows):
        row = rows[structure['total_row']]
        for col in [structure['protein_col'], structure['carbs_col'], structure['fats_col']]:
            if col is not None and col < len(row):
                cell = row[col]
                formula = cell.get('formula') if isinstance(cell, dict) else None
                
                if formula and 'SUM' in formula.upper():
                    has_sum = True
    
    return has_lookup, has_sum


def extract_portions_and_meals(sheet_data: Dict, sheet_name: str, structure: Dict) -> Tuple[List[float], List[str]]:
    """
    Extract portion sizes and meal names.
    """
    rows = sheet_data['sheets'][sheet_name]
    portions = []
    meals = []
    
    for offset in range(min(structure['num_meals'], 10)):
        row_idx = structure['start_row'] + offset
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        
        # Extract portion size
        if structure['portion_col'] is not None and structure['portion_col'] < len(row):
            val = row[structure['portion_col']].get('value') if isinstance(row[structure['portion_col']], dict) else row[structure['portion_col']]
            if val:
                try:
                    portions.append(float(val))
                except (ValueError, TypeError):
                    portions.append(1.0)  # Default
        
        # Extract meal name
        if structure['meal_col'] is not None and structure['meal_col'] < len(row):
            val = row[structure['meal_col']].get('value') if isinstance(row[structure['meal_col']], dict) else row[structure['meal_col']]
            if val and isinstance(val, str):
                meals.append(val.strip())
    
    return portions, meals


def verify_meal_prep_macros(traj, env_info, task_info):
    """
    Verify meal prep macro calculator task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/meal_prep_plan.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get sheet (could be "Meal Plan" or first sheet)
        sheet_names = list(workbook['sheets'].keys())
        sheet_name = None
        for name in sheet_names:
            if 'meal' in name.lower() or 'plan' in name.lower():
                sheet_name = name
                break
        if sheet_name is None:
            sheet_name = sheet_names[0]

        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}

        # Criterion 1: Structure complete
        structure = find_meal_plan_structure(workbook, sheet_name)
        if structure and structure['num_meals'] >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Structure complete ({structure['num_meals']} meals found)")
            subscores['structure_complete'] = True
        else:
            feedback_parts.append("❌ Meal plan structure incomplete or missing")
            subscores['structure_complete'] = False
            # Return early if structure not found
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # Criterion 2: Formulas implemented
        has_lookup, has_sum = check_formulas_present(workbook, sheet_name, structure)
        if has_lookup or has_sum:  # Accept partial formula usage
            if has_lookup and has_sum:
                criteria_passed += 1
                feedback_parts.append("✅ Formulas implemented (lookup + SUM)")
                subscores['formulas_implemented'] = True
            else:
                criteria_passed += 0.5
                feedback_parts.append("⚠️ Some formulas present (missing lookup or SUM)")
                subscores['formulas_implemented'] = False
        else:
            feedback_parts.append("❌ No formulas detected (values appear hardcoded)")
            subscores['formulas_implemented'] = False

        # Extract macro totals
        protein_total, carbs_total, fats_total = extract_macro_totals(workbook, sheet_name, structure)
        
        logger.info(f"Macro totals: Protein={protein_total}g, Carbs={carbs_total}g, Fats={fats_total}g")

        # Criterion 3: Protein target met (175-185g)
        if 175 <= protein_total <= 185:
            criteria_passed += 1
            feedback_parts.append(f"✅ Protein target met ({protein_total:.1f}g / 180g target)")
            subscores['protein_target'] = True
        elif 170 <= protein_total <= 190:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Protein close to target ({protein_total:.1f}g / 180g target)")
            subscores['protein_target'] = False
        else:
            feedback_parts.append(f"❌ Protein off target ({protein_total:.1f}g / 180g target)")
            subscores['protein_target'] = False

        # Criterion 4: Carbs target met (215-225g)
        if 215 <= carbs_total <= 225:
            criteria_passed += 1
            feedback_parts.append(f"✅ Carbs target met ({carbs_total:.1f}g / 220g target)")
            subscores['carbs_target'] = True
        elif 210 <= carbs_total <= 230:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Carbs close to target ({carbs_total:.1f}g / 220g target)")
            subscores['carbs_target'] = False
        else:
            feedback_parts.append(f"❌ Carbs off target ({carbs_total:.1f}g / 220g target)")
            subscores['carbs_target'] = False

        # Criterion 5: Fats target met (55-65g)
        if 55 <= fats_total <= 65:
            criteria_passed += 1
            feedback_parts.append(f"✅ Fats target met ({fats_total:.1f}g / 60g target)")
            subscores['fats_target'] = True
        elif 52 <= fats_total <= 68:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Fats close to target ({fats_total:.1f}g / 60g target)")
            subscores['fats_target'] = False
        else:
            feedback_parts.append(f"❌ Fats off target ({fats_total:.1f}g / 60g target)")
            subscores['fats_target'] = False

        # Criterion 6: Conditional formatting applied (simplified check)
        # For ODS, checking conditional formatting is complex
        # We'll give credit if we can detect it, but not penalize heavily if we can't
        has_cond_format = check_conditional_formatting(workbook, sheet_name, "A1:Z50")
        if has_cond_format:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
            subscores['conditional_formatting'] = True
        else:
            # Don't heavily penalize - detection is unreliable
            feedback_parts.append("⚠️ Conditional formatting not detected (may be present)")
            subscores['conditional_formatting'] = False

        # Criterion 7: Realistic portions (0.5-3.0x)
        portions, meals = extract_portions_and_meals(workbook, sheet_name, structure)
        realistic_portions = all(0.5 <= p <= 3.0 for p in portions) if portions else False
        if realistic_portions:
            criteria_passed += 1
            avg_portion = sum(portions) / len(portions) if portions else 0
            feedback_parts.append(f"✅ Portions realistic (avg {avg_portion:.2f}x)")
            subscores['realistic_portions'] = True
        elif portions:
            feedback_parts.append(f"❌ Some portions unrealistic: {portions}")
            subscores['realistic_portions'] = False
        else:
            feedback_parts.append("⚠️ Portion sizes not detected")
            subscores['realistic_portions'] = False

        # Criterion 8: Meal variety (at least 3 different meals)
        unique_meals = len(set(meals))
        if unique_meals >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Good meal variety ({unique_meals} different meals)")
            subscores['meal_variety'] = True
        else:
            feedback_parts.append(f"⚠️ Limited variety ({unique_meals} different meals)")
            subscores['meal_variety'] = False

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent meal prep plan!")
        elif passed:
            feedback_parts.append("✅ Meal prep task completed")
        else:
            feedback_parts.append("❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
