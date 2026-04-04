#!/usr/bin/env python3
"""
Verifier for Wine Tasting Journal task

Checks:
1. All 6 wines entered with correct data (names, varietals, ratings, prices)
2. Average rating formula in C9
3. Average price formula in D9
4. Recommendation formulas in F2:F7
5. Conditional formatting applied
"""

import sys
import os
import logging
import re
import zipfile
from xml.etree import ElementTree as ET

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    verify_cell_value,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected wine data: (name, varietal, rating, price, recommend)
EXPECTED_WINES = [
    ("Château Margaux Reserve", "Cabernet Sauvignon", 4.5, 22.0, "YES"),
    ("Sunrise Valley Chardonnay", "Chardonnay", 3.5, 18.0, "NO"),
    ("Monte Rosso Pinot", "Pinot Noir", 4.2, 28.0, "NO"),
    ("Desert Bloom Rosé", "Rosé", 3.8, 15.0, "NO"),
    ("Vintage Creek Merlot", "Merlot", 4.3, 24.0, "YES"),
    ("Hillside Sauvignon Blanc", "Sauvignon Blanc", 3.2, 16.0, "NO")
]

EXPECTED_AVG_RATING = 3.92  # (4.5+3.5+4.2+3.8+4.3+3.2)/6 = 23.5/6
EXPECTED_AVG_PRICE = 20.5   # (22+18+28+15+24+16)/6 = 123/6


def normalize_string(s):
    """Normalize string for comparison (lowercase, strip whitespace)"""
    if s is None:
        return ""
    return str(s).strip().lower()


def check_wine_data(workbook, sheet_name):
    """
    Check if all 6 wines have correct data entered.
    Returns (num_correct, feedback_list)
    """
    feedback = []
    wines_correct = 0
    
    for i, expected in enumerate(EXPECTED_WINES):
        row = i + 2  # Data starts at row 2
        exp_name, exp_varietal, exp_rating, exp_price, exp_recommend = expected
        
        # Check wine name (A column)
        actual_name = get_cell_value(workbook, sheet_name, f"A{row}")
        name_match = normalize_string(exp_name) in normalize_string(actual_name) or \
                     normalize_string(actual_name) in normalize_string(exp_name)
        
        # Check varietal (B column)
        actual_varietal = get_cell_value(workbook, sheet_name, f"B{row}")
        varietal_match = normalize_string(exp_varietal) == normalize_string(actual_varietal)
        
        # Check rating (C column) - allow small tolerance
        actual_rating = get_cell_value(workbook, sheet_name, f"C{row}")
        rating_match = False
        try:
            rating_match = abs(float(actual_rating) - exp_rating) <= 0.15
        except (ValueError, TypeError):
            pass
        
        # Check price (D column) - allow small tolerance
        actual_price = get_cell_value(workbook, sheet_name, f"D{row}")
        price_match = False
        try:
            price_match = abs(float(actual_price) - exp_price) <= 1.0
        except (ValueError, TypeError):
            pass
        
        # Count this wine as correct if most fields match
        if sum([name_match, varietal_match, rating_match, price_match]) >= 3:
            wines_correct += 1
        else:
            feedback.append(f"Wine {i+1} (row {row}): issues detected")
    
    if wines_correct == 6:
        feedback.append("✅ All 6 wines entered correctly")
    elif wines_correct >= 4:
        feedback.append(f"⚠️ {wines_correct}/6 wines entered correctly")
    else:
        feedback.append(f"❌ Only {wines_correct}/6 wines entered correctly")
    
    return wines_correct, feedback


def check_average_formulas(workbook, sheet_name):
    """
    Check average rating and price formulas.
    Returns (rating_ok, price_ok, feedback_list)
    """
    feedback = []
    
    # Check average rating formula (C9)
    c9_formula = get_cell_formula(workbook, sheet_name, "C9")
    c9_value = get_cell_value(workbook, sheet_name, "C9")
    
    rating_formula_ok = False
    if c9_formula and "AVERAGE" in c9_formula.upper():
        # Check if result is approximately correct
        try:
            if abs(float(c9_value) - EXPECTED_AVG_RATING) <= 0.15:
                rating_formula_ok = True
                feedback.append(f"✅ Average rating formula correct: {c9_formula} = {c9_value:.2f}")
            else:
                feedback.append(f"⚠️ Average rating formula present but result unexpected: {c9_value} (expected ~{EXPECTED_AVG_RATING:.2f})")
                rating_formula_ok = True  # Still give credit for having the formula
        except (ValueError, TypeError):
            feedback.append(f"❌ Average rating formula present but value invalid: {c9_value}")
    else:
        feedback.append(f"❌ C9 missing AVERAGE formula (got: {c9_formula or 'no formula'})")
    
    # Check average price formula (D9)
    d9_formula = get_cell_formula(workbook, sheet_name, "D9")
    d9_value = get_cell_value(workbook, sheet_name, "D9")
    
    price_formula_ok = False
    if d9_formula and "AVERAGE" in d9_formula.upper():
        # Check if result is approximately correct
        try:
            if abs(float(d9_value) - EXPECTED_AVG_PRICE) <= 1.5:
                price_formula_ok = True
                feedback.append(f"✅ Average price formula correct: {d9_formula} = ${d9_value:.2f}")
            else:
                feedback.append(f"⚠️ Average price formula present but result unexpected: {d9_value} (expected ~${EXPECTED_AVG_PRICE:.2f})")
                price_formula_ok = True  # Still give credit for having the formula
        except (ValueError, TypeError):
            feedback.append(f"❌ Average price formula present but value invalid: {d9_value}")
    else:
        feedback.append(f"❌ D9 missing AVERAGE formula (got: {d9_formula or 'no formula'})")
    
    return rating_formula_ok, price_formula_ok, feedback


def check_recommendation_formulas(workbook, sheet_name):
    """
    Check recommendation formulas in F2:F7.
    Returns (num_correct, feedback_list)
    """
    feedback = []
    formulas_correct = 0
    results_correct = 0
    
    for i, expected in enumerate(EXPECTED_WINES):
        row = i + 2
        exp_recommend = expected[4]
        
        # Check formula structure
        formula = get_cell_formula(workbook, sheet_name, f"F{row}")
        actual_value = get_cell_value(workbook, sheet_name, f"F{row}")
        
        has_formula = formula is not None and \
                     "IF" in formula.upper() and \
                     "AND" in formula.upper()
        
        if has_formula:
            formulas_correct += 1
        
        # Check result
        if normalize_string(actual_value) == normalize_string(exp_recommend):
            results_correct += 1
    
    if formulas_correct >= 5:
        feedback.append(f"✅ Recommendation formulas present ({formulas_correct}/6 cells)")
    elif formulas_correct >= 3:
        feedback.append(f"⚠️ Some recommendation formulas present ({formulas_correct}/6 cells)")
    else:
        feedback.append(f"❌ Missing recommendation formulas ({formulas_correct}/6 cells)")
    
    if results_correct >= 5:
        feedback.append(f"✅ Recommendation results correct ({results_correct}/6 wines)")
    elif results_correct >= 3:
        feedback.append(f"⚠️ Some recommendations correct ({results_correct}/6 wines)")
    else:
        feedback.append(f"❌ Recommendation results incorrect ({results_correct}/6 wines)")
    
    return formulas_correct, results_correct, feedback


def check_conditional_formatting(filepath):
    """
    Check if conditional formatting is applied to the data range.
    Returns (has_formatting, feedback)
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False, "❌ Could not read spreadsheet content"
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Define namespaces
            namespaces = {
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0'
            }
            
            # Look for conditional formatting (table:conditional-format or style:map)
            cond_formats = root.findall('.//style:map', namespaces)
            table_cond_formats = root.findall('.//table:conditional-format', namespaces)
            
            # Also check for cell styles that might indicate formatting was applied
            cells_with_style = root.findall('.//table:table-cell[@table:style-name]', namespaces)
            
            has_formatting = len(cond_formats) > 0 or len(table_cond_formats) > 0
            has_styled_cells = len(cells_with_style) > 5  # At least some cells should be styled
            
            if has_formatting:
                return True, "✅ Conditional formatting detected"
            elif has_styled_cells:
                return True, "✅ Cell formatting detected (conditional formatting may be applied)"
            else:
                return False, "❌ No conditional formatting detected"
    
    except Exception as e:
        logger.warning(f"Could not check conditional formatting: {e}")
        return False, "⚠️ Could not verify conditional formatting"


def verify_wine_journal(traj, env_info, task_info):
    """
    Main verification function for Wine Tasting Journal task.
    
    Checks:
    1. All 6 wines entered correctly (names, varietals, ratings, prices)
    2. Average rating formula in C9
    3. Average price formula in D9  
    4. Recommendation formulas in F2:F7 with correct logic
    5. Conditional formatting applied
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/wine_journal.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        # Get sheet name
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        sheet_name = sheet_names[0]
        
        # Track criteria
        total_criteria = 8
        criteria_met = 0
        all_feedback = []
        
        # 1. Check wine data entry (worth 2 points if 6/6, 1 point if 4-5/6)
        wines_correct, wine_feedback = check_wine_data(workbook, sheet_name)
        all_feedback.extend(wine_feedback)
        if wines_correct == 6:
            criteria_met += 2
        elif wines_correct >= 4:
            criteria_met += 1
        
        # 2. Check average rating formula (C9)
        rating_formula_ok, price_formula_ok, avg_feedback = check_average_formulas(workbook, sheet_name)
        all_feedback.extend(avg_feedback)
        if rating_formula_ok:
            criteria_met += 1
        
        # 3. Check average price formula (D9)
        if price_formula_ok:
            criteria_met += 1
        
        # 4. Check recommendation formulas (worth 2 points)
        formulas_correct, results_correct, rec_feedback = check_recommendation_formulas(workbook, sheet_name)
        all_feedback.extend(rec_feedback)
        
        if formulas_correct >= 5 and results_correct >= 5:
            criteria_met += 2  # Both formula structure and results correct
        elif formulas_correct >= 3 or results_correct >= 4:
            criteria_met += 1  # Partial credit
        
        # 5. Check conditional formatting (worth 1 point)
        # Get the actual file path from temp directory
        file_path = workbook.get('filepath', '')
        if os.path.exists(file_path):
            has_formatting, format_feedback = check_conditional_formatting(file_path)
            all_feedback.append(format_feedback)
            if has_formatting:
                criteria_met += 1
        else:
            all_feedback.append("⚠️ Could not verify conditional formatting")
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need 6/8 criteria (75%)
        
        # Add summary
        if passed and score >= 90:
            all_feedback.insert(0, "🎉 Excellent work! Wine journal completed successfully!")
        elif passed:
            all_feedback.insert(0, "✅ Wine journal task completed")
        else:
            all_feedback.insert(0, "❌ Wine journal incomplete - review requirements")
        
        feedback = " | ".join(all_feedback)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "wine_data_complete": wines_correct >= 6,
                "avg_rating_formula": rating_formula_ok,
                "avg_price_formula": price_formula_ok,
                "recommendation_formulas": formulas_correct >= 5,
                "recommendation_results": results_correct >= 5,
                "conditional_formatting": has_formatting if 'has_formatting' in locals() else False
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_temp(temp_dir)
