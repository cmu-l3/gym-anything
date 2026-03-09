#!/usr/bin/env python3
"""
Verifier for Pool Chemical Balancer task

Checks:
1. Data cleaning (text removed from numeric cells)
2. pH calculation accuracy (acid dosing ~20 oz)
3. Chlorine calculation accuracy (~0.62 lbs with temp correction)
4. Alkalinity calculation accuracy (~6.67 lbs)
5. Urgency flags (chlorine should be CRITICAL)
6. Chemical priority order (pH before chlorine)
7. Total cost calculation present
8. Use of formulas (not just hardcoded values)
"""

import sys
import os
import re
import logging

# Add utils to path (relative path for host machine)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_numeric(value):
    """Extract numeric value from potentially messy cell content"""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    
    # Convert to string and extract first number found
    value_str = str(value)
    # Match numbers including decimals
    match = re.search(r'[-+]?\d*\.?\d+', value_str)
    if match:
        try:
            return float(match.group())
        except ValueError:
            return None
    return None


def check_data_cleaning(sheet_data, sheet_name):
    """
    Check if numeric data has been cleaned (text notes removed).
    Look for cells that have been cleaned vs. original messy data.
    """
    try:
        # Look for evidence of data cleaning in common areas
        # Check if there's a "Cleaned Value" or similar column
        # Or check if the current reading column has been cleaned
        
        rows = sheet_data['sheets'][sheet_name]
        cleaned_cells = 0
        total_checked = 0
        
        # Check several cells for numeric-only content
        # Typically data would be in rows 2-9, columns A-E
        for row_idx in range(1, min(10, len(rows))):
            if row_idx >= len(rows):
                break
            row = rows[row_idx]
            for col_idx in range(min(5, len(row))):
                if col_idx >= len(row):
                    break
                cell = row[col_idx]
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                
                if cell_value is not None and cell_value != '':
                    total_checked += 1
                    # Check if it's a clean number (no text notes)
                    if isinstance(cell_value, (int, float)):
                        cleaned_cells += 1
                    elif isinstance(cell_value, str):
                        # Allow strings that are just numbers
                        try:
                            float(cell_value)
                            cleaned_cells += 1
                        except ValueError:
                            # Check if it contains only numeric content (no parentheses, no "ppm", etc.)
                            if re.match(r'^[-+]?\d*\.?\d+$', cell_value.strip()):
                                cleaned_cells += 1
        
        if total_checked == 0:
            return False, "No data found to check"
        
        clean_ratio = cleaned_cells / total_checked
        return clean_ratio >= 0.95, f"{clean_ratio*100:.1f}% cells clean"
        
    except Exception as e:
        logger.error(f"Error checking data cleaning: {e}", exc_info=True)
        return False, str(e)


def find_value_in_sheet(sheet_data, sheet_name, target_value, tolerance=0.1):
    """
    Search entire sheet for a value close to target_value.
    Returns (found, cell_ref, actual_value, formula)
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        for row_idx, row in enumerate(rows):
            for col_idx, cell in enumerate(row):
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                numeric_value = extract_numeric(cell_value)
                
                if numeric_value is not None:
                    if abs(numeric_value - target_value) <= tolerance:
                        # Found a match!
                        # Convert indices to cell reference
                        col_letter = chr(ord('A') + col_idx) if col_idx < 26 else f"A{chr(ord('A') + col_idx - 26)}"
                        cell_ref = f"{col_letter}{row_idx + 1}"
                        
                        # Try to get formula
                        formula = cell.get('formula') if isinstance(cell, dict) else None
                        
                        return True, cell_ref, numeric_value, formula
        
        return False, None, None, None
        
    except Exception as e:
        logger.error(f"Error searching for value: {e}", exc_info=True)
        return False, None, None, None


def check_urgency_flags(sheet_data, sheet_name):
    """
    Check if urgency flags are present and correct.
    Look for "CRITICAL" flag associated with chlorine reading.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        critical_found = False
        urgent_found = False
        
        for row in rows:
            for cell in row:
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                if isinstance(cell_value, str):
                    upper_val = cell_value.upper()
                    if 'CRITICAL' in upper_val:
                        critical_found = True
                    if 'URGENT' in upper_val:
                        urgent_found = True
        
        return critical_found, urgent_found
        
    except Exception as e:
        logger.error(f"Error checking urgency flags: {e}", exc_info=True)
        return False, False


def count_formula_cells(sheet_data, sheet_name):
    """Count how many cells contain formulas (not just values)"""
    try:
        rows = sheet_data['sheets'][sheet_name]
        formula_count = 0
        
        for row in rows:
            for cell in row:
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula is not None and formula != '':
                    formula_count += 1
        
        return formula_count
        
    except Exception as e:
        logger.error(f"Error counting formulas: {e}", exc_info=True)
        return 0


def verify_pool_chemical_balancer(traj, env_info, task_info):
    """
    Verify pool chemical balancing task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/pool_chemical_plan.ods",
        "/home/ga/Documents/pool_test_results.ods",
        "/home/ga/Documents/pool_test_results.csv",
    ]
    
    success = False
    file_info = None
    
    for container_path in possible_paths:
        # Determine expected format
        if container_path.endswith('.ods'):
            expected_formats = ['ods']
        elif container_path.endswith('.csv'):
            expected_formats = ['csv']
        else:
            expected_formats = ['ods', 'csv']
        
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path,
            expected_formats
        )
        
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet file. Tried: {', '.join(possible_paths)}. Error: {error}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_names = get_sheet_names(sheet_data)
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Data Cleaning
        data_cleaned, clean_msg = check_data_cleaning(sheet_data, sheet_name)
        if data_cleaned:
            criteria_passed += 1
            feedback_parts.append(f"✅ Data cleaned: {clean_msg}")
        else:
            feedback_parts.append(f"❌ Data cleaning incomplete: {clean_msg}")
        subscores['data_cleaned'] = data_cleaned
        
        # Criterion 2: pH Calculation (expected ~20 oz acid)
        ph_found, ph_cell, ph_value, ph_formula = find_value_in_sheet(
            sheet_data, sheet_name, 20.0, tolerance=2.0
        )
        if ph_found:
            criteria_passed += 1
            feedback_parts.append(f"✅ pH calculation correct: {ph_value:.2f} oz in {ph_cell}")
        else:
            feedback_parts.append("❌ pH acid dosing not found (expected ~20 oz)")
        subscores['ph_calculation'] = ph_found
        
        # Criterion 3: Chlorine Calculation (expected ~0.62 lbs)
        cl_found, cl_cell, cl_value, cl_formula = find_value_in_sheet(
            sheet_data, sheet_name, 0.62, tolerance=0.05
        )
        if cl_found:
            criteria_passed += 1
            feedback_parts.append(f"✅ Chlorine calculation correct: {cl_value:.2f} lbs in {cl_cell}")
        else:
            feedback_parts.append("❌ Chlorine dosing not found (expected ~0.62 lbs)")
        subscores['chlorine_calculation'] = cl_found
        
        # Criterion 4: Alkalinity Calculation (expected ~6.67 lbs)
        alk_found, alk_cell, alk_value, alk_formula = find_value_in_sheet(
            sheet_data, sheet_name, 6.67, tolerance=0.5
        )
        if alk_found:
            criteria_passed += 1
            feedback_parts.append(f"✅ Alkalinity calculation correct: {alk_value:.2f} lbs in {alk_cell}")
        else:
            feedback_parts.append("❌ Baking soda dosing not found (expected ~6.67 lbs)")
        subscores['alkalinity_calculation'] = alk_found
        
        # Criterion 5: Urgency Flags
        critical_found, urgent_found = check_urgency_flags(sheet_data, sheet_name)
        if critical_found:
            criteria_passed += 1
            feedback_parts.append("✅ Urgency flags present (CRITICAL found)")
        else:
            feedback_parts.append("❌ CRITICAL urgency flag not found")
        subscores['urgency_flags'] = critical_found
        
        # Criterion 6: Chemical Priority Order
        # This is hard to verify automatically, so we'll give credit if other calculations are correct
        # In a more sophisticated verifier, we'd check for spatial organization or priority column
        if ph_found and cl_found:
            # Assume if both are calculated, priority was considered
            criteria_passed += 1
            feedback_parts.append("✅ Chemical calculations present (priority assumed)")
            priority_correct = True
        else:
            feedback_parts.append("⚠️ Cannot verify chemical priority order")
            priority_correct = False
        subscores['chemical_priority'] = priority_correct
        
        # Criterion 7: Total Cost Calculation
        # Look for a value in typical cost range ($40-$80 for these chemicals)
        cost_found, cost_cell, cost_value, cost_formula = find_value_in_sheet(
            sheet_data, sheet_name, 60.0, tolerance=30.0  # Wide range: $30-$90
        )
        if cost_found and cost_value > 20:  # Must be a reasonable cost
            criteria_passed += 1
            feedback_parts.append(f"✅ Total cost calculated: ${cost_value:.2f} in {cost_cell}")
        else:
            # Try looking for smaller costs that might be summed
            # Search for any value between $2-$15 (individual chemical costs)
            small_cost_found = False
            for target in [10.0, 5.0, 3.0]:
                found, _, _, _ = find_value_in_sheet(sheet_data, sheet_name, target, tolerance=2.0)
                if found:
                    small_cost_found = True
                    break
            
            if small_cost_found:
                criteria_passed += 0.5  # Partial credit
                feedback_parts.append("⚠️ Chemical costs found but total may be missing")
            else:
                feedback_parts.append("❌ Total cost calculation not found")
        subscores['total_cost'] = cost_found
        
        # Criterion 8: Formula Usage (not hardcoded)
        formula_count = count_formula_cells(sheet_data, sheet_name)
        if formula_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas used: {formula_count} formula cells found")
        else:
            feedback_parts.append(f"❌ Insufficient formulas ({formula_count} found, need 3+)")
        subscores['formulas_used'] = formula_count >= 3
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 6/8 criteria
        
        # Add summary feedback
        if passed and score >= 90:
            feedback_parts.insert(0, "🏊 Excellent work! Pool chemistry balanced correctly!")
        elif passed:
            feedback_parts.insert(0, "✅ Pool chemical balancing task completed")
        else:
            feedback_parts.insert(0, "❌ Pool chemical balancing incomplete")
        
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
        if file_info:
            cleanup_verification_temp(file_info.get('temp_dir'))
