#!/usr/bin/env python3
"""
Verifier for Yarn Project Calculator task

Checks:
1. Safety margin applied (10-15% buffer)
2. CEILING function used for skein calculations
3. Accurate cost calculations
4. Best option identified
5. Cross-sheet formula references
6. Proper formatting
"""

import sys
import os
import re
import math
import logging

# Add utils to path (relative path for host execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_sheet_reference(formula):
    """
    Extract sheet references from formula.
    Returns list of sheet names referenced.
    """
    if not formula:
        return []
    
    # Match patterns like "Pattern_Specs.B3" or "Yarn_Options.C2"
    pattern = r'([A-Za-z_][A-Za-z0-9_]*)\.[A-Z]+[0-9]+'
    matches = re.findall(pattern, formula)
    return matches


def check_ceiling_function(formula):
    """Check if formula contains CEILING or ROUNDUP function"""
    if not formula:
        return False
    
    formula_upper = formula.upper()
    return 'CEILING' in formula_upper or 'ROUNDUP' in formula_upper


def verify_yarn_calculator(traj, env_info, task_info):
    """
    Verify yarn calculator task completion.
    
    Checks:
    1. Safety margin applied (adjusted yardage 10-15% higher than base)
    2. CEILING function used for rounding skeins up
    3. Cost calculations accurate (skeins × price)
    4. Best option identification
    5. Cross-sheet references present
    6. Proper formatting
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/yarn_calculator.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get sheet names
        sheet_names = list(workbook['sheets'].keys())
        
        # Find Calculations sheet
        calc_sheet = None
        for name in sheet_names:
            if 'calc' in name.lower():
                calc_sheet = name
                break
        
        if not calc_sheet:
            return {"passed": False, "score": 0, "feedback": "Calculations sheet not found"}

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}

        # Expected values from Pattern_Specs (Medium = 1400 yards)
        EXPECTED_BASE_YARDAGE = 1400
        EXPECTED_ADJUSTED_MIN = EXPECTED_BASE_YARDAGE * 1.10
        EXPECTED_ADJUSTED_MAX = EXPECTED_BASE_YARDAGE * 1.20  # Allow up to 20% for flexibility
        
        # Yarn options data
        yarn_data = [
            {"name": "Cozy Wool", "yards_per_skein": 220, "price": 8.50},
            {"name": "Budget Acrylic", "yards_per_skein": 280, "price": 4.99},
            {"name": "Luxury Blend", "yards_per_skein": 200, "price": 12.00}
        ]

        # ===== Criterion 1: Safety Margin Applied =====
        base_yardage = get_cell_value(workbook, calc_sheet, 'B4')
        adjusted_yardage = get_cell_value(workbook, calc_sheet, 'B5')
        
        safety_margin_correct = False
        if base_yardage and adjusted_yardage:
            try:
                base = float(base_yardage)
                adjusted = float(adjusted_yardage)
                
                # Check if adjusted is 10-20% higher than base
                if EXPECTED_ADJUSTED_MIN <= adjusted <= EXPECTED_ADJUSTED_MAX:
                    ratio = adjusted / base if base > 0 else 0
                    if 1.10 <= ratio <= 1.20:
                        criteria_passed += 1
                        safety_margin_correct = True
                        feedback_parts.append(f"✅ Safety margin applied: {base:.0f} → {adjusted:.0f} yards ({(ratio-1)*100:.1f}% buffer)")
                    else:
                        feedback_parts.append(f"❌ Safety margin incorrect: ratio {ratio:.2f} (expected 1.10-1.15)")
                else:
                    feedback_parts.append(f"❌ Adjusted yardage {adjusted:.0f} out of expected range")
            except (ValueError, TypeError) as e:
                feedback_parts.append(f"❌ Invalid yardage values: base={base_yardage}, adjusted={adjusted_yardage}")
        else:
            feedback_parts.append(f"❌ Missing yardage calculations (B4={base_yardage}, B5={adjusted_yardage})")
        
        subscores['safety_margin_applied'] = safety_margin_correct

        # ===== Criterion 2: CEILING Function Used =====
        ceiling_used = False
        skein_formulas = []
        for col in ['B8', 'C8', 'D8']:
            formula = get_cell_formula(workbook, calc_sheet, col)
            skein_formulas.append(formula)
            if check_ceiling_function(formula):
                ceiling_used = True
                break
        
        if ceiling_used:
            criteria_passed += 1
            feedback_parts.append("✅ CEILING function used for rounding skeins")
        else:
            feedback_parts.append(f"❌ CEILING function not found in skein calculations")
            logger.debug(f"Skein formulas: {skein_formulas}")
        
        subscores['ceiling_function_used'] = ceiling_used

        # ===== Criterion 3: Accurate Cost Calculations =====
        costs_correct = True
        cost_errors = []
        
        if adjusted_yardage:
            try:
                adj_yards = float(adjusted_yardage)
                
                for idx, yarn in enumerate(yarn_data):
                    col_letter = chr(ord('B') + idx)  # B, C, D
                    
                    # Get skeins needed
                    skeins_cell = f"{col_letter}8"
                    skeins_value = get_cell_value(workbook, calc_sheet, skeins_cell)
                    
                    # Get total cost
                    cost_cell = f"{col_letter}9"
                    cost_value = get_cell_value(workbook, calc_sheet, cost_cell)
                    
                    if skeins_value and cost_value:
                        try:
                            skeins = float(skeins_value)
                            cost = float(cost_value)
                            
                            # Calculate expected values
                            expected_skeins = math.ceil(adj_yards / yarn['yards_per_skein'])
                            expected_cost = expected_skeins * yarn['price']
                            
                            # Verify skeins is integer
                            if skeins != int(skeins):
                                costs_correct = False
                                cost_errors.append(f"{yarn['name']}: skeins not integer ({skeins})")
                            
                            # Verify skeins within reasonable range (±1 for rounding differences)
                            if abs(skeins - expected_skeins) > 1:
                                costs_correct = False
                                cost_errors.append(f"{yarn['name']}: skeins {skeins} vs expected {expected_skeins}")
                            
                            # Verify cost calculation (±$1 tolerance)
                            if abs(cost - expected_cost) > 1.0:
                                costs_correct = False
                                cost_errors.append(f"{yarn['name']}: cost ${cost:.2f} vs expected ${expected_cost:.2f}")
                        
                        except (ValueError, TypeError):
                            costs_correct = False
                            cost_errors.append(f"{yarn['name']}: invalid values")
            
            except (ValueError, TypeError):
                costs_correct = False
                cost_errors.append("Invalid adjusted yardage")
        else:
            costs_correct = False
            cost_errors.append("Missing adjusted yardage")
        
        if costs_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Cost calculations accurate for all yarn options")
        else:
            feedback_parts.append(f"❌ Cost calculation errors: {'; '.join(cost_errors[:2])}")
        
        subscores['costs_accurate'] = costs_correct

        # ===== Criterion 4: Best Option Identified =====
        best_option_correct = False
        
        # Get all three costs
        costs = []
        for col in ['B9', 'C9', 'D9']:
            val = get_cell_value(workbook, calc_sheet, col)
            if val:
                try:
                    costs.append(float(val))
                except (ValueError, TypeError):
                    costs.append(float('inf'))
            else:
                costs.append(float('inf'))
        
        if costs and min(costs) < float('inf'):
            min_cost = min(costs)
            min_idx = costs.index(min_cost)
            best_yarn = yarn_data[min_idx]['name']
            
            # Check shopping list section for best option
            # Look for yarn name in cells around B12-B16
            shopping_list_cells = ['B12', 'B13', 'C12', 'C13', 'B14', 'C14']
            found_best = False
            
            for cell in shopping_list_cells:
                val = get_cell_value(workbook, calc_sheet, cell)
                if val and best_yarn.lower() in str(val).lower():
                    found_best = True
                    break
            
            if found_best:
                criteria_passed += 1
                best_option_correct = True
                feedback_parts.append(f"✅ Best option identified: {best_yarn} (${min_cost:.2f})")
            else:
                feedback_parts.append(f"❌ Shopping list doesn't show best option ({best_yarn})")
        else:
            feedback_parts.append("❌ Unable to determine best option (costs missing)")
        
        subscores['best_option_identified'] = best_option_correct

        # ===== Criterion 5: Cross-sheet References =====
        cross_sheet_refs = False
        
        # Check formulas for sheet references
        check_cells = ['B4', 'B5', 'B8', 'C8', 'D8', 'B9', 'C9', 'D9']
        referenced_sheets = set()
        
        for cell in check_cells:
            formula = get_cell_formula(workbook, calc_sheet, cell)
            if formula:
                sheets = extract_sheet_reference(formula)
                referenced_sheets.update(sheets)
        
        # Should reference Pattern_Specs and Yarn_Options
        has_pattern = any('pattern' in s.lower() for s in referenced_sheets)
        has_yarn = any('yarn' in s.lower() for s in referenced_sheets)
        
        if has_pattern and has_yarn:
            criteria_passed += 1
            cross_sheet_refs = True
            feedback_parts.append(f"✅ Cross-sheet formulas used: {', '.join(referenced_sheets)}")
        elif has_pattern or has_yarn:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Partial cross-sheet references: {', '.join(referenced_sheets)}")
        else:
            feedback_parts.append("❌ No cross-sheet references detected")
        
        subscores['cross_sheet_formulas'] = cross_sheet_refs

        # ===== Criterion 6: Proper Formatting =====
        formatting_correct = False
        formatting_issues = []
        
        # Check that skeins are integers
        skeins_are_integers = True
        for col in ['B8', 'C8', 'D8']:
            val = get_cell_value(workbook, calc_sheet, col)
            if val:
                try:
                    if float(val) != int(float(val)):
                        skeins_are_integers = False
                        formatting_issues.append(f"{col} not integer")
                except (ValueError, TypeError):
                    pass
        
        # Check formulas exist (not just hardcoded values)
        has_formulas = False
        formula_count = 0
        for cell in ['B4', 'B5', 'B8', 'C8', 'D8', 'B9', 'C9', 'D9']:
            formula = get_cell_formula(workbook, calc_sheet, cell)
            if formula:
                formula_count += 1
        
        if formula_count >= 6:  # At least 6 formulas expected
            has_formulas = True
        else:
            formatting_issues.append(f"Only {formula_count} formulas found (expected 8+)")
        
        if skeins_are_integers and has_formulas:
            criteria_passed += 1
            formatting_correct = True
            feedback_parts.append("✅ Proper formatting: integers for skeins, formulas used")
        else:
            feedback_parts.append(f"❌ Formatting issues: {'; '.join(formatting_issues)}")
        
        subscores['proper_formatting'] = formatting_correct

        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75

        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent yarn calculator!")
        elif passed:
            feedback_parts.insert(0, "✅ Yarn calculator completed")
        else:
            feedback_parts.insert(0, "❌ Yarn calculator incomplete or incorrect")

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
