#!/usr/bin/env python3
"""
Verifier for Estate Sale Organizer task
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Any, Set

# Add utils to path - use relative path for host machine execution
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_sheet_names,
    get_cell_value,
    get_cell_formula
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_price_text(price_str: str) -> Tuple[float, float]:
    """
    Parse messy price text into (low, high) numeric tuple.
    
    Examples:
        "$50-75" → (50.0, 75.0)
        "around 100" → (90.0, 110.0)
        "200" → (200.0, 200.0)
        "150 to 200" → (150.0, 200.0)
    """
    if not price_str or price_str.strip() == "":
        return (None, None)
    
    # Remove currency symbols and clean
    clean = re.sub(r'[$,]', '', str(price_str).strip())
    
    # Check for range patterns: "50-75" or "50 to 75"
    range_match = re.search(r'(\d+(?:\.\d+)?)\s*(?:-|to)\s*(\d+(?:\.\d+)?)', clean, re.IGNORECASE)
    if range_match:
        return (float(range_match.group(1)), float(range_match.group(2)))
    
    # Check for "around X" pattern
    around_match = re.search(r'around\s+(\d+(?:\.\d+)?)', clean, re.IGNORECASE)
    if around_match:
        base = float(around_match.group(1))
        return (base * 0.9, base * 1.1)  # ±10%
    
    # Single number
    number_match = re.search(r'(\d+(?:\.\d+)?)', clean)
    if number_match:
        val = float(number_match.group(1))
        return (val, val)
    
    return (None, None)


def normalize_item_name(name: str) -> str:
    """Normalize item names for comparison (lowercase, strip whitespace)"""
    if not name:
        return ""
    return str(name).strip().lower()


def get_sheet_items(sheet_data: List[List[Dict]], item_col: int = 0, skip_header: bool = True) -> Set[str]:
    """Extract set of normalized item names from a sheet"""
    items = set()
    start_row = 1 if skip_header else 0
    
    for row_idx in range(start_row, len(sheet_data)):
        if row_idx < len(sheet_data) and item_col < len(sheet_data[row_idx]):
            cell = sheet_data[row_idx][item_col]
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value:
                items.add(normalize_item_name(value))
    
    return items


def count_item_occurrences(sheet_data: List[List[Dict]], item_col: int = 0, skip_header: bool = True) -> Dict[str, int]:
    """Count how many times each item appears in a sheet"""
    counts = {}
    start_row = 1 if skip_header else 0
    
    for row_idx in range(start_row, len(sheet_data)):
        if row_idx < len(sheet_data) and item_col < len(sheet_data[row_idx]):
            cell = sheet_data[row_idx][item_col]
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value:
                normalized = normalize_item_name(value)
                counts[normalized] = counts.get(normalized, 0) + 1
    
    return counts


def verify_estate_sale_organizer(traj, env_info, task_info):
    """
    Verify estate sale organizer task completion.
    
    Checks:
    1. All items from Main_Inventory consolidated
    2. Conflicts detected (items in Family_Promises multiple times)
    3. For_Sale sheet excludes sentimental items and conflicts
    4. Prices standardized to numeric ranges
    5. Total sale value calculated
    6. Urgent_Conflicts sheet created
    7. No sentimental items in For_Sale
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Setup verification
    container_path = "/home/ga/Documents/estate_inventory.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods']
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        workbook = file_info['sheet_data']
        sheet_names = get_sheet_names(workbook)
        
        logger.info(f"Found sheets: {sheet_names}")
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}

        # Get source sheets
        main_inventory = workbook['sheets'].get('Main_Inventory', [])
        family_promises = workbook['sheets'].get('Family_Promises', [])
        sentimental_keep = workbook['sheets'].get('Sentimental_Keep', [])

        # Expected conflicts in source data
        expected_conflicts = {
            'antique oak dresser',  # John + Sarah
            'quilt collection',      # Mary + Elizabeth
            'piano',                 # Sarah + Michael
            'telescope'              # David + Robert
        }

        # Items that should NOT be for sale (in Sentimental_Keep)
        sentimental_items = {
            'wedding album', 'military medals', 'photo albums',
            "grandmother's china set", 'grandfather clock',
            'piano', 'quilt collection', 'jewelry box'
        }

        # Criterion 1: All items consolidated
        main_items = get_sheet_items(main_inventory, item_col=0)
        logger.info(f"Main_Inventory has {len(main_items)} items")
        
        consolidated_exists = 'Consolidated' in sheet_names
        if consolidated_exists:
            consolidated = workbook['sheets']['Consolidated']
            consolidated_items = get_sheet_items(consolidated, item_col=0)
            
            # Check if all main items are in consolidated
            missing_items = main_items - consolidated_items
            if len(missing_items) <= 2:  # Allow small margin
                criteria_passed += 1
                feedback_parts.append(f"✅ All items consolidated ({len(consolidated_items)} items)")
                subscores['consolidation'] = True
            else:
                feedback_parts.append(f"❌ Consolidation incomplete (missing {len(missing_items)} items)")
                subscores['consolidation'] = False
        else:
            feedback_parts.append("❌ Consolidated sheet not found")
            subscores['consolidation'] = False

        # Criterion 2: Conflicts detected
        conflict_items_found = set()
        if consolidated_exists:
            # Look for conflict flags in Consolidated sheet
            for row_idx in range(1, len(consolidated)):
                if row_idx >= len(consolidated):
                    break
                row = consolidated[row_idx]
                
                # Check last few columns for conflict flag
                for col_idx in range(min(len(row), 10)):
                    cell = row[col_idx]
                    value = str(cell.get('value', '') if isinstance(cell, dict) else cell).upper()
                    if 'URGENT' in value or 'MULTIPLE' in value or 'CONFLICT' in value:
                        # Get item name from first column
                        if len(row) > 0:
                            item_cell = row[0]
                            item_name = item_cell.get('value') if isinstance(item_cell, dict) else item_cell
                            if item_name:
                                conflict_items_found.add(normalize_item_name(item_name))
                        break
            
            # Check how many expected conflicts were found
            conflicts_detected = len(expected_conflicts & conflict_items_found)
            if conflicts_detected >= 2:  # At least half of conflicts found
                criteria_passed += 1
                feedback_parts.append(f"✅ Conflicts detected ({conflicts_detected} flagged)")
                subscores['conflict_detection'] = True
            else:
                feedback_parts.append(f"❌ Conflicts not properly detected ({conflicts_detected}/4 expected)")
                subscores['conflict_detection'] = False
        else:
            feedback_parts.append("❌ Cannot check conflicts (no Consolidated sheet)")
            subscores['conflict_detection'] = False

        # Criterion 3: For_Sale sheet exists and filters correctly
        for_sale_exists = 'For_Sale' in sheet_names or 'For Sale' in sheet_names or 'ForSale' in sheet_names
        for_sale_sheet_name = None
        for name in sheet_names:
            if 'sale' in name.lower() and 'for' in name.lower():
                for_sale_sheet_name = name
                for_sale_exists = True
                break
        
        if for_sale_exists and for_sale_sheet_name:
            for_sale = workbook['sheets'][for_sale_sheet_name]
            for_sale_items = get_sheet_items(for_sale, item_col=0)
            
            # Check that sentimental items are NOT in for_sale
            sentimental_in_sale = sentimental_items & for_sale_items
            
            # Check that conflict items are NOT in for_sale
            conflicts_in_sale = expected_conflicts & for_sale_items
            
            if len(sentimental_in_sale) == 0 and len(conflicts_in_sale) <= 1:
                criteria_passed += 1
                feedback_parts.append(f"✅ For_Sale sheet filters correctly ({len(for_sale_items)} sellable items)")
                subscores['sale_filter'] = True
            else:
                issues = []
                if sentimental_in_sale:
                    issues.append(f"{len(sentimental_in_sale)} sentimental items")
                if conflicts_in_sale:
                    issues.append(f"{len(conflicts_in_sale)} conflict items")
                feedback_parts.append(f"❌ For_Sale contains items that shouldn't be sold ({', '.join(issues)})")
                subscores['sale_filter'] = False
        else:
            feedback_parts.append("❌ For_Sale sheet not found")
            subscores['sale_filter'] = False

        # Criterion 4: Prices standardized
        price_standardized = False
        if consolidated_exists:
            # Check if there are numeric Low/High columns
            header_row = consolidated[0] if len(consolidated) > 0 else []
            has_low_col = any('low' in str(cell.get('value', '') if isinstance(cell, dict) else cell).lower() 
                            for cell in header_row)
            has_high_col = any('high' in str(cell.get('value', '') if isinstance(cell, dict) else cell).lower() 
                             for cell in header_row)
            
            if has_low_col and has_high_col:
                # Sample check: look for numeric values in price columns
                numeric_count = 0
                for row_idx in range(1, min(10, len(consolidated))):
                    if row_idx >= len(consolidated):
                        break
                    row = consolidated[row_idx]
                    for cell in row:
                        value = cell.get('value') if isinstance(cell, dict) else cell
                        if isinstance(value, (int, float)) and value > 0:
                            numeric_count += 1
                
                if numeric_count >= 5:
                    criteria_passed += 1
                    feedback_parts.append("✅ Prices standardized to numeric ranges")
                    subscores['price_standardization'] = True
                    price_standardized = True
        
        if not price_standardized:
            feedback_parts.append("❌ Prices not properly standardized")
            subscores['price_standardization'] = False

        # Criterion 5: Total sale value calculated
        total_calculated = False
        if for_sale_exists and for_sale_sheet_name:
            for_sale = workbook['sheets'][for_sale_sheet_name]
            # Look for "total" in any cell
            for row in for_sale:
                for cell in row:
                    value = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
                    if 'total' in value:
                        # Check if there are SUM formulas nearby or large numbers
                        for check_cell in row:
                            cell_value = check_cell.get('value') if isinstance(check_cell, dict) else check_cell
                            formula = check_cell.get('formula') if isinstance(check_cell, dict) else None
                            
                            if formula and 'SUM' in str(formula).upper():
                                total_calculated = True
                                break
                            elif isinstance(cell_value, (int, float)) and cell_value > 1000:
                                total_calculated = True
                                break
                if total_calculated:
                    break
        
        if total_calculated:
            criteria_passed += 1
            feedback_parts.append("✅ Total sale value calculated")
            subscores['total_calculated'] = True
        else:
            feedback_parts.append("❌ Total sale value not calculated")
            subscores['total_calculated'] = False

        # Criterion 6: Urgent_Conflicts sheet exists
        urgent_exists = False
        for name in sheet_names:
            if ('urgent' in name.lower() or 'conflict' in name.lower()) and name not in ['Main_Inventory', 'Family_Promises']:
                urgent_exists = True
                urgent_sheet = workbook['sheets'][name]
                # Check if it has any data
                if len(urgent_sheet) > 1:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Urgent_Conflicts sheet created ('{name}')")
                    subscores['urgent_sheet'] = True
                    break
        
        if not urgent_exists:
            feedback_parts.append("❌ Urgent_Conflicts sheet not found")
            subscores['urgent_sheet'] = False

        # Criterion 7: No sentimental items in For_Sale (redundant with criterion 3 but weighted separately)
        if for_sale_exists and for_sale_sheet_name:
            for_sale_items = get_sheet_items(workbook['sheets'][for_sale_sheet_name], item_col=0)
            sentimental_in_sale = sentimental_items & for_sale_items
            
            if len(sentimental_in_sale) == 0:
                criteria_passed += 1
                feedback_parts.append("✅ No sentimental items in For_Sale (verified)")
                subscores['sentimental_protection'] = True
            else:
                feedback_parts.append(f"❌ {len(sentimental_in_sale)} sentimental items found in For_Sale")
                subscores['sentimental_protection'] = False
        else:
            subscores['sentimental_protection'] = False

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: {criteria_passed}/{total_criteria} criteria passed")
        
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
        cleanup_verification_temp(file_info.get('temp_dir'))
