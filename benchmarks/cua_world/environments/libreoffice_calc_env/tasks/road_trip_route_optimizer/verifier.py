#!/usr/bin/env python3
"""
Verifier for Road Trip Route Optimizer task
"""

import sys
import os
import logging

# Add utils to path using relative path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants for calculations
MPG = 25
GAS_PRICE = 3.80  # $/gallon
AVG_SPEED = 60    # mph

# Route data (miles for each leg)
ROUTE_MILES = [173, 285, 90, 130, 185, 155, 410, 280]

# Tolerances
FUEL_COST_TOLERANCE = 0.10  # $0.10
DRIVE_TIME_TOLERANCE = 0.05  # 0.05 hours (3 minutes)
TOTAL_TOLERANCE = 0.50  # $0.50 for totals


def expected_fuel_cost(miles):
    """Calculate expected fuel cost for given miles"""
    return (miles / MPG) * GAS_PRICE


def expected_drive_time(miles):
    """Calculate expected drive time for given miles"""
    return miles / AVG_SPEED


def expected_cumulative_miles(leg_miles_list, current_index):
    """Calculate expected cumulative miles up to current index"""
    return sum(leg_miles_list[:current_index + 1])


def verify_road_trip_optimizer(traj, env_info, task_info):
    """
    Verify road trip route optimizer task completion.
    
    Checks:
    1. Formulas present (not hardcoded values)
    2. Fuel costs calculated correctly for all legs
    3. Drive times calculated correctly for all legs
    4. Cumulative miles calculated correctly
    5. Totals calculated correctly using SUM
    6. Proper formatting applied
    7. No formula errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/road_trip_plan.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]

        criteria_scores = {
            'formulas_present': 0,
            'fuel_cost_accurate': 0,
            'drive_time_accurate': 0,
            'cumulative_miles_correct': 0,
            'totals_accurate': 0,
            'proper_formatting': 0,
            'no_errors': 0
        }
        
        feedback_parts = []
        
        # Starting row for data (row 4 in 1-indexed, row 3 in 0-indexed)
        data_start_row = 4
        
        # Criterion 1 & 2: Check Fuel Cost formulas and accuracy
        fuel_cost_formulas_count = 0
        fuel_cost_correct_count = 0
        fuel_cost_errors = []
        
        for i, miles in enumerate(ROUTE_MILES):
            row_num = data_start_row + i
            cell_ref = f"D{row_num}"
            
            value = get_cell_value(workbook, sheet_name, cell_ref)
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            
            # Check if formula exists
            if formula:
                fuel_cost_formulas_count += 1
            
            # Check accuracy
            if value is not None:
                try:
                    actual_cost = float(value)
                    expected_cost = expected_fuel_cost(miles)
                    
                    if abs(actual_cost - expected_cost) <= FUEL_COST_TOLERANCE:
                        fuel_cost_correct_count += 1
                    else:
                        fuel_cost_errors.append(
                            f"Leg {i+1}: expected ${expected_cost:.2f}, got ${actual_cost:.2f}"
                        )
                except (ValueError, TypeError):
                    fuel_cost_errors.append(f"Leg {i+1}: invalid value '{value}'")
        
        # Score fuel cost formulas (out of 20 points)
        if fuel_cost_formulas_count >= 7:  # At least 7 of 8 have formulas
            criteria_scores['formulas_present'] += 10
        elif fuel_cost_formulas_count >= 5:
            criteria_scores['formulas_present'] += 5
        
        # Score fuel cost accuracy (out of 20 points)
        if fuel_cost_correct_count == 8:
            criteria_scores['fuel_cost_accurate'] = 20
            feedback_parts.append("✅ Fuel costs: All 8 legs calculated correctly")
        elif fuel_cost_correct_count >= 6:
            criteria_scores['fuel_cost_accurate'] = 15
            feedback_parts.append(f"✅ Fuel costs: {fuel_cost_correct_count}/8 correct")
        elif fuel_cost_correct_count >= 4:
            criteria_scores['fuel_cost_accurate'] = 10
            feedback_parts.append(f"⚠️ Fuel costs: {fuel_cost_correct_count}/8 correct")
        else:
            feedback_parts.append(f"❌ Fuel costs: Only {fuel_cost_correct_count}/8 correct")
            if fuel_cost_errors:
                feedback_parts.append(f"   Errors: {fuel_cost_errors[0]}")
        
        # Criterion 3: Check Drive Time formulas and accuracy
        drive_time_formulas_count = 0
        drive_time_correct_count = 0
        drive_time_errors = []
        
        for i, miles in enumerate(ROUTE_MILES):
            row_num = data_start_row + i
            cell_ref = f"E{row_num}"
            
            value = get_cell_value(workbook, sheet_name, cell_ref)
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            
            # Check if formula exists
            if formula:
                drive_time_formulas_count += 1
            
            # Check accuracy
            if value is not None:
                try:
                    actual_time = float(value)
                    expected_time = expected_drive_time(miles)
                    
                    if abs(actual_time - expected_time) <= DRIVE_TIME_TOLERANCE:
                        drive_time_correct_count += 1
                    else:
                        drive_time_errors.append(
                            f"Leg {i+1}: expected {expected_time:.2f}hrs, got {actual_time:.2f}hrs"
                        )
                except (ValueError, TypeError):
                    drive_time_errors.append(f"Leg {i+1}: invalid value '{value}'")
        
        # Score drive time formulas (out of 10 points)
        if drive_time_formulas_count >= 7:
            criteria_scores['formulas_present'] += 10
        elif drive_time_formulas_count >= 5:
            criteria_scores['formulas_present'] += 5
        
        # Score drive time accuracy (out of 15 points)
        if drive_time_correct_count == 8:
            criteria_scores['drive_time_accurate'] = 15
            feedback_parts.append("✅ Drive times: All 8 legs calculated correctly")
        elif drive_time_correct_count >= 6:
            criteria_scores['drive_time_accurate'] = 10
            feedback_parts.append(f"✅ Drive times: {drive_time_correct_count}/8 correct")
        elif drive_time_correct_count >= 4:
            criteria_scores['drive_time_accurate'] = 7
            feedback_parts.append(f"⚠️ Drive times: {drive_time_correct_count}/8 correct")
        else:
            feedback_parts.append(f"❌ Drive times: Only {drive_time_correct_count}/8 correct")
        
        # Criterion 4: Check Cumulative Miles
        cumulative_formulas_count = 0
        cumulative_correct_count = 0
        
        for i in range(len(ROUTE_MILES)):
            row_num = data_start_row + i
            cell_ref = f"F{row_num}"
            
            value = get_cell_value(workbook, sheet_name, cell_ref)
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            
            if formula:
                cumulative_formulas_count += 1
            
            if value is not None:
                try:
                    actual_cumulative = float(value)
                    expected_cumulative = expected_cumulative_miles(ROUTE_MILES, i)
                    
                    if abs(actual_cumulative - expected_cumulative) <= 1:  # Allow 1 mile tolerance
                        cumulative_correct_count += 1
                except (ValueError, TypeError):
                    pass
        
        # Score cumulative miles (out of 20 points)
        if cumulative_correct_count == 8 and cumulative_formulas_count >= 7:
            criteria_scores['cumulative_miles_correct'] = 20
            feedback_parts.append("✅ Cumulative miles: All correct with formulas")
        elif cumulative_correct_count >= 6:
            criteria_scores['cumulative_miles_correct'] = 15
            feedback_parts.append(f"✅ Cumulative miles: {cumulative_correct_count}/8 correct")
        elif cumulative_correct_count >= 4:
            criteria_scores['cumulative_miles_correct'] = 10
            feedback_parts.append(f"⚠️ Cumulative miles: {cumulative_correct_count}/8 correct")
        else:
            feedback_parts.append(f"❌ Cumulative miles: Only {cumulative_correct_count}/8 correct")
        
        # Criterion 5: Check Totals (row 13)
        total_fuel_value = get_cell_value(workbook, sheet_name, 'D13')
        total_fuel_formula = get_cell_formula(workbook, sheet_name, 'D13')
        
        total_time_value = get_cell_value(workbook, sheet_name, 'E13')
        total_time_formula = get_cell_formula(workbook, sheet_name, 'E13')
        
        totals_correct = 0
        
        # Check total fuel cost
        if total_fuel_formula and 'SUM' in total_fuel_formula.upper():
            if total_fuel_value is not None:
                try:
                    actual_total_fuel = float(total_fuel_value)
                    expected_total_fuel = sum(expected_fuel_cost(m) for m in ROUTE_MILES)
                    
                    if abs(actual_total_fuel - expected_total_fuel) <= TOTAL_TOLERANCE:
                        totals_correct += 1
                        feedback_parts.append(f"✅ Total fuel cost: ${actual_total_fuel:.2f} (correct)")
                    else:
                        feedback_parts.append(f"⚠️ Total fuel cost: ${actual_total_fuel:.2f} (expected ~${expected_total_fuel:.2f})")
                except (ValueError, TypeError):
                    feedback_parts.append("❌ Total fuel cost: invalid value")
        else:
            feedback_parts.append("❌ Total fuel cost: missing SUM formula")
        
        # Check total drive time
        if total_time_formula and 'SUM' in total_time_formula.upper():
            if total_time_value is not None:
                try:
                    actual_total_time = float(total_time_value)
                    expected_total_time = sum(expected_drive_time(m) for m in ROUTE_MILES)
                    
                    if abs(actual_total_time - expected_total_time) <= TOTAL_TOLERANCE:
                        totals_correct += 1
                        feedback_parts.append(f"✅ Total drive time: {actual_total_time:.1f}hrs (correct)")
                    else:
                        feedback_parts.append(f"⚠️ Total drive time: {actual_total_time:.1f}hrs (expected ~{expected_total_time:.1f}hrs)")
                except (ValueError, TypeError):
                    feedback_parts.append("❌ Total drive time: invalid value")
        else:
            feedback_parts.append("❌ Total drive time: missing SUM formula")
        
        # Score totals (out of 15 points)
        if totals_correct == 2:
            criteria_scores['totals_accurate'] = 15
        elif totals_correct == 1:
            criteria_scores['totals_accurate'] = 8
        
        # Criterion 6: Check for formula errors
        error_found = False
        for i in range(len(ROUTE_MILES)):
            row_num = data_start_row + i
            for col in ['D', 'E', 'F']:
                cell_ref = f"{col}{row_num}"
                value = get_cell_value(workbook, sheet_name, cell_ref)
                if value and isinstance(value, str) and ('#REF' in value or '#VALUE' in value or '#DIV' in value or '#NAME' in value):
                    error_found = True
                    feedback_parts.append(f"❌ Formula error in {cell_ref}: {value}")
                    break
            if error_found:
                break
        
        # Score no errors (out of 10 points)
        if not error_found:
            criteria_scores['no_errors'] = 10
            feedback_parts.append("✅ No formula errors detected")
        
        # Criterion 7: Overall formula presence (already scored above)
        if criteria_scores['formulas_present'] >= 15:
            feedback_parts.append("✅ Formulas present (not hardcoded)")
        else:
            feedback_parts.append("⚠️ Some values may be hardcoded instead of formulas")
        
        # Calculate final score (out of 100)
        total_score = sum(criteria_scores.values())
        score = min(100, total_score)
        passed = score >= 85
        
        # Add summary
        if passed:
            expected_total_fuel = sum(expected_fuel_cost(m) for m in ROUTE_MILES)
            expected_total_time = sum(expected_drive_time(m) for m in ROUTE_MILES)
            feedback_parts.insert(0, f"✅ TASK COMPLETE! Trip: ${expected_total_fuel:.0f} fuel, {expected_total_time:.1f}hrs")
        else:
            feedback_parts.insert(0, "❌ Task incomplete - check formulas and calculations")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "formulas_present": criteria_scores['formulas_present'] >= 15,
                "fuel_cost_accurate": fuel_cost_correct_count >= 7,
                "drive_time_accurate": drive_time_correct_count >= 7,
                "cumulative_miles_correct": cumulative_correct_count >= 7,
                "totals_accurate": totals_correct == 2,
                "no_errors": not error_found
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
