#!/usr/bin/env python3
"""
Verifier for Formula Detective task.
Validates that corrupted formulas have been correctly reconstructed.
"""

import sys
import os
import logging
import re
from typing import Tuple, Dict, Any

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


def validate_commission_formula(formula_str: str, row_num: int) -> Tuple[bool, str]:
    """
    Validate reconstructed commission formula structure.
    
    Expected pattern: nested IF with thresholds at 10000 and 25000
    Rates: 5%, 7%, 10%
    
    Args:
        formula_str: The formula string from the cell
        row_num: Expected row number
        
    Returns:
        Tuple of (is_valid, message)
    """
    if not formula_str or not formula_str.startswith('='):
        return False, "Not a formula"
    
    # Normalize: remove spaces, convert to uppercase for comparison
    normalized = formula_str.upper().replace(' ', '')
    
    # Must contain IF statements
    if 'IF' not in normalized:
        return False, "Missing IF function"
    
    # Check for threshold values (10000 and 25000)
    has_10k = '10000' in normalized
    has_25k = '25000' in normalized
    
    if not (has_10k and has_25k):
        return False, f"Missing tier thresholds (need 10000 and 25000)"
    
    # Check for rate multipliers (0.05, 0.07, 0.1 or 5%, 7%, 10%)
    has_5pct = ('0.05' in normalized or '5%' in normalized or '*5/' in normalized)
    has_7pct = ('0.07' in normalized or '7%' in normalized or '*7/' in normalized)
    has_10pct = ('0.1' in normalized or '0.10' in normalized or '10%' in normalized or '*10/' in normalized)
    
    if not (has_5pct and has_7pct and has_10pct):
        return False, f"Missing commission rates (need 5%, 7%, 10%)"
    
    # Check that formula references the correct row (column C for sales)
    # Allow both C{row_num} and relative references
    expected_cell_ref = f"C{row_num}"
    if expected_cell_ref not in formula_str.upper() and expected_cell_ref not in normalized:
        # Maybe using relative reference without row number visible
        # Check if it at least references column C
        if 'C' not in normalized.split('=')[1][:20]:  # Check early in formula
            return False, f"Formula doesn't reference column C (sales amount)"
    
    return True, "Valid commission formula structure"


def validate_payout_formula(formula_str: str, row_num: int) -> Tuple[bool, str]:
    """
    Validate reconstructed total payout formula.
    
    Expected: Commission + Bonus logic
    Bonus: IF(AND(Status="Premium", Commission>1000), 500, 0)
    
    Args:
        formula_str: The formula string from the cell
        row_num: Expected row number
        
    Returns:
        Tuple of (is_valid, message)
    """
    if not formula_str or not formula_str.startswith('='):
        return False, "Not a formula"
    
    # Normalize
    normalized = formula_str.upper().replace(' ', '')
    
    # Must contain addition (commission + bonus)
    if '+' not in normalized:
        return False, "Missing addition operator (commission + bonus)"
    
    # Should reference commission column (D)
    expected_commission_ref = f"D{row_num}"
    if expected_commission_ref not in formula_str.upper() and 'D' not in normalized.split('=')[1][:10]:
        return False, "Missing reference to commission column (D)"
    
    # Should check for Premium status
    if 'PREMIUM' not in normalized:
        return False, "Missing Premium status check"
    
    # Should have conditional logic (IF)
    if 'IF' not in normalized:
        return False, "Missing IF function for bonus logic"
    
    # Should check commission threshold (1000)
    if '1000' not in normalized:
        return False, "Missing bonus threshold check (commission > 1000)"
    
    # Should have bonus amount (500)
    if '500' not in normalized:
        return False, "Missing bonus amount (500)"
    
    # Should have AND function for multiple conditions
    if 'AND' not in normalized:
        # Some valid formulas might nest IFs instead of using AND
        # This is acceptable, so don't fail hard
        logger.debug("Formula uses nested IFs instead of AND - acceptable")
    
    return True, "Valid payout formula structure"


def calculate_expected_commission(sales: float) -> float:
    """Calculate expected commission based on tier structure."""
    if sales <= 10000:
        return sales * 0.05
    elif sales <= 25000:
        return sales * 0.07
    else:
        return sales * 0.10


def calculate_expected_payout(commission: float, status: str) -> float:
    """Calculate expected total payout including bonus."""
    bonus = 500 if (status == "Premium" and commission > 1000) else 0
    return commission + bonus


def check_formula_detective(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify formula detective task completion.
    
    Checks:
    1. All corrupted cells now contain formulas
    2. Commission formula structure correct
    3. Payout formula structure correct
    4. Calculations are accurate
    5. Formulas use proper relative references
    6. No hard-coded values from wrong rows
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Setup verification
    container_path = "/home/ga/Documents/sales_commissions.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods']
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        
        # Define corrupted cells that should now have formulas
        # Row 3: Bob Smith, $12,000, Standard
        # Row 5: David Lee, $22,000, Premium  
        # Row 7: Frank Wilson, $15,000, Premium
        corrupted_commission_cells = ['D3', 'D5', 'D7']
        corrupted_payout_cells = ['F3', 'F5', 'F7']
        all_corrupted_cells = corrupted_commission_cells + corrupted_payout_cells
        
        # Expected values for validation
        test_cases = [
            # (row, sales_cell, sales_amt, status_cell, status, expected_commission, expected_payout)
            (3, 'C3', 12000, 'E3', 'Standard', 840, 840),
            (5, 'C5', 22000, 'E5', 'Premium', 1540, 2040),
            (7, 'C7', 15000, 'E7', 'Premium', 1050, 1550),
        ]
        
        criteria_met = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: All corrupted cells now contain formulas
        formulas_restored = 0
        for cell_ref in all_corrupted_cells:
            formula = get_cell_formula(data, sheet_name, cell_ref)
            if formula and formula.startswith('='):
                formulas_restored += 1
                logger.debug(f"✓ Cell {cell_ref} has formula: {formula}")
            else:
                logger.info(f"✗ Cell {cell_ref} missing formula (got: {formula})")
                feedback_parts.append(f"❌ {cell_ref} still contains static value")
        
        if formulas_restored == len(all_corrupted_cells):
            criteria_met += 1
            feedback_parts.append(f"✅ All {len(all_corrupted_cells)} corrupted cells restored")
        else:
            feedback_parts.append(f"⚠️  Only {formulas_restored}/{len(all_corrupted_cells)} cells have formulas")
        
        # Criterion 2: Commission formulas structurally correct
        commission_formulas_correct = 0
        for cell_ref in corrupted_commission_cells:
            formula = get_cell_formula(data, sheet_name, cell_ref)
            row_num = int(re.search(r'\d+', cell_ref).group())
            
            if formula:
                is_valid, msg = validate_commission_formula(formula, row_num)
                if is_valid:
                    commission_formulas_correct += 1
                    logger.debug(f"✓ {cell_ref} commission formula valid")
                else:
                    logger.info(f"✗ {cell_ref} commission formula invalid: {msg}")
                    feedback_parts.append(f"❌ {cell_ref} commission: {msg}")
        
        if commission_formulas_correct >= len(corrupted_commission_cells):
            criteria_met += 1
            feedback_parts.append(f"✅ Commission formulas correct ({commission_formulas_correct}/{len(corrupted_commission_cells)})")
        elif commission_formulas_correct > 0:
            feedback_parts.append(f"⚠️  Partial commission formulas ({commission_formulas_correct}/{len(corrupted_commission_cells)})")
        
        # Criterion 3: Payout formulas structurally correct
        payout_formulas_correct = 0
        for cell_ref in corrupted_payout_cells:
            formula = get_cell_formula(data, sheet_name, cell_ref)
            row_num = int(re.search(r'\d+', cell_ref).group())
            
            if formula:
                is_valid, msg = validate_payout_formula(formula, row_num)
                if is_valid:
                    payout_formulas_correct += 1
                    logger.debug(f"✓ {cell_ref} payout formula valid")
                else:
                    logger.info(f"✗ {cell_ref} payout formula invalid: {msg}")
                    feedback_parts.append(f"❌ {cell_ref} payout: {msg}")
        
        if payout_formulas_correct >= len(corrupted_payout_cells):
            criteria_met += 1
            feedback_parts.append(f"✅ Payout formulas correct ({payout_formulas_correct}/{len(corrupted_payout_cells)})")
        elif payout_formulas_correct > 0:
            feedback_parts.append(f"⚠️  Partial payout formulas ({payout_formulas_correct}/{len(corrupted_payout_cells)})")
        
        # Criterion 4: Calculations are numerically accurate
        calculations_accurate = 0
        for row, sales_cell, sales_amt, status_cell, status, exp_commission, exp_payout in test_cases:
            commission_cell = f"D{row}"
            payout_cell = f"F{row}"
            
            actual_commission = get_cell_value(data, sheet_name, commission_cell)
            actual_payout = get_cell_value(data, sheet_name, payout_cell)
            
            commission_ok = False
            payout_ok = False
            
            if actual_commission is not None:
                try:
                    if abs(float(actual_commission) - exp_commission) < 0.01:
                        commission_ok = True
                except (ValueError, TypeError):
                    pass
            
            if actual_payout is not None:
                try:
                    if abs(float(actual_payout) - exp_payout) < 0.01:
                        payout_ok = True
                except (ValueError, TypeError):
                    pass
            
            if commission_ok and payout_ok:
                calculations_accurate += 1
                logger.debug(f"✓ Row {row} calculations correct")
            else:
                if not commission_ok:
                    logger.info(f"✗ Row {row} commission: expected {exp_commission}, got {actual_commission}")
                if not payout_ok:
                    logger.info(f"✗ Row {row} payout: expected {exp_payout}, got {actual_payout}")
        
        if calculations_accurate >= len(test_cases):
            criteria_met += 1
            feedback_parts.append(f"✅ All calculations accurate")
        elif calculations_accurate >= len(test_cases) * 0.66:  # 2/3 threshold
            criteria_met += 0.5  # Partial credit
            feedback_parts.append(f"⚠️  Most calculations accurate ({calculations_accurate}/{len(test_cases)})")
        else:
            feedback_parts.append(f"❌ Calculations incorrect ({calculations_accurate}/{len(test_cases)} rows correct)")
        
        # Criterion 5: Dynamic updating (formulas use proper relative references)
        dynamic_formulas = 0
        for cell_ref in all_corrupted_cells:
            formula = get_cell_formula(data, sheet_name, cell_ref)
            if not formula:
                continue
            
            row_num = int(re.search(r'\d+', cell_ref).group())
            
            # Formula should reference its own row number
            if str(row_num) in formula:
                dynamic_formulas += 1
            else:
                # Check if using completely relative references (no row numbers)
                # This is also acceptable
                if not any(str(i) in formula for i in range(2, 10) if i != row_num):
                    dynamic_formulas += 1
        
        if dynamic_formulas >= len(all_corrupted_cells) * 0.8:  # 80% threshold
            criteria_met += 1
            feedback_parts.append("✅ Formulas use proper relative references")
        else:
            feedback_parts.append(f"⚠️  Some formulas may not update dynamically")
        
        # Criterion 6: No hard-coded values from wrong rows
        no_hardcoded = True
        for cell_ref in all_corrupted_cells:
            formula = get_cell_formula(data, sheet_name, cell_ref)
            if not formula:
                continue
            
            row_num = int(re.search(r'\d+', cell_ref).group())
            
            # Check for other row numbers in formula
            other_rows = [str(i) for i in range(2, 10) if i != row_num]
            for other_row in other_rows:
                # Look for patterns like C3, D4, E5 etc in the formula
                if re.search(r'[A-Z]' + other_row + r'\b', formula):
                    no_hardcoded = False
                    feedback_parts.append(f"❌ {cell_ref}: references row {other_row} instead of {row_num}")
                    logger.info(f"✗ {cell_ref} hard-codes row {other_row}: {formula}")
                    break
            
            if not no_hardcoded:
                break
        
        if no_hardcoded:
            criteria_met += 1
            feedback_parts.append("✅ No hard-coded references to wrong rows")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 85  # Need 5/6 criteria (85%)
        
        # Add summary
        if passed:
            feedback_parts.insert(0, "🎉 Formula reconstruction successful!")
        else:
            feedback_parts.insert(0, "❌ Formula reconstruction incomplete")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "formulas_restored": formulas_restored == len(all_corrupted_cells),
                "commission_structure": commission_formulas_correct >= len(corrupted_commission_cells),
                "payout_structure": payout_formulas_correct >= len(corrupted_payout_cells),
                "calculations_accurate": calculations_accurate >= len(test_cases),
                "dynamic_updating": dynamic_formulas >= len(all_corrupted_cells) * 0.8,
                "no_hardcoding": no_hardcoded
            },
            "criteria_met": f"{criteria_met}/{total_criteria}"
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
