#!/usr/bin/env python3
"""
Verifier for Photography Gear Depreciation task.

Verifies:
1. Date standardization (all dates valid)
2. No missing prices
3. Age calculation formulas
4. Useful life conditional logic
5. Depreciation formulas (annual, accumulated, book value)
6. Sell candidate logic
7. Total depreciation sum
8. No formula errors
"""

import sys
import os
import logging
from datetime import datetime, date
from typing import Dict, Any, Tuple, Optional, List
import re

# Use relative path to utils folder (verifier runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_by_header(data: Dict[str, Any], sheet_name: str, header_text: str) -> Optional[int]:
    """Find column index by searching for header text (case-insensitive)."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return None
        
        rows = sheets[sheet_name]
        if not rows:
            return None
        
        header_row = rows[0]
        header_lower = header_text.lower()
        
        for col_idx, cell in enumerate(header_row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and header_lower in str(cell_value).lower():
                return col_idx
        
        return None
    except Exception as e:
        logger.error(f"Error finding column: {e}")
        return None


def check_column_dates_valid(data: Dict[str, Any], sheet_name: str, col_idx: int, 
                             min_valid_ratio: float = 0.9) -> bool:
    """Check if column contains valid dates (not text strings)."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        valid_count = 0
        total_count = 0
        
        for row_idx in range(1, len(rows)):  # Skip header
            if row_idx < len(rows) and col_idx < len(rows[row_idx]):
                cell = rows[row_idx][col_idx]
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                cell_type = cell.get('type') if isinstance(cell, dict) else None
                
                if cell_value:
                    total_count += 1
                    # Check if it's a date type or contains date-like content
                    if cell_type == 'date' or isinstance(cell_value, (date, datetime)):
                        valid_count += 1
                    elif isinstance(cell_value, str):
                        # Check if string looks like a valid date format
                        if re.match(r'\d{4}-\d{2}-\d{2}', cell_value) or \
                           re.match(r'\d{2}/\d{2}/\d{4}', cell_value):
                            valid_count += 1
        
        if total_count == 0:
            return False
        
        return (valid_count / total_count) >= min_valid_ratio
    
    except Exception as e:
        logger.error(f"Error checking date validity: {e}")
        return False


def check_column_completeness(data: Dict[str, Any], sheet_name: str, col_idx: int,
                              min_ratio: float = 0.95) -> bool:
    """Check if column is mostly filled (few missing values)."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        filled_count = 0
        total_count = 0
        
        for row_idx in range(1, len(rows)):  # Skip header
            if row_idx < len(rows) and col_idx < len(rows[row_idx]):
                cell = rows[row_idx][col_idx]
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                
                # Count non-header rows
                # Check if row has any data (not completely empty)
                row_has_data = any(
                    (c.get('value') if isinstance(c, dict) else c) 
                    for c in rows[row_idx]
                )
                
                if row_has_data:
                    total_count += 1
                    if cell_value not in (None, '', ' '):
                        filled_count += 1
        
        if total_count == 0:
            return False
        
        return (filled_count / total_count) >= min_ratio
    
    except Exception as e:
        logger.error(f"Error checking completeness: {e}")
        return False


def check_value_range(data: Dict[str, Any], sheet_name: str, col_idx: int,
                     min_val: float, max_val: float) -> bool:
    """Check if numeric values in column are within reasonable range."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        
        for row_idx in range(1, len(rows)):  # Skip header
            if row_idx < len(rows) and col_idx < len(rows[row_idx]):
                cell = rows[row_idx][col_idx]
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                
                if cell_value not in (None, '', ' '):
                    try:
                        num_val = float(cell_value)
                        if num_val < min_val or num_val > max_val:
                            logger.warning(f"Value {num_val} out of range [{min_val}, {max_val}]")
                            return False
                    except (ValueError, TypeError):
                        # Skip non-numeric values
                        pass
        
        return True
    
    except Exception as e:
        logger.error(f"Error checking value range: {e}")
        return False


def check_column_has_formulas(data: Dict[str, Any], sheet_name: str, col_idx: int,
                              min_ratio: float = 0.8) -> bool:
    """Check if column contains formulas (not hardcoded values)."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        formula_count = 0
        data_count = 0
        
        for row_idx in range(1, len(rows)):  # Skip header
            if row_idx < len(rows) and col_idx < len(rows[row_idx]):
                cell = rows[row_idx][col_idx]
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                cell_formula = cell.get('formula') if isinstance(cell, dict) else None
                
                # Check if row has data
                row_has_data = any(
                    (c.get('value') if isinstance(c, dict) else c) 
                    for c in rows[row_idx]
                )
                
                if row_has_data and cell_value not in (None, '', ' '):
                    data_count += 1
                    if cell_formula:
                        formula_count += 1
        
        if data_count == 0:
            return False
        
        return (formula_count / data_count) >= min_ratio
    
    except Exception as e:
        logger.error(f"Error checking formulas: {e}")
        return False


def spot_check_age_calculations(data: Dict[str, Any], sheet_name: str, 
                                purchase_date_col: int, age_col: int,
                                samples: int = 3, tolerance: float = 0.15) -> bool:
    """Spot-check age calculations against actual date differences."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        checked = 0
        correct = 0
        
        for row_idx in range(1, min(len(rows), samples + 1)):
            if row_idx < len(rows):
                # Get purchase date
                date_cell = rows[row_idx][purchase_date_col] if purchase_date_col < len(rows[row_idx]) else None
                age_cell = rows[row_idx][age_col] if age_col < len(rows[row_idx]) else None
                
                if not date_cell or not age_cell:
                    continue
                
                date_value = date_cell.get('value') if isinstance(date_cell, dict) else date_cell
                age_value = age_cell.get('value') if isinstance(age_cell, dict) else age_cell
                
                if date_value and age_value:
                    checked += 1
                    
                    # Try to parse date and calculate expected age
                    try:
                        # Parse various date formats
                        purchase_date = None
                        if isinstance(date_value, (date, datetime)):
                            purchase_date = date_value
                        elif isinstance(date_value, str):
                            for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y']:
                                try:
                                    purchase_date = datetime.strptime(date_value, fmt).date()
                                    break
                                except:
                                    pass
                        
                        if purchase_date:
                            today = datetime.now().date()
                            expected_age = (today - purchase_date).days / 365.25
                            actual_age = float(age_value)
                            
                            if abs(expected_age - actual_age) <= tolerance:
                                correct += 1
                            else:
                                logger.warning(f"Age mismatch row {row_idx+1}: expected ~{expected_age:.2f}, got {actual_age:.2f}")
                    
                    except Exception as e:
                        logger.warning(f"Could not verify age calculation for row {row_idx+1}: {e}")
        
        if checked == 0:
            return False
        
        return correct >= (checked * 0.7)  # At least 70% of checked rows should be correct
    
    except Exception as e:
        logger.error(f"Error spot-checking ages: {e}")
        return False


def verify_useful_life_assignments(data: Dict[str, Any], sheet_name: str,
                                   category_col: int, useful_life_col: int,
                                   rules: Dict[str, int]) -> bool:
    """Verify useful life values match category rules."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        correct_count = 0
        total_count = 0
        
        for row_idx in range(1, len(rows)):
            if row_idx < len(rows):
                category_cell = rows[row_idx][category_col] if category_col < len(rows[row_idx]) else None
                life_cell = rows[row_idx][useful_life_col] if useful_life_col < len(rows[row_idx]) else None
                
                if not category_cell or not life_cell:
                    continue
                
                category = str(category_cell.get('value') if isinstance(category_cell, dict) else category_cell).lower()
                life_value = life_cell.get('value') if isinstance(life_cell, dict) else life_cell
                
                if category and life_value:
                    total_count += 1
                    
                    # Match category to expected life
                    expected_life = None
                    for cat_key, life_years in rules.items():
                        if cat_key.lower() in category:
                            expected_life = life_years
                            break
                    
                    if expected_life and float(life_value) == expected_life:
                        correct_count += 1
                    else:
                        logger.warning(f"Row {row_idx+1}: category '{category}' has life {life_value}, expected {expected_life}")
        
        if total_count == 0:
            return False
        
        return (correct_count / total_count) >= 0.9  # 90% must be correct
    
    except Exception as e:
        logger.error(f"Error verifying useful life: {e}")
        return False


def spot_check_depreciation_formulas(data: Dict[str, Any], sheet_name: str,
                                     price_col: int, life_col: int, age_col: int,
                                     annual_col: int, accum_col: int, book_col: int,
                                     samples: int = 3, tolerance: float = 15) -> bool:
    """Spot-check depreciation calculations."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        checked = 0
        correct = 0
        
        for row_idx in range(1, min(len(rows), samples + 3)):
            if row_idx >= len(rows):
                break
            
            row = rows[row_idx]
            
            # Extract values
            price = float(row[price_col].get('value') if isinstance(row[price_col], dict) else row[price_col]) if price_col < len(row) else None
            life = float(row[life_col].get('value') if isinstance(row[life_col], dict) else row[life_col]) if life_col < len(row) else None
            age = float(row[age_col].get('value') if isinstance(row[age_col], dict) else row[age_col]) if age_col < len(row) else None
            annual = float(row[annual_col].get('value') if isinstance(row[annual_col], dict) else row[annual_col]) if annual_col < len(row) else None
            accum = float(row[accum_col].get('value') if isinstance(row[accum_col], dict) else row[accum_col]) if accum_col < len(row) else None
            book = float(row[book_col].get('value') if isinstance(row[book_col], dict) else row[book_col]) if book_col < len(row) else None
            
            if all(v is not None for v in [price, life, age, annual, accum, book]):
                checked += 1
                
                # Calculate expected values
                expected_annual = price / life
                expected_accum = expected_annual * min(age, life)
                expected_book = max(0, price - expected_accum)
                
                # Check with tolerance
                annual_ok = abs(annual - expected_annual) <= tolerance
                accum_ok = abs(accum - expected_accum) <= tolerance
                book_ok = abs(book - expected_book) <= tolerance
                
                if annual_ok and accum_ok and book_ok:
                    correct += 1
                else:
                    logger.warning(f"Row {row_idx+1} depreciation mismatch: annual {annual} vs {expected_annual:.2f}, accum {accum} vs {expected_accum:.2f}, book {book} vs {expected_book:.2f}")
        
        if checked == 0:
            return False
        
        return correct >= (checked * 0.7)  # 70% must be correct
    
    except Exception as e:
        logger.error(f"Error checking depreciation: {e}")
        return False


def verify_sell_logic(data: Dict[str, Any], sheet_name: str,
                     market_col: int, book_col: int, sell_col: int) -> bool:
    """Verify sell candidate logic (market > book)."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        correct_count = 0
        total_count = 0
        
        for row_idx in range(1, len(rows)):
            if row_idx >= len(rows):
                break
            
            row = rows[row_idx]
            
            market = row[market_col].get('value') if isinstance(row[market_col], dict) else row[market_col] if market_col < len(row) else None
            book = row[book_col].get('value') if isinstance(row[book_col], dict) else row[book_col] if book_col < len(row) else None
            sell = row[sell_col].get('value') if isinstance(row[sell_col], dict) else row[sell_col] if sell_col < len(row) else None
            
            if market is not None and book is not None and sell is not None:
                total_count += 1
                
                try:
                    market_val = float(market)
                    book_val = float(book)
                    sell_str = str(sell).upper().strip()
                    
                    expected_sell = "YES" if market_val > book_val else "NO"
                    
                    if sell_str in expected_sell or expected_sell in sell_str:
                        correct_count += 1
                    else:
                        logger.warning(f"Row {row_idx+1}: market {market_val} vs book {book_val}, expected '{expected_sell}' got '{sell_str}'")
                
                except (ValueError, TypeError) as e:
                    logger.warning(f"Row {row_idx+1}: Could not compare sell logic: {e}")
        
        if total_count == 0:
            return False
        
        return (correct_count / total_count) >= 0.85  # 85% must be correct
    
    except Exception as e:
        logger.error(f"Error verifying sell logic: {e}")
        return False


def find_cell_with_label(data: Dict[str, Any], sheet_name: str, label_text: str) -> Optional[Tuple[int, int]]:
    """Find cell containing label text, return coordinates of adjacent cell."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return None
        
        rows = sheets[sheet_name]
        label_lower = label_text.lower()
        
        for row_idx, row in enumerate(rows):
            for col_idx, cell in enumerate(row):
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                if cell_value and label_lower in str(cell_value).lower():
                    # Return cell to the right or below
                    if col_idx + 1 < len(row):
                        return (row_idx, col_idx + 1)
                    elif row_idx + 1 < len(rows):
                        return (row_idx + 1, col_idx)
        
        return None
    except Exception as e:
        logger.error(f"Error finding labeled cell: {e}")
        return None


def check_cell_has_sum_formula(data: Dict[str, Any], sheet_name: str, coords: Tuple[int, int]) -> bool:
    """Check if cell contains SUM formula."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        row_idx, col_idx = coords
        
        if row_idx < len(rows) and col_idx < len(rows[row_idx]):
            cell = rows[row_idx][col_idx]
            formula = cell.get('formula') if isinstance(cell, dict) else None
            
            if formula and 'SUM' in formula.upper():
                return True
        
        return False
    except Exception as e:
        logger.error(f"Error checking SUM formula: {e}")
        return False


def check_total_depreciation_reasonable(data: Dict[str, Any], sheet_name: str,
                                       coords: Tuple[int, int], price_col: int,
                                       min_ratio: float = 0.05, max_ratio: float = 0.40) -> bool:
    """Check if total depreciation is reasonable proportion of total gear value."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        row_idx, col_idx = coords
        
        # Get total depreciation value
        if row_idx < len(rows) and col_idx < len(rows[row_idx]):
            cell = rows[row_idx][col_idx]
            total_dep = cell.get('value') if isinstance(cell, dict) else cell
            
            if total_dep is None:
                return False
            
            try:
                total_dep_val = float(total_dep)
            except:
                return False
            
            # Calculate total gear value
            total_price = 0
            for r_idx in range(1, len(rows)):
                if price_col < len(rows[r_idx]):
                    price_cell = rows[r_idx][price_col]
                    price = price_cell.get('value') if isinstance(price_cell, dict) else price_cell
                    if price:
                        try:
                            total_price += float(price)
                        except:
                            pass
            
            if total_price == 0:
                return False
            
            ratio = total_dep_val / total_price
            return min_ratio <= ratio <= max_ratio
        
        return False
    except Exception as e:
        logger.error(f"Error checking total depreciation: {e}")
        return False


def check_no_formula_errors(data: Dict[str, Any], sheet_name: str) -> bool:
    """Check for formula errors (#REF!, #VALUE!, #DIV/0!, etc.)."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        
        for row_idx, row in enumerate(rows):
            for col_idx, cell in enumerate(row):
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                
                if cell_value and isinstance(cell_value, str):
                    if any(err in cell_value for err in ['#REF!', '#VALUE!', '#DIV/0!', '#NAME?', '#NUM!', '#N/A']):
                        logger.warning(f"Formula error at row {row_idx+1}, col {col_idx+1}: {cell_value}")
                        return False
        
        return True
    except Exception as e:
        logger.error(f"Error checking for formula errors: {e}")
        return False


def verify_photo_gear_depreciation(traj, env_info, task_info):
    """
    Main verifier function for photography gear depreciation task.
    
    Verifies 8 criteria:
    1. Dates standardized
    2. No missing prices
    3. Age calculations correct
    4. Useful life logic correct
    5. Depreciation formulas correct
    6. Sell logic correct
    7. Total depreciation calculated
    8. No formula errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible output locations
    temp_dir = None
    success = False
    
    for path in [
        "/home/ga/Documents/gear_depreciation_report.ods",
        "/home/ga/Documents/photography_gear_messy.ods",
        "/home/ga/Documents/photography_gear_messy.csv"
    ]:
        fmt = 'csv' if path.endswith('.csv') else 'ods'
        success, file_info, error = setup_calc_verification(copy_from_env, path, [fmt])
        if success:
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    try:
        data = file_info['sheet_data']
        sheet_name = list(data.get('sheets', {}).keys())[0]
        
        score = 0
        max_score = 8
        feedback_parts = []
        subscores = {}
        
        # Find columns
        purchase_date_col = find_column_by_header(data, sheet_name, "purchase date")
        price_col = find_column_by_header(data, sheet_name, "purchase price")
        market_col = find_column_by_header(data, sheet_name, "market value")
        category_col = find_column_by_header(data, sheet_name, "category")
        age_col = find_column_by_header(data, sheet_name, "years owned")
        useful_life_col = find_column_by_header(data, sheet_name, "useful life")
        annual_dep_col = find_column_by_header(data, sheet_name, "annual depreciation")
        accum_dep_col = find_column_by_header(data, sheet_name, "accumulated depreciation")
        book_value_col = find_column_by_header(data, sheet_name, "book value")
        sell_col = find_column_by_header(data, sheet_name, "sell")
        
        # Criterion 1: Date Standardization
        if purchase_date_col is not None:
            date_validity = check_column_dates_valid(data, sheet_name, purchase_date_col, min_valid_ratio=0.85)
            if date_validity:
                score += 1
                feedback_parts.append("✅ Dates standardized and valid")
                subscores['dates_standardized'] = True
            else:
                feedback_parts.append("❌ Purchase dates not properly standardized")
                subscores['dates_standardized'] = False
        else:
            feedback_parts.append("❌ Purchase Date column not found")
            subscores['dates_standardized'] = False
        
        # Criterion 2: No Missing Prices
        if price_col is not None:
            completeness = check_column_completeness(data, sheet_name, price_col, min_ratio=0.95)
            reasonable = check_value_range(data, sheet_name, price_col, min_val=50, max_val=15000)
            if completeness and reasonable:
                score += 1
                feedback_parts.append("✅ Purchase prices complete and reasonable")
                subscores['prices_complete'] = True
            else:
                feedback_parts.append("❌ Missing or unreasonable purchase prices")
                subscores['prices_complete'] = False
        else:
            feedback_parts.append("❌ Purchase Price column not found")
            subscores['prices_complete'] = False
        
        # Criterion 3: Age Calculation
        if age_col is not None and purchase_date_col is not None:
            has_formulas = check_column_has_formulas(data, sheet_name, age_col, min_ratio=0.75)
            accuracy = spot_check_age_calculations(data, sheet_name, purchase_date_col, age_col, samples=4, tolerance=0.2)
            if has_formulas and accuracy:
                score += 1
                feedback_parts.append("✅ Age calculations correct with proper formulas")
                subscores['age_correct'] = True
            else:
                if not has_formulas:
                    feedback_parts.append("❌ Age calculations missing formulas (hardcoded values)")
                else:
                    feedback_parts.append("❌ Age calculations inaccurate")
                subscores['age_correct'] = False
        else:
            feedback_parts.append("❌ Years Owned column not found or no date column")
            subscores['age_correct'] = False
        
        # Criterion 4: Useful Life Logic
        if useful_life_col is not None and category_col is not None:
            rules = {
                "camera": 5,
                "lens": 7,
                "accessory": 3,
                "computer": 3,
                "storage": 3
            }
            correct_logic = verify_useful_life_assignments(data, sheet_name, category_col, useful_life_col, rules)
            if correct_logic:
                score += 1
                feedback_parts.append("✅ Useful life correctly assigned by category")
                subscores['useful_life_correct'] = True
            else:
                feedback_parts.append("❌ Useful life assignment logic incorrect")
                subscores['useful_life_correct'] = False
        else:
            feedback_parts.append("❌ Useful Life or Category column not found")
            subscores['useful_life_correct'] = False
        
        # Criterion 5: Depreciation Formulas
        if all([annual_dep_col, accum_dep_col, book_value_col, price_col, useful_life_col, age_col]):
            formulas_correct = spot_check_depreciation_formulas(
                data, sheet_name,
                price_col, useful_life_col, age_col,
                annual_dep_col, accum_dep_col, book_value_col,
                samples=4, tolerance=20
            )
            if formulas_correct:
                score += 1
                feedback_parts.append("✅ Depreciation formulas correct")
                subscores['depreciation_correct'] = True
            else:
                feedback_parts.append("❌ Depreciation calculations incorrect")
                subscores['depreciation_correct'] = False
        else:
            missing = []
            if not annual_dep_col: missing.append("Annual Depreciation")
            if not accum_dep_col: missing.append("Accumulated Depreciation")
            if not book_value_col: missing.append("Book Value")
            feedback_parts.append(f"❌ Missing columns: {', '.join(missing)}")
            subscores['depreciation_correct'] = False
        
        # Criterion 6: Sell Candidate Logic
        if sell_col is not None and market_col is not None and book_value_col is not None:
            logic_correct = verify_sell_logic(data, sheet_name, market_col, book_value_col, sell_col)
            if logic_correct:
                score += 1
                feedback_parts.append("✅ Sell candidate logic correct")
                subscores['sell_logic_correct'] = True
            else:
                feedback_parts.append("❌ Sell candidate logic incorrect")
                subscores['sell_logic_correct'] = False
        else:
            feedback_parts.append("❌ Sell, Market Value, or Book Value column not found")
            subscores['sell_logic_correct'] = False
        
        # Criterion 7: Total Depreciation Sum
        total_dep_cell = find_cell_with_label(data, sheet_name, "total depreciation")
        if total_dep_cell and price_col is not None:
            has_sum = check_cell_has_sum_formula(data, sheet_name, total_dep_cell)
            reasonable_range = check_total_depreciation_reasonable(
                data, sheet_name, total_dep_cell, price_col,
                min_ratio=0.05, max_ratio=0.40
            )
            if has_sum and reasonable_range:
                score += 1
                feedback_parts.append("✅ Total depreciation calculated correctly")
                subscores['total_depreciation_correct'] = True
            else:
                if not has_sum:
                    feedback_parts.append("❌ Total depreciation missing SUM formula")
                else:
                    feedback_parts.append("❌ Total depreciation value unreasonable")
                subscores['total_depreciation_correct'] = False
        else:
            feedback_parts.append("❌ Total depreciation not found or labeled")
            subscores['total_depreciation_correct'] = False
        
        # Criterion 8: No Formula Errors
        error_free = check_no_formula_errors(data, sheet_name)
        if error_free:
            score += 1
            feedback_parts.append("✅ No formula errors detected")
            subscores['no_errors'] = True
        else:
            feedback_parts.append("❌ Formula errors found (#REF!, #VALUE!, etc.)")
            subscores['no_errors'] = False
        
        # Calculate final score
        percentage = (score / max_score) * 100
        passed = percentage >= 75  # Need 6/8 criteria
        
        # Add summary
        if passed and percentage >= 90:
            feedback_parts.append("🎉 Excellent depreciation calculation!")
        elif passed:
            feedback_parts.append("✅ Depreciation task completed successfully")
        else:
            feedback_parts.append("❌ Depreciation task requirements not fully met")
        
        detailed_feedback = " | ".join(feedback_parts)
        detailed_feedback += f"\n\nFinal Score: {score}/{max_score} ({percentage:.1f}%)"
        
        return {
            "passed": passed,
            "score": int(percentage),
            "feedback": detailed_feedback,
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
        cleanup_verification_temp(file_info.get('temp_dir'))
