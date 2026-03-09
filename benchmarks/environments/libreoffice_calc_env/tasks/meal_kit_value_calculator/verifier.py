#!/usr/bin/env python3
"""
Verifier for Meal Kit Value Calculator task.
Checks for per-serving calculations, waste adjustments, averages, subscription fee integration,
cost difference calculations, and proper formatting.
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path for host execution
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_meal_kit_rows(sheet_data):
    """Find row indices that contain meal kit data"""
    meal_kit_rows = []
    for i, row in enumerate(sheet_data):
        if len(row) > 0:
            first_cell = row[0].get('value') if isinstance(row[0], dict) else row[0]
            if first_cell and 'mealkit' in str(first_cell).lower():
                meal_kit_rows.append(i)
    return meal_kit_rows


def find_grocery_rows(sheet_data):
    """Find row indices that contain grocery data"""
    grocery_rows = []
    for i, row in enumerate(sheet_data):
        if len(row) > 0:
            first_cell = row[0].get('value') if isinstance(row[0], dict) else row[0]
            if first_cell and 'grocery' in str(first_cell).lower():
                grocery_rows.append(i)
    return grocery_rows


def find_subscription_fee(sheet_data):
    """Find subscription fee value from data"""
    for row in sheet_data:
        if len(row) > 0:
            first_cell = row[0].get('value') if isinstance(row[0], dict) else row[0]
            if first_cell and 'subscription' in str(first_cell).lower():
                # Try to find the fee in this row
                for cell in row:
                    val = cell.get('value') if isinstance(cell, dict) else cell
                    if val and isinstance(val, (int, float)) and 5 <= val <= 20:
                        return float(val)
    return 9.99  # Default


def check_per_serving_formulas(workbook, sheet_name, meal_rows):
    """Check if per-serving cost formulas exist (Total_Cost / Servings)"""
    sheet_data = workbook['sheets'][sheet_name]
    formulas_found = 0
    
    for row_idx in meal_rows[:3]:  # Check first 3 meals
        if row_idx >= len(sheet_data):
            continue
        row = sheet_data[row_idx]
        
        # Look for formulas in columns F onwards (after the data columns A-E)
        for col_idx in range(5, min(len(row), 12)):
            cell = row[col_idx]
            formula = cell.get('formula') if isinstance(cell, dict) else None
            
            if formula:
                # Check if formula divides total cost by servings
                # Should reference columns D and E (or 3 and 4 in 0-indexed)
                formula_upper = formula.upper()
                if '/' in formula and ('D' in formula_upper or 'E' in formula_upper):
                    formulas_found += 1
                    break
    
    return formulas_found >= 2  # At least 2 meals should have the formula


def check_waste_adjustment_formulas(workbook, sheet_name, grocery_rows):
    """Check if waste adjustment formulas exist for grocery items"""
    sheet_data = workbook['sheets'][sheet_name]
    adjustments_found = 0
    
    for row_idx in grocery_rows[:3]:  # Check first 3 grocery items
        if row_idx >= len(sheet_data):
            continue
        row = sheet_data[row_idx]
        
        # Look for formulas that involve (1 - waste_percent)
        for col_idx in range(5, min(len(row), 12)):
            cell = row[col_idx]
            formula = cell.get('formula') if isinstance(cell, dict) else None
            
            if formula:
                # Check for pattern like: D2/(1-F2) or D2/(1-0.3)
                if '/(1-' in formula.replace(' ', '') or '/\(1-' in formula.replace(' ', ''):
                    adjustments_found += 1
                    break
    
    return adjustments_found >= 2  # At least 2 grocery items should have waste adjustment


def check_average_functions(workbook, sheet_name):
    """Check if AVERAGE functions are used"""
    sheet_data = workbook['sheets'][sheet_name]
    average_count = 0
    
    # Check rows 10-25 (likely summary section)
    for row_idx in range(10, min(25, len(sheet_data))):
        row = sheet_data[row_idx]
        for col_idx in range(len(row)):
            cell = row[col_idx]
            formula = cell.get('formula') if isinstance(cell, dict) else None
            
            if formula and 'AVERAGE' in formula.upper():
                average_count += 1
    
    return average_count >= 2  # Should have at least 2 averages (meal kit and grocery)


def find_calculated_averages(workbook, sheet_name):
    """Find calculated average values in the summary section"""
    sheet_data = workbook['sheets'][sheet_name]
    averages = []
    
    # Look in rows 10-25 for calculated values that might be averages
    for row_idx in range(10, min(25, len(sheet_data))):
        row = sheet_data[row_idx]
        for col_idx in range(len(row)):
            cell = row[col_idx]
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if isinstance(value, (int, float)) and 4 <= value <= 15:  # Reasonable per-serving range
                averages.append(value)
    
    return averages


def check_subscription_fee_integration(workbook, sheet_name, meal_kit_rows, subscription_fee):
    """Check if subscription fee is factored into calculations"""
    sheet_data = workbook['sheets'][sheet_name]
    
    # Count total meal kit servings
    total_servings = 0
    for row_idx in meal_kit_rows:
        if row_idx < len(sheet_data):
            row = sheet_data[row_idx]
            if len(row) > 4:
                servings_cell = row[4]  # Column E (0-indexed: 4)
                servings = servings_cell.get('value') if isinstance(servings_cell, dict) else servings_cell
                if isinstance(servings, (int, float)):
                    total_servings += servings
    
    if total_servings == 0:
        return False
    
    expected_fee_per_serving = subscription_fee / total_servings
    
    # Look for values close to this in the summary section
    for row_idx in range(10, min(25, len(sheet_data))):
        row = sheet_data[row_idx]
        for cell in row:
            value = cell.get('value') if isinstance(cell, dict) else cell
            if isinstance(value, (int, float)):
                if abs(value - expected_fee_per_serving) < 0.10:
                    return True
    
    return False


def check_cost_difference_calculation(workbook, sheet_name):
    """Check if cost difference (absolute or percentage) is calculated"""
    sheet_data = workbook['sheets'][sheet_name]
    
    # Look for percentage formulas or difference calculations
    for row_idx in range(10, min(25, len(sheet_data))):
        row = sheet_data[row_idx]
        for cell in row:
            formula = cell.get('formula') if isinstance(cell, dict) else None
            if formula:
                formula_upper = formula.upper()
                # Check for percentage calculation or subtraction
                if ('*100' in formula.replace(' ', '') or 
                    '/100' in formula.replace(' ', '') or
                    '%-' in formula_upper or
                    '-' in formula):
                    return True
    
    return False


def check_reasonable_values(workbook, sheet_name):
    """Check if calculated values are within reasonable ranges"""
    sheet_data = workbook['sheets'][sheet_name]
    
    # Look for per-serving costs in reasonable range ($3-$12)
    reasonable_count = 0
    
    for row_idx in range(1, min(13, len(sheet_data))):  # Check meal rows
        row = sheet_data[row_idx]
        for col_idx in range(5, min(len(row), 12)):
            cell = row[col_idx]
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if isinstance(value, (int, float)) and 3 <= value <= 12:
                reasonable_count += 1
                break
    
    return reasonable_count >= 6  # At least half the meals should have reasonable per-serving costs


def check_formatting(workbook, sheet_name):
    """Check if proper formatting is applied (currency or percentages)"""
    sheet_data = workbook['sheets'][sheet_name]
    
    # This is harder to check from parsed data, so we'll look for:
    # 1. Percentage values (0.05, 0.30 = waste percents should be present)
    # 2. Dollar amounts in reasonable ranges
    
    has_percentages = False
    has_currency_values = False
    
    for row in sheet_data[:13]:
        for cell in row:
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if isinstance(value, (int, float)):
                if 0 < value < 1:  # Likely a percentage in decimal form
                    has_percentages = True
                if 5 <= value <= 20:  # Likely currency amounts
                    has_currency_values = True
    
    return has_percentages and has_currency_values


def verify_meal_kit_calculator(traj, env_info, task_info):
    """
    Verify meal kit value calculator task completion.
    
    Checks:
    1. Per-serving cost formulas exist
    2. Waste adjustment applied to grocery costs
    3. AVERAGE functions used
    4. Subscription fees factored in
    5. Cost difference calculated
    6. Values are reasonable
    7. Proper formatting applied
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/meal_analysis_result.ods'),
        ('ods', '/home/ga/Documents/meal_comparison_data.ods'),
        ('csv', '/home/ga/Documents/meal_comparison_data.csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = workbook['sheets'][sheet_name]
        
        # Find meal kit and grocery rows
        meal_kit_rows = find_meal_kit_rows(sheet_data)
        grocery_rows = find_grocery_rows(sheet_data)
        subscription_fee = find_subscription_fee(sheet_data)
        
        logger.info(f"Found {len(meal_kit_rows)} meal kit rows, {len(grocery_rows)} grocery rows")
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Per-serving cost formulas
        has_per_serving = check_per_serving_formulas(workbook, sheet_name, meal_kit_rows + grocery_rows)
        if has_per_serving:
            criteria_passed += 1
            feedback_parts.append("✅ Per-serving cost formulas detected")
            subscores['per_serving_formulas'] = True
        else:
            feedback_parts.append("❌ Per-serving cost formulas not found (need: Total_Cost / Servings)")
            subscores['per_serving_formulas'] = False
        
        # Criterion 2: Waste adjustment for grocery items
        has_waste_adjustment = check_waste_adjustment_formulas(workbook, sheet_name, grocery_rows)
        if has_waste_adjustment:
            criteria_passed += 1
            feedback_parts.append("✅ Waste adjustment formulas found for grocery items")
            subscores['waste_adjustment'] = True
        else:
            feedback_parts.append("❌ Waste adjustment missing (need: Cost / (1 - Waste%))")
            subscores['waste_adjustment'] = False
        
        # Criterion 3: AVERAGE functions used
        has_averages = check_average_functions(workbook, sheet_name)
        if has_averages:
            criteria_passed += 1
            feedback_parts.append("✅ AVERAGE functions used for cost analysis")
            subscores['average_functions'] = True
        else:
            feedback_parts.append("❌ AVERAGE functions not found")
            subscores['average_functions'] = False
        
        # Criterion 4: Subscription fee integration
        has_subscription = check_subscription_fee_integration(workbook, sheet_name, meal_kit_rows, subscription_fee)
        if has_subscription:
            criteria_passed += 1
            feedback_parts.append("✅ Subscription fee factored into meal kit costs")
            subscores['subscription_fee'] = True
        else:
            feedback_parts.append("⚠️  Subscription fee may not be integrated")
            subscores['subscription_fee'] = False
        
        # Criterion 5: Cost difference calculation
        has_difference = check_cost_difference_calculation(workbook, sheet_name)
        if has_difference:
            criteria_passed += 1
            feedback_parts.append("✅ Cost difference calculated")
            subscores['cost_difference'] = True
        else:
            feedback_parts.append("❌ Cost difference calculation not found")
            subscores['cost_difference'] = False
        
        # Criterion 6: Reasonable values
        has_reasonable_values = check_reasonable_values(workbook, sheet_name)
        if has_reasonable_values:
            criteria_passed += 1
            feedback_parts.append("✅ Calculated values within reasonable ranges")
            subscores['reasonable_values'] = True
        else:
            feedback_parts.append("⚠️  Some calculated values may be incorrect")
            subscores['reasonable_values'] = False
        
        # Criterion 7: Formatting
        has_formatting = check_formatting(workbook, sheet_name)
        if has_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Data formatting appears correct")
            subscores['formatting'] = True
        else:
            feedback_parts.append("⚠️  Consider applying currency/percentage formatting")
            subscores['formatting'] = False
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent cost analysis completed!")
        elif passed:
            feedback_parts.append("✅ Cost analysis task completed adequately")
        else:
            feedback_parts.append("❌ Analysis incomplete - missing key calculations")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
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
