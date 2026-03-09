#!/usr/bin/env python3
"""
Verifier for Tip Pool Calculator task
Validates fair tip distribution calculations based on hours worked
"""

import sys
import os
import logging

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


def verify_tip_pool_calculator(traj, env_info, task_info):
    """
    Verify tip pool calculator task completion.
    
    Checks:
    1. Total tips calculated correctly with formula
    2. Total hours calculated correctly with formula
    3. Percentages calculated correctly (hours/total with absolute ref)
    4. Tip shares calculated correctly (pct * total with absolute ref)
    5. Conservation law: sum of shares ≈ total tips
    6. Formulas present (not hardcoded values)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/tip_pool.ods"
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
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Extract all necessary values
        # Tip sources
        cash_tips = get_cell_value(workbook, sheet_name, 'B11')
        credit_tips = get_cell_value(workbook, sheet_name, 'B12')
        total_tips = get_cell_value(workbook, sheet_name, 'B13')
        total_tips_formula = get_cell_formula(workbook, sheet_name, 'B13')
        
        # Hours data
        hours = []
        for i in range(2, 7):  # B2 to B6
            val = get_cell_value(workbook, sheet_name, f'B{i}')
            hours.append(float(val) if val is not None else 0.0)
        
        total_hours = get_cell_value(workbook, sheet_name, 'B8')
        total_hours_formula = get_cell_formula(workbook, sheet_name, 'B8')
        
        # Percentages
        percentages = []
        percentage_formulas = []
        for i in range(2, 7):  # C2 to C6
            val = get_cell_value(workbook, sheet_name, f'C{i}')
            formula = get_cell_formula(workbook, sheet_name, f'C{i}')
            percentages.append(float(val) if val is not None else 0.0)
            percentage_formulas.append(formula)
        
        # Tip shares
        tip_shares = []
        tip_share_formulas = []
        for i in range(2, 7):  # D2 to D6
            val = get_cell_value(workbook, sheet_name, f'D{i}')
            formula = get_cell_formula(workbook, sheet_name, f'D{i}')
            tip_shares.append(float(val) if val is not None else 0.0)
            tip_share_formulas.append(formula)
        
        logger.info(f"Cash tips: {cash_tips}, Credit tips: {credit_tips}, Total: {total_tips}")
        logger.info(f"Hours: {hours}, Total hours: {total_hours}")
        logger.info(f"Percentages: {percentages}")
        logger.info(f"Tip shares: {tip_shares}")
        
        # Criterion 1: Total tips calculation (16.7%)
        tips_correct = False
        if total_tips_formula and ('SUM' in total_tips_formula.upper() or '+' in total_tips_formula):
            expected_total = float(cash_tips) + float(credit_tips)
            if total_tips is not None and abs(float(total_tips) - expected_total) <= 0.01:
                criteria_passed += 1
                tips_correct = True
                feedback_parts.append(f"✅ Total tips correct: ${float(total_tips):.2f}")
            else:
                feedback_parts.append(f"❌ Total tips incorrect: expected ${expected_total:.2f}, got ${float(total_tips) if total_tips else 0:.2f}")
        else:
            feedback_parts.append(f"❌ Total tips missing formula (B13). Got: {total_tips_formula or 'no formula'}")
        
        subscores['total_tips_correct'] = tips_correct
        
        # Criterion 2: Total hours calculation (16.7%)
        hours_correct = False
        if total_hours_formula and 'SUM' in total_hours_formula.upper():
            expected_hours = sum(hours)
            if total_hours is not None and abs(float(total_hours) - expected_hours) <= 0.01:
                criteria_passed += 1
                hours_correct = True
                feedback_parts.append(f"✅ Total hours correct: {float(total_hours):.1f}")
            else:
                feedback_parts.append(f"❌ Total hours incorrect: expected {expected_hours:.1f}, got {float(total_hours) if total_hours else 0:.1f}")
        else:
            feedback_parts.append(f"❌ Total hours missing SUM formula (B8). Got: {total_hours_formula or 'no formula'}")
        
        subscores['total_hours_correct'] = hours_correct
        
        # Criterion 3: Percentages calculation (16.7%)
        percentages_correct = True
        has_absolute_ref = False
        
        if total_hours and float(total_hours) > 0:
            for i, (pct, formula, hour) in enumerate(zip(percentages, percentage_formulas, hours)):
                if formula is None:
                    percentages_correct = False
                    feedback_parts.append(f"❌ Missing percentage formula in C{i+2}")
                    break
                
                # Check for absolute reference ($B$8 or similar)
                if '$' in formula:
                    has_absolute_ref = True
                
                expected_pct = hour / float(total_hours)
                if abs(pct - expected_pct) > 0.001:
                    percentages_correct = False
                    feedback_parts.append(f"❌ Percentage incorrect in C{i+2}: expected {expected_pct:.3f}, got {pct:.3f}")
                    break
            
            # Check percentages sum to ~1.0
            if percentages_correct and abs(sum(percentages) - 1.0) > 0.01:
                percentages_correct = False
                feedback_parts.append(f"❌ Percentages sum to {sum(percentages):.3f}, expected ~1.0")
        else:
            percentages_correct = False
            feedback_parts.append("❌ Cannot verify percentages: total hours not calculated")
        
        if percentages_correct:
            if has_absolute_ref:
                criteria_passed += 1
                feedback_parts.append("✅ Percentages calculated correctly with absolute references")
            else:
                criteria_passed += 0.5
                feedback_parts.append("⚠️ Percentages calculated but missing absolute reference ($)")
        
        subscores['percentages_correct'] = percentages_correct
        
        # Criterion 4: Tip shares calculation (16.7%)
        shares_correct = True
        has_absolute_ref_tips = False
        
        if total_tips and float(total_tips) > 0:
            for i, (share, formula, pct) in enumerate(zip(tip_shares, tip_share_formulas, percentages)):
                if formula is None:
                    shares_correct = False
                    feedback_parts.append(f"❌ Missing tip share formula in D{i+2}")
                    break
                
                # Check for absolute reference ($B$13 or similar)
                if '$' in formula:
                    has_absolute_ref_tips = True
                
                expected_share = pct * float(total_tips)
                if abs(share - expected_share) > 0.10:
                    shares_correct = False
                    feedback_parts.append(f"❌ Tip share incorrect in D{i+2}: expected ${expected_share:.2f}, got ${share:.2f}")
                    break
        else:
            shares_correct = False
            feedback_parts.append("❌ Cannot verify tip shares: total tips not calculated")
        
        if shares_correct:
            if has_absolute_ref_tips:
                criteria_passed += 1
                feedback_parts.append("✅ Tip shares calculated correctly with absolute references")
            else:
                criteria_passed += 0.5
                feedback_parts.append("⚠️ Tip shares calculated but missing absolute reference ($)")
        
        subscores['tip_shares_correct'] = shares_correct
        
        # Criterion 5: Conservation law (16.7%)
        conservation_ok = False
        if total_tips and float(total_tips) > 0:
            total_distributed = sum(tip_shares)
            if abs(total_distributed - float(total_tips)) <= 0.50:
                criteria_passed += 1
                conservation_ok = True
                feedback_parts.append(f"✅ Conservation law satisfied: distributed ${total_distributed:.2f} ≈ collected ${float(total_tips):.2f}")
            else:
                feedback_parts.append(f"❌ Conservation law violated: distributed ${total_distributed:.2f} ≠ collected ${float(total_tips):.2f}")
        else:
            feedback_parts.append("❌ Cannot verify conservation: total tips not calculated")
        
        subscores['conservation_law'] = conservation_ok
        
        # Criterion 6: Formulas present (16.7%)
        formulas_present = (
            total_tips_formula is not None and
            total_hours_formula is not None and
            all(f is not None for f in percentage_formulas) and
            all(f is not None for f in tip_share_formulas)
        )
        
        if formulas_present:
            criteria_passed += 1
            feedback_parts.append("✅ All required formulas present")
        else:
            missing = []
            if not total_tips_formula:
                missing.append("B13 (total tips)")
            if not total_hours_formula:
                missing.append("B8 (total hours)")
            if not all(f is not None for f in percentage_formulas):
                missing.append("C2:C6 (percentages)")
            if not all(f is not None for f in tip_share_formulas):
                missing.append("D2:D6 (tip shares)")
            feedback_parts.append(f"❌ Missing formulas in: {', '.join(missing)}")
        
        subscores['formulas_present'] = formulas_present
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 4/6 criteria (70%)
        
        # Add summary
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent tip distribution calculation!")
        elif passed:
            feedback_parts.append("✅ Tip pool distribution task completed")
        else:
            feedback_parts.append("❌ Task requirements not met - check formulas and calculations")
        
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
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }

    finally:
        cleanup_verification_temp(temp_dir)
