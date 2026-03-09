#!/usr/bin/env python3
"""
Verifier for Road Trip Planner task.
Checks route data, formulas, calculations, and formatting.
"""

import sys
import os
import logging
import zipfile
from xml.etree import ElementTree as ET

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    verify_cell_value,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected route data
EXPECTED_DISTANCES = [420, 210, 135, 315, 195]
EXPECTED_CUMULATIVE = [420, 630, 765, 1080, 1275]

# Reference values
GAS_PRICE = 3.45
MPG = 28.0
AVG_SPEED = 60.0

# Tolerance for numeric comparisons
FUEL_TOLERANCE = 0.5
COST_TOLERANCE = 0.50
TIME_TOLERANCE = 0.1
DISTANCE_TOLERANCE = 5


def calculate_expected_values():
    """Calculate expected values for verification"""
    expected = []
    for dist in EXPECTED_DISTANCES:
        fuel = dist / MPG
        cost = fuel * GAS_PRICE
        time = dist / AVG_SPEED
        expected.append({
            'fuel': fuel,
            'cost': cost,
            'time': time
        })
    return expected


def verify_road_trip_planner(traj, env_info, task_info):
    """
    Verify road trip planner task completion.
    
    Checks:
    1. Route data entered correctly
    2. Formulas present for cumulative distance, fuel, cost, time
    3. Calculations are accurate
    4. Totals row exists and is correct
    5. Conditional formatting applied (bonus)
    6. Professional formatting (bonus)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    success = False
    temp_dir = None
    for path in [
        "/home/ga/Documents/road_trip_planner_result.ods",
        "/home/ga/Documents/road_trip_template.ods",
        "/home/ga/Documents/road_trip.ods"
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format='ods'
        )
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_scores = {}
        feedback_parts = []
        
        expected_values = calculate_expected_values()
        
        # ===== CRITERION 1: Route Data Complete (15 points) =====
        route_data_correct = True
        for i, expected_dist in enumerate(EXPECTED_DISTANCES, start=2):
            cell_ref = f"C{i}"
            actual = get_cell_value(workbook, sheet_name, cell_ref)
            if actual is None or abs(float(actual) - expected_dist) > DISTANCE_TOLERANCE:
                route_data_correct = False
                feedback_parts.append(f"❌ Distance in C{i}: expected {expected_dist}, got {actual}")
                break
        
        if route_data_correct:
            criteria_scores['route_data'] = 15
            feedback_parts.append("✅ Route data entered correctly (all 5 days)")
        else:
            criteria_scores['route_data'] = 0
            if not any("Distance" in f for f in feedback_parts):
                feedback_parts.append("❌ Route data incomplete or incorrect")
        
        # ===== CRITERION 2: Cumulative Distance Formulas (20 points) =====
        cumulative_correct = True
        cumulative_values_correct = True
        
        for i, expected_cum in enumerate(EXPECTED_CUMULATIVE, start=2):
            cell_ref = f"D{i}"
            actual = get_cell_value(workbook, sheet_name, cell_ref)
            
            if actual is None or abs(float(actual) - expected_cum) > DISTANCE_TOLERANCE:
                cumulative_values_correct = False
                feedback_parts.append(f"❌ Cumulative distance D{i}: expected {expected_cum}, got {actual}")
                break
        
        # Check if formulas exist (not just hardcoded values)
        # D2 should be =C2 or just the value
        # D3 should contain a formula like =D2+C3
        d3_formula = get_cell_formula(workbook, sheet_name, 'D3')
        if d3_formula and ('+' in d3_formula or 'SUM' in d3_formula.upper()):
            cumulative_correct = True
        else:
            cumulative_correct = False
            feedback_parts.append(f"⚠️ Cumulative formula missing in D3 (got: {d3_formula})")
        
        if cumulative_values_correct and cumulative_correct:
            criteria_scores['cumulative'] = 20
            feedback_parts.append("✅ Cumulative distance formulas correct")
        elif cumulative_values_correct:
            criteria_scores['cumulative'] = 10
            feedback_parts.append("⚠️ Cumulative values correct but formulas may be hardcoded")
        else:
            criteria_scores['cumulative'] = 0
        
        # ===== CRITERION 3: Fuel Calculations (20 points) =====
        fuel_correct = True
        fuel_formula_correct = False
        
        for i, expected in enumerate(expected_values, start=2):
            cell_ref = f"E{i}"
            actual = get_cell_value(workbook, sheet_name, cell_ref)
            
            if actual is None or abs(float(actual) - expected['fuel']) > FUEL_TOLERANCE:
                fuel_correct = False
                feedback_parts.append(f"❌ Fuel calculation E{i}: expected {expected['fuel']:.2f}, got {actual}")
                break
        
        # Check formula in E2
        e2_formula = get_cell_formula(workbook, sheet_name, 'E2')
        if e2_formula and ('J3' in e2_formula or '$J$3' in e2_formula):
            fuel_formula_correct = True
        
        if fuel_correct and fuel_formula_correct:
            criteria_scores['fuel'] = 20
            feedback_parts.append("✅ Fuel calculations correct with proper formula")
        elif fuel_correct:
            criteria_scores['fuel'] = 12
            feedback_parts.append("⚠️ Fuel values correct but formula may not use absolute reference")
        else:
            criteria_scores['fuel'] = 0
        
        # ===== CRITERION 4: Cost Calculations (20 points) =====
        cost_correct = True
        cost_formula_correct = False
        
        for i, expected in enumerate(expected_values, start=2):
            cell_ref = f"F{i}"
            actual = get_cell_value(workbook, sheet_name, cell_ref)
            
            if actual is None or abs(float(actual) - expected['cost']) > COST_TOLERANCE:
                cost_correct = False
                feedback_parts.append(f"❌ Cost calculation F{i}: expected ${expected['cost']:.2f}, got {actual}")
                break
        
        # Check formula in F2
        f2_formula = get_cell_formula(workbook, sheet_name, 'F2')
        if f2_formula and ('J2' in f2_formula or '$J$2' in f2_formula):
            cost_formula_correct = True
        
        if cost_correct and cost_formula_correct:
            criteria_scores['cost'] = 20
            feedback_parts.append("✅ Cost calculations correct with proper formula")
        elif cost_correct:
            criteria_scores['cost'] = 12
            feedback_parts.append("⚠️ Cost values correct but formula may not use absolute reference")
        else:
            criteria_scores['cost'] = 0
        
        # ===== CRITERION 5: Time Calculations (15 points) =====
        time_correct = True
        
        for i, expected in enumerate(expected_values, start=2):
            cell_ref = f"G{i}"
            actual = get_cell_value(workbook, sheet_name, cell_ref)
            
            if actual is None or abs(float(actual) - expected['time']) > TIME_TOLERANCE:
                time_correct = False
                feedback_parts.append(f"❌ Time calculation G{i}: expected {expected['time']:.2f} hrs, got {actual}")
                break
        
        if time_correct:
            criteria_scores['time'] = 15
            feedback_parts.append("✅ Driving time calculations correct")
        else:
            criteria_scores['time'] = 0
        
        # ===== CRITERION 6: Totals Row (10 points) =====
        totals_correct = 0
        max_totals_points = 10
        
        # Check D7 (final cumulative)
        d7_value = get_cell_value(workbook, sheet_name, 'D7')
        if d7_value and abs(float(d7_value) - 1275) < DISTANCE_TOLERANCE:
            totals_correct += 2.5
        
        # Check E7 (total fuel)
        total_fuel = sum(exp['fuel'] for exp in expected_values)
        e7_value = get_cell_value(workbook, sheet_name, 'E7')
        e7_formula = get_cell_formula(workbook, sheet_name, 'E7')
        if e7_value and abs(float(e7_value) - total_fuel) < FUEL_TOLERANCE:
            totals_correct += 2.5
        if e7_formula and 'SUM' in e7_formula.upper():
            totals_correct += 2.5
        
        # Check F7 (total cost)
        total_cost = sum(exp['cost'] for exp in expected_values)
        f7_value = get_cell_value(workbook, sheet_name, 'F7')
        f7_formula = get_cell_formula(workbook, sheet_name, 'F7')
        if f7_value and abs(float(f7_value) - total_cost) < COST_TOLERANCE:
            totals_correct += 2.5
        
        criteria_scores['totals'] = totals_correct
        if totals_correct >= 7:
            feedback_parts.append("✅ Totals row complete and correct")
        elif totals_correct > 0:
            feedback_parts.append(f"⚠️ Totals row partially correct ({totals_correct}/{max_totals_points} points)")
        else:
            feedback_parts.append("❌ Totals row missing or incorrect")
        
        # ===== BONUS: Conditional Formatting (5 points) =====
        # Check if conditional formatting exists (this is a bonus, not required for passing)
        try:
            has_cond_format = check_conditional_formatting(workbook, sheet_name, "G2:G6")
            if has_cond_format:
                criteria_scores['conditional_format'] = 5
                feedback_parts.append("🌟 Bonus: Conditional formatting applied")
            else:
                criteria_scores['conditional_format'] = 0
        except:
            criteria_scores['conditional_format'] = 0
        
        # ===== Calculate Final Score =====
        # Core criteria: 100 points (route data, cumulative, fuel, cost, time, totals)
        # Bonus: 5 points (conditional formatting)
        total_score = sum(criteria_scores.values())
        max_core_score = 100
        
        # Normalize to 100 scale
        score = min(100, int((total_score / max_core_score) * 100))
        passed = score >= 75
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent road trip planner!")
        elif passed:
            feedback_parts.insert(0, "✅ Road trip planner completed successfully")
        else:
            feedback_parts.insert(0, "❌ Road trip planner incomplete or has errors")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": criteria_scores,
            "details": {
                "route_data_correct": route_data_correct,
                "cumulative_correct": cumulative_values_correct,
                "fuel_correct": fuel_correct,
                "cost_correct": cost_correct,
                "time_correct": time_correct,
                "totals_correct": totals_correct >= 7
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_temp(temp_dir)
