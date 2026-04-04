#!/usr/bin/env python3
"""
Verifier for Credit Card Rewards Optimizer Task

Checks:
1. Structured data with categories and cards
2. Cashback calculation formulas (multiplication with percentages)
3. Optimization logic (MAX or nested IF functions)
4. Calculation accuracy (spot-check sample calculations)
5. Actionable recommendations (best card indicators)
6. File saved properly
"""

import sys
import os
import re
import logging

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_verification_environment,
    cleanup_verification_environment,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_credit_card_optimizer(traj, env_info, task_info):
    """
    Verify the credit card rewards optimizer spreadsheet.
    
    Returns:
        dict: Verification result with passed status, score, and feedback
    """
    copy_from_env_fn = env_info.get('copy_from_env')
    if not copy_from_env_fn:
        logger.error("Copy function not available")
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/Documents/credit_card_optimizer.ods"
    
    # Setup verification environment
    success, result = setup_verification_environment(
        copy_from_env_fn,
        container_path,
        expected_formats=['ods', 'xlsx']
    )
    
    if not success:
        logger.error(f"Failed to load spreadsheet: {result.get('error', 'Unknown error')}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {result.get('error', 'Unknown error')}"
        }
    
    data = result.get('data', {})
    temp_dir = result.get('temp_dir')
    
    try:
        sheets = get_sheet_names(data)
        if not sheets:
            logger.warning("No sheets found in spreadsheet")
            return {"passed": False, "score": 0, "feedback": "No sheets found in spreadsheet"}
        
        sheet_name = sheets[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        criteria_met = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Structured data with categories and cards
        has_structure = check_data_structure(data, sheet_name)
        subscores['structured_data'] = has_structure
        if has_structure:
            criteria_met += 1
            feedback_parts.append("✅ Structured data with categories and cards found")
            logger.info("PASS: Data structure criterion")
        else:
            feedback_parts.append("❌ Missing proper data structure (need 3+ categories, 5+ columns)")
            logger.warning("FAIL: Data structure criterion")
        
        # Criterion 2: Cashback formulas present (multiplication with percentages)
        formula_count, formula_details = count_cashback_formulas(data, sheet_name)
        subscores['formula_count'] = formula_count
        if formula_count >= 6:
            criteria_met += 1
            feedback_parts.append(f"✅ Found {formula_count} cashback calculation formulas")
            logger.info(f"PASS: Formula criterion ({formula_count} formulas)")
        else:
            feedback_parts.append(f"❌ Insufficient cashback formulas (found {formula_count}, need 6+)")
            logger.warning(f"FAIL: Formula criterion (only {formula_count} formulas)")
            if formula_details:
                logger.debug(f"Formula details: {formula_details}")
        
        # Criterion 3: Optimization logic (MAX or nested IF)
        has_optimization, opt_details = check_optimization_logic(data, sheet_name)
        subscores['has_optimization'] = has_optimization
        if has_optimization:
            criteria_met += 1
            feedback_parts.append(f"✅ Optimization logic detected: {opt_details}")
            logger.info(f"PASS: Optimization criterion ({opt_details})")
        else:
            feedback_parts.append("❌ No optimization formulas (MAX/IF) found")
            logger.warning("FAIL: Optimization criterion")
        
        # Criterion 4: Calculation accuracy
        calc_accurate, calc_feedback = verify_sample_calculations(data, sheet_name)
        subscores['calculations_accurate'] = calc_accurate
        if calc_accurate:
            criteria_met += 1
            feedback_parts.append(f"✅ Calculations accurate: {calc_feedback}")
            logger.info(f"PASS: Calculation accuracy ({calc_feedback})")
        else:
            feedback_parts.append(f"⚠️ Calculation issues: {calc_feedback}")
            logger.warning(f"FAIL: Calculation accuracy ({calc_feedback})")
        
        # Criterion 5: Actionable recommendations present
        has_recommendations, rec_count = check_recommendations_present(data, sheet_name)
        subscores['has_recommendations'] = has_recommendations
        subscores['recommendation_count'] = rec_count
        if has_recommendations:
            criteria_met += 1
            feedback_parts.append(f"✅ Actionable recommendations present ({rec_count} found)")
            logger.info(f"PASS: Recommendations criterion ({rec_count} recommendations)")
        else:
            feedback_parts.append(f"❌ No clear card recommendations found")
            logger.warning("FAIL: Recommendations criterion")
        
        # Criterion 6: File saved properly (if we got here, file was saved)
        criteria_met += 1
        feedback_parts.append("✅ File saved correctly")
        subscores['file_saved'] = True
        logger.info("PASS: File saved criterion")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 67  # Need 4/6 criteria (67%)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent credit card optimizer!")
        elif passed:
            feedback_parts.append("✅ Credit card optimizer task completed")
        else:
            feedback_parts.append("❌ Task requirements not met")
        
        logger.info(f"Final Score: {criteria_met}/{total_criteria} ({score}%)")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_environment(temp_dir)


def check_data_structure(data, sheet_name):
    """
    Check if spreadsheet has proper structure with categories and cards.
    Need at least 3-4 category rows and 5+ columns (spending + 3 cards + best).
    """
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        logger.warning(f"Sheet {sheet_name} not found")
        return False
    
    rows = sheets[sheet_name]
    
    # Need at least 4 rows (header + 3 categories minimum)
    if len(rows) < 4:
        logger.debug(f"Insufficient rows: {len(rows)}")
        return False
    
    # Check for sufficient columns in first few rows
    # Need at least 5 columns (category, spending, card1, card2, card3)
    has_enough_cols = False
    for i in range(min(6, len(rows))):
        if len(rows[i]) >= 5:
            # Check if row has actual data (not all empty)
            non_empty = sum(1 for cell in rows[i][:8] if cell.get('value') not in [None, '', 0])
            if non_empty >= 3:
                has_enough_cols = True
                break
    
    logger.debug(f"Structure check: rows={len(rows)}, has_enough_cols={has_enough_cols}")
    return has_enough_cols


def count_cashback_formulas(data, sheet_name):
    """
    Count cells with cashback calculation formulas (multiplication with percentages).
    Returns count and sample formula details.
    """
    formula_count = 0
    formula_examples = []
    
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return 0, []
    
    rows = sheets[sheet_name]
    
    # Check first 15 rows and 12 columns
    for row_idx, row in enumerate(rows[:15]):
        for col_idx, cell in enumerate(row[:12]):
            formula = cell.get('formula', '')
            if not formula:
                continue
            
            formula_upper = formula.upper()
            
            # Check if it's a multiplication formula
            if '*' not in formula:
                continue
            
            # Check if it involves percentages or decimals
            # Look for patterns like: =A1*0.03, =A1*3%, =A1*.02
            has_percentage = '%' in formula
            has_decimal = re.search(r'0\.\d+', formula)
            has_cell_ref = re.search(r'[A-Z]+\d+', formula)
            
            if has_cell_ref and (has_decimal or has_percentage):
                formula_count += 1
                if len(formula_examples) < 3:
                    formula_examples.append(f"Cell({row_idx+1},{col_idx+1}): {formula}")
                logger.debug(f"Found cashback formula at ({row_idx+1},{col_idx+1}): {formula}")
    
    logger.info(f"Total cashback formulas found: {formula_count}")
    return formula_count, formula_examples


def check_optimization_logic(data, sheet_name):
    """
    Check for MAX or nested IF formulas that identify best card.
    Returns (has_optimization, details).
    """
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return False, "Sheet not found"
    
    rows = sheets[sheet_name]
    
    max_count = 0
    nested_if_count = 0
    
    for row_idx, row in enumerate(rows[:15]):
        for col_idx, cell in enumerate(row[:12]):
            formula = cell.get('formula', '')
            if not formula:
                continue
            
            formula_upper = formula.upper()
            
            # Check for MAX function
            if 'MAX(' in formula_upper:
                max_count += 1
                logger.debug(f"Found MAX at ({row_idx+1},{col_idx+1}): {formula}")
            
            # Check for nested IF (at least 2 IF statements)
            if formula_upper.count('IF(') >= 2:
                nested_if_count += 1
                logger.debug(f"Found nested IF at ({row_idx+1},{col_idx+1}): {formula}")
    
    if max_count > 0:
        return True, f"{max_count} MAX function(s)"
    elif nested_if_count > 0:
        return True, f"{nested_if_count} nested IF statement(s)"
    else:
        return False, "No optimization functions found"


def verify_sample_calculations(data, sheet_name):
    """
    Verify at least one calculation is mathematically correct.
    Look for cashback values that are reasonable percentages of spending.
    """
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return False, "Sheet not found"
    
    rows = sheets[sheet_name]
    
    # Look for patterns: spending amount (100-2000) and cashback result (1-100)
    verified_calculations = 0
    
    for row_idx in range(1, min(8, len(rows))):
        row = rows[row_idx]
        
        # Collect all numeric values in the row
        values = []
        for col_idx in range(min(12, len(row))):
            val = row[col_idx].get('value')
            if isinstance(val, (int, float)) and val > 0:
                values.append((col_idx, val))
        
        if len(values) < 2:
            continue
        
        # Look for potential spending-cashback pairs
        for i, (col1, val1) in enumerate(values):
            if not (100 <= val1 <= 2000):
                continue
            
            # This could be spending, look for cashback values
            for j, (col2, val2) in enumerate(values):
                if i == j:
                    continue
                
                if not (1 <= val2 <= 100):
                    continue
                
                # Calculate ratio
                ratio = val2 / val1
                
                # Check if ratio is a reasonable reward percentage (0.5% - 5%)
                if 0.005 <= ratio <= 0.05:
                    verified_calculations += 1
                    logger.debug(f"Verified calculation: ${val1} * {ratio:.1%} = ${val2}")
                    
                    if verified_calculations >= 2:
                        return True, f"At least {verified_calculations} calculations verified"
    
    if verified_calculations > 0:
        return True, f"{verified_calculations} calculation(s) verified"
    else:
        return False, "Could not verify calculation accuracy"


def check_recommendations_present(data, sheet_name):
    """
    Check if recommendations (card names or indicators) are present.
    Look for cells containing card identifiers like "Card A", "Card B", "A", "B", etc.
    """
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return False, 0
    
    rows = sheets[sheet_name]
    
    card_mentions = 0
    card_patterns = [
        r'CARD\s*[ABC]',  # "Card A", "Card B", etc.
        r'^[ABC]$',        # Just "A", "B", "C"
        r'OPTION\s*[ABC]', # "Option A", etc.
    ]
    
    # Check first 10 rows
    for row_idx, row in enumerate(rows[:10]):
        for col_idx, cell in enumerate(row[:12]):
            value = str(cell.get('value', '')).upper().strip()
            
            if not value or len(value) > 20:
                continue
            
            # Check against patterns
            for pattern in card_patterns:
                if re.search(pattern, value):
                    card_mentions += 1
                    logger.debug(f"Found card mention at ({row_idx+1},{col_idx+1}): {value}")
                    break
    
    logger.info(f"Total card recommendations found: {card_mentions}")
    
    # Should have at least 3 card recommendations (one per category minimum)
    return card_mentions >= 3, card_mentions
