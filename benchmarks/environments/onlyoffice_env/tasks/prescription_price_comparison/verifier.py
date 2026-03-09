#!/usr/bin/env python3
"""
Verifier for Prescription Price Comparison task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_prescription_comparison(traj, env_info, task_info):
    """
    Verify that prescription price comparison spreadsheet was created correctly.

    Checks:
    1. All 4 medications are listed (Metformin, Lisinopril, Atorvastatin, Levothyroxine)
    2. At least 5 pharmacy options are included
    3. Sufficient price data is entered (at least 18 price cells)
    4. Formula(s) are used for calculations
    5. Total row exists
    6. Reasonable table structure
    
    Scoring:
    - 2.0 points: All 4 medications present
    - 1.5 points: At least 5 pharmacy options
    - 2.0 points: Adequate price data (18+ prices)
    - 1.5 points: Formula usage
    - 1.0 point: Total row
    - 1.0 point: Good table structure
    - 1.0 point: Overall quality bonus
    Total: 10.0 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/medication_costs.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_prescription_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load spreadsheet: {error}"
            }

        # Get the active sheet
        try:
            sheet = wb.active
        except Exception as e:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Could not access worksheet: {str(e)}"
            }

        # Extract data from sheet
        data = []
        try:
            for row in sheet.iter_rows(min_row=1, max_row=50, max_col=20, values_only=True):
                data.append(row)
        except Exception as e:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Error reading sheet data: {str(e)}"
            }

        # Initialize scoring
        score = 0.0
        feedback_parts = []
        max_score = 10.0

        # Convert all cells to lowercase strings for comparison
        data_lower = []
        for row in data:
            row_lower = []
            for cell in row:
                if cell is None:
                    row_lower.append('')
                else:
                    row_lower.append(str(cell).lower())
            data_lower.append(row_lower)
        
        all_text = ' '.join([' '.join(row) for row in data_lower])

        # Check 1: All 4 medications present (2.0 points)
        required_meds = {
            'metformin': False,
            'lisinopril': False,
            'atorvastatin': False,
            'levothyroxine': False
        }
        
        for med in required_meds.keys():
            if med in all_text:
                required_meds[med] = True
        
        meds_found = sum(required_meds.values())
        
        if meds_found == 4:
            score += 2.0
            feedback_parts.append("✅ All 4 medications listed")
        elif meds_found == 3:
            score += 1.5
            missing = [m for m, found in required_meds.items() if not found]
            feedback_parts.append(f"⚠️ 3/4 medications found (missing: {', '.join(missing)})")
        elif meds_found == 2:
            score += 1.0
            missing = [m for m, found in required_meds.items() if not found]
            feedback_parts.append(f"⚠️ Only 2/4 medications found (missing: {', '.join(missing)})")
        else:
            feedback_parts.append(f"❌ Only {meds_found}/4 medications found")

        # Check 2: At least 5 pharmacy names (1.5 points)
        pharmacies = ['cvs', 'walgreens', 'costco', 'walmart', 'kroger', 'goodrx', 'target']
        pharmacies_found = 0
        found_pharmacy_names = []
        
        for pharm in pharmacies:
            if pharm in all_text:
                pharmacies_found += 1
                found_pharmacy_names.append(pharm)
        
        if pharmacies_found >= 5:
            score += 1.5
            feedback_parts.append(f"✅ {pharmacies_found} pharmacy options included")
        elif pharmacies_found >= 4:
            score += 1.0
            feedback_parts.append(f"⚠️ 4 pharmacies compared (expected 5+)")
        elif pharmacies_found >= 3:
            score += 0.5
            feedback_parts.append(f"⚠️ Only {pharmacies_found} pharmacies found")
        else:
            feedback_parts.append(f"❌ Only {pharmacies_found} pharmacies found (expected 5+)")

        # Check 3: Price data present - look for $ or numbers in typical price range (2.0 points)
        price_cells = 0
        dollar_signs = 0
        
        for row in data:
            for cell in row:
                if cell is not None:
                    cell_str = str(cell)
                    # Check if cell contains $
                    if '$' in cell_str:
                        dollar_signs += 1
                        price_cells += 1
                    # Check if cell is a number between 1-100 (likely prices)
                    elif isinstance(cell, (int, float)) and 1 < cell < 100:
                        price_cells += 1
        
        if price_cells >= 18:  # 4 meds × 5 pharmacies = 20, allow some missing
            score += 2.0
            feedback_parts.append(f"✅ {price_cells} price values entered")
        elif price_cells >= 15:
            score += 1.5
            feedback_parts.append(f"⚠️ {price_cells} price values (expected ~20)")
        elif price_cells >= 12:
            score += 1.0
            feedback_parts.append(f"⚠️ {price_cells} price values (expected ~20)")
        elif price_cells >= 8:
            score += 0.5
            feedback_parts.append(f"⚠️ Only {price_cells} price values found")
        else:
            feedback_parts.append(f"❌ Only {price_cells} price values found (expected ~20)")

        # Check 4: Formula usage for totals/calculations (1.5 points)
        formula_found = False
        formula_count = 0
        
        try:
            for row in sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula_found = True
                        formula_count += 1
        except Exception as e:
            logger.warning(f"Error checking for formulas: {e}")
        
        if formula_count >= 3:
            score += 1.5
            feedback_parts.append(f"✅ {formula_count} formula(s) used for calculations")
        elif formula_count >= 1:
            score += 1.0
            feedback_parts.append(f"⚠️ {formula_count} formula(s) found (expected more for totals)")
        else:
            feedback_parts.append("❌ No formulas detected (totals should use formulas)")

        # Check 5: Total row exists (1.0 point)
        has_total = 'total' in all_text
        has_sum = 'sum' in all_text
        
        if has_total or has_sum:
            score += 1.0
            feedback_parts.append("✅ Total cost row included")
        else:
            feedback_parts.append("❌ No total row found")

        # Check 6: Reasonable table structure (1.0 point)
        # Check if there's a decent grid structure (at least 5 rows, 5 columns with content)
        non_empty_rows = sum(1 for row in data if any(cell for cell in row if cell is not None))
        max_cols_in_row = max((len([cell for cell in row if cell is not None]) for row in data), default=0)
        
        if non_empty_rows >= 6 and max_cols_in_row >= 5:
            score += 1.0
            feedback_parts.append(f"✅ Well-structured table ({non_empty_rows} rows × {max_cols_in_row} cols)")
        elif non_empty_rows >= 5 and max_cols_in_row >= 4:
            score += 0.5
            feedback_parts.append(f"⚠️ Table structure adequate ({non_empty_rows} rows × {max_cols_in_row} cols)")
        else:
            feedback_parts.append(f"❌ Table structure insufficient ({non_empty_rows} rows × {max_cols_in_row} cols)")

        # Bonus check: Overall quality (1.0 point)
        # Award bonus if: has all meds, good pharmacy coverage, formulas, and totals
        quality_score = 0
        if meds_found >= 3:
            quality_score += 0.25
        if pharmacies_found >= 4:
            quality_score += 0.25
        if formula_found:
            quality_score += 0.25
        if has_total:
            quality_score += 0.25
        
        score += quality_score
        if quality_score >= 0.75:
            feedback_parts.append("✅ High-quality comparison spreadsheet")
        elif quality_score >= 0.5:
            feedback_parts.append("⚠️ Good effort, some improvements possible")

        # Normalize score to 0-1 range
        final_score = min(score / max_score, 1.0)
        passed = final_score >= 0.7

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
