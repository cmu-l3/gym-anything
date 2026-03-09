#!/usr/bin/env python3
"""
Verifier for Home Appliance Replacement Advisor task.
Validates lifecycle analysis calculations and decision support logic.
"""

import sys
import os
import logging
import re
from datetime import datetime

# Use relative path to utils folder (runs on host machine, not container)
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


def find_column_by_name(sheet_rows, possible_names):
    """
    Find column index by searching header row for column name.
    Returns column index (0-based) or None if not found.
    """
    if not sheet_rows or len(sheet_rows) == 0:
        return None
    
    header_row = sheet_rows[0]
    for col_idx, cell in enumerate(header_row):
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        if cell_value:
            cell_text = str(cell_value).lower().strip()
            for name in possible_names:
                if name.lower() in cell_text:
                    return col_idx
    return None


def check_formula_structure(formula, expected_patterns):
    """
    Check if formula contains expected patterns (functions, operators).
    Returns True if any pattern matches.
    """
    if not formula:
        return False
    
    formula_upper = formula.upper().replace(' ', '')
    for pattern in expected_patterns:
        if pattern.upper() in formula_upper:
            return True
    return False


def check_date_formula(formula):
    """Check if formula uses date functions (TODAY, YEAR, DATEDIF, etc.)"""
    if not formula:
        return False
    return check_formula_structure(formula, ['TODAY()', 'YEAR(', 'DATEDIF(', 'NOW()'])


def check_if_formula(formula):
    """Check if formula contains IF statement"""
    if not formula:
        return False
    return check_formula_structure(formula, ['IF('])


def check_percentage_formula(formula, age_col_ref, lifespan_col_ref):
    """Check if formula divides age by lifespan"""
    if not formula:
        return False
    formula_clean = formula.upper().replace(' ', '')
    # Look for division pattern
    return '/' in formula_clean and ('100' in formula_clean or '*100' in formula_clean)


def verify_appliance_advisor(traj, env_info, task_info):
    """
    Verify appliance replacement advisor task completion.
    
    Checks 8 criteria:
    1. Age calculation with date formulas
    2. Age percentage calculation
    3. Priority flags with IF logic
    4. 50% repair rule implementation
    5. Energy cost calculation
    6. Formulas present (not hardcoded)
    7. Data sorted or urgency score created
    8. Evidence of formatting/organization
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/appliance_analysis.ods",
        "/home/ga/Documents/appliance_inventory.ods",
        "/home/ga/Documents/appliance_inventory.csv"
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path in possible_paths:
        file_format = 'ods' if container_path.endswith('.ods') else 'csv'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file from: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {error}. Tried: {', '.join(possible_paths)}"
        }

    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_rows = workbook['sheets'][sheet_name]
        
        if len(sheet_rows) < 3:  # Need header + at least 2 data rows
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Insufficient data rows (found {len(sheet_rows)}, need at least 3)"
            }
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Find column indices (original columns)
        purchase_date_col = find_column_by_name(sheet_rows, ['purchase date', 'purchase', 'date'])
        lifespan_col = find_column_by_name(sheet_rows, ['expected lifespan', 'lifespan', 'expected life'])
        repair_quote_col = find_column_by_name(sheet_rows, ['current repair', 'repair quote', 'current quote'])
        replacement_cost_col = find_column_by_name(sheet_rows, ['replacement cost', 'replacement'])
        energy_use_col = find_column_by_name(sheet_rows, ['energy use', 'kwh', 'energy'])
        
        # Try to find new calculated columns
        age_col = find_column_by_name(sheet_rows, ['age (years)', 'age', 'current age', 'years'])
        age_percent_col = find_column_by_name(sheet_rows, ['age %', 'age percent', '% of lifespan', 'percentage'])
        priority_col = find_column_by_name(sheet_rows, ['priority', 'replacement priority', 'urgency'])
        repair_rec_col = find_column_by_name(sheet_rows, ['repair recommended', 'recommendation', 'repair?'])
        energy_cost_col = find_column_by_name(sheet_rows, ['energy cost', 'annual cost', 'annual energy'])
        urgency_score_col = find_column_by_name(sheet_rows, ['urgency score', 'score', 'urgency'])
        
        logger.info(f"Found columns - Age: {age_col}, Age%: {age_percent_col}, Priority: {priority_col}")
        
        # CRITERION 1: Age Calculation with Date Formula
        age_formula_found = False
        if age_col is not None and len(sheet_rows) > 1:
            # Check a few data rows for age formula
            for row_idx in range(1, min(4, len(sheet_rows))):
                if row_idx < len(sheet_rows) and age_col < len(sheet_rows[row_idx]):
                    cell_data = sheet_rows[row_idx][age_col]
                    formula = cell_data.get('formula') if isinstance(cell_data, dict) else None
                    
                    if check_date_formula(formula):
                        age_formula_found = True
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Age calculation uses date formula: {formula[:50]}")
                        subscores['age_formula'] = True
                        break
        
        if not age_formula_found:
            feedback_parts.append("❌ Age calculation missing or not using date formulas (TODAY/YEAR/DATEDIF)")
            subscores['age_formula'] = False
        
        # CRITERION 2: Age Percentage Calculation
        age_percent_found = False
        if age_percent_col is not None and len(sheet_rows) > 1:
            for row_idx in range(1, min(4, len(sheet_rows))):
                if row_idx < len(sheet_rows) and age_percent_col < len(sheet_rows[row_idx]):
                    cell_data = sheet_rows[row_idx][age_percent_col]
                    formula = cell_data.get('formula') if isinstance(cell_data, dict) else None
                    value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                    
                    # Check if formula divides and multiplies by 100, or if value is reasonable percentage
                    if formula and ('/' in formula and ('100' in formula or '*100' in formula)):
                        age_percent_found = True
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Age percentage calculated correctly")
                        subscores['age_percentage'] = True
                        break
                    elif value is not None and isinstance(value, (int, float)) and 0 <= value <= 200:
                        # Might be formatted as percentage already
                        age_percent_found = True
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Age percentage values present")
                        subscores['age_percentage'] = True
                        break
        
        if not age_percent_found:
            feedback_parts.append("❌ Age percentage calculation missing (Age/Lifespan*100)")
            subscores['age_percentage'] = False
        
        # CRITERION 3: Priority Flags with IF Logic
        priority_logic_found = False
        if priority_col is not None and len(sheet_rows) > 1:
            for row_idx in range(1, min(4, len(sheet_rows))):
                if row_idx < len(sheet_rows) and priority_col < len(sheet_rows[row_idx]):
                    cell_data = sheet_rows[row_idx][priority_col]
                    formula = cell_data.get('formula') if isinstance(cell_data, dict) else None
                    value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                    
                    if check_if_formula(formula):
                        priority_logic_found = True
                        criteria_passed += 1
                        feedback_parts.append("✅ Priority logic implemented with IF statements")
                        subscores['priority_logic'] = True
                        break
                    elif value and str(value).upper() in ['HIGH', 'MEDIUM', 'LOW']:
                        # Has priority values (might be hardcoded, but give partial credit)
                        priority_logic_found = True
                        criteria_passed += 0.7  # Partial credit if no formula but values present
                        feedback_parts.append("⚠️ Priority values present (prefer formula-based)")
                        subscores['priority_logic'] = True
                        break
        
        if not priority_logic_found:
            feedback_parts.append("❌ Priority flags missing (HIGH/MEDIUM/LOW)")
            subscores['priority_logic'] = False
        
        # CRITERION 4: 50% Repair Rule
        repair_rule_found = False
        if repair_rec_col is not None and len(sheet_rows) > 1:
            for row_idx in range(1, min(4, len(sheet_rows))):
                if row_idx < len(sheet_rows) and repair_rec_col < len(sheet_rows[row_idx]):
                    cell_data = sheet_rows[row_idx][repair_rec_col]
                    formula = cell_data.get('formula') if isinstance(cell_data, dict) else None
                    value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                    
                    # Check for IF formula with division (cost ratio)
                    if formula and check_if_formula(formula) and '/' in formula:
                        # Check if it references repair cost and replacement cost columns
                        if '0.5' in formula or '>0.5' in formula or '>50' in formula:
                            repair_rule_found = True
                            criteria_passed += 1
                            feedback_parts.append("✅ 50% repair rule applied correctly")
                            subscores['repair_rule'] = True
                            break
                    elif value and ('REPAIR' in str(value).upper() or 'REPLACE' in str(value).upper()):
                        repair_rule_found = True
                        criteria_passed += 0.7
                        feedback_parts.append("⚠️ Repair recommendations present")
                        subscores['repair_rule'] = True
                        break
        
        if not repair_rule_found:
            feedback_parts.append("❌ 50% repair rule not implemented")
            subscores['repair_rule'] = False
        
        # CRITERION 5: Energy Cost Calculation
        energy_cost_found = False
        if energy_cost_col is not None and len(sheet_rows) > 1:
            for row_idx in range(1, min(4, len(sheet_rows))):
                if row_idx < len(sheet_rows) and energy_cost_col < len(sheet_rows[row_idx]):
                    cell_data = sheet_rows[row_idx][energy_cost_col]
                    formula = cell_data.get('formula') if isinstance(cell_data, dict) else None
                    value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                    
                    if formula and '*' in formula:
                        # Check for $ signs indicating absolute reference
                        if '$' in formula:
                            energy_cost_found = True
                            criteria_passed += 1
                            feedback_parts.append("✅ Energy cost calculated with absolute reference")
                            subscores['energy_cost'] = True
                            break
                        else:
                            energy_cost_found = True
                            criteria_passed += 0.8
                            feedback_parts.append("⚠️ Energy cost calculated (prefer absolute reference)")
                            subscores['energy_cost'] = True
                            break
                    elif value is not None and isinstance(value, (int, float)) and value > 0:
                        energy_cost_found = True
                        criteria_passed += 0.6
                        feedback_parts.append("⚠️ Energy cost values present")
                        subscores['energy_cost'] = True
                        break
        
        if not energy_cost_found:
            feedback_parts.append("❌ Energy cost calculation missing")
            subscores['energy_cost'] = False
        
        # CRITERION 6: Formulas Present (not hardcoded)
        formula_count = 0
        for row_idx in range(1, min(5, len(sheet_rows))):
            if row_idx < len(sheet_rows):
                for cell_data in sheet_rows[row_idx]:
                    if isinstance(cell_data, dict):
                        formula = cell_data.get('formula')
                        if formula and formula.startswith('='):
                            formula_count += 1
        
        if formula_count >= 3:  # At least 3 formulas per row * some rows
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas used ({formula_count} formulas detected)")
            subscores['formulas_present'] = True
        else:
            feedback_parts.append(f"❌ Insufficient formulas ({formula_count} found, values may be hardcoded)")
            subscores['formulas_present'] = False
        
        # CRITERION 7: Data Sorted or Urgency Score
        sorted_or_scored = False
        
        # Check if urgency score column exists
        if urgency_score_col is not None:
            sorted_or_scored = True
            criteria_passed += 1
            feedback_parts.append("✅ Urgency score column created")
            subscores['sorted_or_scored'] = True
        else:
            # Check if data appears sorted by age percentage (descending)
            if age_percent_col is not None and len(sheet_rows) > 3:
                age_values = []
                for row_idx in range(1, min(6, len(sheet_rows))):
                    if row_idx < len(sheet_rows) and age_percent_col < len(sheet_rows[row_idx]):
                        cell_data = sheet_rows[row_idx][age_percent_col]
                        value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                        if value is not None and isinstance(value, (int, float)):
                            age_values.append(value)
                
                if len(age_values) >= 3:
                    # Check if descending
                    is_descending = all(age_values[i] >= age_values[i+1] for i in range(len(age_values)-1))
                    if is_descending:
                        sorted_or_scored = True
                        criteria_passed += 1
                        feedback_parts.append("✅ Data sorted by priority (descending age %)")
                        subscores['sorted_or_scored'] = True
        
        if not sorted_or_scored:
            feedback_parts.append("⚠️ Data not sorted by urgency (recommended for prioritization)")
            subscores['sorted_or_scored'] = False
        
        # CRITERION 8: Evidence of Formatting/Organization
        # Check if there are more columns than original (indicates analysis was performed)
        header_row = sheet_rows[0]
        original_col_count = 8  # Based on CSV provided
        current_col_count = len(header_row)
        
        if current_col_count > original_col_count:
            criteria_passed += 1
            new_cols = current_col_count - original_col_count
            feedback_parts.append(f"✅ Analysis columns added ({new_cols} new columns)")
            subscores['organization'] = True
        else:
            feedback_parts.append("❌ No new analysis columns added")
            subscores['organization'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # 6/8 criteria needed
        
        # Add summary feedback
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent appliance lifecycle analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Good appliance analysis completed")
        else:
            feedback_parts.insert(0, "❌ Incomplete analysis - missing key calculations")
        
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
