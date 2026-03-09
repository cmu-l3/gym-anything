#!/usr/bin/env python3
"""
Verifier for Insurance Quote Comparison task
"""

import sys
import os
import logging
import re
from typing import Dict, Any, Tuple, Optional

# Add utils to path - use relative path since verification runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Expected data
PROVIDERS = ['SafeDrive', 'QuickQuote', 'BudgetShield']
PROVIDER_DATA = {
    'SafeDrive': {'monthly': 85, 'semi': 320, 'annual': 450, 'total': 2110},
    'QuickQuote': {'monthly': 78, 'semi': 340, 'annual': 475, 'total': 2091},
    'BudgetShield': {'monthly': 92, 'semi': 295, 'annual': 425, 'total': 2119}
}
CHEAPEST_PROVIDER = 'QuickQuote'
CHEAPEST_TOTAL = 2091


def find_provider_row(sheet_data: Dict, sheet_name: str, provider_keyword: str) -> Optional[int]:
    """
    Find the row number containing the provider name.
    
    Args:
        sheet_data: Parsed spreadsheet data
        sheet_name: Name of sheet
        provider_keyword: Keyword to search for (e.g., 'SafeDrive', 'QuickQuote')
        
    Returns:
        Row index (0-based) or None if not found
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return None
    
    rows = sheets[sheet_name]
    for row_idx, row in enumerate(rows):
        for cell in row:
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and isinstance(cell_value, str) and provider_keyword.lower() in cell_value.lower():
                return row_idx
    
    return None


def find_data_in_row(sheet_data: Dict, sheet_name: str, row_idx: int, 
                     expected_values: list, tolerance: float = 1.0) -> Tuple[bool, list]:
    """
    Find expected numeric values in a row.
    
    Returns:
        Tuple of (all_found, found_values)
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets or row_idx >= len(sheets[sheet_name]):
        return False, []
    
    row = sheets[sheet_name][row_idx]
    found_values = []
    
    for cell in row:
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        if isinstance(cell_value, (int, float)):
            found_values.append(float(cell_value))
    
    # Check if all expected values are found
    for expected in expected_values:
        found = any(abs(fv - expected) <= tolerance for fv in found_values)
        if not found:
            return False, found_values
    
    return True, found_values


def check_formulas_exist(sheet_data: Dict, sheet_name: str, row_idx: int) -> Tuple[bool, Optional[str]]:
    """
    Check if formulas exist in the row (especially for total calculation).
    
    Returns:
        Tuple of (has_formula, formula_text)
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets or row_idx >= len(sheets[sheet_name]):
        return False, None
    
    row = sheets[sheet_name][row_idx]
    
    for cell in row:
        formula = cell.get('formula') if isinstance(cell, dict) else None
        if formula:
            # Check for arithmetic operations or SUM
            if any(op in str(formula).upper() for op in ['*', '+', 'SUM', 'PRODUCT']):
                return True, formula
    
    return False, None


def find_total_column_values(sheet_data: Dict, sheet_name: str, 
                            start_row: int, num_providers: int = 3) -> list:
    """
    Find total annual cost values (rightmost numeric column with large values).
    
    Returns:
        List of total values found
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return []
    
    totals = []
    
    for i in range(num_providers):
        row_idx = start_row + i
        if row_idx >= len(sheets[sheet_name]):
            continue
        
        row = sheets[sheet_name][row_idx]
        
        # Look for values in range 2000-3000 (likely annual totals)
        for cell in row:
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if isinstance(cell_value, (int, float)) and 2000 <= cell_value <= 3000:
                totals.append(float(cell_value))
    
    return totals


def verify_insurance_comparison(traj, env_info, task_info):
    """
    Verify insurance comparison task completion.
    
    Checks:
    1. All provider names present
    2. Base premium values entered correctly
    3. Formulas exist for calculations
    4. Total annual costs are correct
    5. Conditional formatting highlights minimum
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/insurance_comparison.ods"
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
        total_criteria = 5
        feedback_parts = []
        subscores = {}

        # Criterion 1: Check provider names are present
        providers_found = {}
        for provider_key in PROVIDERS:
            row_idx = find_provider_row(workbook, sheet_name, provider_key)
            providers_found[provider_key] = row_idx
        
        num_providers_found = sum(1 for v in providers_found.values() if v is not None)
        
        if num_providers_found == 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ All 3 providers found")
            subscores['providers_found'] = True
        elif num_providers_found > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Only {num_providers_found}/3 providers found")
            subscores['providers_found'] = False
        else:
            feedback_parts.append("❌ Provider names not found")
            subscores['providers_found'] = False

        # Criterion 2: Check base premium values
        data_correct = 0
        for provider_key, row_idx in providers_found.items():
            if row_idx is None:
                continue
            
            expected = PROVIDER_DATA[provider_key]
            expected_values = [expected['monthly'], expected['semi'], expected['annual']]
            
            found, values = find_data_in_row(workbook, sheet_name, row_idx, expected_values)
            if found:
                data_correct += 1
        
        if data_correct == 3:
            criteria_passed += 1
            feedback_parts.append("✅ All premium values entered correctly")
            subscores['data_entry'] = True
        elif data_correct > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Only {data_correct}/3 providers have correct data")
            subscores['data_entry'] = False
        else:
            feedback_parts.append("❌ Premium values not found or incorrect")
            subscores['data_entry'] = False

        # Criterion 3: Check formulas exist
        formulas_found = 0
        for provider_key, row_idx in providers_found.items():
            if row_idx is None:
                continue
            
            has_formula, formula_text = check_formulas_exist(workbook, sheet_name, row_idx)
            if has_formula:
                formulas_found += 1
                logger.info(f"Formula found for {provider_key}: {formula_text}")
        
        if formulas_found >= 2:  # At least 2 providers should have formulas
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas present ({formulas_found} found)")
            subscores['formulas_present'] = True
        elif formulas_found > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some formulas found ({formulas_found})")
            subscores['formulas_present'] = False
        else:
            feedback_parts.append("❌ No calculation formulas detected")
            subscores['formulas_present'] = False

        # Criterion 4: Check total calculations are correct
        # Find all values that look like annual totals
        min_row = min(r for r in providers_found.values() if r is not None) if any(providers_found.values()) else 2
        totals = find_total_column_values(workbook, sheet_name, min_row, num_providers=3)
        
        # Check if expected totals are present
        expected_totals = [PROVIDER_DATA[p]['total'] for p in PROVIDERS]
        totals_correct = 0
        
        for expected_total in expected_totals:
            if any(abs(t - expected_total) <= 10 for t in totals):  # $10 tolerance
                totals_correct += 1
        
        if totals_correct == 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ All totals correct: {totals}")
            subscores['calculations_correct'] = True
        elif totals_correct > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Only {totals_correct}/3 totals correct (found: {totals})")
            subscores['calculations_correct'] = False
        else:
            feedback_parts.append(f"❌ Totals incorrect or missing (found: {totals})")
            subscores['calculations_correct'] = False

        # Criterion 5: Check conditional formatting exists
        # This is a simplified check - full conditional formatting detection is complex
        has_formatting = check_conditional_formatting(workbook, sheet_name, "A1:Z30")
        
        # Also check if minimum value is present
        has_minimum = any(abs(t - CHEAPEST_TOTAL) <= 10 for t in totals)
        
        if has_formatting or (has_minimum and totals_correct >= 2):
            criteria_passed += 1
            feedback_parts.append("✅ Formatting/minimum value detected")
            subscores['formatting_applied'] = True
        else:
            feedback_parts.append("⚠️ Conditional formatting not clearly detected")
            subscores['formatting_applied'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent comparison tool!")
        elif passed:
            feedback_parts.append("✅ Task completed")
        else:
            feedback_parts.append("❌ Task requirements not met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
