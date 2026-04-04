#!/usr/bin/env python3
"""
Verifier for Bathroom Renovation Materials Calculator task
"""

import sys
import os
import logging
import math

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def convert_to_sqft(length, width, unit):
    """Convert measurements to square feet"""
    if unit == "decimal ft":
        return length * width
    elif unit == "cm":
        # Convert cm to feet: 1 cm = 1/30.48 feet
        length_ft = length / 30.48
        width_ft = width / 30.48
        return length_ft * width_ft
    else:
        return None


def verify_bathroom_reno_materials(traj, env_info, task_info):
    """
    Verify bathroom renovation materials calculator task.
    
    Checks:
    1. Area calculations correct (with unit conversion)
    2. Waste factors filled in appropriately
    3. Adjusted quantities calculated correctly
    4. Package rounding uses ROUNDUP
    5. Total costs calculated correctly
    6. Budget flags accurate
    7. Grand total correct
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/bathroom_reno_materials.ods"
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
        
        # Expected data (from setup)
        items = [
            {"name": "Floor Tile (Porcelain)", "length": 5.25, "width": 4.67, "unit": "decimal ft", 
             "waste_given": None, "coverage": 12, "price": 42.99, "budget": 500},
            {"name": "Wall Tile (Subway)", "length": 8.5, "width": 6.25, "unit": "decimal ft", 
             "waste_given": 10, "coverage": 11, "price": 38.50, "budget": 400},
            {"name": "Waterproof Membrane", "length": 160, "width": 142, "unit": "cm", 
             "waste_given": None, "coverage": 107.64, "price": 89.99, "budget": 200},
            {"name": "Paint (Waterproof)", "length": 8, "width": 6, "unit": "decimal ft", 
             "waste_given": 5, "coverage": 350, "price": 31.99, "budget": 100},
            {"name": "Tile Adhesive", "length": 5.25, "width": 4.75, "unit": "decimal ft", 
             "waste_given": None, "coverage": 50, "price": 28.50, "budget": 150},
            {"name": "Grout", "length": 5.25, "width": 4.75, "unit": "decimal ft", 
             "waste_given": 10, "coverage": 100, "price": 19.99, "budget": 150}
        ]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        area_correct_count = 0
        waste_filled_count = 0
        adjusted_correct_count = 0
        packages_correct_count = 0
        cost_correct_count = 0
        budget_flag_correct_count = 0
        
        calculated_total = 0
        
        # Check each row
        for i, item in enumerate(items, start=2):  # Start from row 2 (row 1 is header)
            row_num = i
            
            # Column mapping: I=Area, J=Adjusted, K=Packages, L=Cost, M=Status
            # Area Sq Ft (column I)
            area_cell = get_cell_value(workbook, sheet_name, f'I{row_num}')
            expected_area = convert_to_sqft(item['length'], item['width'], item['unit'])
            
            if area_cell and expected_area:
                try:
                    area_value = float(area_cell)
                    if abs(area_value - expected_area) < 0.2:  # Tolerance for rounding
                        area_correct_count += 1
                except (ValueError, TypeError):
                    pass
            
            # Waste Factor (column E) - check if filled for blanks
            waste_cell = get_cell_value(workbook, sheet_name, f'E{row_num}')
            waste_value = None
            if waste_cell:
                try:
                    waste_value = float(waste_cell)
                    if item['waste_given'] is None:
                        # This was blank, check if filled with reasonable value (5-20%)
                        if 5 <= waste_value <= 20:
                            waste_filled_count += 1
                    else:
                        # Was already provided, just use it
                        waste_filled_count += 1
                except (ValueError, TypeError):
                    pass
            elif item['waste_given'] is not None:
                # Original value might still be there
                waste_value = item['waste_given']
                waste_filled_count += 1
            
            # Adjusted Sq Ft (column J)
            adjusted_cell = get_cell_value(workbook, sheet_name, f'J{row_num}')
            if adjusted_cell and area_cell and waste_value is not None:
                try:
                    adjusted_value = float(adjusted_cell)
                    area_val = float(area_cell)
                    expected_adjusted = area_val * (1 + waste_value / 100)
                    if abs(adjusted_value - expected_adjusted) < 0.5:
                        adjusted_correct_count += 1
                except (ValueError, TypeError):
                    pass
            
            # Packages Needed (column K)
            packages_cell = get_cell_value(workbook, sheet_name, f'K{row_num}')
            packages_formula = get_cell_formula(workbook, sheet_name, f'K{row_num}')
            
            if packages_cell and adjusted_cell:
                try:
                    packages_value = float(packages_cell)
                    adjusted_val = float(adjusted_cell)
                    expected_packages = math.ceil(adjusted_val / item['coverage'])
                    
                    # Check if ROUNDUP is used and result is correct
                    roundup_used = packages_formula and 'ROUNDUP' in packages_formula.upper()
                    correct_value = packages_value == expected_packages
                    
                    if roundup_used and correct_value:
                        packages_correct_count += 1
                    elif correct_value:
                        # Correct value but might not have used ROUNDUP
                        packages_correct_count += 0.5
                except (ValueError, TypeError):
                    pass
            
            # Total Cost (column L)
            cost_cell = get_cell_value(workbook, sheet_name, f'L{row_num}')
            if cost_cell and packages_cell:
                try:
                    cost_value = float(cost_cell)
                    packages_val = float(packages_cell)
                    expected_cost = packages_val * item['price']
                    if abs(cost_value - expected_cost) < 0.5:
                        cost_correct_count += 1
                        calculated_total += cost_value
                except (ValueError, TypeError):
                    pass
            
            # Budget Status (column M)
            status_cell = get_cell_value(workbook, sheet_name, f'M{row_num}')
            if status_cell and cost_cell:
                try:
                    cost_val = float(cost_cell)
                    status_str = str(status_cell).lower()
                    
                    if cost_val > item['budget']:
                        # Should be flagged as over budget
                        if 'over' in status_str or 'exceed' in status_str:
                            budget_flag_correct_count += 1
                    else:
                        # Should be OK
                        if 'ok' in status_str or status_str == '' or 'within' in status_str:
                            budget_flag_correct_count += 1
                except (ValueError, TypeError):
                    pass
        
        # Criterion 1: Area calculations (at least 5/6 correct)
        if area_correct_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Area calculations correct ({area_correct_count}/6 items)")
        else:
            feedback_parts.append(f"❌ Area calculations incomplete ({area_correct_count}/6 correct)")
        
        # Criterion 2: Waste factors filled (at least 2/3 blanks filled appropriately)
        blanks_to_fill = 3  # Floor Tile, Membrane, Adhesive
        if waste_filled_count >= 5:  # All 6 items should have waste factors now
            criteria_passed += 1
            feedback_parts.append(f"✅ Waste factors filled appropriately")
        else:
            feedback_parts.append(f"❌ Waste factors missing or incorrect ({waste_filled_count}/6)")
        
        # Criterion 3: Adjusted quantities (at least 5/6 correct)
        if adjusted_correct_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Adjusted quantities calculated correctly ({adjusted_correct_count}/6)")
        else:
            feedback_parts.append(f"❌ Adjusted quantities incorrect ({adjusted_correct_count}/6)")
        
        # Criterion 4: Package rounding (at least 5/6 correct)
        if packages_correct_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Package rounding correct ({int(packages_correct_count)}/6)")
        else:
            feedback_parts.append(f"❌ Package rounding incorrect ({int(packages_correct_count)}/6)")
        
        # Criterion 5: Total costs (at least 5/6 correct)
        if cost_correct_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Total costs calculated correctly ({cost_correct_count}/6)")
        else:
            feedback_parts.append(f"❌ Total costs incorrect ({cost_correct_count}/6)")
        
        # Criterion 6: Budget flags (at least 5/6 correct)
        if budget_flag_correct_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Budget flags accurate ({budget_flag_correct_count}/6)")
        else:
            feedback_parts.append(f"❌ Budget flags incorrect ({budget_flag_correct_count}/6)")
        
        # Criterion 7: Grand total
        # Look for grand total in rows 9-12, any column with SUM formula or value close to calculated_total
        grand_total_found = False
        for row in range(9, 13):
            for col in ['L', 'M', 'A', 'B']:
                total_cell = get_cell_value(workbook, sheet_name, f'{col}{row}')
                if total_cell:
                    try:
                        total_val = float(total_cell)
                        if abs(total_val - calculated_total) < 1.0:
                            grand_total_found = True
                            criteria_passed += 1
                            feedback_parts.append(f"✅ Grand total correct: ${total_val:.2f}")
                            break
                    except (ValueError, TypeError):
                        pass
            if grand_total_found:
                break
        
        if not grand_total_found:
            feedback_parts.append(f"❌ Grand total missing or incorrect (expected ~${calculated_total:.2f})")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 6/7 criteria
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "area_calculations": area_correct_count >= 5,
                "waste_factors_filled": waste_filled_count >= 5,
                "adjusted_quantities": adjusted_correct_count >= 5,
                "package_rounding": packages_correct_count >= 5,
                "total_costs": cost_correct_count >= 5,
                "budget_flags": budget_flag_correct_count >= 5,
                "grand_total": grand_total_found
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
