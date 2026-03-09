#!/usr/bin/env python3
"""
Verifier for Data Restructuring Task (Wide to Long Format)

Validates that quarterly sales data was correctly transformed from:
  Wide format:  Category | Q1 | Q2 | Q3 | Q4
  Long format:  Category | Quarter | Sales
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Optional, Any

# Use relative path to utils folder (verification runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Expected source data
SOURCE_DATA = {
    "Electronics": {"Q1": 45000, "Q2": 52000, "Q3": 48000, "Q4": 61000},
    "Home & Garden": {"Q1": 23000, "Q2": 28000, "Q3": 31000, "Q4": 26000},
    "Clothing": {"Q1": 18000, "Q2": 15000, "Q3": 22000, "Q4": 29000},
    "Sports Equipment": {"Q1": 12000, "Q2": 14000, "Q3": 19000, "Q4": 16000},
    "Books": {"Q1": 8000, "Q2": 7500, "Q3": 8200, "Q4": 11000}
}

QUARTERS = ["Q1", "Q2", "Q3", "Q4"]
EXPECTED_CATEGORIES = list(SOURCE_DATA.keys())
EXPECTED_ROW_COUNT = len(EXPECTED_CATEGORIES) * len(QUARTERS)  # 20 rows


def normalize_text(text: Any) -> str:
    """Normalize text for comparison (lowercase, strip whitespace)"""
    if text is None:
        return ""
    return str(text).strip().lower()


def is_quarter_label(value: Any) -> Optional[str]:
    """Check if value is a quarter label, return normalized form (Q1-Q4) or None"""
    if value is None:
        return None
    text = normalize_text(value)
    # Match Q1, q1, Quarter 1, Q1 2024, etc.
    match = re.search(r'q[1-4]', text)
    if match:
        return match.group(0).upper()
    # Match "Quarter 1", "quarter 1", etc.
    match = re.search(r'quarter\s*([1-4])', text)
    if match:
        return f"Q{match.group(1)}"
    return None


def find_restructured_data(workbook: Dict, sheet_name: str) -> Optional[Tuple[int, int]]:
    """
    Search for the restructured data area (3-column structure).
    Returns (start_row, start_col) of the header row, or None if not found.
    """
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return None
    
    rows = sheets[sheet_name]
    
    # Search for a header row with something like "Category", "Quarter", "Sales"
    for row_idx, row in enumerate(rows):
        if len(row) < 3:
            continue
        
        # Check if this looks like our header row
        for col_start in range(len(row) - 2):
            cell1 = row[col_start].get('value') if isinstance(row[col_start], dict) else row[col_start]
            cell2 = row[col_start + 1].get('value') if isinstance(row[col_start + 1], dict) else row[col_start + 1]
            cell3 = row[col_start + 2].get('value') if isinstance(row[col_start + 2], dict) else row[col_start + 2]
            
            text1 = normalize_text(cell1)
            text2 = normalize_text(cell2)
            text3 = normalize_text(cell3)
            
            # Check if headers match expected pattern
            if ('category' in text1 or 'product' in text1) and \
               ('quarter' in text2 or 'period' in text2) and \
               ('sales' in text3 or 'amount' in text3 or 'revenue' in text3):
                logger.info(f"Found restructured data header at row {row_idx + 1}, col {col_start + 1}")
                return (row_idx, col_start)
    
    return None


def extract_restructured_data(workbook: Dict, sheet_name: str, 
                              start_row: int, start_col: int) -> List[Tuple[str, str, float]]:
    """
    Extract restructured data starting from given position.
    Returns list of (category, quarter, sales) tuples.
    """
    sheets = workbook.get('sheets', {})
    rows = sheets[sheet_name]
    
    data = []
    
    # Start from the row after header
    for row_idx in range(start_row + 1, len(rows)):
        if row_idx >= len(rows):
            break
        
        row = rows[row_idx]
        
        # Check if we have data in the three columns
        if start_col + 2 >= len(row):
            continue
        
        cat_cell = row[start_col].get('value') if isinstance(row[start_col], dict) else row[start_col]
        quarter_cell = row[start_col + 1].get('value') if isinstance(row[start_col + 1], dict) else row[start_col + 1]
        sales_cell = row[start_col + 2].get('value') if isinstance(row[start_col + 2], dict) else row[start_col + 2]
        
        # Stop if we hit empty rows
        if not cat_cell and not quarter_cell and not sales_cell:
            break
        
        # Skip if any cell is empty (incomplete data)
        if not cat_cell or not quarter_cell or sales_cell is None:
            continue
        
        # Normalize quarter
        quarter_normalized = is_quarter_label(quarter_cell)
        if not quarter_normalized:
            logger.warning(f"Invalid quarter format in row {row_idx + 1}: {quarter_cell}")
            continue
        
        # Parse sales value
        try:
            sales_value = float(sales_cell)
        except (ValueError, TypeError):
            logger.warning(f"Invalid sales value in row {row_idx + 1}: {sales_cell}")
            continue
        
        data.append((str(cat_cell).strip(), quarter_normalized, sales_value))
    
    return data


def verify_restructured_data(restructured_data: List[Tuple[str, str, float]]) -> Dict[str, Any]:
    """
    Verify the restructured data against expected source data.
    Returns dict with verification results.
    """
    results = {
        'row_count_correct': False,
        'category_coverage': {},
        'quarter_coverage': {},
        'value_accuracy': {},
        'all_values_correct': True,
        'feedback': []
    }
    
    # Check row count
    actual_count = len(restructured_data)
    results['row_count_correct'] = actual_count == EXPECTED_ROW_COUNT
    if actual_count == EXPECTED_ROW_COUNT:
        results['feedback'].append(f"✅ Row count correct: {actual_count} rows")
    else:
        results['feedback'].append(f"❌ Row count incorrect: expected {EXPECTED_ROW_COUNT}, got {actual_count}")
    
    # Track coverage
    category_counts = {cat: 0 for cat in EXPECTED_CATEGORIES}
    quarter_per_category = {cat: set() for cat in EXPECTED_CATEGORIES}
    
    # Verify each row
    incorrect_values = []
    for category, quarter, sales in restructured_data:
        # Find matching category (case-insensitive, fuzzy match)
        matched_category = None
        category_lower = category.lower()
        for expected_cat in EXPECTED_CATEGORIES:
            if expected_cat.lower() in category_lower or category_lower in expected_cat.lower():
                matched_category = expected_cat
                break
        
        if not matched_category:
            logger.warning(f"Unrecognized category: {category}")
            continue
        
        category_counts[matched_category] += 1
        quarter_per_category[matched_category].add(quarter)
        
        # Check value accuracy
        expected_value = SOURCE_DATA[matched_category].get(quarter)
        if expected_value is not None:
            if abs(sales - expected_value) > 0.01:
                incorrect_values.append(f"{matched_category} {quarter}: expected {expected_value}, got {sales}")
                results['all_values_correct'] = False
    
    # Check category coverage (each should appear 4 times)
    all_categories_covered = True
    for cat in EXPECTED_CATEGORIES:
        count = category_counts[cat]
        results['category_coverage'][cat] = count
        if count != 4:
            all_categories_covered = False
            results['feedback'].append(f"❌ Category '{cat}' appears {count} times (expected 4)")
    
    if all_categories_covered:
        results['feedback'].append("✅ All categories appear exactly 4 times")
    
    # Check quarter coverage (each category should have Q1-Q4)
    all_quarters_covered = True
    for cat in EXPECTED_CATEGORIES:
        quarters = quarter_per_category[cat]
        results['quarter_coverage'][cat] = list(quarters)
        if len(quarters) != 4 or quarters != set(QUARTERS):
            all_quarters_covered = False
            missing = set(QUARTERS) - quarters
            if missing:
                results['feedback'].append(f"❌ Category '{cat}' missing quarters: {missing}")
    
    if all_quarters_covered:
        results['feedback'].append("✅ All quarters (Q1-Q4) present for each category")
    
    # Check value accuracy
    if results['all_values_correct']:
        results['feedback'].append("✅ All sales values match source data")
    else:
        results['feedback'].append(f"❌ Value mismatches found: {len(incorrect_values)} errors")
        for error in incorrect_values[:3]:  # Show first 3 errors
            results['feedback'].append(f"   • {error}")
    
    return results


def verify_data_restructuring(traj, env_info, task_info):
    """
    Main verifier function for data restructuring task.
    
    Checks:
    1. Restructured data exists (3-column structure)
    2. Correct row count (20 rows)
    3. Each category appears exactly 4 times
    4. Each quarter appears once per category
    5. All values match source data
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/quarterly_sales.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        # Find restructured data
        header_pos = find_restructured_data(workbook, sheet_name)
        
        if not header_pos:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Could not find restructured data. Expected 3-column structure with headers like 'Category', 'Quarter', 'Sales'."
            }
        
        start_row, start_col = header_pos
        logger.info(f"Extracting data from row {start_row + 1}, column {start_col + 1}")
        
        # Extract restructured data
        restructured_data = extract_restructured_data(workbook, sheet_name, start_row, start_col)
        
        if not restructured_data:
            return {
                "passed": False,
                "score": 10,
                "feedback": "❌ Found header structure but no data rows detected below it."
            }
        
        logger.info(f"Extracted {len(restructured_data)} data rows")
        
        # Verify restructured data
        verification = verify_restructured_data(restructured_data)
        
        # Calculate score based on criteria
        criteria_met = 0
        total_criteria = 6
        
        # Criterion 1: Correct row count
        if verification['row_count_correct']:
            criteria_met += 1
        
        # Criterion 2: Category coverage (all categories present)
        all_categories_present = all(
            count > 0 for count in verification['category_coverage'].values()
        )
        if all_categories_present:
            criteria_met += 1
        
        # Criterion 3: Each category appears 4 times
        all_categories_4x = all(
            count == 4 for count in verification['category_coverage'].values()
        )
        if all_categories_4x:
            criteria_met += 1
        
        # Criterion 4: All quarters present for each category
        all_quarters_complete = all(
            len(quarters) == 4 for quarters in verification['quarter_coverage'].values()
        )
        if all_quarters_complete:
            criteria_met += 1
        
        # Criterion 5: Values match source data
        if verification['all_values_correct']:
            criteria_met += 1
        
        # Criterion 6: Data structure found
        criteria_met += 1  # Already verified by finding header
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        # Build feedback
        feedback_parts = verification['feedback']
        
        if passed:
            if score >= 95:
                feedback_parts.insert(0, "🎉 Perfect data restructuring!")
            else:
                feedback_parts.insert(0, "✅ Data restructuring completed successfully")
        else:
            feedback_parts.insert(0, "❌ Data restructuring incomplete or incorrect")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "structure_found": True,
                "row_count_correct": verification['row_count_correct'],
                "category_coverage_complete": all_categories_present,
                "category_count_correct": all_categories_4x,
                "quarter_coverage_complete": all_quarters_complete,
                "values_accurate": verification['all_values_correct']
            }
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
