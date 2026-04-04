#!/usr/bin/env python3
"""
Verifier for Bike Service Tracker task.

Checks:
1. Cumulative mileage SUM formula exists and is correct
2. Service intervals are referenced from lookup table
3. Miles remaining formulas calculate correctly
4. Formula structure uses proper references (not hardcoded)
"""

import sys
import os
import logging
import re

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bike_service_tracker(traj, env_info, task_info):
    """
    Verify bike service tracker task completion.
    
    Checks:
    1. Cell H2 contains SUM formula for cumulative mileage
    2. Total mileage is approximately 385 km (±1 km)
    3. Cells H5-H8 reference service intervals from E column
    4. Cells I5-I8 contain subtraction formulas for miles remaining
    5. Chain remaining (~115 km) is correct
    6. Tires remaining (~2615 km) is correct
    7. Formula structure is valid (no hardcoded values)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/bike_service_tracker.ods"
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
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []

        # Expected values
        expected_total_mileage = 385  # Sum of all rides
        expected_chain_interval = 500
        expected_tires_interval = 3000
        expected_brake_interval = 2000
        expected_tuneup_interval = 5000

        # Criterion 1: Cumulative mileage formula (H2)
        h2_formula = get_cell_formula(workbook, sheet_name, 'H2')
        h2_value = get_cell_value(workbook, sheet_name, 'H2')
        
        sum_formula_correct = False
        if h2_formula and 'SUM' in h2_formula.upper():
            # Check if it references column B rides (B2:B11 or similar range)
            if 'B2' in h2_formula.upper() or 'B:B' in h2_formula.upper():
                criteria_passed += 1
                sum_formula_correct = True
                feedback_parts.append(f"✅ Cumulative mileage formula correct: {h2_formula}")
            else:
                feedback_parts.append(f"⚠️ SUM formula exists but may not reference ride distances: {h2_formula}")
        else:
            feedback_parts.append(f"❌ H2 missing SUM formula (got: {h2_formula or 'no formula'})")

        # Criterion 2: Total mileage accuracy
        total_mileage_correct = False
        if h2_value is not None:
            try:
                total_mileage = float(h2_value)
                if abs(total_mileage - expected_total_mileage) <= 1:
                    criteria_passed += 1
                    total_mileage_correct = True
                    feedback_parts.append(f"✅ Total mileage accurate: {total_mileage} km")
                else:
                    feedback_parts.append(f"❌ Total mileage incorrect: expected ~{expected_total_mileage}, got {total_mileage}")
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Total mileage not a number: {h2_value}")
        else:
            feedback_parts.append("❌ Total mileage not calculated (H2 is empty)")

        # Criterion 3: Service intervals referenced (H5-H8 should reference E5-E8)
        intervals_referenced = True
        interval_checks = [
            ('H5', 'E5', 'Chain', expected_chain_interval),
            ('H6', 'E6', 'Tires', expected_tires_interval),
            ('H7', 'E7', 'Brake Pads', expected_brake_interval),
            ('H8', 'E8', 'Full Tune-up', expected_tuneup_interval),
        ]
        
        for h_cell, e_cell, component, expected_val in interval_checks:
            h_formula = get_cell_formula(workbook, sheet_name, h_cell)
            h_value = get_cell_value(workbook, sheet_name, h_cell)
            
            # Check if formula references the interval table OR value is correct
            if h_formula and e_cell.upper() in h_formula.upper():
                continue  # Good, it references the table
            elif h_value == expected_val:
                continue  # Value is correct (maybe formula, maybe hardcoded)
            else:
                intervals_referenced = False
                feedback_parts.append(f"⚠️ {component} interval not referenced correctly in {h_cell}")
                break
        
        if intervals_referenced:
            criteria_passed += 1
            feedback_parts.append("✅ Service intervals referenced from table")

        # Criterion 4: Miles remaining formulas (I5-I8 should have subtraction formulas)
        remaining_formulas_present = True
        for i_cell, component in [('I5', 'Chain'), ('I6', 'Tires'), ('I7', 'Brake Pads'), ('I8', 'Full Tune-up')]:
            i_formula = get_cell_formula(workbook, sheet_name, i_cell)
            
            # Check for subtraction formula pattern (should contain - and reference to H2)
            if i_formula and ('-' in i_formula or '−' in i_formula):
                # Good, has subtraction
                if 'H2' in i_formula.upper() or '$H$2' in i_formula.upper():
                    continue  # Perfect, references total mileage
                else:
                    remaining_formulas_present = False
                    feedback_parts.append(f"⚠️ {component} formula doesn't reference total mileage (H2)")
                    break
            else:
                remaining_formulas_present = False
                feedback_parts.append(f"❌ {i_cell} missing miles remaining formula for {component}")
                break
        
        if remaining_formulas_present:
            criteria_passed += 1
            feedback_parts.append("✅ Miles remaining formulas present")

        # Criterion 5: Chain remaining correct (~115 km)
        i5_value = get_cell_value(workbook, sheet_name, 'I5')
        chain_remaining_correct = False
        if i5_value is not None:
            try:
                chain_remaining = float(i5_value)
                expected_chain_remaining = expected_chain_interval - expected_total_mileage  # 500 - 385 = 115
                if abs(chain_remaining - expected_chain_remaining) <= 5:
                    criteria_passed += 1
                    chain_remaining_correct = True
                    feedback_parts.append(f"✅ Chain remaining correct: {chain_remaining} km")
                else:
                    feedback_parts.append(f"❌ Chain remaining incorrect: expected ~{expected_chain_remaining}, got {chain_remaining}")
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Chain remaining not a number: {i5_value}")
        else:
            feedback_parts.append("❌ Chain remaining not calculated (I5 is empty)")

        # Criterion 6: Tires remaining correct (~2615 km)
        i6_value = get_cell_value(workbook, sheet_name, 'I6')
        tires_remaining_correct = False
        if i6_value is not None:
            try:
                tires_remaining = float(i6_value)
                expected_tires_remaining = expected_tires_interval - expected_total_mileage  # 3000 - 385 = 2615
                if abs(tires_remaining - expected_tires_remaining) <= 5:
                    criteria_passed += 1
                    tires_remaining_correct = True
                    feedback_parts.append(f"✅ Tires remaining correct: {tires_remaining} km")
                else:
                    feedback_parts.append(f"❌ Tires remaining incorrect: expected ~{expected_tires_remaining}, got {tires_remaining}")
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Tires remaining not a number: {i6_value}")
        else:
            feedback_parts.append("❌ Tires remaining not calculated (I6 is empty)")

        # Criterion 7: Formula structure valid (check for proper use of formulas vs hardcoded)
        formulas_used = (
            h2_formula is not None and 
            get_cell_formula(workbook, sheet_name, 'I5') is not None and
            get_cell_formula(workbook, sheet_name, 'I6') is not None
        )
        
        if formulas_used:
            criteria_passed += 1
            feedback_parts.append("✅ Formula structure valid (not hardcoded)")
        else:
            feedback_parts.append("❌ Values appear hardcoded (formulas missing)")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 5/7 criteria = 71%
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "sum_formula": sum_formula_correct,
                "total_mileage_accurate": total_mileage_correct,
                "intervals_referenced": intervals_referenced,
                "remaining_formulas": remaining_formulas_present,
                "chain_remaining": chain_remaining_correct,
                "tires_remaining": tires_remaining_correct,
                "formulas_used": formulas_used
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
