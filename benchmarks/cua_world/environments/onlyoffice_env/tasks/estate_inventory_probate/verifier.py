#!/usr/bin/env python3
"""
Verifier for Estate Inventory Probate task

Verifies that the user has:
1. Created a valid spreadsheet file
2. Organized assets and liabilities into clear sections
3. Included all required asset values from the source document
4. Included all required liability values from the source document
5. Used formulas (not hard-coded values) for calculations
6. Calculated correct totals for Assets, Liabilities, and Net Estate
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values from the estate documents
EXPECTED_ASSETS = {
    8450.23: "First National checking",
    15200.00: "First National savings",
    3100.50: "Credit Union",
    47850.00: "Vanguard IRA",
    12300.00: "Schwab account",
    185000.00: "Primary residence",
    22000.00: "Undeveloped lot",
    11500.00: "2015 CR-V",
    4200.00: "2008 Camry",
    8500.00: "Jewelry",
    5000.00: "Furniture"
}

EXPECTED_LIABILITIES = {
    68400.00: "Mortgage",
    3245.18: "Credit card",
    2180.00: "Medical bills",
    6500.00: "Funeral expenses"
}

TOTAL_ASSETS = 323100.73
TOTAL_LIABILITIES = 80325.18
NET_ESTATE = 242775.55


def find_value_in_sheet(sheet, target_value, tolerance=0.50):
    """
    Search for a numeric value in the sheet within tolerance.
    Returns (found, cell_reference) tuple.
    """
    try:
        for row in sheet.iter_rows(max_row=200, max_col=20):
            for cell in row:
                if cell.value is not None and isinstance(cell.value, (int, float)):
                    if abs(float(cell.value) - target_value) <= tolerance:
                        return True, cell.coordinate
        return False, None
    except Exception as e:
        logger.error(f"Error searching for value {target_value}: {e}")
        return False, None


def check_cell_has_formula(sheet, cell_ref):
    """
    Check if a cell contains a formula (not just a value).
    """
    try:
        cell = sheet[cell_ref]
        # Check if cell has a formula
        if hasattr(cell, 'data_type') and cell.data_type == 'f':
            return True
        # Alternative: check if value starts with '='
        if hasattr(cell, 'value') and isinstance(cell.value, str) and cell.value.startswith('='):
            return True
        return False
    except Exception as e:
        logger.error(f"Error checking formula in {cell_ref}: {e}")
        return False


def find_formulas_in_sheet(sheet):
    """
    Find all cells containing formulas in the sheet.
    Returns list of (cell_reference, formula_value) tuples.
    """
    formulas = []
    try:
        for row in sheet.iter_rows(max_row=200, max_col=20):
            for cell in row:
                if cell.value is not None:
                    # Check if it's a formula cell
                    if hasattr(cell, 'data_type') and cell.data_type == 'f':
                        formulas.append((cell.coordinate, str(cell.value)))
                    elif isinstance(cell.value, str) and cell.value.startswith('='):
                        formulas.append((cell.coordinate, cell.value))
    except Exception as e:
        logger.error(f"Error finding formulas: {e}")
    return formulas


def search_for_section_headers(sheet):
    """
    Search for section headers like "ASSETS", "LIABILITIES", "TOTAL", etc.
    Returns dict with section names and their row positions.
    """
    sections = {
        'assets': False,
        'liabilities': False,
        'total': False
    }
    
    try:
        for row in sheet.iter_rows(max_row=200, max_col=10):
            for cell in row:
                if cell.value and isinstance(cell.value, str):
                    text = cell.value.lower()
                    if 'asset' in text and 'liabilit' not in text:
                        sections['assets'] = True
                    if 'liabilit' in text or 'debt' in text:
                        sections['liabilities'] = True
                    if 'total' in text or 'net' in text or 'summary' in text:
                        sections['total'] = True
    except Exception as e:
        logger.error(f"Error searching for sections: {e}")
    
    return sections


def verify_estate_inventory_probate(traj, env_info, task_info):
    """
    Verify that estate inventory spreadsheet was created correctly for probate filing.
    
    Scoring breakdown (100 points total):
    - File exists and valid: 10 points
    - Required sections present: 15 points
    - Asset completeness: 25 points
    - Liability completeness: 20 points
    - Formula usage and calculations: 20 points
    - Professional organization: 10 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Copy function not available"
        }

    container_path = "/home/ga/Documents/Estate_Inventory.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_estate_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load estate inventory: {error}"
            }

        score = 0
        max_score = 100
        feedback = []

        # ==== CRITERION 1: File exists and is valid (10 points) ====
        score += 10
        feedback.append("✅ File exists and is valid XLSX format")

        # Get the first sheet
        sheet_name = wb.sheetnames[0]
        sheet = wb[sheet_name]

        # ==== CRITERION 2: Required sections present (15 points) ====
        sections = search_for_section_headers(sheet)
        section_score = 0
        
        if sections['assets']:
            section_score += 5
            feedback.append("✅ Assets section header found")
        else:
            feedback.append("❌ Assets section not clearly labeled")
        
        if sections['liabilities']:
            section_score += 5
            feedback.append("✅ Liabilities section header found")
        else:
            feedback.append("❌ Liabilities section not clearly labeled")
        
        if sections['total']:
            section_score += 5
            feedback.append("✅ Total/Summary section found")
        else:
            feedback.append("❌ Total/Summary section not found")
        
        score += section_score

        # ==== CRITERION 3: Asset completeness (25 points) ====
        assets_found = 0
        missing_assets = []
        tolerance = 0.50

        for expected_val, description in EXPECTED_ASSETS.items():
            found, cell_ref = find_value_in_sheet(sheet, expected_val, tolerance)
            if found:
                assets_found += 1
                logger.debug(f"Found asset {description}: ${expected_val:,.2f} at {cell_ref}")
            else:
                missing_assets.append(f"{description} (${expected_val:,.2f})")

        asset_score = int((assets_found / len(EXPECTED_ASSETS)) * 25)
        score += asset_score
        
        if assets_found == len(EXPECTED_ASSETS):
            feedback.append(f"✅ All {len(EXPECTED_ASSETS)} required assets found ({asset_score}/25 pts)")
        else:
            feedback.append(f"⚠️  Found {assets_found}/{len(EXPECTED_ASSETS)} required assets ({asset_score}/25 pts)")
            if len(missing_assets) <= 3:
                for missing in missing_assets:
                    feedback.append(f"   Missing: {missing}")
            else:
                feedback.append(f"   Missing {len(missing_assets)} assets")

        # ==== CRITERION 4: Liability completeness (20 points) ====
        liabilities_found = 0
        missing_liabilities = []

        for expected_val, description in EXPECTED_LIABILITIES.items():
            found, cell_ref = find_value_in_sheet(sheet, expected_val, tolerance)
            if found:
                liabilities_found += 1
                logger.debug(f"Found liability {description}: ${expected_val:,.2f} at {cell_ref}")
            else:
                missing_liabilities.append(f"{description} (${expected_val:,.2f})")

        liability_score = int((liabilities_found / len(EXPECTED_LIABILITIES)) * 20)
        score += liability_score
        
        if liabilities_found == len(EXPECTED_LIABILITIES):
            feedback.append(f"✅ All {len(EXPECTED_LIABILITIES)} required liabilities found ({liability_score}/20 pts)")
        else:
            feedback.append(f"⚠️  Found {liabilities_found}/{len(EXPECTED_LIABILITIES)} required liabilities ({liability_score}/20 pts)")
            for missing in missing_liabilities:
                feedback.append(f"   Missing: {missing}")

        # ==== CRITERION 5: Formula usage and correct calculations (20 points) ====
        formulas = find_formulas_in_sheet(sheet)
        formula_score = 0
        
        # Check for presence of formulas
        if len(formulas) >= 3:
            formula_score += 6
            feedback.append(f"✅ Formulas detected ({len(formulas)} formula cells found)")
            logger.debug(f"Formulas found: {formulas}")
        elif len(formulas) >= 1:
            formula_score += 3
            feedback.append(f"⚠️  Some formulas found ({len(formulas)}), but expected at least 3")
        else:
            feedback.append("❌ No formulas detected - values appear hard-coded")

        # Check for correct total calculations (with generous tolerance for rounding)
        calc_tolerance = 2.0  # Allow for rounding differences
        
        # Total Assets
        total_assets_found, ta_cell = find_value_in_sheet(sheet, TOTAL_ASSETS, calc_tolerance)
        if total_assets_found:
            formula_score += 5
            feedback.append(f"✅ Total Assets correct (~${TOTAL_ASSETS:,.2f})")
        else:
            feedback.append(f"❌ Total Assets incorrect or missing (expected ${TOTAL_ASSETS:,.2f})")
        
        # Total Liabilities
        total_liab_found, tl_cell = find_value_in_sheet(sheet, TOTAL_LIABILITIES, calc_tolerance)
        if total_liab_found:
            formula_score += 4
            feedback.append(f"✅ Total Liabilities correct (~${TOTAL_LIABILITIES:,.2f})")
        else:
            feedback.append(f"❌ Total Liabilities incorrect or missing (expected ${TOTAL_LIABILITIES:,.2f})")
        
        # Net Estate
        net_estate_found, ne_cell = find_value_in_sheet(sheet, NET_ESTATE, calc_tolerance)
        if net_estate_found:
            formula_score += 5
            feedback.append(f"✅ Net Estate Value correct (~${NET_ESTATE:,.2f})")
        else:
            feedback.append(f"❌ Net Estate Value incorrect or missing (expected ${NET_ESTATE:,.2f})")
        
        score += formula_score

        # ==== CRITERION 6: Professional organization (10 points) ====
        org_score = 0
        
        # Check if reasonable amount of data exists
        data = get_sheet_data(wb, sheet_name, max_rows=100, max_cols=10)
        non_empty_cells = sum(1 for row in data for cell in row if cell is not None)
        
        if non_empty_cells >= 20:
            org_score += 5
            feedback.append(f"✅ Spreadsheet has substantial content ({non_empty_cells} filled cells)")
        else:
            feedback.append(f"⚠️  Spreadsheet seems sparse ({non_empty_cells} filled cells)")
        
        # Check if sections are clearly delineated
        if section_score >= 10:
            org_score += 5
            feedback.append("✅ Document structure is clear")
        else:
            feedback.append("⚠️  Document structure could be clearer")
        
        score += org_score

        # ==== FINAL ASSESSMENT ====
        passed = score >= 70  # Pass threshold: 70/100
        
        # Add summary feedback
        summary = f"SCORE: {score}/{max_score} | "
        if passed:
            summary += "✅ PASSED - Estate inventory is adequate for court filing"
        else:
            summary += "❌ FAILED - Estate inventory needs improvement"
        
        feedback.insert(0, summary)
        
        return {
            "passed": passed,
            "score": score / max_score,
            "feedback": " | ".join(feedback)
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
