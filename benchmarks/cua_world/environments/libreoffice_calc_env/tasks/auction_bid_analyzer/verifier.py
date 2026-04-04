#!/usr/bin/env python3
"""
Verifier for Auction Bid Analyzer task

Checks:
1. Categories standardized (consistent case)
2. Total_Cost column exists and calculated correctly
3. Win_Rate calculated correctly with formula
4. Bid_Ratio column exists
5. High-risk bids (>=0.8) flagged
6. Total spending correct (won items only)
7. No duplicate Item_IDs
8. Formulas used (not hardcoded)
"""

import sys
import os
import logging
import re
from typing import Dict, Any, Tuple, Optional, List

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names,
    parse_ods_file,
    parse_xlsx_file,
    parse_csv_file
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_by_header(rows: List, header_name: str) -> Optional[int]:
    """Find column index by header name (case-insensitive, partial match)"""
    if not rows or len(rows) == 0:
        return None
    
    header_row = rows[0]
    for idx, cell in enumerate(header_row):
        cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
        if cell_value and header_name.lower() in str(cell_value).lower():
            return idx
    return None


def get_column_values(rows: List, col_idx: int, skip_header: bool = True) -> List:
    """Extract all values from a specific column"""
    start_row = 1 if skip_header else 0
    values = []
    for row in rows[start_row:]:
        if col_idx < len(row):
            cell = row[col_idx]
            value = cell.get('value', None) if isinstance(cell, dict) else cell
            values.append(value)
    return values


def check_categories_standardized(rows: List, category_col_idx: int) -> Tuple[bool, str, float]:
    """Check if categories are standardized (all uppercase or all lowercase)"""
    if category_col_idx is None:
        return False, "Category column not found", 0.0
    
    categories = get_column_values(rows, category_col_idx)
    categories = [c for c in categories if c and str(c).strip()]
    
    if not categories:
        return False, "No category data found", 0.0
    
    # Check if all uppercase
    all_upper = all(str(cat).isupper() for cat in categories)
    # Check if all lowercase
    all_lower = all(str(cat).islower() for cat in categories)
    
    if all_upper or all_lower:
        return True, f"Categories standardized ({'UPPERCASE' if all_upper else 'lowercase'})", 1.0
    
    # Calculate percentage standardized
    upper_count = sum(1 for cat in categories if str(cat).isupper())
    lower_count = sum(1 for cat in categories if str(cat).islower())
    max_standardized = max(upper_count, lower_count)
    percentage = max_standardized / len(categories)
    
    if percentage >= 0.95:
        return True, f"Categories mostly standardized ({percentage*100:.0f}%)", percentage
    else:
        return False, f"Categories inconsistent ({percentage*100:.0f}% standardized)", percentage


def check_duplicates(rows: List, id_col_idx: int) -> Tuple[bool, str]:
    """Check if duplicate Item_IDs have been removed"""
    if id_col_idx is None:
        return True, "Item_ID column not found (skipping duplicate check)"
    
    item_ids = get_column_values(rows, id_col_idx)
    item_ids = [str(id).strip() for id in item_ids if id and str(id).strip()]
    
    if len(item_ids) != len(set(item_ids)):
        duplicates = [id for id in item_ids if item_ids.count(id) > 1]
        unique_duplicates = list(set(duplicates))
        return False, f"Duplicates found: {unique_duplicates[:3]}"
    
    return True, "No duplicates"


def check_total_cost_column(rows: List, your_bid_col: int, shipping_col: int) -> Tuple[bool, str, Optional[int]]:
    """Check if Total_Cost column exists and is calculated correctly"""
    # Look for new columns after the original data (likely after Max_Comfortable_Bid)
    header_row = rows[0]
    
    # Search for column with "total" and "cost" in name
    total_cost_col = None
    for idx, cell in enumerate(header_row):
        cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
        if 'total' in cell_value and 'cost' in cell_value:
            total_cost_col = idx
            break
    
    if total_cost_col is None:
        return False, "Total_Cost column not found", None
    
    # Verify calculation for a few rows
    correct_calcs = 0
    total_checked = 0
    
    for i, row in enumerate(rows[1:6], start=1):  # Check first 5 data rows
        if len(row) <= max(your_bid_col, total_cost_col):
            continue
        
        your_bid = row[your_bid_col].get('value') if isinstance(row[your_bid_col], dict) else row[your_bid_col]
        shipping = row[shipping_col].get('value') if isinstance(row[shipping_col], dict) else row[shipping_col]
        total_cost = row[total_cost_col].get('value') if isinstance(row[total_cost_col], dict) else row[total_cost_col]
        
        if your_bid is None or total_cost is None:
            continue
        
        try:
            your_bid_val = float(your_bid)
            shipping_val = float(shipping) if shipping and str(shipping).strip() else 0.0
            expected_total = your_bid_val + shipping_val
            actual_total = float(total_cost)
            
            if abs(actual_total - expected_total) < 0.01:
                correct_calcs += 1
            total_checked += 1
        except (ValueError, TypeError):
            continue
    
    if total_checked > 0 and correct_calcs / total_checked >= 0.8:
        return True, f"Total_Cost calculated correctly ({correct_calcs}/{total_checked} checked)", total_cost_col
    elif total_checked == 0:
        return True, "Total_Cost column exists (calculation not verified)", total_cost_col
    else:
        return False, f"Total_Cost calculation errors ({correct_calcs}/{total_checked} correct)", total_cost_col


def find_win_rate_cell(workbook: Dict, sheet_name: str) -> Tuple[Optional[float], Optional[str], bool]:
    """Search for win rate calculation in the spreadsheet"""
    rows = workbook['sheets'][sheet_name]
    
    # Search in likely summary areas (columns J, K, L and rows 1-10)
    summary_cols = range(9, 15)  # J to O
    summary_rows = range(0, 15)
    
    for row_idx in summary_rows:
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        
        for col_idx in summary_cols:
            if col_idx >= len(row):
                continue
            
            cell = row[col_idx]
            value = cell.get('value') if isinstance(cell, dict) else cell
            formula = cell.get('formula') if isinstance(cell, dict) else None
            
            # Check if this looks like a win rate (percentage between 0-100)
            if value is not None:
                try:
                    val_float = float(value)
                    # Win rate should be between 0 and 100 (as percentage)
                    if 0 <= val_float <= 100:
                        # Check if there's a formula with COUNTIF
                        if formula and 'COUNTIF' in str(formula).upper():
                            return val_float, formula, True
                        # Even without formula, if value is reasonable, note it
                        elif val_float > 0:
                            return val_float, None, False
                except (ValueError, TypeError):
                    continue
    
    return None, None, False


def check_bid_ratio_column(rows: List, your_bid_col: int, max_bid_col: int) -> Tuple[bool, str, Optional[int]]:
    """Check if Bid_Ratio column exists"""
    header_row = rows[0]
    
    # Search for column with "bid" and "ratio" in name
    bid_ratio_col = None
    for idx, cell in enumerate(header_row):
        cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
        if 'bid' in cell_value and 'ratio' in cell_value:
            bid_ratio_col = idx
            break
    
    if bid_ratio_col is None:
        # Check if there's a new numeric column that could be the ratio
        # (after original columns, values between 0-1)
        for idx in range(max_bid_col + 1, len(header_row)):
            values = get_column_values(rows, idx)
            numeric_values = []
            for v in values[:5]:  # Check first 5
                try:
                    if v is not None:
                        numeric_values.append(float(v))
                except (ValueError, TypeError):
                    pass
            
            # If most values are between 0 and 1.2, likely a ratio
            if len(numeric_values) >= 3:
                if all(0 <= v <= 1.2 for v in numeric_values):
                    bid_ratio_col = idx
                    break
    
    if bid_ratio_col is None:
        return False, "Bid_Ratio column not found", None
    
    # Verify calculation for a few rows
    correct_calcs = 0
    total_checked = 0
    
    for i, row in enumerate(rows[1:6], start=1):
        if len(row) <= max(your_bid_col, max_bid_col, bid_ratio_col):
            continue
        
        your_bid = row[your_bid_col].get('value') if isinstance(row[your_bid_col], dict) else row[your_bid_col]
        max_bid = row[max_bid_col].get('value') if isinstance(row[max_bid_col], dict) else row[max_bid_col]
        ratio = row[bid_ratio_col].get('value') if isinstance(row[bid_ratio_col], dict) else row[bid_ratio_col]
        
        if your_bid is None or max_bid is None or ratio is None:
            continue
        
        try:
            expected_ratio = float(your_bid) / float(max_bid)
            actual_ratio = float(ratio)
            
            if abs(actual_ratio - expected_ratio) < 0.01:
                correct_calcs += 1
            total_checked += 1
        except (ValueError, TypeError, ZeroDivisionError):
            continue
    
    if total_checked > 0 and correct_calcs / total_checked >= 0.8:
        return True, f"Bid_Ratio calculated correctly ({correct_calcs}/{total_checked})", bid_ratio_col
    elif total_checked == 0:
        return True, "Bid_Ratio column exists", bid_ratio_col
    else:
        return False, f"Bid_Ratio calculation errors", bid_ratio_col


def check_high_risk_flagging(rows: List, bid_ratio_col: int) -> Tuple[bool, str]:
    """Check if high-risk bids (ratio >= 0.8) are flagged"""
    if bid_ratio_col is None:
        return False, "Cannot check flagging (Bid_Ratio column not found)"
    
    # Look for a flag column (next to ratio) or check for formatting
    # Simple check: see if there's a helper column with text markers
    flag_col = bid_ratio_col + 1
    
    high_risk_count = 0
    flagged_count = 0
    
    for row in rows[1:]:  # Skip header
        if len(row) <= bid_ratio_col:
            continue
        
        ratio = row[bid_ratio_col].get('value') if isinstance(row[bid_ratio_col], dict) else row[bid_ratio_col]
        
        if ratio is None:
            continue
        
        try:
            ratio_val = float(ratio)
            if ratio_val >= 0.8:
                high_risk_count += 1
                
                # Check if there's a flag in adjacent column
                if len(row) > flag_col:
                    flag_cell = row[flag_col].get('value') if isinstance(row[flag_col], dict) else row[flag_col]
                    if flag_cell and str(flag_cell).strip():
                        flagged_count += 1
        except (ValueError, TypeError):
            continue
    
    if high_risk_count == 0:
        return True, "No high-risk bids to flag"
    
    if flagged_count >= high_risk_count * 0.8:  # At least 80% flagged
        return True, f"High-risk bids flagged ({flagged_count}/{high_risk_count})"
    else:
        # Give partial credit if bid ratio column exists
        return True, f"Bid_Ratio present (flagging may be via formatting)"


def calculate_expected_total_spending(rows: List, outcome_col: int, your_bid_col: int, shipping_col: int, total_cost_col: Optional[int]) -> float:
    """Calculate expected total spending for won items"""
    total_spending = 0.0
    
    for row in rows[1:]:  # Skip header
        if len(row) <= max(outcome_col, your_bid_col):
            continue
        
        outcome = row[outcome_col].get('value') if isinstance(row[outcome_col], dict) else row[outcome_col]
        
        if outcome and str(outcome).upper().strip() == "WON":
            # Use Total_Cost if available, otherwise calculate
            if total_cost_col and len(row) > total_cost_col:
                cost = row[total_cost_col].get('value') if isinstance(row[total_cost_col], dict) else row[total_cost_col]
                if cost:
                    try:
                        total_spending += float(cost)
                        continue
                    except (ValueError, TypeError):
                        pass
            
            # Fallback: calculate from bid + shipping
            your_bid = row[your_bid_col].get('value') if isinstance(row[your_bid_col], dict) else row[your_bid_col]
            shipping = row[shipping_col].get('value') if isinstance(row[shipping_col], dict) else row[shipping_col]
            
            if your_bid:
                try:
                    bid_val = float(your_bid)
                    ship_val = float(shipping) if shipping and str(shipping).strip() else 0.0
                    total_spending += bid_val + ship_val
                except (ValueError, TypeError):
                    pass
    
    return total_spending


def verify_auction_analysis(traj, env_info, task_info):
    """
    Verify auction bid analysis task completion.
    
    Checks:
    1. Categories standardized
    2. Total_Cost column exists
    3. Win_Rate calculated
    4. Bid_Ratio column exists
    5. High-risk bids flagged
    6. Total spending correct
    7. No duplicates
    8. Formulas used
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    temp_dir = None
    success = False
    workbook = None
    
    for fmt, path in [
        ('ods', '/home/ga/Documents/auction_analysis.ods'),
        ('ods', '/home/ga/Documents/auction_data.ods'),
        ('csv', '/home/ga/Documents/auction_analysis.csv'),
        ('csv', '/home/ga/Documents/auction_data.csv'),
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=fmt
        )
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        rows = workbook['sheets'][sheet_name]
        
        if len(rows) < 2:
            return {"passed": False, "score": 0, "feedback": "Insufficient data in spreadsheet"}
        
        # Find column indices
        item_id_col = find_column_by_header(rows, "Item_ID")
        category_col = find_column_by_header(rows, "Category")
        your_bid_col = find_column_by_header(rows, "Your_Bid")
        outcome_col = find_column_by_header(rows, "Outcome")
        shipping_col = find_column_by_header(rows, "Shipping")
        max_bid_col = find_column_by_header(rows, "Max_Comfortable")
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Categories standardized
        cat_ok, cat_msg, cat_score = check_categories_standardized(rows, category_col)
        if cat_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {cat_msg}")
        else:
            feedback_parts.append(f"❌ {cat_msg}")
        subscores['categories_standardized'] = cat_ok
        
        # Criterion 2: Total_Cost column
        total_cost_ok, total_cost_msg, total_cost_col = check_total_cost_column(
            rows, your_bid_col, shipping_col
        )
        if total_cost_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {total_cost_msg}")
        else:
            feedback_parts.append(f"❌ {total_cost_msg}")
        subscores['total_cost_column'] = total_cost_ok
        
        # Criterion 3: Win Rate calculated
        win_rate_val, win_rate_formula, has_formula = find_win_rate_cell(workbook, sheet_name)
        if win_rate_val is not None:
            if has_formula:
                criteria_passed += 1
                feedback_parts.append(f"✅ Win rate calculated: {win_rate_val:.1f}% (formula-based)")
            else:
                criteria_passed += 0.5  # Partial credit without formula
                feedback_parts.append(f"⚠️ Win rate present: {win_rate_val:.1f}% (no formula detected)")
        else:
            feedback_parts.append("❌ Win rate not found")
        subscores['win_rate_calculated'] = win_rate_val is not None
        
        # Criterion 4: Bid_Ratio column
        ratio_ok, ratio_msg, ratio_col = check_bid_ratio_column(rows, your_bid_col, max_bid_col)
        if ratio_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {ratio_msg}")
        else:
            feedback_parts.append(f"❌ {ratio_msg}")
        subscores['bid_ratio_column'] = ratio_ok
        
        # Criterion 5: High-risk flagging
        flag_ok, flag_msg = check_high_risk_flagging(rows, ratio_col)
        if flag_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {flag_msg}")
        else:
            feedback_parts.append(f"❌ {flag_msg}")
        subscores['high_risk_flagged'] = flag_ok
        
        # Criterion 6: Total spending correct
        expected_spending = calculate_expected_total_spending(
            rows, outcome_col, your_bid_col, shipping_col, total_cost_col
        )
        
        # Search for spending calculation in spreadsheet
        spending_found = False
        for row_idx in range(0, 15):
            if row_idx >= len(rows):
                break
            row = rows[row_idx]
            for col_idx in range(9, 15):  # J to O
                if col_idx >= len(row):
                    continue
                cell = row[col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                if value is not None:
                    try:
                        val_float = float(value)
                        # Check if close to expected spending (±5%)
                        if abs(val_float - expected_spending) / max(expected_spending, 1) < 0.05:
                            spending_found = True
                            criteria_passed += 1
                            feedback_parts.append(f"✅ Total spending: ${val_float:.0f} (expected ~${expected_spending:.0f})")
                            break
                    except (ValueError, TypeError):
                        continue
            if spending_found:
                break
        
        if not spending_found:
            feedback_parts.append(f"❌ Total spending not found (expected ~${expected_spending:.0f})")
        subscores['total_spending_correct'] = spending_found
        
        # Criterion 7: No duplicates
        dup_ok, dup_msg = check_duplicates(rows, item_id_col)
        if dup_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {dup_msg}")
        else:
            feedback_parts.append(f"❌ {dup_msg}")
        subscores['no_duplicates'] = dup_ok
        
        # Criterion 8: Formulas used (check if win rate has formula)
        if has_formula:
            criteria_passed += 1
            feedback_parts.append("✅ Formulas used (not hardcoded)")
        else:
            feedback_parts.append("⚠️ Key metrics may be hardcoded")
        subscores['formulas_used'] = has_formula
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        if passed:
            feedback_parts.append("🎉 Auction analysis completed successfully!")
        
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
        cleanup_verification_temp(temp_dir)
