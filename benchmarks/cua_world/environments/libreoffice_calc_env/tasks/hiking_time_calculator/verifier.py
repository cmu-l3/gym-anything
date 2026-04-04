#!/usr/bin/env python3
"""
Verifier for Hiking Time Calculator task.

Checks that formulas are correctly applied to calculate hiking times
using Naismith's Rule with elevation adjustments and safety margins.
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path since verification runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_environment,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_formula(formula):
    """Normalize formula for comparison (remove spaces, uppercase)"""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def formula_references_column(formula, column_letter):
    """Check if formula references a specific column"""
    if not formula:
        return False
    normalized = normalize_formula(formula)
    # Check for column references like B2, B3, etc.
    pattern = f"{column_letter.upper()}\\d+"
    return bool(re.search(pattern, normalized))


def check_formula_pattern(formula, expected_operator, expected_divisor=None):
    """
    Check if formula matches expected pattern.
    
    Args:
        formula: Formula string
        expected_operator: Expected operator ('+', '-', '/', '*')
        expected_divisor: Expected divisor value (for division formulas)
    
    Returns:
        bool: True if pattern matches
    """
    if not formula:
        return False
    
    normalized = normalize_formula(formula)
    
    # Check for operator
    if expected_operator not in normalized:
        return False
    
    # Check for divisor if specified
    if expected_divisor is not None:
        if str(expected_divisor) not in normalized:
            return False
    
    return True


def verify_hiking_calculator(traj, env_info, task_info):
    """
    Verify hiking time calculator task completion.
    
    Checks:
    1. Base time formulas present (distance-based)
    2. Elevation adjustment formulas present
    3. Total segment time calculated
    4. Total moving time calculated
    5. Safety margin added (20-30%)
    6. Feasibility determination present
    7. Results are mathematically reasonable
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }
    
    # Setup verification
    container_path = "/home/ga/Documents/hiking_calculator.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods']
    )
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = get_sheet_names(data)
        
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        
        criteria_met = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Base time formulas present (column E, rows 2-8)
        base_time_formulas_count = 0
        for row in range(2, 9):  # Rows 2-8 (7 segments)
            cell_ref = f"E{row}"
            formula = get_cell_formula(data, sheet_name, cell_ref)
            # Check if formula references distance column (B) and uses division
            if formula and formula_references_column(formula, 'B') and '/' in formula:
                base_time_formulas_count += 1
                logger.debug(f"Base time formula in {cell_ref}: {formula}")
        
        if base_time_formulas_count >= 5:  # At least 5 segments have correct formulas
            criteria_met += 1
            feedback_parts.append(f"✅ Base time formulas present ({base_time_formulas_count}/7 segments)")
            subscores['base_time_formulas'] = True
        else:
            feedback_parts.append(f"❌ Base time formulas missing or incorrect ({base_time_formulas_count}/7 found)")
            subscores['base_time_formulas'] = False
        
        # Criterion 2: Elevation adjustment formulas present (columns F, G, rows 2-8)
        elevation_formulas_count = 0
        for row in range(2, 9):
            # Check ascent time (column F should reference column C)
            ascent_formula = get_cell_formula(data, sheet_name, f"F{row}")
            # Check descent bonus (column G should reference column D)
            descent_formula = get_cell_formula(data, sheet_name, f"G{row}")
            
            has_ascent = ascent_formula and formula_references_column(ascent_formula, 'C') and '/' in ascent_formula
            has_descent = descent_formula and formula_references_column(descent_formula, 'D')
            
            if has_ascent or has_descent:
                elevation_formulas_count += 1
                logger.debug(f"Elevation formulas in row {row}: ascent={ascent_formula}, descent={descent_formula}")
        
        if elevation_formulas_count >= 5:
            criteria_met += 1
            feedback_parts.append(f"✅ Elevation adjustment formulas present ({elevation_formulas_count}/7 segments)")
            subscores['elevation_formulas'] = True
        else:
            feedback_parts.append(f"❌ Elevation adjustment formulas missing ({elevation_formulas_count}/7 found)")
            subscores['elevation_formulas'] = False
        
        # Criterion 3: Total segment time calculated (column H, rows 2-8)
        total_segment_formulas_count = 0
        for row in range(2, 9):
            formula = get_cell_formula(data, sheet_name, f"H{row}")
            # Should reference columns E, F, G (or use SUM)
            if formula:
                has_addition = '+' in formula
                references_calcs = (formula_references_column(formula, 'E') or 
                                  formula_references_column(formula, 'F') or 
                                  formula_references_column(formula, 'G'))
                has_sum = 'SUM' in normalize_formula(formula)
                
                if (has_addition and references_calcs) or has_sum:
                    total_segment_formulas_count += 1
                    logger.debug(f"Total segment formula in H{row}: {formula}")
        
        if total_segment_formulas_count >= 5:
            criteria_met += 1
            feedback_parts.append(f"✅ Total segment time formulas present ({total_segment_formulas_count}/7 segments)")
            subscores['segment_totals'] = True
        else:
            feedback_parts.append(f"❌ Total segment time formulas missing ({total_segment_formulas_count}/7 found)")
            subscores['segment_totals'] = False
        
        # Criterion 4: Total moving time calculated (should be around row 10-11)
        total_moving_time = None
        total_moving_formula = None
        for row in range(9, 14):  # Check rows 9-13 for total
            formula = get_cell_formula(data, sheet_name, f"B{row}")
            value = get_cell_value(data, sheet_name, f"B{row}")
            
            # Look for SUM formula referencing column H
            if formula and 'SUM' in normalize_formula(formula) and formula_references_column(formula, 'H'):
                total_moving_time = value
                total_moving_formula = formula
                logger.info(f"Found total moving time in B{row}: {formula} = {value}")
                break
            # Or just a reasonable value
            elif value and isinstance(value, (int, float)) and 3 <= value <= 10:
                total_moving_time = value
                logger.info(f"Found total moving time value in B{row}: {value}")
        
        if total_moving_time and 3.5 <= total_moving_time <= 8.0:
            criteria_met += 1
            if total_moving_formula:
                feedback_parts.append(f"✅ Total moving time calculated: {total_moving_time:.2f} hours (formula: {total_moving_formula})")
            else:
                feedback_parts.append(f"✅ Total moving time calculated: {total_moving_time:.2f} hours")
            subscores['total_moving_time'] = True
        else:
            feedback_parts.append(f"❌ Total moving time not found or unreasonable (got: {total_moving_time})")
            subscores['total_moving_time'] = False
        
        # Criterion 5: Safety margin added (should be 20-30% of moving time)
        safety_margin_applied = False
        total_with_margin = None
        
        if total_moving_time:
            # Look for total with margin in subsequent rows
            for row in range(10, 16):
                value = get_cell_value(data, sheet_name, f"B{row}")
                formula = get_cell_formula(data, sheet_name, f"B{row}")
                
                if value and isinstance(value, (int, float)):
                    # Check if value is 20-30% larger than moving time
                    ratio = value / total_moving_time
                    if 1.15 <= ratio <= 1.35:  # 15-35% margin (allowing some flexibility)
                        safety_margin_applied = True
                        total_with_margin = value
                        logger.info(f"Found total with margin in B{row}: {value} (ratio: {ratio:.2f})")
                        break
        
        if safety_margin_applied:
            criteria_met += 1
            feedback_parts.append(f"✅ Safety margin applied: {total_with_margin:.2f} hours total")
            subscores['safety_margin'] = True
        else:
            feedback_parts.append("❌ Safety margin not properly applied (should be 20-30% of moving time)")
            subscores['safety_margin'] = False
        
        # Criterion 6: Feasibility determination present
        feasibility_found = False
        feasibility_text = None
        
        for row in range(10, 18):  # Check rows 10-17 for feasibility
            for col in ['A', 'B', 'C']:
                value = get_cell_value(data, sheet_name, f"{col}{row}")
                if value and isinstance(value, str):
                    value_upper = value.upper()
                    if any(keyword in value_upper for keyword in ['YES', 'NO', 'SAFE', 'TOO LONG', 'FEASIBLE']):
                        feasibility_found = True
                        feasibility_text = value
                        logger.info(f"Found feasibility determination in {col}{row}: {value}")
                        break
            if feasibility_found:
                break
        
        if feasibility_found:
            criteria_met += 1
            feedback_parts.append(f"✅ Feasibility determination: {feasibility_text}")
            subscores['feasibility'] = True
        else:
            feedback_parts.append("❌ Feasibility determination not found (should contain YES/NO or SAFE/TOO LONG)")
            subscores['feasibility'] = False
        
        # Criterion 7: Results are mathematically reasonable
        # Expected for sample data: ~4.6 hours moving, ~5.75 with margin
        results_reasonable = False
        
        if total_with_margin and 4.5 <= total_with_margin <= 8.0:
            results_reasonable = True
            criteria_met += 1
            feedback_parts.append("✅ Results are mathematically reasonable for trail data")
            subscores['results_reasonable'] = True
        elif total_moving_time and 3.5 <= total_moving_time <= 7.0:
            # Partial credit if moving time is reasonable even without margin
            results_reasonable = True
            criteria_met += 0.5
            feedback_parts.append("⚠️ Results partially reasonable (moving time OK, but check margin)")
            subscores['results_reasonable'] = True
        else:
            feedback_parts.append(f"❌ Results seem mathematically unreasonable (expected ~5-6 hours total)")
            subscores['results_reasonable'] = False
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 70% (5 out of 7 criteria)
        
        # Build feedback string
        feedback_header = f"Criteria met: {criteria_met}/{total_criteria} ({score}%)"
        feedback = feedback_header + " | " + " | ".join(feedback_parts)
        
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
        # Clean up temporary files
        temp_dir = file_info.get('temp_dir')
        if temp_dir:
            cleanup_verification_environment(temp_dir)
