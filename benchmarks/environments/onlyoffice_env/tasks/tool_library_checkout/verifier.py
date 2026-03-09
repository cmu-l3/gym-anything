#!/usr/bin/env python3
"""
Verifier for Tool Library Checkout task

This verifier checks that a tool checkout tracking spreadsheet was created with:
1. Proper header row structure
2. Exactly 5 data rows with tool and borrower information
3. Valid dates in checkout and due date columns
4. Working formulas for Days Out (TODAY() - checkout date)
5. Working Status formula (OVERDUE if >7 days, else OK)
6. Working Late Fee formula ($2/day beyond 7 days)
7. Diversity requirement: at least 2 OVERDUE and 2 OK records
"""

import sys
import os
import logging
import tempfile
from datetime import datetime, date
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


def is_date_value(value):
    """Check if a value is a date type"""
    return isinstance(value, (datetime, date))


def extract_numeric_value(value):
    """Extract numeric value from cell (handles currency formatting)"""
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        # Remove currency symbols and parse
        cleaned = re.sub(r'[$,\s]', '', value)
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def verify_tool_checkout_spreadsheet(traj, env_info, task_info):
    """
    Verify that tool checkout tracking spreadsheet was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/tool_checkout.xlsx"
    
    # Create a temporary file to copy the spreadsheet to
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_tool_')
    temp_file_path = os.path.join(temp_dir, 'tool_checkout.xlsx')

    try:
        # Copy file from container
        copy_from_env(container_path, temp_file_path)
        
        if not os.path.exists(temp_file_path) or os.path.getsize(temp_file_path) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"File not found or empty: {container_path}"
            }

        # Parse the spreadsheet
        wb = parse_xlsx_file(temp_file_path)
        if wb is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to parse spreadsheet file"
            }

        # Get the active sheet
        sheet_name = wb.sheetnames[0]
        ws = wb[sheet_name]

        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []

        # Get all data from sheet
        data = get_sheet_data(wb, sheet_name, max_rows=20, max_cols=10)

        # Find header row (look for row with multiple non-empty cells)
        header_row_idx = None
        header_row = None
        for idx, row in enumerate(data[:5]):  # Check first 5 rows
            non_empty = [cell for cell in row if cell is not None and str(cell).strip()]
            if len(non_empty) >= 5:  # Header should have at least 5 columns
                header_row_idx = idx
                header_row = row
                break

        if header_row is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No valid header row found. Expected at least 5 column headers."
            }

        # Criterion 1: Check header row contains expected terms
        header_text = ' '.join([str(cell).lower() for cell in header_row if cell is not None])
        expected_terms = ['tool', 'borrower', 'date', 'status', 'fee']
        header_terms_found = sum(1 for term in expected_terms if term in header_text)
        
        if header_terms_found >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Header row found with {header_terms_found}/5 expected terms")
        else:
            feedback_parts.append(f"❌ Header row incomplete ({header_terms_found}/5 terms found)")

        # Find column indices (flexible ordering)
        def find_column_index(keywords, row):
            for idx, cell in enumerate(row):
                if cell is None:
                    continue
                cell_str = str(cell).lower()
                if any(kw in cell_str for kw in keywords):
                    return idx
            return None

        tool_col = find_column_index(['tool', 'item'], header_row)
        borrower_col = find_column_index(['borrower', 'member', 'name'], header_row)
        checkout_col = find_column_index(['checkout', 'borrowed', 'out'], header_row)
        due_col = find_column_index(['due', 'return'], header_row)
        days_col = find_column_index(['days', 'day out', 'days out'], header_row)
        status_col = find_column_index(['status', 'state'], header_row)
        fee_col = find_column_index(['fee', 'late', 'charge'], header_row)

        # Get data rows (rows after header)
        data_rows = data[header_row_idx + 1:]
        non_empty_data_rows = []
        
        for row in data_rows[:10]:  # Check up to 10 rows after header
            # A row is considered data if it has content in key columns
            if tool_col is not None and row[tool_col] is not None and str(row[tool_col]).strip():
                non_empty_data_rows.append(row)

        # Criterion 2: Check for exactly 5 data rows
        num_data_rows = len(non_empty_data_rows)
        if num_data_rows == 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Exactly 5 data rows found")
        else:
            feedback_parts.append(f"❌ Expected 5 data rows, found {num_data_rows}")

        if num_data_rows == 0:
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts) + " | Cannot verify further without data rows"
            }

        # Criterion 3: Check that tool names and borrower names are filled
        tools_filled = 0
        borrowers_filled = 0
        
        for row in non_empty_data_rows:
            if tool_col is not None and row[tool_col] is not None and str(row[tool_col]).strip():
                tools_filled += 1
            if borrower_col is not None and row[borrower_col] is not None and str(row[borrower_col]).strip():
                borrowers_filled += 1

        if tools_filled >= num_data_rows and borrowers_filled >= num_data_rows:
            criteria_passed += 1
            feedback_parts.append(f"✅ All rows have tool names and borrower names")
        else:
            feedback_parts.append(f"❌ Some rows missing tool/borrower names ({tools_filled}/{num_data_rows} tools, {borrowers_filled}/{num_data_rows} borrowers)")

        # Criterion 4: Check for valid dates in checkout and due date columns
        valid_dates = 0
        for row in non_empty_data_rows:
            checkout_date = None
            if checkout_col is not None and checkout_col < len(row):
                checkout_date = row[checkout_col]
            
            if is_date_value(checkout_date):
                valid_dates += 1

        if valid_dates >= num_data_rows * 0.8:  # At least 80% should have valid dates
            criteria_passed += 1
            feedback_parts.append(f"✅ Valid dates found ({valid_dates}/{num_data_rows} rows)")
        else:
            feedback_parts.append(f"❌ Insufficient valid dates ({valid_dates}/{num_data_rows} rows have date values)")

        # Criterion 5-7: Verify formulas work correctly
        today = date.today()
        formula_errors = []
        days_out_correct = 0
        status_correct = 0
        fee_correct = 0
        overdue_count = 0
        ok_count = 0

        for i, row in enumerate(non_empty_data_rows):
            # Get checkout date
            checkout_date = None
            if checkout_col is not None and checkout_col < len(row):
                checkout_val = row[checkout_col]
                if is_date_value(checkout_val):
                    if isinstance(checkout_val, datetime):
                        checkout_date = checkout_val.date()
                    else:
                        checkout_date = checkout_val

            if checkout_date is None:
                continue

            # Calculate expected days out
            expected_days_out = (today - checkout_date).days

            # Check Days Out column
            if days_col is not None and days_col < len(row):
                days_out_val = row[days_col]
                if isinstance(days_out_val, (int, float)):
                    # Allow ±1 day tolerance for calculation differences
                    if abs(days_out_val - expected_days_out) <= 1:
                        days_out_correct += 1
                    else:
                        formula_errors.append(f"Row {i+1}: Days Out is {days_out_val}, expected ~{expected_days_out}")

            # Check Status column
            if status_col is not None and status_col < len(row):
                status_val = row[status_col]
                if status_val is not None:
                    status_str = str(status_val).upper().strip()
                    expected_status = "OVERDUE" if expected_days_out > 7 else "OK"
                    
                    if expected_status in status_str:
                        status_correct += 1
                        if expected_status == "OVERDUE":
                            overdue_count += 1
                        else:
                            ok_count += 1
                    else:
                        formula_errors.append(f"Row {i+1}: Status is '{status_val}', expected '{expected_status}'")

            # Check Late Fee column
            if fee_col is not None and fee_col < len(row):
                fee_val = row[fee_col]
                fee_num = extract_numeric_value(fee_val)
                
                if fee_num is not None:
                    expected_fee = max(0, (expected_days_out - 7) * 2)
                    # Allow ±2 dollar tolerance
                    if abs(fee_num - expected_fee) <= 2:
                        fee_correct += 1
                    else:
                        formula_errors.append(f"Row {i+1}: Late Fee is ${fee_num}, expected ~${expected_fee}")

        # Criterion 5: Days Out formula
        if days_out_correct >= num_data_rows * 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Days Out formula correct ({days_out_correct}/{num_data_rows} rows)")
        else:
            feedback_parts.append(f"❌ Days Out formula issues ({days_out_correct}/{num_data_rows} correct)")

        # Criterion 6: Status formula
        if status_correct >= num_data_rows * 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Status formula correct ({status_correct}/{num_data_rows} rows)")
        else:
            feedback_parts.append(f"❌ Status formula issues ({status_correct}/{num_data_rows} correct)")

        # Criterion 7: Late Fee formula
        if fee_correct >= num_data_rows * 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Late Fee formula correct ({fee_correct}/{num_data_rows} rows)")
        else:
            feedback_parts.append(f"❌ Late Fee formula issues ({fee_correct}/{num_data_rows} correct)")

        # Criterion 8: Diversity requirement (at least 2 overdue and 2 OK)
        if overdue_count >= 2 and ok_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Diversity requirement met ({overdue_count} overdue, {ok_count} OK)")
        else:
            feedback_parts.append(f"❌ Diversity requirement not met ({overdue_count} overdue, {ok_count} OK - need at least 2 of each)")

        # Add formula errors to feedback if any
        if formula_errors and len(formula_errors) <= 3:
            feedback_parts.extend(formula_errors[:3])

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 85

        feedback = " | ".join(feedback_parts)

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
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)