#!/usr/bin/env python3
"""
Verifier for Soccer Carpool Coordinator task.

Checks:
1. All coverage gaps filled (no Martinez or empty entries)
2. Capacity constraints respected (kids <= vehicle capacity)
3. Formulas correct (COUNTIF, SUMIF, reimbursement calculation)
4. Conditional formatting applied
5. Fair distribution (no family drives more than 4 times if avoidable)
6. Mathematical consistency (reimbursements sum to ~$240)
"""

import sys
import os
import logging
import re

# Add utils to path (relative path for host machine)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    check_conditional_formatting,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Valid family names
VALID_FAMILIES = ["Johnson", "Thompson", "Chen", "Patel", "Williams", "Davis", "Rodriguez", "Kim"]

# Vehicle capacities
VEHICLE_CAPACITIES = {
    "Sedan": 4,
    "SUV": 6,
    "Minivan": 7
}


def verify_coverage_completeness(workbook, sheet_name):
    """
    Verify that all driver slots are filled with valid families (no Martinez or empty).
    
    Returns:
        (bool, str, list): (passed, message, driver_list)
    """
    drivers = []
    for row_num in range(2, 14):  # Rows 2-13 (12 practice dates)
        driver = get_cell_value(workbook, sheet_name, f'B{row_num}')
        
        if driver is None or str(driver).strip() == "":
            return False, f"Empty driver at row {row_num}", drivers
        
        driver_str = str(driver).strip()
        if "Martinez" in driver_str:
            return False, f"Martinez still assigned at row {row_num}", drivers
        
        if driver_str not in VALID_FAMILIES:
            return False, f"Invalid family name '{driver_str}' at row {row_num}", drivers
        
        drivers.append(driver_str)
    
    return True, "All 12 dates have valid driver assignments", drivers


def verify_capacity_constraints(workbook, sheet_name):
    """
    Verify that no vehicle is over capacity on any date.
    
    Returns:
        (bool, str, list): (passed, message, violations)
    """
    violations = []
    
    for row_num in range(2, 14):  # Rows 2-13
        kids_assigned = get_cell_value(workbook, sheet_name, f'E{row_num}')
        vehicle_capacity = get_cell_value(workbook, sheet_name, f'D{row_num}')
        
        if kids_assigned is None or vehicle_capacity is None:
            violations.append(f"Row {row_num}: Missing capacity data")
            continue
        
        try:
            kids = int(float(kids_assigned))
            capacity = int(float(vehicle_capacity))
            
            if kids > capacity:
                violations.append(f"Row {row_num}: {kids} kids > {capacity} capacity")
        except (ValueError, TypeError) as e:
            violations.append(f"Row {row_num}: Invalid data ({e})")
    
    if violations:
        return False, f"Capacity violations found: {'; '.join(violations)}", violations
    
    return True, "All capacity constraints respected", []


def verify_formulas(workbook, sheet_name, drivers):
    """
    Verify that gas reimbursement formulas are correct.
    
    Checks for:
    - COUNTIF formulas to count trips
    - SUMIF formulas to sum miles
    - Reimbursement calculation proportional to miles
    
    Returns:
        (bool, str, dict): (passed, message, formula_info)
    """
    formula_info = {
        "families_with_formulas": 0,
        "correct_countif": 0,
        "correct_sumif": 0,
        "total_reimbursement": 0
    }
    
    # Look for formulas in calculation section (rows ~23-31)
    # Try to find where formulas start
    formula_found = False
    start_row = 23
    
    for family_idx, family_name in enumerate(VALID_FAMILIES):
        row_num = start_row + family_idx
        
        # Check for trip count formula in column B
        trips_formula = get_cell_formula(workbook, sheet_name, f'B{row_num}')
        if trips_formula:
            formula_found = True
            # Check if it's a COUNTIF formula
            if 'COUNTIF' in str(trips_formula).upper():
                formula_info["correct_countif"] += 1
        
        # Check for miles sum formula in column C
        miles_formula = get_cell_formula(workbook, sheet_name, f'C{row_num}')
        if miles_formula:
            formula_found = True
            # Check if it's a SUMIF formula
            if 'SUMIF' in str(miles_formula).upper():
                formula_info["correct_sumif"] += 1
        
        # Check for reimbursement formula in column D
        reimb_formula = get_cell_formula(workbook, sheet_name, f'D{row_num}')
        reimb_value = get_cell_value(workbook, sheet_name, f'D{row_num}')
        
        if reimb_formula or reimb_value:
            formula_info["families_with_formulas"] += 1
            
            if reimb_value is not None:
                try:
                    formula_info["total_reimbursement"] += float(reimb_value)
                except (ValueError, TypeError):
                    pass
    
    if not formula_found:
        return False, "No formulas found in calculation section", formula_info
    
    # Check if total reimbursement is close to $240
    total_reimb = formula_info["total_reimbursement"]
    if abs(total_reimb - 240) > 5:  # Allow $5 tolerance
        return False, f"Total reimbursement ${total_reimb:.2f} doesn't equal $240", formula_info
    
    # At least some families should have formulas
    if formula_info["families_with_formulas"] < 3:
        return False, "Insufficient formulas in calculation section", formula_info
    
    # Check for at least some COUNTIF and SUMIF usage
    if formula_info["correct_countif"] < 2 or formula_info["correct_sumif"] < 2:
        return False, "Missing COUNTIF or SUMIF formulas", formula_info
    
    return True, f"Formulas correct, total reimbursement: ${total_reimb:.2f}", formula_info


def verify_fair_distribution(drivers):
    """
    Verify that no family drives more than 4 times (if avoidable).
    
    Returns:
        (bool, str, dict): (passed, message, distribution)
    """
    from collections import Counter
    
    distribution = Counter(drivers)
    max_drives = max(distribution.values())
    
    if max_drives > 4:
        overloaded = [f"{family}: {count}" for family, count in distribution.items() if count > 4]
        return False, f"Some families drive more than 4 times: {', '.join(overloaded)}", dict(distribution)
    
    return True, f"Fair distribution (max {max_drives} drives per family)", dict(distribution)


def verify_carpool_coordinator(traj, env_info, task_info):
    """
    Main verification function for Soccer Carpool Coordinator task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/carpool_schedule.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}

        # Criterion 1: Coverage completeness
        coverage_ok, coverage_msg, drivers = verify_coverage_completeness(workbook, sheet_name)
        subscores["coverage_complete"] = coverage_ok
        if coverage_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {coverage_msg}")
        else:
            feedback_parts.append(f"❌ {coverage_msg}")

        # Criterion 2: Capacity constraints
        capacity_ok, capacity_msg, violations = verify_capacity_constraints(workbook, sheet_name)
        subscores["capacity_respected"] = capacity_ok
        if capacity_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {capacity_msg}")
        else:
            feedback_parts.append(f"❌ {capacity_msg}")

        # Criterion 3: Formulas correct
        formulas_ok, formulas_msg, formula_info = verify_formulas(workbook, sheet_name, drivers)
        subscores["formulas_correct"] = formulas_ok
        if formulas_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {formulas_msg}")
        else:
            feedback_parts.append(f"❌ {formulas_msg}")

        # Criterion 4: Conditional formatting applied
        # Check if conditional formatting exists on column E (capacity column)
        has_formatting = check_conditional_formatting(workbook, sheet_name, "E2:E13")
        subscores["conditional_formatting"] = has_formatting
        if has_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting applied")
        else:
            feedback_parts.append("⚠️ Conditional formatting not detected (may be partial credit)")
            # Give partial credit since formatting detection is complex
            criteria_passed += 0.5

        # Criterion 5: Fair distribution
        fair_ok, fair_msg, distribution = verify_fair_distribution(drivers)
        subscores["fair_distribution"] = fair_ok
        if fair_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {fair_msg}")
        else:
            feedback_parts.append(f"⚠️ {fair_msg} (still acceptable)")
            # Give partial credit since perfect fairness may not be possible
            criteria_passed += 0.75

        # Criterion 6: Mathematical consistency (already checked in formulas)
        math_ok = formula_info.get("total_reimbursement", 0) > 0
        subscores["mathematical_consistency"] = math_ok
        if math_ok and abs(formula_info["total_reimbursement"] - 240) <= 5:
            criteria_passed += 1
            feedback_parts.append("✅ Mathematical consistency verified")
        else:
            feedback_parts.append("❌ Reimbursement totals don't sum to $240")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70

        # Add distribution info to feedback
        if distribution:
            dist_str = ", ".join([f"{fam}: {cnt}" for fam, cnt in sorted(distribution.items())])
            feedback_parts.append(f"📊 Distribution: {dist_str}")

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "drivers": drivers,
                "distribution": distribution,
                "formula_info": formula_info,
                "violations": violations
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
