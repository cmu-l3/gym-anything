#!/usr/bin/env python3
"""
Verifier for Garage Sale Pricing Strategy task.

Checks:
1. Base Price formula correctness (condition-based percentages)
2. Quick Sale logic (Furniture/Appliances flagged)
3. Minimum price enforcement (all items >= $1.00)
4. Revenue sum accuracy
5. Currency formatting
6. File saved correctly
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_by_header(sheet_data, header_keywords):
    """Find column index by searching for header keywords in first row."""
    if not sheet_data:
        return None
    
    first_row = sheet_data[0]
    for col_idx, cell in enumerate(first_row):
        cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
        cell_str = str(cell_value).lower().strip()
        
        for keyword in header_keywords:
            if keyword.lower() in cell_str:
                return col_idx
    return None


def get_column_letter(col_idx):
    """Convert 0-based column index to letter (0->A, 25->Z, 26->AA)."""
    result = ""
    col_idx += 1  # Make 1-based
    while col_idx > 0:
        col_idx -= 1
        result = chr(ord('A') + (col_idx % 26)) + result
        col_idx //= 26
    return result


def verify_base_price_formula(data, sheet_name, sheet_data):
    """
    Verify Base Price formula implements condition-based percentages.
    Tests multiple items with different conditions.
    """
    # Find relevant columns
    condition_col = find_column_by_header(sheet_data, ['condition'])
    market_price_col = find_column_by_header(sheet_data, ['market research', 'market price', 'research price'])
    base_price_col = find_column_by_header(sheet_data, ['base price', 'baseprice'])
    
    if condition_col is None or market_price_col is None or base_price_col is None:
        logger.warning(f"Could not find required columns: condition={condition_col}, market={market_price_col}, base={base_price_col}")
        return False, "Required columns not found"
    
    # Test multiple rows (skip header row 0)
    test_results = []
    conditions_tested = {'Excellent': 0, 'Good': 0, 'Fair': 0}
    
    for row_idx in range(1, min(len(sheet_data), 25)):  # Test up to 24 data rows
        row = sheet_data[row_idx]
        
        if row_idx >= len(row) or len(row) <= max(condition_col, market_price_col, base_price_col):
            continue
            
        condition_cell = row[condition_col]
        condition = str(condition_cell.get('value', '') if isinstance(condition_cell, dict) else condition_cell).strip()
        
        market_cell = row[market_price_col]
        market_price = market_cell.get('value', 0) if isinstance(market_cell, dict) else market_cell
        
        base_cell = row[base_price_col]
        base_price = base_cell.get('value', None) if isinstance(base_cell, dict) else base_cell
        
        if not condition or market_price == 0 or base_price is None:
            continue
        
        try:
            market_price = float(market_price)
            base_price = float(base_price)
        except (ValueError, TypeError):
            continue
        
        # Determine expected percentage range based on condition
        if 'Excellent' in condition:
            expected_min, expected_max = 0.75, 0.85
            conditions_tested['Excellent'] += 1
        elif 'Good' in condition:
            expected_min, expected_max = 0.60, 0.70
            conditions_tested['Good'] += 1
        elif 'Fair' in condition:
            expected_min, expected_max = 0.40, 0.50
            conditions_tested['Fair'] += 1
        else:
            continue
        
        actual_ratio = base_price / market_price if market_price > 0 else 0
        is_correct = expected_min <= actual_ratio <= expected_max
        
        test_results.append({
            'row': row_idx + 1,
            'condition': condition,
            'market_price': market_price,
            'base_price': base_price,
            'ratio': actual_ratio,
            'expected_range': (expected_min, expected_max),
            'correct': is_correct
        })
    
    if len(test_results) < 4:
        return False, f"Insufficient data to verify (only {len(test_results)} rows)"
    
    correct_count = sum(1 for r in test_results if r['correct'])
    total_count = len(test_results)
    
    # Need at least 70% correct and at least 4 correct items
    if correct_count >= 4 and correct_count / total_count >= 0.70:
        return True, f"Base Price formula correct ({correct_count}/{total_count} items)"
    else:
        # Log some failures for debugging
        failures = [r for r in test_results if not r['correct']][:3]
        failure_msg = "; ".join([
            f"Row {r['row']} ({r['condition']}): {r['ratio']:.2f} not in {r['expected_range']}"
            for r in failures
        ])
        return False, f"Base Price formula incorrect ({correct_count}/{total_count}): {failure_msg}"


def verify_quick_sale_logic(data, sheet_name, sheet_data):
    """
    Verify Quick Sale logic correctly identifies Furniture and Large Appliances.
    """
    category_col = find_column_by_header(sheet_data, ['category'])
    quick_sale_col = find_column_by_header(sheet_data, ['quick sale', 'quicksale', 'quick_sale'])
    
    if category_col is None or quick_sale_col is None:
        logger.warning(f"Could not find required columns: category={category_col}, quick_sale={quick_sale_col}")
        return False, "Quick Sale or Category column not found"
    
    furniture_correct = 0
    furniture_total = 0
    other_correct = 0
    other_total = 0
    
    for row_idx in range(1, min(len(sheet_data), 25)):
        row = sheet_data[row_idx]
        
        if len(row) <= max(category_col, quick_sale_col):
            continue
        
        category_cell = row[category_col]
        category = str(category_cell.get('value', '') if isinstance(category_cell, dict) else category_cell).strip().lower()
        
        quick_sale_cell = row[quick_sale_col]
        quick_sale_value = str(quick_sale_cell.get('value', '') if isinstance(quick_sale_cell, dict) else quick_sale_cell).strip().lower()
        
        if not category:
            continue
        
        # Check if this should be marked for quick sale
        should_be_quick_sale = 'furniture' in category or 'appliance' in category
        is_marked_quick_sale = 'yes' in quick_sale_value or 'true' in quick_sale_value or quick_sale_value == '1'
        
        if should_be_quick_sale:
            furniture_total += 1
            if is_marked_quick_sale:
                furniture_correct += 1
        else:
            other_total += 1
            if not is_marked_quick_sale or 'no' in quick_sale_value:
                other_correct += 1
    
    if furniture_total == 0 or other_total == 0:
        return False, f"Insufficient data (furniture:{furniture_total}, other:{other_total})"
    
    # Need at least 70% correct in both categories
    furniture_pct = furniture_correct / furniture_total if furniture_total > 0 else 0
    other_pct = other_correct / other_total if other_total > 0 else 0
    
    if furniture_pct >= 0.70 and other_pct >= 0.70:
        return True, f"Quick Sale logic correct (Furniture:{furniture_correct}/{furniture_total}, Other:{other_correct}/{other_total})"
    else:
        return False, f"Quick Sale logic incorrect (Furniture:{furniture_correct}/{furniture_total}={furniture_pct:.0%}, Other:{other_correct}/{other_total}={other_pct:.0%})"


def verify_minimum_prices(data, sheet_name, sheet_data):
    """Verify all final prices are >= $1.00."""
    final_price_col = find_column_by_header(sheet_data, ['final sale price', 'final price', 'sale price'])
    
    if final_price_col is None:
        return False, "Final Sale Price column not found"
    
    violations = []
    for row_idx in range(1, min(len(sheet_data), 25)):
        row = sheet_data[row_idx]
        
        if len(row) <= final_price_col:
            continue
        
        price_cell = row[final_price_col]
        price = price_cell.get('value', None) if isinstance(price_cell, dict) else price_cell
        
        # Skip empty cells or text cells
        if price is None or price == '':
            continue
        
        # Skip cells that look like headers or labels
        if isinstance(price, str) and any(word in str(price).lower() for word in ['total', 'revenue', 'sum', 'price']):
            continue
        
        try:
            price_float = float(price)
            if price_float < 1.00 and price_float > 0:  # Only flag prices between 0 and 1
                violations.append((row_idx + 1, price_float))
        except (ValueError, TypeError):
            continue
    
    if violations:
        violation_str = ", ".join([f"Row {r}: ${p:.2f}" for r, p in violations[:3]])
        return False, f"Minimum price violated: {violation_str}"
    else:
        return True, "All prices >= $1.00"


def verify_revenue_sum(data, sheet_name, sheet_data):
    """Verify total revenue is correctly summed."""
    final_price_col = find_column_by_header(sheet_data, ['final sale price', 'final price', 'sale price'])
    
    if final_price_col is None:
        return False, "Final Sale Price column not found"
    
    # Collect all final prices (excluding total row)
    prices = []
    for row_idx in range(1, len(sheet_data)):
        row = sheet_data[row_idx]
        
        if len(row) <= final_price_col:
            continue
        
        price_cell = row[final_price_col]
        price = price_cell.get('value', None) if isinstance(price_cell, dict) else price_cell
        
        # Skip empty or text cells
        if price is None or price == '':
            continue
        
        # Check if this might be the total row (contains "total", "revenue", "sum")
        # Look at nearby cells for these keywords
        is_total_row = False
        for cell in row:
            cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
            if any(word in cell_val for word in ['total', 'revenue', 'sum']):
                is_total_row = True
                break
        
        try:
            price_float = float(price)
            if not is_total_row:
                prices.append(price_float)
            else:
                # This might be the total - save it
                reported_total = price_float
        except (ValueError, TypeError):
            continue
    
    if len(prices) < 10:
        return False, f"Insufficient price data ({len(prices)} prices found)"
    
    calculated_total = sum(prices)
    
    # Try to find the reported total (look for a SUM formula or a large value)
    # Check last few rows for total
    reported_total = None
    for row_idx in range(len(sheet_data) - 1, max(len(sheet_data) - 5, 0), -1):
        row = sheet_data[row_idx]
        
        if len(row) <= final_price_col:
            continue
        
        price_cell = row[final_price_col]
        
        # Check if this cell has a formula
        formula = price_cell.get('formula', '') if isinstance(price_cell, dict) else ''
        if formula and 'SUM' in formula.upper():
            price = price_cell.get('value', None) if isinstance(price_cell, dict) else price_cell
            try:
                reported_total = float(price)
                break
            except (ValueError, TypeError):
                pass
    
    if reported_total is None:
        return False, f"Total revenue sum not found (expected ~${calculated_total:.2f})"
    
    # Allow $0.50 tolerance
    if abs(reported_total - calculated_total) <= 0.50:
        return True, f"Revenue correctly summed: ${reported_total:.2f}"
    else:
        return False, f"Revenue sum incorrect: ${reported_total:.2f} (expected ${calculated_total:.2f})"


def check_currency_formatting(data, sheet_name, sheet_data):
    """Check if price columns have currency formatting (basic check)."""
    # This is a simplified check - just verify that some cells have $ or are formatted as currency
    # In a real implementation, we'd check cell format properties
    
    final_price_col = find_column_by_header(sheet_data, ['final sale price', 'final price', 'sale price'])
    base_price_col = find_column_by_header(sheet_data, ['base price', 'baseprice'])
    
    if final_price_col is None:
        return False, "Final Sale Price column not found"
    
    # Check a few cells for numeric values that look like they could be currency
    # This is a weak check but better than nothing without full format info
    has_numeric_prices = False
    for row_idx in range(1, min(len(sheet_data), 5)):
        row = sheet_data[row_idx]
        if len(row) > final_price_col:
            price_cell = row[final_price_col]
            price = price_cell.get('value', None) if isinstance(price_cell, dict) else price_cell
            try:
                if float(price) > 0:
                    has_numeric_prices = True
                    break
            except (ValueError, TypeError):
                pass
    
    if has_numeric_prices:
        return True, "Price columns appear formatted"
    else:
        return False, "Currency formatting not detected"


def verify_garage_sale_pricing(traj, env_info, task_info):
    """
    Main verification function for Garage Sale Pricing task.
    
    Checks:
    1. Base Price formula correctness
    2. Quick Sale logic
    3. Minimum price enforcement
    4. Revenue sum accuracy
    5. Currency formatting
    6. File saved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/garage_sale_pricing.ods",
        "/home/ga/Documents/garage_sale_items.ods",
        "/home/ga/Documents/garage_sale_items.csv",
    ]
    
    success = False
    file_info = None
    temp_dir = None
    
    for container_path in possible_paths:
        # Determine format
        file_format = 'ods' if container_path.endswith('.ods') else 'csv'
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            [file_format]
        )
        if success:
            logger.info(f"Successfully loaded file from {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load file from any expected location: {error}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = get_sheet_names(data)
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = data['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Base Price formula correctness
        base_ok, base_msg = verify_base_price_formula(data, sheet_name, sheet_data)
        if base_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {base_msg}")
        else:
            feedback_parts.append(f"❌ {base_msg}")
        subscores['base_price_formula'] = base_ok
        
        # Criterion 2: Quick Sale logic
        quick_ok, quick_msg = verify_quick_sale_logic(data, sheet_name, sheet_data)
        if quick_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {quick_msg}")
        else:
            feedback_parts.append(f"❌ {quick_msg}")
        subscores['quick_sale_logic'] = quick_ok
        
        # Criterion 3: Minimum price enforcement
        min_ok, min_msg = verify_minimum_prices(data, sheet_name, sheet_data)
        if min_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {min_msg}")
        else:
            feedback_parts.append(f"❌ {min_msg}")
        subscores['minimum_price'] = min_ok
        
        # Criterion 4: Revenue sum accuracy
        revenue_ok, revenue_msg = verify_revenue_sum(data, sheet_name, sheet_data)
        if revenue_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {revenue_msg}")
        else:
            feedback_parts.append(f"❌ {revenue_msg}")
        subscores['revenue_sum'] = revenue_ok
        
        # Criterion 5: Currency formatting (weak check)
        currency_ok, currency_msg = check_currency_formatting(data, sheet_name, sheet_data)
        if currency_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {currency_msg}")
        else:
            feedback_parts.append(f"⚠️ {currency_msg}")
        subscores['currency_format'] = currency_ok
        
        # Criterion 6: File saved (we got here, so file exists)
        criteria_passed += 1
        feedback_parts.append("✅ File saved successfully")
        subscores['file_saved'] = True
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 4/6 criteria = 67%, so need at least 70%
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent pricing strategy created!")
        elif passed:
            feedback_parts.append("✅ Pricing strategy completed")
        else:
            feedback_parts.append("❌ Pricing strategy incomplete")
        
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
        cleanup_verification_temp(file_info.get('temp_dir') if file_info else None)
