#!/usr/bin/env python3
"""
Verifier for Grocery Price Comparison task
Checks data cleaning, unit price calculations, minimum detection, recommendations, and formatting
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Any, Optional

# Use relative path to utils folder (verification runs on host, not container)
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


def check_product_name_standardization(workbook: Dict, sheet_name: str) -> Tuple[bool, str, float]:
    """
    Check if product names have been standardized.
    
    Returns:
        Tuple of (passed, feedback, consistency_score)
    """
    try:
        # Look for a standardized product name column (likely in column J or later)
        # Check columns J through O for potential standardized names
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Sample some rows to check for standardization patterns
        standardized_names = []
        for col_idx in range(9, 15):  # Columns J through O (0-indexed: 9-14)
            for row_idx in range(1, min(20, len(sheet_rows))):  # Skip header, check up to 20 rows
                if row_idx < len(sheet_rows) and col_idx < len(sheet_rows[row_idx]):
                    cell = sheet_rows[row_idx][col_idx]
                    value = cell.get('value') if isinstance(cell, dict) else cell
                    if value and isinstance(value, str) and len(value) > 3:
                        standardized_names.append(value)
        
        if not standardized_names:
            return False, "❌ No standardized product name column found", 0.0
        
        # Check for consistency patterns (no all caps, reasonable formatting)
        consistency_score = 0.0
        good_names = 0
        
        for name in standardized_names[:20]:  # Check first 20
            # Good standardization: mixed case, possibly commas, no excessive spaces
            if name != name.upper() and name != name.lower():
                good_names += 1
            elif ',' in name:  # Structured format like "Milk, Whole, 1 Gal"
                good_names += 1
        
        if standardized_names:
            consistency_score = good_names / len(standardized_names[:20])
        
        if consistency_score >= 0.7:
            return True, f"✅ Product names standardized (consistency: {consistency_score:.0%})", consistency_score
        else:
            return False, f"⚠️ Product standardization incomplete (consistency: {consistency_score:.0%})", consistency_score
            
    except Exception as e:
        logger.error(f"Error checking standardization: {e}", exc_info=True)
        return False, "❌ Could not verify product name standardization", 0.0


def check_unit_price_formulas(workbook: Dict, sheet_name: str) -> Tuple[bool, str, int]:
    """
    Check if unit price calculations exist with formulas.
    
    Returns:
        Tuple of (passed, feedback, formula_count)
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        formula_count = 0
        division_formulas = 0
        
        # Check columns J through R for unit price formulas (after original data)
        for col_idx in range(9, 18):  # Extended range for unit prices
            for row_idx in range(1, min(25, len(sheet_rows))):
                if row_idx < len(sheet_rows) and col_idx < len(sheet_rows[row_idx]):
                    cell = sheet_rows[row_idx][col_idx]
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    
                    if formula:
                        formula_count += 1
                        # Check if it's a division formula (unit price = price / quantity)
                        if '/' in formula:
                            division_formulas += 1
        
        if division_formulas >= 15:  # At least 15 division formulas (rough estimate)
            return True, f"✅ Unit price formulas found ({division_formulas} division formulas)", division_formulas
        elif formula_count >= 10:
            return True, f"⚠️ Some formulas found ({formula_count} total, {division_formulas} division)", formula_count
        else:
            return False, f"❌ Insufficient unit price formulas ({formula_count} found)", formula_count
            
    except Exception as e:
        logger.error(f"Error checking unit prices: {e}", exc_info=True)
        return False, "❌ Could not verify unit price formulas", 0


def check_minimum_detection(workbook: Dict, sheet_name: str) -> Tuple[bool, str, int]:
    """
    Check if MIN() function is used to identify lowest prices.
    
    Returns:
        Tuple of (passed, feedback, min_function_count)
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        min_function_count = 0
        
        # Scan for MIN function usage
        for row in sheet_rows[1:25]:  # Skip header, check first 24 data rows
            for cell in row:
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula and 'MIN' in formula.upper():
                    min_function_count += 1
        
        if min_function_count >= 15:  # Should have MIN for most products
            return True, f"✅ MIN function used ({min_function_count} instances)", min_function_count
        elif min_function_count >= 5:
            return True, f"⚠️ Some MIN functions found ({min_function_count} instances)", min_function_count
        else:
            return False, f"❌ MIN function not properly used ({min_function_count} instances)", min_function_count
            
    except Exception as e:
        logger.error(f"Error checking MIN functions: {e}", exc_info=True)
        return False, "❌ Could not verify MIN function usage", 0


def check_recommendation_logic(workbook: Dict, sheet_name: str) -> Tuple[bool, str, int]:
    """
    Check if IF() logic is used to generate store recommendations.
    
    Returns:
        Tuple of (passed, feedback, if_function_count)
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        if_function_count = 0
        store_mentions = 0
        
        # Scan for IF function usage and store name mentions
        for row in sheet_rows[1:25]:
            for cell in row:
                formula = cell.get('formula') if isinstance(cell, dict) else None
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                if formula and 'IF' in formula.upper():
                    if_function_count += 1
                    # Check if formula mentions stores
                    if any(store in str(formula).upper() for store in ['STORE A', 'STORE B', 'STORE C', 'STOREA', 'STOREB', 'STOREC']):
                        store_mentions += 1
                
                # Also check cell values for store recommendations
                if value and isinstance(value, str):
                    if any(store in value.upper() for store in ['STORE A', 'STORE B', 'STORE C']):
                        store_mentions += 1
        
        if if_function_count >= 10 and store_mentions >= 10:
            return True, f"✅ Recommendation logic implemented (IF: {if_function_count}, stores: {store_mentions})", if_function_count
        elif if_function_count >= 5 or store_mentions >= 5:
            return True, f"⚠️ Partial recommendation logic (IF: {if_function_count}, stores: {store_mentions})", if_function_count
        else:
            return False, f"❌ Recommendation logic missing (IF: {if_function_count}, stores: {store_mentions})", 0
            
    except Exception as e:
        logger.error(f"Error checking recommendations: {e}", exc_info=True)
        return False, "❌ Could not verify recommendation logic", 0


def check_formatting_applied(workbook: Dict, sheet_name: str, filepath: str) -> Tuple[bool, str]:
    """
    Check if conditional formatting has been applied.
    
    Returns:
        Tuple of (passed, feedback)
    """
    try:
        # Use the check_conditional_formatting utility
        # This checks if conditional formatting exists in the file
        has_formatting = check_conditional_formatting(workbook, sheet_name, "A1:Z30")
        
        if has_formatting:
            return True, "✅ Conditional formatting applied"
        else:
            # Even if we can't detect it programmatically, don't fail entirely
            return False, "⚠️ Could not confirm conditional formatting"
            
    except Exception as e:
        logger.debug(f"Conditional formatting check inconclusive: {e}")
        return False, "⚠️ Could not verify conditional formatting"


def check_summary_statistics(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if summary statistics are present (savings, store comparison).
    
    Returns:
        Tuple of (passed, feedback)
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Look for summary-related text and numbers in bottom rows or side columns
        summary_indicators = ['total', 'savings', 'average', 'store', 'count', 'sum']
        summary_found = False
        
        # Check last 10 rows and rightmost columns
        for row_idx in range(max(0, len(sheet_rows) - 10), len(sheet_rows)):
            if row_idx < len(sheet_rows):
                for cell in sheet_rows[row_idx]:
                    value = cell.get('value') if isinstance(cell, dict) else cell
                    if value and isinstance(value, str):
                        if any(indicator in value.lower() for indicator in summary_indicators):
                            summary_found = True
                            break
        
        if summary_found:
            return True, "✅ Summary statistics present"
        else:
            return False, "⚠️ Summary statistics not clearly identified"
            
    except Exception as e:
        logger.debug(f"Summary check inconclusive: {e}")
        return False, "⚠️ Could not verify summary statistics"


def verify_grocery_comparison(traj, env_info, task_info):
    """
    Verify grocery price comparison task completion.
    
    Checks:
    1. Product names standardized (≥70% consistency)
    2. Unit price formulas present (division operations)
    3. MIN function used to identify lowest prices
    4. IF logic generates store recommendations
    5. Conditional formatting applied
    6. Summary statistics calculated
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/grocery_comparison.ods'),
        ('ods', '/home/ga/Documents/grocery_data.ods'),
        ('csv', '/home/ga/Documents/grocery_data.csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0.0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Product name standardization (25% weight)
        std_passed, std_feedback, std_score = check_product_name_standardization(workbook, sheet_name)
        if std_passed or std_score >= 0.7:
            criteria_passed += 1.0
            subscores['standardization'] = True
        elif std_score >= 0.5:
            criteria_passed += 0.5
            subscores['standardization'] = False
        else:
            subscores['standardization'] = False
        feedback_parts.append(std_feedback)
        
        # Criterion 2: Unit price calculation (25% weight)
        unit_passed, unit_feedback, unit_count = check_unit_price_formulas(workbook, sheet_name)
        if unit_passed:
            criteria_passed += 1.0
            subscores['unit_prices'] = True
        elif unit_count >= 5:
            criteria_passed += 0.5
            subscores['unit_prices'] = False
        else:
            subscores['unit_prices'] = False
        feedback_parts.append(unit_feedback)
        
        # Criterion 3: Minimum price detection (20% weight)
        min_passed, min_feedback, min_count = check_minimum_detection(workbook, sheet_name)
        if min_passed:
            criteria_passed += 1.0
            subscores['minimum_detection'] = True
        elif min_count >= 3:
            criteria_passed += 0.5
            subscores['minimum_detection'] = False
        else:
            subscores['minimum_detection'] = False
        feedback_parts.append(min_feedback)
        
        # Criterion 4: Shopping recommendations (20% weight)
        rec_passed, rec_feedback, rec_count = check_recommendation_logic(workbook, sheet_name)
        if rec_passed:
            criteria_passed += 1.0
            subscores['recommendations'] = True
        elif rec_count >= 3:
            criteria_passed += 0.5
            subscores['recommendations'] = False
        else:
            subscores['recommendations'] = False
        feedback_parts.append(rec_feedback)
        
        # Criterion 5: Conditional formatting (10% weight)
        fmt_passed, fmt_feedback = check_formatting_applied(workbook, sheet_name, workbook.get('filepath', ''))
        if fmt_passed:
            criteria_passed += 1.0
            subscores['formatting'] = True
        else:
            # Don't penalize too heavily if we can't detect it
            criteria_passed += 0.3
            subscores['formatting'] = False
        feedback_parts.append(fmt_feedback)
        
        # Criterion 6: Summary statistics (10% weight)
        sum_passed, sum_feedback = check_summary_statistics(workbook, sheet_name)
        if sum_passed:
            criteria_passed += 1.0
            subscores['summary'] = True
        else:
            # Partial credit if other work is good
            criteria_passed += 0.3
            subscores['summary'] = False
        feedback_parts.append(sum_feedback)
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add overall assessment
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent grocery comparison analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Grocery comparison task completed")
        else:
            feedback_parts.insert(0, "❌ Grocery comparison requirements not met")
        
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
        if temp_dir:
            cleanup_verification_temp(temp_dir)
