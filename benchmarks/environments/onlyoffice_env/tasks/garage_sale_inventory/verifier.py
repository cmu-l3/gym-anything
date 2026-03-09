#!/usr/bin/env python3
"""
Verifier for Garage Sale Inventory task
"""

import sys
import os
import logging
import tempfile
from typing import Tuple, List, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_garage_sale_inventory(traj, env_info, task_info):
    """
    Verify that the garage sale inventory was completed correctly.

    Checks:
    1. All items (rows 2-46) have prices in Column C
    2. All items have categories in Column B
    3. Column D has "Minimum Price" header and formulas calculating 75% of Column C
    4. Summary section exists with 4 metrics (all using formulas)
    5. Data is sorted by category (grouped together)
    6. Headers are formatted as bold
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/garage_sale_items.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_garage_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0.0, "feedback": f"Failed to load spreadsheet: {error}"}

        sheet = wb.active
        score = 0.0
        feedback_parts = []
        max_score = 100.0

        # ===================================================================
        # Check 1: No missing prices (20 points)
        # ===================================================================
        missing_prices = 0
        price_values = []
        
        for row in range(2, 47):  # Rows 2-46 (45 items)
            price = sheet.cell(row, 3).value  # Column C
            if price is None or not isinstance(price, (int, float)) or price <= 0:
                missing_prices += 1
            else:
                price_values.append(price)
        
        if missing_prices == 0:
            score += 20
            feedback_parts.append("✅ All 45 items have valid prices")
        elif missing_prices <= 3:
            score += 15
            feedback_parts.append(f"⚠️ Only {missing_prices} items missing prices (mostly complete)")
        else:
            feedback_parts.append(f"❌ {missing_prices} items still missing prices")

        # ===================================================================
        # Check 2: No missing categories (15 points)
        # ===================================================================
        missing_categories = 0
        categories = []
        
        for row in range(2, 47):
            category = sheet.cell(row, 2).value  # Column B
            if not category or str(category).strip() == "":
                missing_categories += 1
            else:
                categories.append(str(category).strip())
        
        if missing_categories == 0:
            score += 15
            feedback_parts.append("✅ All items have categories")
        elif missing_categories <= 3:
            score += 10
            feedback_parts.append(f"⚠️ Only {missing_categories} items missing categories")
        else:
            feedback_parts.append(f"❌ {missing_categories} items missing categories")

        # ===================================================================
        # Check 3: Minimum price column with formulas (25 points)
        # ===================================================================
        has_min_price_header = False
        col_d_header = sheet.cell(1, 4).value
        
        # Check for variations of "Minimum Price" header
        if col_d_header:
            header_lower = str(col_d_header).lower()
            if "min" in header_lower and ("price" in header_lower or "floor" in header_lower):
                has_min_price_header = True
        
        formula_count = 0
        formula_correct = 0
        
        for row in range(2, 47):
            cell_d = sheet.cell(row, 4)
            cell_c_value = sheet.cell(row, 3).value
            
            # Check if it's a formula (not hardcoded value)
            if cell_d.data_type == 'f':
                formula_count += 1
                
                # Verify the result is approximately 75% of asking price
                result = cell_d.value
                if cell_c_value and isinstance(cell_c_value, (int, float)):
                    expected = cell_c_value * 0.75
                    # Allow small rounding differences (within 2% or 50 cents, whichever is larger)
                    tolerance = max(0.50, expected * 0.02)
                    if result and isinstance(result, (int, float)):
                        if abs(result - expected) <= tolerance:
                            formula_correct += 1
        
        min_price_score = 0
        if has_min_price_header and formula_count >= 40:
            # Full points if header exists and most formulas are present and correct
            if formula_correct >= 40:
                min_price_score = 25
                feedback_parts.append(f"✅ Minimum Price column with formulas ({formula_correct}/45 correct)")
            elif formula_correct >= 35:
                min_price_score = 20
                feedback_parts.append(f"✅ Minimum Price column mostly correct ({formula_correct}/45 formulas)")
            else:
                min_price_score = 15
                feedback_parts.append(f"⚠️ Minimum Price formulas partially correct ({formula_correct}/45)")
        elif has_min_price_header:
            min_price_score = 10
            feedback_parts.append(f"⚠️ Minimum Price header exists but formulas incomplete ({formula_count}/45)")
        else:
            feedback_parts.append(f"❌ Minimum Price column missing or incomplete (header: {has_min_price_header}, formulas: {formula_count}/45)")
        
        score += min_price_score

        # ===================================================================
        # Check 4: Summary section with formulas (20 points)
        # ===================================================================
        summary_metrics_found = {
            'total_revenue': False,
            'min_revenue': False,
            'item_count': False,
            'average': False
        }
        
        # Search for summary section (could be at top, bottom, or side)
        for row in range(1, 55):  # Check first 55 rows to be safe
            for col in range(1, 10):  # Check first 10 columns
                try:
                    cell_val = sheet.cell(row, col).value
                    if not cell_val or not isinstance(cell_val, str):
                        continue
                    
                    cell_lower = cell_val.lower()
                    
                    # Look for adjacent formula cells
                    adjacent_cells = [
                        sheet.cell(row, col+1),
                        sheet.cell(row+1, col),
                        sheet.cell(row, col+2)  # Sometimes there's a gap
                    ]
                    
                    has_formula_adjacent = any(c.data_type == 'f' for c in adjacent_cells)
                    
                    if has_formula_adjacent:
                        # Check for Total Revenue
                        if ("total" in cell_lower or "potential" in cell_lower) and "revenue" in cell_lower:
                            summary_metrics_found['total_revenue'] = True
                        
                        # Check for Minimum Revenue
                        if "minimum" in cell_lower and "revenue" in cell_lower:
                            summary_metrics_found['min_revenue'] = True
                        elif "min" in cell_lower and "revenue" in cell_lower:
                            summary_metrics_found['min_revenue'] = True
                        elif "acceptable" in cell_lower and "revenue" in cell_lower:
                            summary_metrics_found['min_revenue'] = True
                        
                        # Check for Item Count
                        if ("item" in cell_lower or "total" in cell_lower) and "count" in cell_lower:
                            summary_metrics_found['item_count'] = True
                        elif cell_lower.strip() in ["count", "items", "total items"]:
                            summary_metrics_found['item_count'] = True
                        
                        # Check for Average
                        if "average" in cell_lower and "price" in cell_lower:
                            summary_metrics_found['average'] = True
                        elif cell_lower.strip() in ["average", "avg price", "average price"]:
                            summary_metrics_found['average'] = True
                
                except Exception as e:
                    continue
        
        summary_count = sum(summary_metrics_found.values())
        
        if summary_count >= 4:
            score += 20
            feedback_parts.append("✅ Complete summary section with all 4 metrics")
        elif summary_count == 3:
            score += 15
            feedback_parts.append("⚠️ Summary section with 3/4 metrics")
        elif summary_count >= 2:
            score += 10
            feedback_parts.append(f"⚠️ Partial summary section ({summary_count}/4 metrics)")
        else:
            feedback_parts.append(f"❌ Summary section incomplete or missing ({summary_count}/4 metrics)")

        # ===================================================================
        # Check 5: Data sorted by category (10 points)
        # ===================================================================
        # Extract categories to check if they're grouped
        sorted_categories = []
        for row in range(2, 47):
            cat = sheet.cell(row, 2).value
            sorted_categories.append(str(cat).strip().lower() if cat else "")
        
        # Check if categories are grouped (same category appears consecutively)
        is_grouped = True
        seen_categories = set()
        current_category = sorted_categories[0] if sorted_categories else ""
        
        for i, cat in enumerate(sorted_categories):
            if cat != current_category:
                # Category changed
                if cat in seen_categories and cat != "":
                    # This category appeared before - not properly grouped
                    is_grouped = False
                    break
                seen_categories.add(current_category)
                current_category = cat
        
        if is_grouped:
            score += 10
            feedback_parts.append("✅ Data sorted by category (grouped)")
        else:
            feedback_parts.append("❌ Data not properly grouped by category")

        # ===================================================================
        # Check 6: Headers formatted as bold (10 points)
        # ===================================================================
        headers_bold_count = 0
        for col in range(1, 5):  # Check columns A-D
            cell = sheet.cell(1, col)
            if cell.font and cell.font.bold:
                headers_bold_count += 1
        
        if headers_bold_count >= 3:
            score += 10
            feedback_parts.append(f"✅ Headers formatted (bold)")
        elif headers_bold_count >= 2:
            score += 5
            feedback_parts.append(f"⚠️ Some headers formatted ({headers_bold_count}/4)")
        else:
            feedback_parts.append(f"❌ Headers not formatted")

        # ===================================================================
        # Final scoring
        # ===================================================================
        passed = score >= 75  # Need 75/100 to pass
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete. Score: {score}/100, Passed: {passed}")

        return {
            "passed": passed,
            "score": score / 100.0,  # Normalize to 0-1
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0.0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
