#!/usr/bin/env python3
"""
Verifier for Recipe Scaler task.
Checks that recipe scaling calculations are correct with proper formulas and rounding.
"""

import sys
import os
import logging
import math

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_scaling_factor(sheet_data, sheet_name):
    """
    Search for scaling factor in the spreadsheet.
    Look for a cell containing value close to 3.125.
    
    Returns: (scaling_factor_value, cell_location)
    """
    expected_factor = 75.0 / 24.0  # 3.125
    
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return None, None
    
    rows = sheets[sheet_name]
    
    for row_idx, row in enumerate(rows[:20]):  # Check first 20 rows
        for col_idx, cell in enumerate(row[:10]):  # Check first 10 columns
            if isinstance(cell, dict):
                value = cell.get('value')
            else:
                value = cell
            
            if value is not None:
                try:
                    numeric_value = float(value)
                    if abs(numeric_value - expected_factor) < 0.05:
                        cell_ref = f"{chr(65 + col_idx)}{row_idx + 1}"
                        logger.info(f"Found potential scaling factor {numeric_value} at {cell_ref}")
                        return numeric_value, cell_ref
                except (ValueError, TypeError):
                    continue
    
    return None, None


def find_column_by_ingredient(sheet_data, sheet_name, ingredient_name):
    """
    Find the row containing a specific ingredient.
    
    Returns: row_index (0-based) or None
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return None
    
    rows = sheets[sheet_name]
    
    for row_idx, row in enumerate(rows[:20]):
        for cell in row[:5]:  # Check first 5 columns
            if isinstance(cell, dict):
                value = cell.get('value')
            else:
                value = cell
            
            if value and isinstance(value, str) and ingredient_name.lower() in value.lower():
                return row_idx
    
    return None


def count_formula_cells(sheet_data, sheet_name):
    """
    Count the number of cells containing formulas.
    
    Returns: count of formula cells
    """
    formula_count = 0
    
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return 0
    
    rows = sheets[sheet_name]
    
    for row in rows[:20]:
        for cell in row[:10]:
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula and formula.startswith('='):
                    formula_count += 1
    
    return formula_count


def get_row_values(sheet_data, sheet_name, row_idx):
    """
    Get all cell values and formulas from a specific row.
    
    Returns: list of (value, formula) tuples
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return []
    
    rows = sheets[sheet_name]
    if row_idx >= len(rows):
        return []
    
    row = rows[row_idx]
    result = []
    
    for cell in row[:10]:  # Check first 10 columns
        if isinstance(cell, dict):
            value = cell.get('value')
            formula = cell.get('formula')
        else:
            value = cell
            formula = None
        
        result.append((value, formula))
    
    return result


def verify_recipe_scaler(traj, env_info, task_info):
    """
    Verify recipe scaling task completion.
    
    Checks:
    1. Scaling factor calculated correctly (3.125)
    2. All 8 ingredients have scaled amounts
    3. Eggs properly rounded to whole number (7)
    4. Formulas present (not hardcoded)
    5. Practical amounts created
    6. Structure valid
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    possible_paths = [
        "/home/ga/Documents/scaled_recipe.ods",
        "/home/ga/Documents/recipe_original.ods",
        "/home/ga/Documents/recipe_original.csv"
    ]
    
    success = False
    file_info = None
    
    for container_path in possible_paths:
        # Determine format from extension
        if container_path.endswith('.ods'):
            formats = ['ods']
        elif container_path.endswith('.csv'):
            formats = ['csv', 'ods']  # CSV might have been saved as ODS
        else:
            formats = ['ods', 'csv']
        
        success, file_info, error = setup_calc_verification(copy_from_env, container_path, formats)
        if success:
            logger.info(f"Successfully loaded file from: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet file. Tried: {', '.join(possible_paths)}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_names = list(sheet_data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: Scaling factor correct
        scaling_factor, factor_cell = find_scaling_factor(sheet_data, sheet_name)
        expected_factor = 75.0 / 24.0  # 3.125
        
        scaling_factor_correct = False
        if scaling_factor is not None and abs(scaling_factor - expected_factor) < 0.01:
            criteria_passed += 1
            scaling_factor_correct = True
            feedback_parts.append(f"✅ Scaling factor correct: {scaling_factor:.3f}")
        else:
            feedback_parts.append(f"❌ Scaling factor not found or incorrect (expected 3.125, found {scaling_factor})")
        
        # Criterion 2: All ingredients scaled (check for 8 ingredients)
        # Look for original values and their scaled counterparts
        ingredient_names = ["Flour", "Sugar", "Butter", "Eggs", "Vanilla", "Baking Soda", "Salt", "Chocolate"]
        ingredients_found = 0
        eggs_row_idx = None
        
        for ingredient in ingredient_names:
            row_idx = find_column_by_ingredient(sheet_data, sheet_name, ingredient)
            if row_idx is not None:
                ingredients_found += 1
                if "egg" in ingredient.lower():
                    eggs_row_idx = row_idx
        
        if ingredients_found >= 7:  # Allow for slight variations in naming
            criteria_passed += 1
            feedback_parts.append(f"✅ All ingredients present ({ingredients_found} found)")
        else:
            feedback_parts.append(f"❌ Missing ingredients (found {ingredients_found}, expected 8)")
        
        # Criterion 3: Eggs properly rounded
        eggs_proper = False
        if eggs_row_idx is not None:
            row_values = get_row_values(sheet_data, sheet_name, eggs_row_idx)
            
            # Original eggs value should be 2
            # Scaled should be around 6.25 (2 * 3.125)
            # Practical should be 7 (rounded up)
            
            for value, formula in row_values:
                if value is not None:
                    try:
                        numeric_value = float(value)
                        # Check if this is the practical rounded value for eggs (should be 7)
                        if numeric_value == 7:
                            eggs_proper = True
                            criteria_passed += 1
                            feedback_parts.append(f"✅ Eggs properly rounded to whole number: {int(numeric_value)}")
                            break
                        elif 6 <= numeric_value <= 8 and numeric_value != 6.25:
                            # Close but check if it's rounded correctly
                            if numeric_value % 1 == 0:  # Is whole number
                                eggs_proper = True
                                criteria_passed += 1
                                feedback_parts.append(f"✅ Eggs rounded to whole number: {int(numeric_value)}")
                                break
                    except (ValueError, TypeError):
                        continue
        
        if not eggs_proper:
            feedback_parts.append("❌ Eggs not properly rounded to whole number (expected 7)")
        
        # Criterion 4: Formulas present
        formula_count = count_formula_cells(sheet_data, sheet_name)
        
        if formula_count >= 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas detected ({formula_count} formula cells)")
        else:
            feedback_parts.append(f"❌ Insufficient formulas (found {formula_count}, expected at least 8)")
        
        # Criterion 5: Practical amounts present (check for rounded values)
        # Look for at least one scaled value that's been rounded
        practical_amounts_found = False
        
        sheets = sheet_data.get('sheets', {})
        if sheet_name in sheets:
            rows = sheets[sheet_name]
            
            for row_idx, row in enumerate(rows[:15]):
                for col_idx, cell in enumerate(row[:10]):
                    if isinstance(cell, dict):
                        value = cell.get('value')
                        formula = cell.get('formula')
                    else:
                        value = cell
                        formula = None
                    
                    # Look for ROUNDUP or ROUND in formulas
                    if formula and ('ROUNDUP' in formula.upper() or 'ROUND' in formula.upper()):
                        practical_amounts_found = True
                        break
                
                if practical_amounts_found:
                    break
        
        if practical_amounts_found:
            criteria_passed += 1
            feedback_parts.append("✅ Practical rounding applied (ROUND/ROUNDUP functions found)")
        else:
            # Alternative: check if there are columns with reasonably rounded values
            # This is a softer check in case they manually rounded but did good work
            feedback_parts.append("⚠️ No rounding functions detected (partial credit may apply)")
            # Give partial credit
            criteria_passed += 0.5
        
        # Criterion 6: Structure valid
        # Check for at least 3 columns beyond the original data (Scaled, Practical, or similar)
        max_columns = 0
        if sheet_name in sheets:
            rows = sheets[sheet_name]
            for row in rows[:15]:
                non_empty = sum(1 for cell in row if (isinstance(cell, dict) and cell.get('value') is not None) or (not isinstance(cell, dict) and cell is not None))
                max_columns = max(max_columns, non_empty)
        
        structure_valid = max_columns >= 5  # Original 3 columns + at least 2 new ones
        
        if structure_valid:
            criteria_passed += 1
            feedback_parts.append(f"✅ Structure valid ({max_columns} columns)")
        else:
            feedback_parts.append(f"❌ Structure incomplete ({max_columns} columns, expected at least 5)")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold is 70%
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Recipe scaled successfully with proper formulas!")
        elif passed:
            feedback_parts.append("✅ Recipe scaling completed")
        else:
            feedback_parts.append("❌ Recipe scaling incomplete or incorrect")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "scaling_factor_correct": scaling_factor_correct,
                "ingredients_scaled": ingredients_found >= 7,
                "eggs_rounded_properly": eggs_proper,
                "formulas_present": formula_count >= 8,
                "practical_amounts": practical_amounts_found,
                "structure_valid": structure_valid
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
        cleanup_verification_temp(file_info.get('temp_dir'))
