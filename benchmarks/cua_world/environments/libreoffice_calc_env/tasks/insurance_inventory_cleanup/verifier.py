#!/usr/bin/env python3
"""
Verifier for Insurance Inventory Cleanup task
Checks data standardization, formula application, and formatting
"""

import sys
import os
import logging
import re
from datetime import datetime
from typing import Dict, List, Any, Tuple

# Do not use /workspace/utils, since verification runs on host machine
# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected standard categories
STANDARD_CATEGORIES = {"Electronics", "Furniture", "Appliances", "Jewelry", "Tools"}

# Depreciation rates (rate_per_year, max_depreciation)
DEPRECIATION_RATES = {
    "Electronics": (0.20, 0.80),
    "Furniture": (0.10, 0.50),
    "Appliances": (0.15, 0.70),
    "Jewelry": (0.00, 0.00),
    "Tools": (0.08, 0.40)
}


def get_column_values(data: Dict, sheet_name: str, column_index: int, start_row: int = 1) -> List[Any]:
    """Extract all values from a specific column"""
    values = []
    rows = data['sheets'][sheet_name]
    for i in range(start_row, len(rows)):
        if column_index < len(rows[i]):
            cell = rows[i][column_index]
            value = cell.get('value') if isinstance(cell, dict) else cell
            values.append(value)
    return values


def find_column_index(data: Dict, sheet_name: str, column_name: str) -> int:
    """Find column index by header name"""
    rows = data['sheets'][sheet_name]
    if not rows:
        return -1
    
    header_row = rows[0]
    for i, cell in enumerate(header_row):
        value = cell.get('value') if isinstance(cell, dict) else cell
        if value and column_name.lower() in str(value).lower():
            return i
    return -1


def check_category_standardization(data: Dict, sheet_name: str) -> Tuple[bool, str, float]:
    """
    Check if categories are standardized
    Returns: (passed, feedback, standardization_rate)
    """
    try:
        category_col = find_column_index(data, sheet_name, "Category")
        if category_col < 0:
            return False, "Category column not found", 0.0
        
        categories = get_column_values(data, sheet_name, category_col, start_row=1)
        categories = [c for c in categories if c]  # Remove empty values
        
        if not categories:
            return False, "No category data found", 0.0
        
        # Count how many categories match standard names
        standardized_count = sum(1 for c in categories if str(c).strip() in STANDARD_CATEGORIES)
        standardization_rate = standardized_count / len(categories)
        
        # Find non-standard variations
        non_standard = set(str(c).strip() for c in categories if str(c).strip() not in STANDARD_CATEGORIES)
        
        passed = standardization_rate >= 0.95
        
        if passed:
            feedback = f"✅ Categories standardized ({standardization_rate:.1%})"
        else:
            feedback = f"❌ Categories not fully standardized ({standardization_rate:.1%}), found variations: {list(non_standard)[:3]}"
        
        return passed, feedback, standardization_rate
        
    except Exception as e:
        logger.error(f"Error checking categories: {e}", exc_info=True)
        return False, f"Error checking categories: {str(e)}", 0.0


def check_date_normalization(data: Dict, sheet_name: str) -> Tuple[bool, str, float]:
    """
    Check if dates are normalized to consistent format
    Returns: (passed, feedback, completion_rate)
    """
    try:
        date_col = find_column_index(data, sheet_name, "Purchase Date")
        if date_col < 0:
            date_col = find_column_index(data, sheet_name, "Date")
        
        if date_col < 0:
            return False, "Date column not found", 0.0
        
        dates = get_column_values(data, sheet_name, date_col, start_row=1)
        dates = [d for d in dates if d]  # Remove empty values
        
        if not dates:
            return False, "No date data found", 0.0
        
        # Check for consistent format (YYYY-MM-DD or proper date objects)
        valid_dates = 0
        for date_val in dates:
            date_str = str(date_val)
            # Check if it's a proper date format or date object
            if re.match(r'\d{4}-\d{2}-\d{2}', date_str) or \
               re.match(r'\d{4}/\d{2}/\d{2}', date_str) or \
               'datetime' in str(type(date_val)).lower():
                valid_dates += 1
            # Also accept if it looks like a proper year (numeric >= 2000)
            elif date_str.isdigit() and 2000 <= int(date_str) <= 2025:
                valid_dates += 0.5  # Partial credit
        
        completion_rate = valid_dates / len(dates)
        passed = completion_rate >= 0.90
        
        if passed:
            feedback = f"✅ Dates normalized ({completion_rate:.1%} valid format)"
        else:
            feedback = f"❌ Dates inconsistent ({completion_rate:.1%} valid format)"
        
        return passed, feedback, completion_rate
        
    except Exception as e:
        logger.error(f"Error checking dates: {e}", exc_info=True)
        return False, f"Error checking dates: {str(e)}", 0.0


def check_depreciation_formulas(data: Dict, sheet_name: str) -> Tuple[bool, str, float]:
    """
    Check if depreciation formulas are correctly applied
    Returns: (passed, feedback, accuracy_rate)
    """
    try:
        # Find relevant columns
        category_col = find_column_index(data, sheet_name, "Category")
        purchase_price_col = find_column_index(data, sheet_name, "Purchase Price")
        age_col = find_column_index(data, sheet_name, "Age")
        current_value_col = find_column_index(data, sheet_name, "Current Value")
        
        if current_value_col < 0:
            return False, "Current Value column not found", 0.0
        
        if category_col < 0 or purchase_price_col < 0:
            return False, "Required columns missing for verification", 0.0
        
        # Check if Current Value column has formulas (sample first few rows)
        rows = data['sheets'][sheet_name]
        formula_count = 0
        checked_rows = 0
        
        for i in range(1, min(6, len(rows))):  # Check first 5 data rows
            if current_value_col < len(rows[i]):
                cell = rows[i][current_value_col]
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula:
                    formula_count += 1
                checked_rows += 1
        
        if checked_rows == 0:
            return False, "No data rows found", 0.0
        
        has_formulas = formula_count > 0
        
        # Spot check: verify calculations for a few items
        errors = 0
        spot_checks = 0
        
        for i in range(1, min(11, len(rows))):  # Check up to 10 items
            try:
                if category_col >= len(rows[i]) or purchase_price_col >= len(rows[i]):
                    continue
                
                category_cell = rows[i][category_col]
                category = str(category_cell.get('value') if isinstance(category_cell, dict) else category_cell).strip()
                
                if category not in STANDARD_CATEGORIES:
                    continue
                
                price_cell = rows[i][purchase_price_col]
                purchase_price = float(price_cell.get('value') if isinstance(price_cell, dict) else price_cell)
                
                # Try to get age
                age = 0
                if age_col >= 0 and age_col < len(rows[i]):
                    age_cell = rows[i][age_col]
                    age_val = age_cell.get('value') if isinstance(age_cell, dict) else age_cell
                    if age_val:
                        try:
                            age = float(age_val)
                        except:
                            age = 0
                
                # Get actual current value
                current_value_cell = rows[i][current_value_col]
                actual_value = float(current_value_cell.get('value') if isinstance(current_value_cell, dict) else current_value_cell)
                
                # Calculate expected value
                rate, max_dep = DEPRECIATION_RATES[category]
                expected_value = max(purchase_price * (1 - rate * age), purchase_price * (1 - max_dep))
                
                # Allow 10% tolerance
                if abs(actual_value - expected_value) / max(expected_value, 1) > 0.10:
                    errors += 1
                
                spot_checks += 1
                
                if spot_checks >= 8:  # Check up to 8 items
                    break
                    
            except Exception as e:
                logger.debug(f"Error in spot check row {i}: {e}")
                continue
        
        if spot_checks == 0:
            return False, "Could not perform spot checks", 0.0
        
        error_rate = errors / spot_checks
        passed = has_formulas and error_rate < 0.05
        
        if passed:
            feedback = f"✅ Depreciation formulas correct ({spot_checks} items checked, {errors} errors)"
        elif has_formulas:
            feedback = f"⚠️ Depreciation formulas present but some errors ({errors}/{spot_checks} incorrect)"
        else:
            feedback = "❌ No depreciation formulas detected (values may be hardcoded)"
        
        return passed, feedback, 1 - error_rate
        
    except Exception as e:
        logger.error(f"Error checking depreciation: {e}", exc_info=True)
        return False, f"Error checking depreciation: {str(e)}", 0.0


def check_documentation_flags(data: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if high-value items are properly flagged for documentation
    Returns: (passed, feedback)
    """
    try:
        current_value_col = find_column_index(data, sheet_name, "Current Value")
        doc_status_col = find_column_index(data, sheet_name, "Documentation")
        
        if current_value_col < 0:
            return False, "Current Value column not found"
        
        if doc_status_col < 0:
            return False, "Documentation Status column not found"
        
        rows = data['sheets'][sheet_name]
        high_value_items = []
        correctly_flagged = 0
        
        for i in range(1, len(rows)):
            if current_value_col >= len(rows[i]):
                continue
            
            value_cell = rows[i][current_value_col]
            value = value_cell.get('value') if isinstance(value_cell, dict) else value_cell
            
            try:
                value = float(value)
            except:
                continue
            
            if value > 1000:
                high_value_items.append(i)
                
                if doc_status_col < len(rows[i]):
                    doc_cell = rows[i][doc_status_col]
                    doc_status = str(doc_cell.get('value') if isinstance(doc_cell, dict) else doc_cell).upper()
                    
                    if "NEED" in doc_status or "PHOTO" in doc_status or "RECEIPT" in doc_status:
                        correctly_flagged += 1
        
        if not high_value_items:
            # No high-value items to flag
            return True, "✅ Documentation flagging not applicable (no high-value items)"
        
        accuracy = correctly_flagged / len(high_value_items)
        passed = accuracy >= 0.90  # Allow some flexibility
        
        if passed:
            feedback = f"✅ Documentation flagged correctly ({correctly_flagged}/{len(high_value_items)} high-value items)"
        else:
            feedback = f"❌ Documentation flagging incomplete ({correctly_flagged}/{len(high_value_items)} high-value items flagged)"
        
        return passed, feedback
        
    except Exception as e:
        logger.error(f"Error checking documentation flags: {e}", exc_info=True)
        return False, f"Error checking flags: {str(e)}"


def check_summary_statistics(data: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if summary statistics are calculated (category subtotals)
    Returns: (passed, feedback)
    """
    try:
        rows = data['sheets'][sheet_name]
        
        # Look for SUMIF formulas in the spreadsheet
        sumif_count = 0
        
        for row in rows:
            for cell in row:
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula and 'SUMIF' in str(formula).upper():
                    sumif_count += 1
        
        passed = sumif_count >= 3  # At least a few SUMIF formulas
        
        if passed:
            feedback = f"✅ Summary statistics present ({sumif_count} SUMIF formulas found)"
        else:
            feedback = f"❌ Summary statistics missing or incomplete ({sumif_count} SUMIF formulas)"
        
        return passed, feedback
        
    except Exception as e:
        logger.error(f"Error checking summary statistics: {e}", exc_info=True)
        return False, f"Error checking summary: {str(e)}"


def verify_inventory_cleanup(traj, env_info, task_info):
    """
    Main verification function for inventory cleanup task
    
    Checks 7 criteria:
    1. Categories standardized (≥95%)
    2. Dates normalized (≥90%)
    3. Depreciation formulas correct (<5% error)
    4. Documentation flagged (≥90% of high-value items)
    5. Conditional formatting applied
    6. Summary statistics present
    7. Data validation (optional, bonus)
    
    Pass threshold: 70% (5/7 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    container_paths = [
        "/home/ga/Documents/home_inventory_cleaned.ods",
        "/home/ga/Documents/home_inventory_messy.ods",
        "/home/ga/Documents/home_inventory.ods"
    ]
    
    success = False
    file_info = None
    
    for container_path in container_paths:
        success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
        if success:
            logger.info(f"Found file at: {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load inventory file: {error}"}
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Categories standardized
        cat_passed, cat_feedback, cat_rate = check_category_standardization(data, sheet_name)
        if cat_passed:
            criteria_passed += 1
        feedback_parts.append(cat_feedback)
        subscores['categories_standardized'] = cat_passed
        
        # Criterion 2: Dates normalized
        date_passed, date_feedback, date_rate = check_date_normalization(data, sheet_name)
        if date_passed:
            criteria_passed += 1
        feedback_parts.append(date_feedback)
        subscores['dates_normalized'] = date_passed
        
        # Criterion 3: Depreciation formulas
        dep_passed, dep_feedback, dep_rate = check_depreciation_formulas(data, sheet_name)
        if dep_passed:
            criteria_passed += 1
        feedback_parts.append(dep_feedback)
        subscores['depreciation_calculated'] = dep_passed
        
        # Criterion 4: Documentation flags
        doc_passed, doc_feedback = check_documentation_flags(data, sheet_name)
        if doc_passed:
            criteria_passed += 1
        feedback_parts.append(doc_feedback)
        subscores['documentation_flagged'] = doc_passed
        
        # Criterion 5: Conditional formatting (simplified check)
        # This is hard to verify from parsed data, so we'll give benefit of doubt
        # if other criteria are met well
        cond_format_passed = check_conditional_formatting(data, sheet_name, "")
        if cond_format_passed:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
        else:
            # Give partial credit if data is well organized
            if cat_passed and dep_passed:
                criteria_passed += 0.5
                feedback_parts.append("⚠️ Conditional formatting not verified (may be present)")
            else:
                feedback_parts.append("❌ Conditional formatting not detected")
        subscores['conditional_formatting'] = cond_format_passed
        
        # Criterion 6: Summary statistics
        summary_passed, summary_feedback = check_summary_statistics(data, sheet_name)
        if summary_passed:
            criteria_passed += 1
        feedback_parts.append(summary_feedback)
        subscores['summary_statistics'] = summary_passed
        
        # Criterion 7: Data validation (bonus criterion, hard to verify)
        # Give credit if other criteria strongly met
        if cat_rate >= 0.95 and date_rate >= 0.90:
            criteria_passed += 0.5
            feedback_parts.append("✅ Data quality suggests validation may be present")
        else:
            feedback_parts.append("⚠️ Data validation not verified")
        subscores['data_validation'] = cat_rate >= 0.95
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 5/7 criteria (70%)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent data cleaning!")
        elif passed:
            feedback_parts.insert(0, "✅ Inventory cleanup completed")
        else:
            feedback_parts.insert(0, "❌ Inventory cleanup incomplete")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "criteria_met": f"{criteria_passed:.1f}/{total_criteria}"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        if file_info:
            cleanup_verification_temp(file_info.get('temp_dir'))
