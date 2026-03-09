#!/usr/bin/env python3
"""
Verifier for basement_flood_claim@1

This verifier checks that the user created a professional insurance claim inventory
spreadsheet with proper structure, required items, formulas, and formatting.

Verification strategy:
- Flexible about exact cell positions (real users organize differently)
- Search entire sheet for required content
- Verify formulas exist (not just typed numbers)
- Check for required items with approximate values
- Ensure professional organization with categories
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_numbers_from_text(text):
    """Extract all numbers from text string"""
    if text is None:
        return []
    text_str = str(text)
    # Find all numbers including decimals and currency
    numbers = re.findall(r'[\d,]+\.?\d*', text_str.replace('$', '').replace(',', ''))
    return [float(n) for n in numbers if n]


def search_sheet_for_text(data, search_terms, case_sensitive=False):
    """
    Search entire sheet for text, return True if found
    search_terms can be a string or list of strings (any match)
    """
    if isinstance(search_terms, str):
        search_terms = [search_terms]
    
    for row in data:
        for cell in row:
            if cell is None:
                continue
            cell_str = str(cell)
            if not case_sensitive:
                cell_str = cell_str.lower()
                search_terms = [s.lower() for s in search_terms]
            
            for term in search_terms:
                if term in cell_str:
                    return True
    return False


def find_value_near_text(data, search_text, target_value, tolerance=50):
    """
    Find if a specific value appears near (same row or adjacent) a text
    Useful for finding "Sofa $1200" type entries
    """
    search_text = search_text.lower()
    
    for row_idx, row in enumerate(data):
        for col_idx, cell in enumerate(row):
            if cell is None:
                continue
            
            cell_str = str(cell).lower()
            
            # Check if search text is in this cell
            if search_text in cell_str:
                # Check this cell and neighboring cells for the value
                for check_row in range(max(0, row_idx-1), min(len(data), row_idx+2)):
                    for check_col in range(max(0, col_idx-1), min(len(row), col_idx+3)):
                        check_cell = data[check_row][check_col]
                        if check_cell is None:
                            continue
                        
                        # Extract numbers from cell
                        numbers = extract_numbers_from_text(check_cell)
                        for num in numbers:
                            if abs(num - target_value) <= tolerance:
                                return True
    return False


def count_formula_cells(wb, sheet_name, max_rows=100):
    """
    Count cells containing formulas in the sheet
    """
    try:
        ws = wb[sheet_name]
        formula_count = 0
        
        for row in ws.iter_rows(max_row=max_rows):
            for cell in row:
                # Check if cell contains a formula
                if cell.data_type == 'f':  # Formula type
                    formula_count += 1
                elif hasattr(cell, 'value') and isinstance(cell.value, str):
                    if cell.value.startswith('='):
                        formula_count += 1
        
        return formula_count
    except Exception as e:
        logger.warning(f"Error counting formulas: {e}")
        return 0


def verify_task(traj, env_info, task_info):
    """
    Main verification function for basement flood claim task
    
    Checks (100 points total):
    1. Header information (15 points) - title, name, date, claim number
    2. Column structure (10 points) - proper columns for inventory
    3. Required specific items (30 points) - 8 mandatory items
    4. Item count (10 points) - at least 12 items total
    5. Formulas present (25 points) - subtotals and grand total use formulas
    6. Categories (10 points) - organized by category
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available in environment"
        }

    container_path = "/home/ga/Documents/Spreadsheets/basement_flood_claim.xlsx"
    temp_dir = None

    try:
        # Copy and parse the spreadsheet
        logger.info(f"Attempting to parse spreadsheet: {container_path}")
        
        # Create temp file for copying
        temp_dir = tempfile.mkdtemp(prefix='verify_flood_claim_')
        temp_file = os.path.join(temp_dir, 'basement_flood_claim.xlsx')
        
        # Copy file from container
        try:
            copy_from_env(container_path, temp_file)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not copy file from container: {str(e)}"
            }
        
        # Verify file exists and has content
        if not os.path.exists(temp_file) or os.path.getsize(temp_file) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ File not found or empty: {container_path}"
            }
        
        # Parse the workbook
        wb = parse_xlsx_file(temp_file)
        if wb is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Could not parse basement_flood_claim.xlsx. File may be corrupted or not saved properly."
            }
        
        # Get active sheet
        ws = wb.active
        sheet_name = ws.title
        
        # Get all data (first 100 rows, 20 columns should be sufficient)
        data = get_sheet_data(wb, sheet_name, max_rows=100, max_cols=20)
        
        if not data or len(data) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Spreadsheet is empty. No data found."
            }
        
        # Initialize scoring
        score = 0
        max_score = 100
        feedback_parts = []
        
        # Flatten data to text for searching
        all_text = "\n".join([" ".join([str(cell) if cell else "" for cell in row]) for row in data])
        all_text_lower = all_text.lower()
        
        logger.info(f"Sheet has {len(data)} rows of data")
        logger.info(f"First few rows: {data[:5]}")
        
        # ===================================================================
        # CHECK 1: Header Information (15 points)
        # ===================================================================
        header_score = 0
        header_max = 15
        
        # Check for document title
        if search_sheet_for_text(data, ["basement flood", "damage inventory"]):
            header_score += 4
            feedback_parts.append("✅ Document title present")
        else:
            feedback_parts.append("❌ Missing title 'Basement Flood Damage Inventory'")
        
        # Check for claimant name: Alex Rivera
        if search_sheet_for_text(data, ["alex rivera", "alex", "rivera"]):
            header_score += 4
            feedback_parts.append("✅ Claimant name 'Alex Rivera' found")
        else:
            feedback_parts.append("⚠️ Claimant name 'Alex Rivera' not found")
        
        # Check for date
        if search_sheet_for_text(data, ["january 15", "jan 15", "1/15", "01/15", "2025-01-15"]):
            header_score += 3
            feedback_parts.append("✅ Incident date included")
        else:
            feedback_parts.append("⚠️ Date of incident not clearly visible")
        
        # Check for claim number
        if search_sheet_for_text(data, ["clm-2025-8847", "clm20258847", "8847"]):
            header_score += 4
            feedback_parts.append("✅ Claim number included")
        else:
            feedback_parts.append("⚠️ Claim number CLM-2025-8847 not found")
        
        score += header_score
        
        # ===================================================================
        # CHECK 2: Column Structure (10 points)
        # ===================================================================
        required_columns = ['category', 'description', 'item', 'quantity', 'qty', 'value', 'price', 'subtotal', 'total']
        columns_found = 0
        
        # Check if column headers exist
        if search_sheet_for_text(data, 'category'):
            columns_found += 1
        if search_sheet_for_text(data, ['description', 'item']):
            columns_found += 1
        if search_sheet_for_text(data, ['quantity', 'qty']):
            columns_found += 1
        if search_sheet_for_text(data, ['value', 'price', 'cost']):
            columns_found += 1
        if search_sheet_for_text(data, ['subtotal', 'total']):
            columns_found += 1
        
        column_score = min(10, int((columns_found / 5) * 10))
        score += column_score
        
        if columns_found >= 4:
            feedback_parts.append(f"✅ Column structure present ({columns_found}/5 key columns)")
        else:
            feedback_parts.append(f"❌ Insufficient column structure ({columns_found}/5)")
        
        # ===================================================================
        # CHECK 3: Required Specific Items (30 points)
        # ===================================================================
        required_items = {
            'sectional sofa': 1200,
            'sofa': 1200,
            'mini refrigerator': 180,
            'mini fridge': 180,
            'refrigerator': 180,
            'smart tv': 450,
            'television': 450,
            'tv': 450,
            'playstation': 500,
            'ps5': 500,
            'christmas tree': 250,
            'tree': 250,
            'ornament': 30,  # 4 boxes at $30 each
            'drill': 120,
            'shelving': 85,  # 2 units at $85 each
            'shelf': 85
        }
        
        # Group items for checking
        item_checks = [
            (['sectional sofa', 'sofa'], 1200, 'Sectional sofa'),
            (['mini refrigerator', 'mini fridge', 'fridge'], 180, 'Mini refrigerator'),
            (['smart tv', 'television', '55', 'tv'], 450, '55" Smart TV'),
            (['playstation', 'ps5', 'ps 5'], 500, 'PlayStation 5'),
            (['christmas tree', 'xmas tree', 'tree'], 250, 'Christmas tree'),
            (['ornament', 'decoration box'], 30, 'Ornament boxes'),
            (['drill', 'cordless drill'], 120, 'Drill set'),
            (['shelving', 'shelf', 'shelves', 'metal shelf'], 85, 'Metal shelving')
        ]
        
        items_found = 0
        item_details = []
        
        for search_terms, target_value, display_name in item_checks:
            # Check if item text appears
            text_found = search_sheet_for_text(data, search_terms)
            # Check if value appears near the text
            value_found = find_value_near_text(data, search_terms[0], target_value, tolerance=100)
            
            if text_found:
                items_found += 1
                if value_found:
                    item_details.append(f"✓ {display_name}")
                else:
                    item_details.append(f"~ {display_name} (value check uncertain)")
            else:
                item_details.append(f"✗ {display_name}")
        
        item_score = int((items_found / len(item_checks)) * 30)
        score += item_score
        
        if items_found >= 6:
            feedback_parts.append(f"✅ Required items present ({items_found}/{len(item_checks)})")
        elif items_found >= 4:
            feedback_parts.append(f"⚠️ Some required items missing ({items_found}/{len(item_checks)})")
        else:
            feedback_parts.append(f"❌ Many required items missing ({items_found}/{len(item_checks)})")
        
        # ===================================================================
        # CHECK 4: Item Count (10 points)
        # ===================================================================
        # Count rows that look like item entries (have text and numbers)
        item_rows = 0
        for row in data:
            row_text = " ".join([str(cell) if cell else "" for cell in row]).strip()
            # Skip header-like rows or instruction rows
            if len(row_text) < 5:
                continue
            if any(skip in row_text.lower() for skip in ['create your', 'required items', 'formula', 'column']):
                continue
            
            # If row has text and numbers, likely an item
            has_text = any(cell and isinstance(cell, str) and len(str(cell).strip()) > 2 for cell in row)
            has_number = any(cell and isinstance(cell, (int, float)) for cell in row)
            
            if has_text and has_number:
                item_rows += 1
        
        # Adjust count (may include some header rows, be lenient)
        item_rows = max(0, item_rows - 3)  # Subtract likely header/label rows
        
        if item_rows >= 12:
            score += 10
            feedback_parts.append(f"✅ Sufficient items documented ({item_rows}+ items)")
        elif item_rows >= 8:
            partial = int((item_rows / 12) * 10)
            score += partial
            feedback_parts.append(f"⚠️ Could use more items ({item_rows}/12 minimum)")
        else:
            feedback_parts.append(f"❌ Too few items ({item_rows}/12 minimum)")
        
        # ===================================================================
        # CHECK 5: Formulas Present (25 points)
        # ===================================================================
        formula_count = count_formula_cells(wb, sheet_name, max_rows=100)
        
        # Also check for SUM/AVERAGE/etc in text (case insensitive)
        has_sum = 'sum' in all_text_lower
        has_formula_syntax = '=' in all_text and ('sum' in all_text_lower or 'average' in all_text_lower or '*' in all_text)
        
        logger.info(f"Formula count: {formula_count}, has SUM: {has_sum}")
        
        formula_score = 0
        if formula_count >= 8:
            formula_score = 25
            feedback_parts.append(f"✅ Formulas used extensively ({formula_count} formula cells)")
        elif formula_count >= 5:
            formula_score = 20
            feedback_parts.append(f"✅ Good use of formulas ({formula_count} formula cells)")
        elif formula_count >= 3:
            formula_score = 12
            feedback_parts.append(f"⚠️ Some formulas present ({formula_count} formula cells)")
        elif formula_count >= 1 or has_sum:
            formula_score = 6
            feedback_parts.append(f"⚠️ Very few formulas detected ({formula_count} formula cells)")
        else:
            feedback_parts.append("❌ No formulas detected - must use SUM formulas for totals")
        
        score += formula_score
        
        # ===================================================================
        # CHECK 6: Categories Present (10 points)
        # ===================================================================
        categories = [
            'furniture', 'electronic', 'decoration', 'tool', 
            'holiday', 'appliance', 'media', 'equipment'
        ]
        categories_found = sum(1 for cat in categories if cat in all_text_lower)
        
        category_score = 0
        if categories_found >= 4:
            category_score = 10
            feedback_parts.append(f"✅ Multiple categories used ({categories_found} categories)")
        elif categories_found >= 3:
            category_score = 7
            feedback_parts.append(f"✅ Categories present ({categories_found}/4+)")
        elif categories_found >= 2:
            category_score = 4
            feedback_parts.append(f"⚠️ Minimal categories ({categories_found}/4)")
        else:
            feedback_parts.append("❌ Categories not clearly defined")
        
        score += category_score
        
        # ===================================================================
        # FINAL SCORING
        # ===================================================================
        score = round(min(score, max_score), 1)
        passed = score >= 70
        
        # Compile final feedback
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final score: {score}/{max_score}, Passed: {passed}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temp directory
        if temp_dir:
            cleanup_temp_dir(temp_dir)