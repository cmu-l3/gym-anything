#!/usr/bin/env python3
"""
Verifier for Roommate Expense Reconciliation task

This verifier checks:
1. File exists and is parseable
2. Sheet2 exists with appropriate name
3. Correct calculations for total bills and per-person share
4. Correct final amounts for Alex and Jordan
5. Adjustments are documented
6. Sam's special case is noted
7. Basic table formatting is present
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_numeric_value_near_target(values, target, tolerance=1.0):
    """
    Find if a numeric value close to target exists in the values list.
    
    Args:
        values: List of cell values
        target: Target numeric value
        tolerance: Acceptable difference
    
    Returns:
        Tuple of (found: bool, actual_value: float or None)
    """
    for val in values:
        if val is None:
            continue
        
        # Try to extract numeric value
        try:
            # Handle currency formatted strings
            if isinstance(val, str):
                cleaned = val.replace('$', '').replace(',', '').strip()
                # Extract first number found (handles cases like "Alex: $688.75")
                match = re.search(r'-?\d+\.?\d*', cleaned)
                if match:
                    numeric_val = float(match.group())
                else:
                    continue
            elif isinstance(val, (int, float)):
                numeric_val = float(val)
            else:
                continue
            
            if abs(numeric_val - target) <= tolerance:
                return True, numeric_val
        except (ValueError, TypeError, AttributeError):
            continue
    
    return False, None


def extract_all_text_values(data):
    """Extract all text values from 2D data array for keyword searching"""
    text_values = []
    for row in data:
        for cell in row:
            if cell is not None:
                text_values.append(str(cell).lower())
    return text_values


def verify_roommate_expense_reconciliation(traj, env_info, task_info):
    """
    Verify the roommate expense reconciliation spreadsheet task.
    
    Expected calculations:
    - Total bills: $2610 (2400 + 52 + 87 + 43 + 28)
    - Per-person base: $652.50 (2610 / 4)
    - Alex final: $688.75 (652.50 + 40 - 3.75)
    - Jordan final: $640.75 (652.50 - 8 - 3.75)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/march_bills_raw.xlsx"
    temp_dir = None
    
    try:
        # Create temporary file for copying
        temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_roommate_')
        temp_file_path = os.path.join(temp_dir, 'march_bills_raw.xlsx')
        
        # Copy file from container
        try:
            copy_from_env(container_path, temp_file_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy file: {str(e)}"}
        
        if not os.path.exists(temp_file_path) or os.path.getsize(temp_file_path) == 0:
            return {"passed": False, "score": 0, "feedback": "File not found or empty"}
        
        # Parse workbook
        wb = parse_xlsx_file(temp_file_path)
        if not wb:
            return {"passed": False, "score": 0, "feedback": "Could not parse Excel file - file may be corrupted"}
        
        result = {
            "passed": False,
            "score": 0,
            "feedback": []
        }
        
        # Criterion 1: File exists and is parseable (10 points)
        result["score"] += 10
        result["feedback"].append("✅ File exists and is parseable (10 pts)")
        
        # Criterion 2: Sheet2 exists (15 points)
        sheet_names = wb.sheetnames
        if len(sheet_names) < 2:
            result["feedback"].append("❌ Sheet2 not found - only 1 sheet exists (0/15 pts)")
            result["feedback"].insert(0, f"❌ FAILED with {result['score']}/100 points (need 70)")
            return result
        
        # Find the reconciliation sheet (could be named various things)
        recon_sheet_name = None
        reconciliation_keywords = ['reconciliation', 'march reconciliation', 'march summary', 'summary', 'sheet2']
        
        for sheet_name in sheet_names[1:]:  # Skip first sheet
            if any(keyword in sheet_name.lower() for keyword in reconciliation_keywords):
                recon_sheet_name = sheet_name
                break
        
        if not recon_sheet_name:
            recon_sheet_name = sheet_names[1]  # Fallback to second sheet
        
        result["score"] += 15
        result["feedback"].append(f"✅ Sheet2 exists: '{recon_sheet_name}' (15 pts)")
        
        # Get all data from reconciliation sheet
        try:
            data = get_sheet_data(wb, recon_sheet_name, max_rows=100, max_cols=20)
        except Exception as e:
            result["feedback"].append(f"❌ Could not read sheet data: {str(e)}")
            result["feedback"].insert(0, f"❌ FAILED with {result['score']}/100 points (need 70)")
            return result
        
        # Flatten all numeric and text values for searching
        all_values = []
        all_text = []
        for row in data:
            for cell in row:
                if cell is not None:
                    all_values.append(cell)
                    all_text.append(str(cell).lower())
        
        # Criterion 3: Total bill calculation ($2610) - 10 points
        found_total, actual_total = find_numeric_value_near_target(all_values, 2610, tolerance=1)
        if found_total:
            result["score"] += 10
            result["feedback"].append(f"✅ Total bill ${actual_total:.2f} found (10 pts)")
        else:
            result["feedback"].append("❌ Total bill calculation $2610 not found (0/10 pts)")
        
        # Criterion 4: Per-person base share ($652.50) - 10 points
        found_per_person, actual_per_person = find_numeric_value_near_target(all_values, 652.50, tolerance=0.50)
        if found_per_person:
            result["score"] += 10
            result["feedback"].append(f"✅ Per-person share ${actual_per_person:.2f} found (10 pts)")
        else:
            result["feedback"].append("❌ Per-person share $652.50 not found (0/10 pts)")
        
        # Criterion 5: Alex's final amount ($688.75) - 10 points
        found_alex, actual_alex = find_numeric_value_near_target(all_values, 688.75, tolerance=1)
        if found_alex:
            result["score"] += 10
            result["feedback"].append(f"✅ Alex's amount ${actual_alex:.2f} found (10 pts)")
        else:
            result["feedback"].append("❌ Alex's final amount $688.75 not found (0/10 pts)")
        
        # Criterion 6: Jordan's final amount ($640.75) - 10 points
        found_jordan, actual_jordan = find_numeric_value_near_target(all_values, 640.75, tolerance=1)
        if found_jordan:
            result["score"] += 10
            result["feedback"].append(f"✅ Jordan's amount ${actual_jordan:.2f} found (10 pts)")
        else:
            result["feedback"].append("❌ Jordan's final amount $640.75 not found (0/10 pts)")
        
        # Criterion 7: Adjustments documented (20 points)
        # Check for key adjustment values or keywords
        adjustment_checks = {
            '3.75': False,   # February credit
            '8': False,      # Jordan's overpayment
            '40': False,     # Alex's debt
        }
        
        adjustment_keywords = ['credit', 'overpay', 'debt', 'adjustment', 'owe', 'paid']
        keyword_found = any(keyword in text for text in all_text for keyword in adjustment_keywords)
        
        for key in adjustment_checks.keys():
            # Look for the value in the sheet
            for val in all_values:
                if val is None:
                    continue
                val_str = str(val).replace('$', '').replace(',', '').strip()
                if key in val_str:
                    adjustment_checks[key] = True
                    break
        
        adjustments_found = sum(adjustment_checks.values())
        
        if adjustments_found >= 2 and keyword_found:
            result["score"] += 20
            result["feedback"].append(f"✅ Adjustments properly documented ({adjustments_found}/3 values found) (20 pts)")
        elif adjustments_found >= 1 or keyword_found:
            result["score"] += 10
            result["feedback"].append(f"⚠️ Some adjustments documented ({adjustments_found}/3 values) (10 pts)")
        else:
            result["feedback"].append("❌ Adjustments not clearly documented (0/20 pts)")
        
        # Criterion 8: Sam's special case noted (5 points)
        sam_keywords = ['sam', 'travel', 'april', 'defer', 'later', 'cover']
        sam_mentions = sum(1 for text in all_text if any(keyword in text for keyword in sam_keywords))
        
        if sam_mentions >= 2:  # Need at least 2 keywords (e.g., "sam" + "april")
            result["score"] += 5
            result["feedback"].append("✅ Sam's special case noted (5 pts)")
        else:
            result["feedback"].append("❌ Sam's deferred payment not clearly noted (0/5 pts)")
        
        # Criterion 9: Table structure and formatting (10 points)
        # Check if there's reasonable table structure (multiple rows with data)
        non_empty_rows = sum(1 for row in data if any(cell is not None for cell in row))
        
        # Check for table-like structure with headers/labels
        has_labels = any(
            any(label in str(cell).lower() for label in ['name', 'roommate', 'alex', 'jordan', 'amount', 'share', 'adjustment'])
            for row in data[:15] for cell in row if cell is not None
        )
        
        if non_empty_rows >= 5 and has_labels:
            result["score"] += 10
            result["feedback"].append("✅ Table structure present (10 pts)")
        elif non_empty_rows >= 3:
            result["score"] += 5
            result["feedback"].append("⚠️ Basic structure present (5 pts)")
        else:
            result["feedback"].append("❌ No clear table structure (0/10 pts)")
        
        # Final assessment
        result["passed"] = result["score"] >= 70
        
        if result["passed"]:
            result["feedback"].insert(0, f"🎉 PASSED with {result['score']}/100 points")
        else:
            result["feedback"].insert(0, f"❌ FAILED with {result['score']}/100 points (need 70)")
        
        result["feedback"] = " | ".join(result["feedback"])
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if temp_dir:
            cleanup_temp_dir(temp_dir)