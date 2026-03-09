#!/usr/bin/env python3
"""
Verifier for Theater Prop Tracker task
Verifies transformation of messy props spreadsheet into organized tracking system
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_theater_prop_tracker(traj, env_info, task_info):
    """
    Verify the theater prop tracking spreadsheet organization task.
    
    Checks:
    1. File exists and is valid (10 points)
    2. Title row and summary section structure (15 points)
    3. Column headers present (10 points)
    4. Formulas present in summary (25 points)
    5. Data cleaning quality (30 points)
    6. Categorization quality (10 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    temp_dir = None

    try:
        # Check if organized file exists
        output_path = "/home/ga/Documents/Spreadsheets/props_organized.xlsx"
        success, wb, error = copy_and_parse_document(
            output_path, 
            copy_from_env, 
            'xlsx'
        )
        
        if not success:
            # Try the original file as fallback
            output_path = "/home/ga/Documents/Spreadsheets/props_messy.xlsx"
            success, wb, error = copy_and_parse_document(
                output_path,
                copy_from_env,
                'xlsx'
            )
            if not success:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"Output file not found or couldn't be parsed: {error}"
                }
            else:
                feedback_parts.append("⚠️ File not saved as props_organized.xlsx (using props_messy.xlsx)")
                score += 5
        else:
            feedback_parts.append("✅ Output file exists with correct name")
            score += 10
        
        # Get the active sheet
        sheet = wb.active
        
        # Get all data (increased range to handle larger sheets)
        data = get_sheet_data(wb, sheet.title, max_rows=150, max_cols=20)
        
        if not data or len(data) == 0:
            return {
                "passed": False,
                "score": score,
                "feedback": "Spreadsheet is empty"
            }
        
        # Helper function to check if a cell contains formula
        def has_formula(row_idx, col_idx):
            """Check if cell contains a formula"""
            try:
                cell = sheet.cell(row=row_idx+1, column=col_idx+1)
                # Check if it's a formula (data_only=True shows result, so check for numeric result in summary area)
                # For openpyxl with data_only=False, formulas start with '='
                if hasattr(cell, 'value') and cell.value:
                    if isinstance(cell.value, str) and cell.value.startswith('='):
                        return True
                    # If data_only=True, we won't see formulas, but we can check for numeric values in expected locations
                    if isinstance(cell.value, (int, float)) and cell.value != 0:
                        return True
            except:
                pass
            return False
        
        # 1. Check for title row (should contain "prop" or "tracking" or "streetcar")
        title_found = False
        title_row_idx = -1
        for row_idx in range(min(5, len(data))):
            row_text = " ".join([str(cell).lower() if cell else "" for cell in data[row_idx]])
            if any(keyword in row_text for keyword in ["prop", "tracking", "streetcar", "overview"]):
                title_found = True
                title_row_idx = row_idx
                feedback_parts.append(f"✅ Title row found at row {row_idx + 1}")
                score += 5
                break
        
        if not title_found:
            feedback_parts.append("❌ Missing title row")
        
        # 2. Check for summary section keywords
        summary_keywords = {
            "total": False,
            "acquired": False,
            "needed": False,
            "budget": False,
            "spent": False
        }
        
        summary_rows = []
        for row_idx in range(min(12, len(data))):
            row_text = " ".join([str(cell).lower() if cell else "" for cell in data[row_idx]])
            for keyword in summary_keywords.keys():
                if keyword in row_text and not summary_keywords[keyword]:
                    summary_keywords[keyword] = True
                    summary_rows.append(row_idx)
                    break
        
        summary_count = sum(summary_keywords.values())
        if summary_count >= 4:
            feedback_parts.append(f"✅ Summary section present ({summary_count}/5 metrics)")
            score += 10
        elif summary_count >= 2:
            feedback_parts.append(f"⚠️ Partial summary section ({summary_count}/5 metrics)")
            score += 5
        else:
            feedback_parts.append(f"❌ Summary section incomplete ({summary_count}/5 metrics)")
        
        # 3. Check for formulas in summary area
        formulas_found = 0
        formula_locations = []
        
        # Check first 12 rows for formulas
        for row_idx in range(min(12, len(data))):
            for col_idx in range(min(8, len(data[row_idx]))):
                cell_value = data[row_idx][col_idx]
                # Check if it's a number (likely formula result) in summary area
                if isinstance(cell_value, (int, float)) and cell_value > 0:
                    # Further verify it's in a summary row
                    row_text = " ".join([str(cell).lower() if cell else "" for cell in data[row_idx]])
                    if any(kw in row_text for kw in ["total", "acquired", "needed", "budget", "spent"]):
                        formulas_found += 1
                        formula_locations.append(f"R{row_idx+1}C{col_idx+1}")
                        break
        
        if formulas_found >= 4:
            feedback_parts.append(f"✅ Formulas present in summary ({formulas_found} found)")
            score += 25
        elif formulas_found >= 2:
            feedback_parts.append(f"⚠️ Some formulas present ({formulas_found} found)")
            score += 15
        else:
            feedback_parts.append(f"❌ Missing formulas in summary ({formulas_found} found)")
            score += 5
        
        # 4. Find header row (should contain multiple required headers)
        header_row_idx = None
        required_headers = ["prop", "category", "status", "priority", "cost"]
        
        for row_idx in range(min(20, len(data))):
            row_text = [str(cell).lower() if cell else "" for cell in data[row_idx]]
            matches = sum(1 for header in required_headers if any(header in cell for cell in row_text))
            if matches >= 4:
                header_row_idx = row_idx
                feedback_parts.append(f"✅ Column headers found at row {row_idx + 1} ({matches}/5 required headers)")
                score += 10
                break
        
        if header_row_idx is None:
            feedback_parts.append("❌ Could not locate proper column headers")
            # Can't verify data quality without headers
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # 5. Map column indices
        header_row = [str(cell).lower() if cell else "" for cell in data[header_row_idx]]
        col_map = {}
        
        for idx, cell in enumerate(header_row):
            if "prop" in cell or "item" in cell or "name" in cell:
                col_map['prop'] = idx
            if "category" in cell or "type" in cell:
                col_map['category'] = idx
            if "status" in cell:
                col_map['status'] = idx
            if "priority" in cell:
                col_map['priority'] = idx
            if "cost" in cell or "price" in cell:
                col_map['cost'] = idx
            if "method" in cell or "acquisition" in cell:
                col_map['method'] = idx
            if "responsible" in cell or "person" in cell or "who" in cell:
                col_map['person'] = idx
            if "note" in cell:
                col_map['notes'] = idx
        
        # 6. Analyze data rows
        data_rows = data[header_row_idx + 1:]
        non_empty_rows = [row for row in data_rows if any(cell for cell in row)]
        
        # Count valid data rows (rows with prop names)
        valid_rows = []
        if 'prop' in col_map:
            for row in non_empty_rows:
                if len(row) > col_map['prop'] and row[col_map['prop']]:
                    prop_name = str(row[col_map['prop']]).strip()
                    if prop_name and len(prop_name) > 2:  # Valid prop name
                        valid_rows.append(row)
        
        if len(valid_rows) >= 20:
            feedback_parts.append(f"✅ Data preserved ({len(valid_rows)} props)")
            score += 5
        elif len(valid_rows) >= 15:
            feedback_parts.append(f"⚠️ Most data preserved ({len(valid_rows)} props)")
            score += 3
        else:
            feedback_parts.append(f"⚠️ Some data may be missing ({len(valid_rows)} props)")
            score += 1
        
        # 7. Check for data cleaning - status standardization
        bad_status_values = ["got it", "done", "have"]
        bad_values_found = 0
        standardized_count = 0
        
        if 'status' in col_map:
            for row in valid_rows[:25]:  # Check first 25 rows
                if len(row) > col_map['status'] and row[col_map['status']]:
                    status_val = str(row[col_map['status']]).lower().strip()
                    if any(bad in status_val for bad in bad_status_values):
                        bad_values_found += 1
                    elif status_val in ["acquired", "not started", "in progress", "actor provides", "n/a"]:
                        standardized_count += 1
        
        if bad_values_found == 0 and standardized_count >= 10:
            feedback_parts.append(f"✅ Status values standardized ({standardized_count} proper values)")
            score += 10
        elif bad_values_found <= 2:
            feedback_parts.append(f"⚠️ Mostly standardized ({bad_values_found} old values remain)")
            score += 6
        else:
            feedback_parts.append(f"❌ Status values not standardized ({bad_values_found} old values found)")
            score += 2
        
        # 8. Check for cost formatting (should be numeric, no $ symbols in data)
        costs_numeric = 0
        costs_with_symbols = 0
        
        if 'cost' in col_map:
            for row in valid_rows[:25]:
                if len(row) > col_map['cost'] and row[col_map['cost']]:
                    cost_val = row[col_map['cost']]
                    if isinstance(cost_val, (int, float)):
                        costs_numeric += 1
                    elif isinstance(cost_val, str) and '$' in str(cost_val):
                        costs_with_symbols += 1
        
        if costs_numeric >= 15 and costs_with_symbols == 0:
            feedback_parts.append(f"✅ Costs formatted as numbers ({costs_numeric} numeric)")
            score += 5
        elif costs_numeric >= 10:
            feedback_parts.append(f"⚠️ Most costs numeric ({costs_numeric} formatted)")
            score += 3
        else:
            feedback_parts.append(f"❌ Costs not properly formatted ({costs_numeric} numeric)")
            score += 1
        
        # 9. Check for categories assigned
        categories_assigned = 0
        unique_categories = set()
        
        if 'category' in col_map:
            for row in valid_rows[:25]:
                if len(row) > col_map['category'] and row[col_map['category']]:
                    cat = str(row[col_map['category']]).strip()
                    if cat and len(cat) > 2:
                        categories_assigned += 1
                        unique_categories.add(cat.lower())
        
        if categories_assigned >= 20 and len(unique_categories) >= 3:
            feedback_parts.append(f"✅ Categories assigned ({categories_assigned} items, {len(unique_categories)} types)")
            score += 5
        elif categories_assigned >= 15:
            feedback_parts.append(f"⚠️ Most categories assigned ({categories_assigned} items)")
            score += 3
        else:
            feedback_parts.append(f"❌ Categories incomplete ({categories_assigned} items)")
            score += 1
        
        # 10. Check for priorities assigned
        priorities_assigned = 0
        unique_priorities = set()
        
        if 'priority' in col_map:
            for row in valid_rows[:25]:
                if len(row) > col_map['priority'] and row[col_map['priority']]:
                    pri = str(row[col_map['priority']]).strip()
                    if pri and len(pri) > 2:
                        priorities_assigned += 1
                        unique_priorities.add(pri.lower())
        
        if priorities_assigned >= 20 and len(unique_priorities) >= 2:
            feedback_parts.append(f"✅ Priorities assigned ({priorities_assigned} items, {len(unique_priorities)} levels)")
            score += 5
        elif priorities_assigned >= 15:
            feedback_parts.append(f"⚠️ Most priorities assigned ({priorities_assigned} items)")
            score += 3
        else:
            feedback_parts.append(f"❌ Priorities incomplete ({priorities_assigned} items)")
            score += 1
        
        # 11. Check for duplicate consolidation (look for multiple whiskey/bourbon bottles or kitchen chairs)
        duplicate_check = True
        if 'prop' in col_map:
            prop_names_lower = [str(row[col_map['prop']]).lower().strip() 
                               for row in valid_rows if len(row) > col_map['prop'] and row[col_map['prop']]]
            
            # Check for whiskey/bourbon duplicates
            whiskey_count = sum(1 for name in prop_names_lower if 'whiskey' in name or 'bourbon' in name)
            brandy_count = sum(1 for name in prop_names_lower if 'brandy' in name)
            chair_count = sum(1 for name in prop_names_lower if 'kitchen chair' in name)
            
            duplicates_remaining = 0
            if whiskey_count > 1:
                duplicates_remaining += 1
            if brandy_count > 1:
                duplicates_remaining += 1
            if chair_count > 1:
                duplicates_remaining += 1
            
            if duplicates_remaining == 0:
                feedback_parts.append("✅ Duplicates consolidated")
                score += 5
            else:
                feedback_parts.append(f"⚠️ Some duplicates remain ({duplicates_remaining} sets)")
                score += 2
        
        # Final assessment
        passed = score >= 70
        
        if passed and score >= 90:
            feedback_parts.append("🎭 Excellent work! Props list is production-ready!")
        elif passed:
            feedback_parts.append("🎭 Good job! Props list is usable for the production")
        else:
            feedback_parts.append("⚠️ Needs more work before opening night")
        
        return {
            "passed": passed,
            "score": score,
            "max_score": max_score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": score,
            "feedback": f"Verification error: {str(e)} | Partial: {' | '.join(feedback_parts)}"
        }
    finally:
        if temp_dir:
            cleanup_temp_dir(temp_dir)
