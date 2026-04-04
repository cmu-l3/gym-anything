#!/usr/bin/env python3
"""
Verifier for Quilting Fabric Calculator task
Checks formulas and calculated values for fabric yardage requirements
"""

import sys
import os
import logging
import re

# Add utils to path (use relative path for host-side verification)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_quilt_calculator(traj, env_info, task_info):
    """
    Verify quilting fabric calculator task completion.
    
    Checks:
    1. Column F: Total square inches formulas (B*C*D)
    2. Column G: Conditional yards calculation (directional vs non-directional)
    3. Column H: Safety margin applied (10% increase)
    4. Column I: Proper rounding to 1/8 yard increments
    5. Values are mathematically correct
    6. Directional fabrics have higher yardage than equivalent non-directional
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/quilt_fabric_plan.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Test data rows (rows 2-7 contain fabric data)
        test_rows = [2, 3, 4, 5, 6, 7]
        
        # Criterion 1: Square Inches Formulas (Column F)
        square_inches_correct = 0
        for row_num in test_rows:
            formula = get_cell_formula(workbook, sheet_name, f'F{row_num}')
            if formula:
                # Check if formula multiplies columns B, C, D
                formula_upper = formula.upper()
                # Accept patterns like =B2*C2*D2 or =(B2*C2)*D2 or =B2*D2*C2, etc.
                has_b = f'B{row_num}' in formula_upper
                has_c = f'C{row_num}' in formula_upper
                has_d = f'D{row_num}' in formula_upper
                has_multiplication = '*' in formula
                
                if has_b and has_c and has_d and has_multiplication:
                    square_inches_correct += 1
        
        if square_inches_correct >= len(test_rows) * 0.8:  # At least 80% of rows
            criteria_passed += 1
            feedback_parts.append(f"✅ Square inches formulas correct ({square_inches_correct}/{len(test_rows)} rows)")
        else:
            feedback_parts.append(f"❌ Square inches formulas incomplete ({square_inches_correct}/{len(test_rows)} rows have correct formula)")
        
        # Criterion 2: Conditional Yards Logic (Column G)
        yards_logic_correct = 0
        has_conditional_logic = False
        
        for row_num in test_rows:
            formula = get_cell_formula(workbook, sheet_name, f'G{row_num}')
            if formula:
                formula_upper = formula.upper()
                
                # Check if formula uses IF statement or handles directional logic
                if 'IF(' in formula_upper or 'IF (' in formula_upper:
                    has_conditional_logic = True
                    # Check if IF references column E (directional flag)
                    if f'E{row_num}' in formula_upper:
                        yards_logic_correct += 1
                # Alternative: different formulas for different rows based on directional flag
                elif '/1512' in formula or '/(42*36)' in formula or '/42/36' in formula:
                    # Non-directional formula
                    directional = get_cell_value(workbook, sheet_name, f'E{row_num}')
                    if directional and directional.upper() == "NO":
                        yards_logic_correct += 1
                elif '/36' in formula and '/1512' not in formula:
                    # Directional formula
                    directional = get_cell_value(workbook, sheet_name, f'E{row_num}')
                    if directional and directional.upper() == "YES":
                        yards_logic_correct += 1
        
        if has_conditional_logic or yards_logic_correct >= len(test_rows) * 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Yards calculation handles directional logic")
        else:
            feedback_parts.append(f"❌ Yards calculation missing conditional logic for directional patterns")
        
        # Criterion 3: Safety Margin Applied (Column H)
        safety_margin_correct = 0
        for row_num in test_rows:
            formula = get_cell_formula(workbook, sheet_name, f'H{row_num}')
            if formula:
                formula_upper = formula.upper()
                # Check if formula multiplies G by 1.10 or 1.1 or adds 10%
                has_g_ref = f'G{row_num}' in formula_upper
                has_110_percent = ('1.10' in formula or '1.1' in formula or 
                                  '0.10' in formula or '0.1' in formula or
                                  '10%' in formula or '110%' in formula)
                
                if has_g_ref and has_110_percent:
                    safety_margin_correct += 1
        
        if safety_margin_correct >= len(test_rows) * 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Safety margin (10%) applied correctly")
        else:
            feedback_parts.append(f"❌ Safety margin formulas incomplete or incorrect")
        
        # Criterion 4: Proper Rounding to 1/8 yard (Column I)
        rounding_correct = 0
        for row_num in test_rows:
            formula = get_cell_formula(workbook, sheet_name, f'I{row_num}')
            if formula:
                formula_upper = formula.upper()
                # Check if formula uses CEILING or ROUNDUP with 0.125
                has_ceiling = 'CEILING' in formula_upper
                has_roundup = 'ROUNDUP' in formula_upper
                has_eighth = '0.125' in formula or '1/8' in formula or '0,125' in formula
                
                if (has_ceiling or has_roundup) and has_eighth:
                    rounding_correct += 1
        
        if rounding_correct >= len(test_rows) * 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Rounding to 1/8 yard implemented correctly")
        else:
            feedback_parts.append(f"❌ Rounding formulas incomplete or incorrect")
        
        # Criterion 5: Values Accurate
        values_accurate = True
        tolerance = 0.01
        
        # Test a few specific calculations
        # Row 2: Blue Floral - 12 blocks, 8x8, non-directional
        # Expected: F2=768, G2≈0.5079 (768/1512), H2≈0.559, I2=0.625
        f2_value = get_cell_value(workbook, sheet_name, 'F2')
        if f2_value:
            if abs(float(f2_value) - 768) > tolerance:
                values_accurate = False
                feedback_parts.append(f"⚠️ F2 calculation incorrect: expected 768, got {f2_value}")
        
        # Row 3: Red Stripe - 8 blocks, 10x6, directional
        # Expected: F3=480, G3≈1.333 (8*6/36), H3≈1.467, I3=1.5
        g3_value = get_cell_value(workbook, sheet_name, 'G3')
        if g3_value:
            # For directional, should be significantly higher than non-directional equivalent
            if float(g3_value) < 1.0:
                values_accurate = False
                feedback_parts.append(f"⚠️ G3 (directional) calculation seems incorrect: got {g3_value}")
        
        # Check that all I column values are multiples of 0.125
        all_rounded_correctly = True
        for row_num in test_rows:
            i_value = get_cell_value(workbook, sheet_name, f'I{row_num}')
            if i_value and i_value != '':
                try:
                    i_float = float(i_value)
                    # Check if multiple of 0.125
                    remainder = (i_float * 8) % 1
                    if remainder > 0.01 and remainder < 0.99:  # Allow small floating point error
                        all_rounded_correctly = False
                        break
                except (ValueError, TypeError):
                    pass
        
        if values_accurate and all_rounded_correctly:
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculated values are accurate")
        elif all_rounded_correctly:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some calculated values may be incorrect")
        else:
            feedback_parts.append(f"❌ Values are not correctly calculated or rounded")
        
        # Criterion 6: Directional Premium
        # Check that directional fabrics have higher yardage than non-directional
        # Row 3 (Red, directional) vs Row 2 (Blue, non-directional, similar dimensions)
        g2_value = get_cell_value(workbook, sheet_name, 'G2')
        g3_value = get_cell_value(workbook, sheet_name, 'G3')
        
        directional_premium_correct = False
        if g2_value and g3_value:
            try:
                g2_float = float(g2_value)
                g3_float = float(g3_value)
                # Red Stripe is directional, should have higher yards/block ratio
                # Blue: 768 sq in, Red: 480 sq in, but Red should have higher yards because directional
                if g3_float > g2_float * 0.8:  # Allow some tolerance based on dimensions
                    directional_premium_correct = True
            except (ValueError, TypeError):
                pass
        
        # Alternative check: ensure directional formulas are different from non-directional
        f2_formula = get_cell_formula(workbook, sheet_name, 'G2')
        f3_formula = get_cell_formula(workbook, sheet_name, 'G3')
        
        if f2_formula and f3_formula:
            # If using IF statement, they should be the same formula
            if 'IF' in f2_formula.upper():
                directional_premium_correct = True
            # If using different formulas, they should differ
            elif f2_formula.upper() != f3_formula.upper():
                directional_premium_correct = True
        
        if directional_premium_correct:
            criteria_passed += 1
            feedback_parts.append(f"✅ Directional fabric logic correctly implemented")
        else:
            feedback_parts.append(f"❌ Directional fabrics not handled differently from non-directional")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent work! All formulas correct.")
        elif passed:
            feedback_parts.insert(0, "✅ Task completed successfully.")
        else:
            feedback_parts.insert(0, "❌ Task incomplete or formulas incorrect.")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "square_inches_formulas": square_inches_correct >= len(test_rows) * 0.8,
                "conditional_yards_logic": has_conditional_logic or yards_logic_correct >= len(test_rows) * 0.8,
                "safety_margin_applied": safety_margin_correct >= len(test_rows) * 0.8,
                "proper_rounding": rounding_correct >= len(test_rows) * 0.8,
                "values_accurate": values_accurate and all_rounded_correctly,
                "directional_premium": directional_premium_correct
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
