#!/usr/bin/env python3
"""
Verifier for Canning Inventory Freshness task
"""

import sys
import os
import logging
import tempfile
from datetime import datetime, timedelta

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_canning_inventory(traj, env_info, task_info):
    """
    Verify that canning inventory spreadsheet was created correctly.

    Checks:
    1. Data completeness - all 18 items with correct quantities
    2. Formula implementation - Use By Date, Days Until Expiry, Priority
    3. Conditional formatting - URGENT flags for items <60 days
    4. Sorting - by Days Until Expiry ascending
    5. File integrity
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/canning_inventory.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_canning_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        sheet = wb.active
        data = get_sheet_data(wb, sheet.title, max_rows=50, max_cols=10)

        if len(data) < 2:
            return {"passed": False, "score": 0, "feedback": "Spreadsheet is empty or has no data rows"}

        feedback_parts = []
        score = 0
        max_score = 100

        # Identify column indices (flexible header matching)
        headers = [str(cell).lower().strip() if cell else "" for cell in data[0]]
        
        def find_column(keywords):
            for idx, header in enumerate(headers):
                if any(kw in header for kw in keywords):
                    return idx
            return None
        
        col_item = find_column(['item', 'name', 'food', 'product'])
        col_date = find_column(['processed', 'date', 'canned', 'made'])
        col_qty = find_column(['quantity', 'remaining', 'count', 'qty', 'amount'])
        col_size = find_column(['size', 'container', 'unit'])
        col_location = find_column(['location', 'stored', 'place', 'where'])
        col_useby = find_column(['use by', 'useby', 'expir', 'best by'])
        col_days = find_column(['days until', 'days left', 'remaining', 'days to'])
        col_priority = find_column(['priority', 'urgent', 'status', 'flag'])
        
        if None in [col_item, col_date]:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Missing required columns (Item and Date are essential)"
            }
        
        # Extract data rows (skip header and any helper text)
        data_rows = []
        for row in data[1:]:
            if row and col_item < len(row):
                item_val = row[col_item]
                if item_val and isinstance(item_val, str) and len(item_val.strip()) > 0:
                    # Filter out helper text rows
                    if "read data" not in item_val.lower() and "notes" not in item_val.lower():
                        data_rows.append(row)
        
        # Reference date for the task
        TASK_DATE = datetime(2024, 12, 8)
        
        # CRITERION 1: Data Completeness (30 points)
        item_count = len(data_rows)
        
        if item_count >= 18:
            score += 15
            feedback_parts.append(f"✓ All items entered ({item_count} items)")
        elif item_count >= 15:
            score += 10
            feedback_parts.append(f"⚠ Most items entered ({item_count}/18)")
        elif item_count >= 10:
            score += 5
            feedback_parts.append(f"⚠ Some items entered ({item_count}/18)")
        else:
            feedback_parts.append(f"✗ Insufficient items ({item_count}/18)")
        
        # Build lookup dictionary
        items_dict = {}
        for row in data_rows:
            if col_item < len(row):
                item_name = str(row[col_item]).lower().strip()
                items_dict[item_name] = row
        
        # Check specific items with adjusted quantities
        quantity_checks_passed = 0
        
        # Strawberry Jam should be 2 (gave away 2 from 4)
        for key in items_dict.keys():
            if 'strawberry' in key and 'jam' in key:
                jam_row = items_dict[key]
                if col_qty is not None and col_qty < len(jam_row):
                    qty = jam_row[col_qty]
                    if qty == 2:
                        quantity_checks_passed += 1
                        feedback_parts.append("✓ Strawberry Jam qty correct (2)")
                    else:
                        feedback_parts.append(f"✗ Strawberry Jam qty wrong (expected 2, got {qty})")
                break
        
        # Peach Jam should be 4 (gave 1 to mom from 5)
        for key in items_dict.keys():
            if 'peach' in key and 'jam' in key:
                peach_row = items_dict[key]
                if col_qty is not None and col_qty < len(peach_row):
                    qty = peach_row[col_qty]
                    if qty == 4:
                        quantity_checks_passed += 1
                        feedback_parts.append("✓ Peach Jam qty correct (4)")
                    else:
                        feedback_parts.append(f"✗ Peach Jam qty wrong (expected 4, got {qty})")
                break
        
        # Pumpkin Butter should be 2 (gave 1 already from 3)
        for key in items_dict.keys():
            if 'pumpkin' in key:
                pumpkin_row = items_dict[key]
                if col_qty is not None and col_qty < len(pumpkin_row):
                    qty = pumpkin_row[col_qty]
                    if qty == 2:
                        quantity_checks_passed += 1
                        feedback_parts.append("✓ Pumpkin Butter qty correct (2)")
                    else:
                        feedback_parts.append(f"✗ Pumpkin Butter qty wrong (expected 2, got {qty})")
                break
        
        # Award points for quantity accuracy
        if quantity_checks_passed >= 3:
            score += 15
        elif quantity_checks_passed >= 2:
            score += 10
        elif quantity_checks_passed >= 1:
            score += 5
        
        # CRITERION 2: Formula Implementation (40 points)
        if col_date is not None and col_useby is not None and col_days is not None and col_priority is not None:
            formula_score = 0
            
            # Check date calculations on a few rows
            valid_date_calculations = 0
            valid_days_calculations = 0
            valid_priority_logic = 0
            
            for row_idx, row in enumerate(data_rows[:min(5, len(data_rows))]):
                # Check Use By Date (should be ~12 months after processing)
                if col_date < len(row) and col_useby < len(row):
                    process_date = row[col_date]
                    useby_date = row[col_useby]
                    
                    if isinstance(process_date, datetime) and isinstance(useby_date, datetime):
                        diff_days = (useby_date - process_date).days
                        # 12 months = 365 days, allow 350-380 range
                        if 350 <= diff_days <= 380:
                            valid_date_calculations += 1
                
                # Check Days Until Expiry (should be Use By Date - Dec 8, 2024)
                if col_useby < len(row) and col_days < len(row):
                    useby_date = row[col_useby]
                    days_val = row[col_days]
                    
                    if isinstance(useby_date, datetime) and isinstance(days_val, (int, float)):
                        expected_days = (useby_date - TASK_DATE).days
                        # Allow small tolerance
                        if abs(days_val - expected_days) <= 2:
                            valid_days_calculations += 1
                
                # Check Priority logic (URGENT if < 60 days)
                if col_days < len(row) and col_priority < len(row):
                    days_val = row[col_days]
                    priority_val = row[col_priority]
                    
                    if isinstance(days_val, (int, float)) and priority_val:
                        priority_str = str(priority_val).strip().upper()
                        if days_val < 60 and priority_str == "URGENT":
                            valid_priority_logic += 1
                        elif days_val >= 60 and priority_str == "OK":
                            valid_priority_logic += 1
            
            # Award formula points based on validations
            if valid_date_calculations >= 3:
                formula_score += 15
                feedback_parts.append("✓ Use By Date formulas correct")
            elif valid_date_calculations >= 2:
                formula_score += 10
                feedback_parts.append("⚠ Some Use By Date formulas correct")
            elif valid_date_calculations >= 1:
                formula_score += 5
            
            if valid_days_calculations >= 3:
                formula_score += 15
                feedback_parts.append("✓ Days Until Expiry formulas correct")
            elif valid_days_calculations >= 2:
                formula_score += 10
                feedback_parts.append("⚠ Some Days formulas correct")
            elif valid_days_calculations >= 1:
                formula_score += 5
            
            if valid_priority_logic >= 3:
                formula_score += 10
                feedback_parts.append("✓ Priority logic correct")
            elif valid_priority_logic >= 2:
                formula_score += 5
                feedback_parts.append("⚠ Some Priority logic correct")
            
            score += formula_score
            
        else:
            feedback_parts.append("✗ Missing formula columns (Use By, Days, Priority)")
        
        # CRITERION 3: Conditional Formatting / URGENT Flags (15 points)
        if col_priority is not None:
            urgent_count = 0
            ok_count = 0
            
            for row in data_rows:
                if col_priority < len(row):
                    priority_val = row[col_priority]
                    if priority_val:
                        priority_str = str(priority_val).strip().upper()
                        if priority_str == 'URGENT':
                            urgent_count += 1
                        elif priority_str == 'OK':
                            ok_count += 1
            
            # Should have 3-5 URGENT items (June, July, early August items)
            if urgent_count >= 3 and urgent_count <= 6:
                score += 15
                feedback_parts.append(f"✓ URGENT flags applied correctly ({urgent_count} items)")
            elif urgent_count >= 1:
                score += 8
                feedback_parts.append(f"⚠ Some URGENT flags ({urgent_count} items)")
            else:
                feedback_parts.append("✗ No URGENT priority flags found")
        
        # CRITERION 4: Sorting (10 points)
        if col_days is not None:
            days_values = []
            for row in data_rows:
                if col_days < len(row):
                    days_val = row[col_days]
                    if isinstance(days_val, (int, float)):
                        days_values.append(days_val)
            
            if len(days_values) >= 5:
                # Check if mostly sorted (ascending order - oldest/lowest first)
                sorted_count = 0
                for i in range(len(days_values) - 1):
                    if days_values[i] <= days_values[i + 1]:
                        sorted_count += 1
                
                sort_ratio = sorted_count / (len(days_values) - 1)
                
                if sort_ratio >= 0.9:
                    score += 10
                    feedback_parts.append("✓ Data sorted by Days Until Expiry (oldest first)")
                elif sort_ratio >= 0.7:
                    score += 6
                    feedback_parts.append("⚠ Data partially sorted")
                else:
                    feedback_parts.append("✗ Data not properly sorted")
        
        # CRITERION 5: File Integrity (5 points)
        score += 5
        feedback_parts.append("✓ File saved and readable")
        
        # Normalize score
        score = min(score, max_score)
        
        # Determine pass/fail (70% threshold)
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score / max_score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)