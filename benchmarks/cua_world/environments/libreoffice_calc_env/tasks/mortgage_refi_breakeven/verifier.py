#!/usr/bin/env python3
"""
Verifier for Mortgage Refinance Decision Calculator task
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path for host machine compatibility
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_numeric_value(value):
    """Extract numeric value from various formats (handles currency strings, etc.)"""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        # Remove currency symbols, commas, whitespace
        cleaned = re.sub(r'[$,\s]', '', value)
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def check_pmt_formula(formula):
    """Check if a formula contains PMT function"""
    if not formula:
        return False
    formula_upper = formula.upper()
    return 'PMT(' in formula_upper or 'PMT ' in formula_upper


def calculate_expected_pmt(rate, years, balance):
    """Calculate expected monthly payment using standard mortgage formula"""
    import math
    monthly_rate = rate / 12
    num_payments = years * 12
    if monthly_rate == 0:
        return balance / num_payments
    pmt = balance * (monthly_rate * math.pow(1 + monthly_rate, num_payments)) / \
          (math.pow(1 + monthly_rate, num_payments) - 1)
    return pmt


def verify_mortgage_refi_breakeven(traj, env_info, task_info):
    """
    Verify mortgage refinance decision calculator task completion.
    
    Checks:
    1. PMT formulas present for all 3 offers (Row 16, columns C/D/E)
    2. Monthly payment calculations accurate (within tolerance)
    3. Break-even timeline calculated (Row 19, columns C/D/E)
    4. 5-year savings projections present (Row 22, columns C/D/E)
    5. Decision logic implemented (Row 25, columns C/D/E)
    6. Basic formatting applied (currency for payments)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/mortgage_refi.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        sheet_name = sheet_names[0]

        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Define expected values
        LOAN_BALANCE = 238000
        CURRENT_PAYMENT = 1806
        
        # Offer 1: 4.75% APR, 30-year, $4,200 closing
        OFFER1_RATE = 0.0475
        OFFER1_YEARS = 30
        OFFER1_CLOSING = 4200
        OFFER1_EXPECTED_PMT = calculate_expected_pmt(OFFER1_RATE, OFFER1_YEARS, LOAN_BALANCE)
        OFFER1_EXPECTED_SAVINGS = CURRENT_PAYMENT - OFFER1_EXPECTED_PMT
        OFFER1_EXPECTED_BREAKEVEN_YRS = OFFER1_CLOSING / (OFFER1_EXPECTED_SAVINGS * 12)
        
        # Offer 2: 4.25% APR, 20-year, $6,800 closing
        OFFER2_RATE = 0.0425
        OFFER2_YEARS = 20
        OFFER2_CLOSING = 6800
        OFFER2_EXPECTED_PMT = calculate_expected_pmt(OFFER2_RATE, OFFER2_YEARS, LOAN_BALANCE)
        OFFER2_EXPECTED_SAVINGS = CURRENT_PAYMENT - OFFER2_EXPECTED_PMT
        OFFER2_EXPECTED_BREAKEVEN_YRS = OFFER2_CLOSING / (OFFER2_EXPECTED_SAVINGS * 12)
        
        # Offer 3: 5.125% APR, 30-year, $0 closing
        OFFER3_RATE = 0.05125
        OFFER3_YEARS = 30
        OFFER3_CLOSING = 0
        OFFER3_EXPECTED_PMT = calculate_expected_pmt(OFFER3_RATE, OFFER3_YEARS, LOAN_BALANCE)
        OFFER3_EXPECTED_SAVINGS = CURRENT_PAYMENT - OFFER3_EXPECTED_PMT
        
        expected_pmts = [OFFER1_EXPECTED_PMT, OFFER2_EXPECTED_PMT, OFFER3_EXPECTED_PMT]
        expected_breakevens = [OFFER1_EXPECTED_BREAKEVEN_YRS, OFFER2_EXPECTED_BREAKEVEN_YRS, 0]
        
        logger.info(f"Expected payments: {[round(p) for p in expected_pmts]}")
        logger.info(f"Expected break-evens (years): {[round(b, 2) for b in expected_breakevens]}")

        # Criterion 1: PMT formulas present in Row 16 (C16, D16, E16)
        pmt_formulas_found = 0
        pmt_cells = ['C16', 'D16', 'E16']
        for cell in pmt_cells:
            formula = get_cell_formula(workbook, sheet_name, cell)
            if check_pmt_formula(formula):
                pmt_formulas_found += 1
        
        if pmt_formulas_found == 3:
            criteria_passed += 1
            feedback_parts.append("✅ PMT formulas present for all 3 offers")
        elif pmt_formulas_found > 0:
            feedback_parts.append(f"⚠️ PMT formulas partial ({pmt_formulas_found}/3 offers)")
        else:
            feedback_parts.append("❌ No PMT formulas detected in Row 16")

        # Criterion 2: Monthly payment calculations accurate
        payments_accurate = 0
        payment_cells = ['C16', 'D16', 'E16']
        tolerance = 10  # $10 tolerance for rounding differences
        
        for i, cell in enumerate(payment_cells):
            value = get_cell_value(workbook, sheet_name, cell)
            numeric_value = extract_numeric_value(value)
            
            if numeric_value is not None:
                expected = expected_pmts[i]
                if abs(numeric_value - expected) <= tolerance:
                    payments_accurate += 1
                else:
                    logger.info(f"Payment {cell}: got {numeric_value:.2f}, expected {expected:.2f}")
        
        if payments_accurate == 3:
            criteria_passed += 1
            feedback_parts.append("✅ All payment calculations accurate")
        elif payments_accurate > 0:
            feedback_parts.append(f"⚠️ Some payments accurate ({payments_accurate}/3)")
        else:
            feedback_parts.append("❌ Payment calculations missing or incorrect")

        # Criterion 3: Break-even timeline calculated (Row 19: C19, D19, E19)
        breakeven_found = 0
        breakeven_cells = ['C19', 'D19', 'E19']
        
        for i, cell in enumerate(breakeven_cells):
            value = get_cell_value(workbook, sheet_name, cell)
            formula = get_cell_formula(workbook, sheet_name, cell)
            numeric_value = extract_numeric_value(value)
            
            # Check if value exists and is reasonable (between 0 and 10 years)
            if numeric_value is not None:
                if 0 <= numeric_value <= 10:
                    breakeven_found += 1
                    # For Offer 3 (no closing costs), expect ~0
                    if i == 2 and numeric_value < 0.1:
                        logger.info(f"Offer 3 break-even correctly shows ~0: {numeric_value}")
                else:
                    logger.info(f"Break-even {cell} out of range: {numeric_value}")
        
        if breakeven_found == 3:
            criteria_passed += 1
            feedback_parts.append("✅ Break-even timelines calculated for all offers")
        elif breakeven_found > 0:
            feedback_parts.append(f"⚠️ Break-even partial ({breakeven_found}/3 offers)")
        else:
            feedback_parts.append("❌ Break-even timelines missing")

        # Criterion 4: 5-year savings projections present (Row 22: C22, D22, E22)
        savings_5yr_found = 0
        savings_cells = ['C22', 'D22', 'E22']
        
        for cell in savings_cells:
            value = get_cell_value(workbook, sheet_name, cell)
            formula = get_cell_formula(workbook, sheet_name, cell)
            numeric_value = extract_numeric_value(value)
            
            # Check if value exists and is reasonable (positive savings between $0-50k)
            if numeric_value is not None:
                if 0 <= numeric_value <= 50000:
                    savings_5yr_found += 1
                else:
                    logger.info(f"5-year savings {cell} out of expected range: {numeric_value}")
        
        if savings_5yr_found == 3:
            criteria_passed += 1
            feedback_parts.append("✅ 5-year savings projections calculated")
        elif savings_5yr_found > 0:
            feedback_parts.append(f"⚠️ 5-year savings partial ({savings_5yr_found}/3)")
        else:
            feedback_parts.append("❌ 5-year savings projections missing")

        # Criterion 5: Decision logic implemented (Row 25: C25, D25, E25)
        decision_logic_found = 0
        decision_cells = ['C25', 'D25', 'E25']
        
        for cell in decision_cells:
            value = get_cell_value(workbook, sheet_name, cell)
            formula = get_cell_formula(workbook, sheet_name, cell)
            
            # Check if value contains recommendation text or formula has IF
            if formula and 'IF' in formula.upper():
                decision_logic_found += 1
            elif value and isinstance(value, str):
                value_upper = value.upper()
                if any(word in value_upper for word in ['GOOD', 'DEAL', 'MAYBE', 'AVOID', 'YES', 'NO']):
                    decision_logic_found += 1
        
        if decision_logic_found == 3:
            criteria_passed += 1
            feedback_parts.append("✅ Decision recommendations implemented")
        elif decision_logic_found > 0:
            feedback_parts.append(f"⚠️ Decision logic partial ({decision_logic_found}/3)")
        else:
            feedback_parts.append("❌ Decision recommendations missing")

        # Criterion 6: Formulas used (not hardcoded) - check that key cells have formulas
        formulas_used = 0
        key_formula_cells = ['C16', 'C17', 'C19', 'C22']  # Sample cells that should have formulas
        
        for cell in key_formula_cells:
            formula = get_cell_formula(workbook, sheet_name, cell)
            if formula and formula.strip().startswith('='):
                formulas_used += 1
        
        if formulas_used >= 3:
            criteria_passed += 1
            feedback_parts.append("✅ Formulas used (not hardcoded)")
        elif formulas_used > 0:
            feedback_parts.append(f"⚠️ Some formulas present ({formulas_used}/4 checked)")
        else:
            feedback_parts.append("❌ Values appear hardcoded (no formulas)")

        # Criterion 7: Reasonable overall structure (7-year savings also calculated)
        savings_7yr_found = 0
        savings_7yr_cells = ['C23', 'D23', 'E23']
        
        for cell in savings_7yr_cells:
            value = get_cell_value(workbook, sheet_name, cell)
            numeric_value = extract_numeric_value(value)
            
            if numeric_value is not None and 0 <= numeric_value <= 70000:
                savings_7yr_found += 1
        
        if savings_7yr_found >= 2:  # At least 2 of 3
            criteria_passed += 1
            feedback_parts.append("✅ 7-year savings calculated")
        else:
            feedback_parts.append("⚠️ 7-year savings incomplete or missing")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need at least 5 out of 7 criteria
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent financial analysis!")
        elif passed:
            feedback_parts.append("✅ Refinance analysis completed")
        else:
            feedback_parts.append("❌ Analysis incomplete - missing key calculations")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "pmt_formulas": pmt_formulas_found == 3,
                "payments_accurate": payments_accurate == 3,
                "breakeven_calculated": breakeven_found == 3,
                "savings_5yr": savings_5yr_found == 3,
                "decision_logic": decision_logic_found == 3,
                "formulas_used": formulas_used >= 3,
                "savings_7yr": savings_7yr_found >= 2
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
