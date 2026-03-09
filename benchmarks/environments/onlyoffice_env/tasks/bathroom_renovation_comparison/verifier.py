#!/usr/bin/env python3
"""
Verifier for Bathroom Renovation Comparison task
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def fuzzy_match_text(cell_value, keywords):
    """
    Check if cell contains any of the keywords (case-insensitive)
    
    Args:
        cell_value: Cell value to check
        keywords: List of keywords to match
        
    Returns:
        True if any keyword found
    """
    if cell_value is None:
        return False
    cell_lower = str(cell_value).lower()
    return any(keyword.lower() in cell_lower for keyword in keywords)


def verify_renovation_comparison(traj, env_info, task_info):
    """
    Verify that bathroom renovation comparison spreadsheet was created correctly.

    Checks:
    1. File exists and is parseable
    2. Headers present (Material, store names in row 1)
    3. Materials listed (5 items with fuzzy matching)
    4. Total label in A7
    5. Prices are numeric and in reasonable range
    6. All required data cells filled (15 prices)
    7. SUM formulas calculate correct totals for each store
    8. Bonus: MIN formulas for best prices (optional)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/bathroom_renovation_comparison.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_renovation_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Get the active sheet
        try:
            sheet_name = wb.sheetnames[0]
            sheet = wb[sheet_name]
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Cannot access worksheet: {e}"}

        criteria_passed = 0
        total_criteria = 4  # Core criteria for passing
        feedback_parts = []

        # === CRITERION 1: Check Headers (Row 1) ===
        header_a1 = get_cell_value(wb, sheet_name, 'A1')
        header_b1 = get_cell_value(wb, sheet_name, 'B1')
        header_c1 = get_cell_value(wb, sheet_name, 'C1')
        header_d1 = get_cell_value(wb, sheet_name, 'D1')

        headers_valid = (
            fuzzy_match_text(header_a1, ['material', 'item', 'product']) and
            fuzzy_match_text(header_b1, ['home depot', 'homedepot', 'home', 'depot']) and
            fuzzy_match_text(header_c1, ["lowe's", "lowes", "lowe"]) and
            fuzzy_match_text(header_d1, ["builder's best", "builders best", "builder", "local"])
        )

        if headers_valid:
            criteria_passed += 1
            feedback_parts.append("✅ Headers present and correct")
        else:
            feedback_parts.append(f"❌ Headers missing or incorrect: A1={header_a1}, B1={header_b1}, C1={header_c1}, D1={header_d1}")

        # === CRITERION 2: Check Materials List (A2-A6) and Total Label (A7) ===
        materials_found = []
        material_checks = [
            ('A2', ['toilet']),
            ('A3', ['vanity', 'sink']),
            ('A4', ['faucet', 'tap']),
            ('A5', ['tile']),
            ('A6', ['grout', 'cement'])
        ]

        materials_correct = 0
        for cell_ref, keywords in material_checks:
            cell_value = get_cell_value(wb, sheet_name, cell_ref)
            if fuzzy_match_text(cell_value, keywords):
                materials_correct += 1
                materials_found.append(f"{cell_ref}:{cell_value}")

        total_label = get_cell_value(wb, sheet_name, 'A7')
        has_total_label = fuzzy_match_text(total_label, ['total', 'sum'])

        if materials_correct >= 4 and has_total_label:
            criteria_passed += 1
            feedback_parts.append(f"✅ Materials list complete ({materials_correct}/5 materials, Total label present)")
        elif materials_correct >= 3:
            feedback_parts.append(f"⚠️ Partial materials list ({materials_correct}/5 materials)")
        else:
            feedback_parts.append(f"❌ Materials list incomplete ({materials_correct}/5 found)")
            if not has_total_label:
                feedback_parts.append(f"❌ Total label missing in A7: {total_label}")

        # === CRITERION 3: Check Price Data (All numeric, reasonable range) ===
        price_cells = [
            'B2', 'B3', 'B4', 'B5', 'B6',  # Home Depot
            'C2', 'C3', 'C4', 'C5', 'C6',  # Lowe's
            'D2', 'D3', 'D4', 'D5', 'D6'   # Builder's Best
        ]

        prices_valid = 0
        prices_out_of_range = 0
        prices_missing = 0

        collected_prices = {
            'home_depot': [],
            'lowes': [],
            'builders': []
        }

        for i, cell_ref in enumerate(price_cells):
            cell_value = get_cell_value(wb, sheet_name, cell_ref)
            
            if cell_value is None:
                prices_missing += 1
                continue
                
            if isinstance(cell_value, (int, float)):
                if 10 <= cell_value <= 500:
                    prices_valid += 1
                    # Collect prices for formula validation
                    if i < 5:
                        collected_prices['home_depot'].append(cell_value)
                    elif i < 10:
                        collected_prices['lowes'].append(cell_value)
                    else:
                        collected_prices['builders'].append(cell_value)
                else:
                    prices_out_of_range += 1
            else:
                prices_missing += 1

        if prices_valid >= 12:  # At least 80% of prices filled correctly
            criteria_passed += 1
            feedback_parts.append(f"✅ Price data complete ({prices_valid}/15 valid prices)")
        elif prices_valid >= 9:
            feedback_parts.append(f"⚠️ Partial price data ({prices_valid}/15 valid)")
        else:
            feedback_parts.append(f"❌ Insufficient price data ({prices_valid}/15 valid, {prices_missing} missing)")

        # === CRITERION 4: Check Total Formulas (B7, C7, D7) ===
        total_b7 = get_cell_value(wb, sheet_name, 'B7')
        total_c7 = get_cell_value(wb, sheet_name, 'C7')
        total_d7 = get_cell_value(wb, sheet_name, 'D7')

        formulas_correct = 0
        
        # Validate Home Depot total
        if total_b7 is not None and isinstance(total_b7, (int, float)):
            if len(collected_prices['home_depot']) >= 4:
                expected_total = sum(collected_prices['home_depot'])
                if abs(total_b7 - expected_total) <= 1.0:
                    formulas_correct += 1
                else:
                    feedback_parts.append(f"⚠️ Home Depot total mismatch: {total_b7:.2f} (expected {expected_total:.2f})")
        
        # Validate Lowe's total
        if total_c7 is not None and isinstance(total_c7, (int, float)):
            if len(collected_prices['lowes']) >= 4:
                expected_total = sum(collected_prices['lowes'])
                if abs(total_c7 - expected_total) <= 1.0:
                    formulas_correct += 1
                else:
                    feedback_parts.append(f"⚠️ Lowe's total mismatch: {total_c7:.2f} (expected {expected_total:.2f})")
        
        # Validate Builder's Best total
        if total_d7 is not None and isinstance(total_d7, (int, float)):
            if len(collected_prices['builders']) >= 4:
                expected_total = sum(collected_prices['builders'])
                if abs(total_d7 - expected_total) <= 1.0:
                    formulas_correct += 1
                else:
                    feedback_parts.append(f"⚠️ Builder's Best total mismatch: {total_d7:.2f} (expected {expected_total:.2f})")

        if formulas_correct >= 2:
            criteria_passed += 1
            if formulas_correct == 3:
                feedback_parts.append(f"✅ All total formulas correct (Home Depot: ${total_b7:.2f}, Lowe's: ${total_c7:.2f}, Builder's: ${total_d7:.2f})")
            else:
                feedback_parts.append(f"⚠️ {formulas_correct}/3 total formulas correct")
        else:
            feedback_parts.append(f"❌ Total formulas missing or incorrect ({formulas_correct}/3 correct)")

        # === BONUS: Check for MIN formulas (Column E - optional) ===
        has_min_formulas = False
        min_correct = 0
        
        for row in range(2, 7):  # Check E2 to E6
            cell_ref = f'E{row}'
            cell_value = get_cell_value(wb, sheet_name, cell_ref)
            
            if cell_value is not None and isinstance(cell_value, (int, float)):
                has_min_formulas = True
                # Check if it matches the minimum of the row
                b_val = get_cell_value(wb, sheet_name, f'B{row}')
                c_val = get_cell_value(wb, sheet_name, f'C{row}')
                d_val = get_cell_value(wb, sheet_name, f'D{row}')
                
                if all(isinstance(v, (int, float)) for v in [b_val, c_val, d_val]):
                    expected_min = min(b_val, c_val, d_val)
                    if abs(cell_value - expected_min) <= 0.01:
                        min_correct += 1

        if has_min_formulas and min_correct >= 4:
            feedback_parts.append(f"🌟 BONUS: Best price comparison included ({min_correct}/5 MIN formulas correct)")
            # Add bonus points
            criteria_passed += 0.5

        # === Calculate Final Score ===
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)