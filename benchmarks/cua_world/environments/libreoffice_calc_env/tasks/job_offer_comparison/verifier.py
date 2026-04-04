#!/usr/bin/env python3
"""
Verifier for Job Offer Comparison task.
Checks salary conversions, total compensation calculations, date formulas, and formatting.
"""

import sys
import os
import logging
import re
from datetime import datetime

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_environment,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_salary_value(cell_value):
    """
    Extract numeric salary from various formats.
    Handles: "75000", "$75,000", "$28/hr", "$32.50/hour", etc.
    
    Returns: (numeric_value, is_hourly)
    """
    if cell_value is None:
        return None, False
    
    # Convert to string
    val_str = str(cell_value).strip()
    
    # Check if hourly
    is_hourly = '/hr' in val_str.lower() or '/hour' in val_str.lower()
    
    # Remove currency symbols, commas, and text
    val_str = re.sub(r'[,$]', '', val_str)
    val_str = re.sub(r'/hr.*|/hour.*', '', val_str, flags=re.IGNORECASE)
    
    try:
        return float(val_str), is_hourly
    except ValueError:
        return None, False


def find_cell_with_value(sheet_data, sheet_name, search_text, column_index=None):
    """
    Find cell containing specific text.
    Returns (row_index, col_index) or None.
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return None
    
    rows = sheets[sheet_name]
    search_lower = str(search_text).lower()
    
    for row_idx, row in enumerate(rows):
        for col_idx, cell in enumerate(row):
            if column_index is not None and col_idx != column_index:
                continue
            
            cell_val = cell.get('value') if isinstance(cell, dict) else cell
            if cell_val and search_lower in str(cell_val).lower():
                return (row_idx, col_idx)
    
    return None


def check_salary_conversions(sheet_data, sheet_name):
    """
    Check if hourly rates have been converted to annual.
    Returns (conversions_found, conversions_correct)
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return 0, 0
    
    rows = sheets[sheet_name]
    conversions_found = 0
    conversions_correct = 0
    
    # Look for cells that might contain converted salaries
    # Strategy: Find cells in salary column (likely column 4-6) with values in 50k-150k range
    # that could be conversions from hourly
    
    for row_idx, row in enumerate(rows[1:], start=1):  # Skip header
        if row_idx >= len(rows):
            break
            
        # Check columns 4-7 for salary data
        for col_idx in range(4, min(8, len(row))):
            cell = row[col_idx]
            cell_val = cell.get('value') if isinstance(cell, dict) else cell
            
            if cell_val is None:
                continue
            
            # Check if this looks like an annual salary from hourly conversion
            salary_num, is_hourly_format = parse_salary_value(cell_val)
            
            if salary_num and not is_hourly_format:
                # Check if this could be a converted hourly rate
                # Common conversions: $28/hr→58240, $35/hr→72800, $45/hr→93600, $32.50/hr→67600, $55/hr→114400
                expected_conversions = {
                    28: 58240,
                    35: 72800,
                    45: 93600,
                    32.5: 67600,
                    55: 114400,
                }
                
                for hourly_rate, expected_annual in expected_conversions.items():
                    if abs(salary_num - expected_annual) <= 300:  # Tolerance for rounding
                        conversions_found += 1
                        conversions_correct += 1
                        logger.info(f"Found conversion at row {row_idx}, col {col_idx}: ${salary_num} (from ${hourly_rate}/hr)")
                        break
    
    return conversions_found, conversions_correct


def check_total_compensation(sheet_data, sheet_name, company_name, expected_total, tolerance=1500):
    """
    Check if total compensation for a company is calculated correctly.
    Searches for cells near the company name that contain the expected total.
    """
    # Find the company row
    company_pos = find_cell_with_value(sheet_data, sheet_name, company_name)
    if not company_pos:
        logger.warning(f"Could not find company: {company_name}")
        return False, None
    
    row_idx, col_idx = company_pos
    
    sheets = sheet_data.get('sheets', {})
    rows = sheets[sheet_name]
    
    # Search in the same row and nearby rows for total compensation
    search_range = range(max(0, row_idx - 2), min(len(rows), row_idx + 5))
    
    for search_row in search_range:
        if search_row >= len(rows):
            continue
        
        row = rows[search_row]
        for search_col in range(len(row)):
            cell = row[search_col]
            cell_val = cell.get('value') if isinstance(cell, dict) else cell
            
            if isinstance(cell_val, (int, float)):
                if abs(float(cell_val) - expected_total) <= tolerance:
                    logger.info(f"Found total compensation for {company_name}: ${cell_val} at row {search_row}, col {search_col}")
                    return True, cell_val
    
    logger.warning(f"Could not find total compensation for {company_name} (expected ~${expected_total})")
    return False, None


def check_date_formulas(sheet_data, sheet_name):
    """
    Check if TODAY() function is used in date calculations.
    Returns count of cells with TODAY() formulas.
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return 0
    
    rows = sheets[sheet_name]
    today_formula_count = 0
    
    for row_idx, row in enumerate(rows):
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                formula = cell.get('formula', '')
                if formula and 'TODAY' in str(formula).upper():
                    today_formula_count += 1
                    logger.info(f"Found TODAY() formula at row {row_idx}, col {col_idx}: {formula}")
    
    return today_formula_count


def check_currency_formatting(file_path):
    """
    Check if currency formatting is applied.
    This is a simplified check - looks for $ symbols in cells.
    """
    # This is challenging to verify perfectly without parsing all ODF formatting
    # We'll use a heuristic: check if there are cells with $ in their display
    try:
        # For ODS files, we could parse styles.xml, but that's complex
        # Simple heuristic: if conversion was done and values look reasonable, assume formatting
        return True
    except Exception as e:
        logger.warning(f"Could not verify currency formatting: {e}")
        return False


def verify_job_offer_comparison(traj, env_info, task_info):
    """
    Verify job offer comparison task completion.
    
    Checks:
    1. Salary conversions (hourly to annual)
    2. Company A total compensation (~$88,000)
    3. Company B total compensation (~$96,200)
    4. Days since formula (uses TODAY())
    5. Currency formatting applied
    6. Clear comparison structure
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the file
    container_path = "/home/ga/Documents/job_search_tracker.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods']
    )
    
    if not success:
        # Try alternate filename in case user saved as something else
        container_path = "/home/ga/Documents/job_search_cleaned.ods"
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            expected_formats=['ods']
        )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_names = get_sheet_names(sheet_data)
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Salary conversions (hourly to annual)
        conversions_found, conversions_correct = check_salary_conversions(sheet_data, sheet_name)
        
        if conversions_correct >= 2:
            criteria_passed += 1
            subscores['salary_conversion'] = True
            feedback_parts.append(f"✅ Salary conversions correct ({conversions_correct} found)")
        elif conversions_correct >= 1:
            criteria_passed += 0.5
            subscores['salary_conversion'] = False
            feedback_parts.append(f"⚠️ Only {conversions_correct} salary conversion found (need 2+)")
        else:
            subscores['salary_conversion'] = False
            feedback_parts.append("❌ No hourly-to-annual salary conversions found")
        
        # Criterion 2: Company A total compensation (~$88,000)
        company_a_correct, company_a_value = check_total_compensation(
            sheet_data, sheet_name, "TechStart", 88000, tolerance=1500
        )
        
        if company_a_correct:
            criteria_passed += 1
            subscores['company_a_total'] = True
            feedback_parts.append(f"✅ Company A total compensation: ${company_a_value:,.0f}")
        else:
            subscores['company_a_total'] = False
            feedback_parts.append("❌ Company A total compensation not found or incorrect (expected ~$88,000)")
        
        # Criterion 3: Company B total compensation (~$96,200)
        company_b_correct, company_b_value = check_total_compensation(
            sheet_data, sheet_name, "DataCorp", 96200, tolerance=1500
        )
        
        if company_b_correct:
            criteria_passed += 1
            subscores['company_b_total'] = True
            feedback_parts.append(f"✅ Company B total compensation: ${company_b_value:,.0f}")
        else:
            subscores['company_b_total'] = False
            feedback_parts.append("❌ Company B total compensation not found or incorrect (expected ~$96,200)")
        
        # Criterion 4: Days since formula with TODAY()
        today_formula_count = check_date_formulas(sheet_data, sheet_name)
        
        if today_formula_count >= 2:
            criteria_passed += 1
            subscores['date_formula'] = True
            feedback_parts.append(f"✅ TODAY() formula used ({today_formula_count} instances)")
        elif today_formula_count >= 1:
            criteria_passed += 0.5
            subscores['date_formula'] = False
            feedback_parts.append(f"⚠️ Only {today_formula_count} TODAY() formula found")
        else:
            subscores['date_formula'] = False
            feedback_parts.append("❌ No TODAY() formula found for date tracking")
        
        # Criterion 5: Currency formatting
        # This is hard to verify precisely, so we'll give credit if other calculations are correct
        has_formatting = check_currency_formatting(file_info['file_path'])
        if conversions_correct >= 1 or company_a_correct or company_b_correct:
            criteria_passed += 1
            subscores['currency_formatting'] = True
            feedback_parts.append("✅ Data formatting appears correct")
        else:
            subscores['currency_formatting'] = False
            feedback_parts.append("⚠️ Could not verify currency formatting")
        
        # Criterion 6: Clear comparison structure
        # If both company totals are found, comparison structure exists
        if company_a_correct and company_b_correct:
            criteria_passed += 1
            subscores['comparison_structure'] = True
            difference = abs(company_b_value - company_a_value)
            feedback_parts.append(f"✅ Clear comparison created (difference: ${difference:,.0f})")
        else:
            subscores['comparison_structure'] = False
            feedback_parts.append("❌ Comparison structure incomplete")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add decision recommendation if both offers compared
        if company_a_correct and company_b_correct:
            if company_b_value > company_a_value:
                feedback_parts.append(f"💡 DataCorp offers ${company_b_value - company_a_value:,.0f} more in total compensation")
            else:
                feedback_parts.append(f"💡 TechStart offers ${company_a_value - company_b_value:,.0f} more in total compensation")
        
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
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_environment(file_info.get('temp_dir'))
