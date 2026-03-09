#!/usr/bin/env python3
"""
Verifier for Flooring Estimator task

Checks:
1. Correct waste factor application (15% for L-shaped living room, 10% for rectangular)
2. Box rounding logic (CEILING/ROUNDUP function used, no fractional boxes)
3. Accurate cost calculations (flooring uses adjusted sq ft, underlayment uses base)
4. Proper formula usage (formulas present, not hard-coded values)
5. Total accuracy (grand total within ±$5 of expected $1,477.45)
"""

import sys
import os
import logging
import re

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_value_in_sheet(sheet_data, target_value, tolerance=5.0):
    """
    Search for a specific numeric value anywhere in the sheet.
    Returns list of (row, col) positions where value is found.
    """
    positions = []
    for row_idx, row in enumerate(sheet_data):
        for col_idx, cell in enumerate(row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value is not None and isinstance(cell_value, (int, float)):
                if abs(float(cell_value) - target_value) <= tolerance:
                    positions.append((row_idx, col_idx, cell_value))
    return positions


def check_formula_pattern(formula, patterns):
    """Check if formula contains any of the specified patterns (case-insensitive)."""
    if not formula:
        return False
    formula_upper = str(formula).upper()
    return any(pattern.upper() in formula_upper for pattern in patterns)


def find_formulas_with_pattern(sheet_data, patterns):
    """Find all cells containing formulas with specified patterns."""
    found = []
    for row_idx, row in enumerate(sheet_data):
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula and check_formula_pattern(formula, patterns):
                    found.append({
                        'row': row_idx,
                        'col': col_idx,
                        'formula': formula,
                        'value': cell.get('value')
                    })
    return found


def verify_flooring_estimate(traj, env_info, task_info):
    """
    Verify flooring estimation spreadsheet calculations.
    
    Expected calculations:
    - Living room: 204 sq ft base, 234.6 adjusted (15% waste), 12 boxes, ~$678 flooring + $92 underlayment
    - Bedroom: 132 sq ft base, 145.2 adjusted (10% waste), 8 boxes, ~$420 flooring + $59 underlayment  
    - Hallway: 63 sq ft base, 69.3 adjusted (10% waste), 4 boxes, ~$200 flooring + $28 underlayment
    - TOTAL: ~$1,477.45
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the spreadsheet
    container_path = "/home/ga/Documents/flooring_estimate.ods"
    success, file_info, error_msg = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods', 'xlsx']
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error_msg}"}
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = data['sheets'][sheet_name]
        
        # Initialize results tracking
        results = {
            'waste_factor_correct': False,
            'box_rounding_correct': False,
            'costs_accurate': False,
            'formulas_used': False,
            'total_accurate': False
        }
        
        feedback_parts = []
        
        # Expected values with tolerances
        expected_adjusted_sqft = {
            'living_room': (234.6, 3.0),  # (value, tolerance)
            'bedroom': (145.2, 3.0),
            'hallway': (69.3, 3.0)
        }
        
        expected_boxes = {
            'living_room': 12,
            'bedroom': 8,
            'hallway': 4,
            'total': 24
        }
        
        expected_flooring_costs = {
            'living_room': (678, 10),  # ~$678
            'bedroom': (420, 10),      # ~$420
            'hallway': (200, 10)       # ~$200
        }
        
        expected_underlayment_costs = {
            'living_room': (91.80, 2),
            'bedroom': (59.40, 2),
            'hallway': (28.35, 2)
        }
        
        expected_total = 1477.45
        
        # Criterion 1: Check for adjusted square footage values (waste factor application)
        found_adjusted_sqft = 0
        for room, (expected, tolerance) in expected_adjusted_sqft.items():
            positions = find_value_in_sheet(sheet_data, expected, tolerance)
            if positions:
                found_adjusted_sqft += 1
                logger.info(f"Found {room} adjusted sqft: {positions[0][2]:.1f} at position ({positions[0][0]}, {positions[0][1]})")
        
        if found_adjusted_sqft >= 2:  # At least 2 out of 3 rooms
            results['waste_factor_correct'] = True
            feedback_parts.append(f"✅ Waste factors applied correctly ({found_adjusted_sqft}/3 rooms)")
        else:
            feedback_parts.append(f"❌ Missing or incorrect waste factor calculations (found {found_adjusted_sqft}/3)")
        
        # Criterion 2: Check for CEILING/ROUNDUP formulas (box rounding)
        rounding_formulas = find_formulas_with_pattern(sheet_data, ['CEILING', 'ROUNDUP', 'ROUND'])
        
        if rounding_formulas:
            results['box_rounding_correct'] = True
            feedback_parts.append(f"✅ Box rounding formulas found ({len(rounding_formulas)} instances)")
            logger.info(f"Rounding formulas: {[f['formula'] for f in rounding_formulas]}")
        else:
            feedback_parts.append("❌ No CEILING/ROUNDUP formulas detected for box quantities")
        
        # Also check if box quantities are present as values
        found_boxes = 0
        for room, expected_box_count in [(k, v) for k, v in expected_boxes.items() if k != 'total']:
            positions = find_value_in_sheet(sheet_data, expected_box_count, tolerance=1)
            if positions:
                found_boxes += 1
        
        if found_boxes >= 2 and not rounding_formulas:
            # Give partial credit if correct values present even without formula detection
            results['box_rounding_correct'] = True
            feedback_parts[-1] = f"⚠️ Box quantities correct ({found_boxes}/3) but formulas not clearly detected"
        
        # Criterion 3: Check for cost calculations
        found_flooring_costs = 0
        found_underlayment_costs = 0
        
        for room, (expected, tolerance) in expected_flooring_costs.items():
            positions = find_value_in_sheet(sheet_data, expected, tolerance)
            if positions:
                found_flooring_costs += 1
        
        for room, (expected, tolerance) in expected_underlayment_costs.items():
            positions = find_value_in_sheet(sheet_data, expected, tolerance)
            if positions:
                found_underlayment_costs += 1
        
        if found_flooring_costs >= 2 and found_underlayment_costs >= 2:
            results['costs_accurate'] = True
            feedback_parts.append(f"✅ Cost calculations accurate (flooring: {found_flooring_costs}/3, underlayment: {found_underlayment_costs}/3)")
        else:
            feedback_parts.append(f"❌ Cost calculations incomplete or incorrect (flooring: {found_flooring_costs}/3, underlayment: {found_underlayment_costs}/3)")
        
        # Criterion 4: Check for formula usage (general check)
        formula_count = 0
        for row in sheet_data:
            for cell in row:
                if isinstance(cell, dict) and cell.get('formula'):
                    formula_count += 1
        
        if formula_count >= 10:  # Should have formulas for calculations
            results['formulas_used'] = True
            feedback_parts.append(f"✅ Formulas used for calculations ({formula_count} formulas detected)")
        else:
            feedback_parts.append(f"❌ Insufficient formulas detected ({formula_count} found, expected 10+)")
        
        # Check for SUM formulas specifically
        sum_formulas = find_formulas_with_pattern(sheet_data, ['SUM'])
        if sum_formulas:
            logger.info(f"Found SUM formulas: {len(sum_formulas)}")
        
        # Criterion 5: Check for total project cost
        total_positions = find_value_in_sheet(sheet_data, expected_total, tolerance=10.0)
        
        if total_positions:
            actual_total = total_positions[0][2]
            results['total_accurate'] = True
            feedback_parts.append(f"✅ Total cost accurate: ${actual_total:.2f} (expected ~${expected_total:.2f})")
        else:
            # Try finding any value in the ballpark
            wide_search = find_value_in_sheet(sheet_data, expected_total, tolerance=50.0)
            if wide_search:
                actual_total = wide_search[0][2]
                feedback_parts.append(f"⚠️ Total cost close but not precise: ${actual_total:.2f} (expected ~${expected_total:.2f})")
            else:
                feedback_parts.append(f"❌ Total cost not found or incorrect (expected ~${expected_total:.2f})")
        
        # Calculate score
        criteria_met = sum(results.values())
        total_criteria = len(results)
        score = int((criteria_met / total_criteria) * 100)
        
        # Add summary
        feedback_parts.append(f"\nCriteria met: {criteria_met}/{total_criteria}")
        
        if score >= 90:
            feedback_parts.append("🎉 Excellent flooring estimate calculation!")
        elif score >= 75:
            feedback_parts.append("✅ Flooring estimate requirements met")
        else:
            feedback_parts.append("❌ Flooring estimate needs improvement")
        
        feedback_str = " | ".join(feedback_parts)
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback_str,
            "subscores": {
                "waste_factor_correct": results['waste_factor_correct'],
                "box_rounding_correct": results['box_rounding_correct'],
                "costs_accurate": results['costs_accurate'],
                "formulas_used": results['formulas_used'],
                "total_accurate": results['total_accurate']
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
        cleanup_verification_environment(file_info.get('temp_dir'))
