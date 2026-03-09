#!/usr/bin/env python3
"""
Verifier for School Read-a-thon Tracker task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir,
    parse_docx_file,
    get_document_text
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_currency(value):
    """Parse currency string to float, handling various formats"""
    if value is None:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        # Remove $, commas, extra spaces
        cleaned = re.sub(r'[$,\s]', '', value.strip())
        try:
            return float(cleaned)
        except ValueError:
            return 0.0
    return 0.0


def verify_readathon_tracker(traj, env_info, task_info):
    """
    Verify that read-a-thon tracker was completed correctly.

    Checks:
    1. Spreadsheet file exists and is parseable
    2. "Amount Owed" column present in Column H (or nearby)
    3. Formulas calculate correctly for per-book pledges (spot-check 3+)
    4. Formulas calculate correctly for flat pledges (spot-check 3+)
    5. Summary statistics present (Total Pledged, Collected, Outstanding)
    6. Summary statistics are mathematically accurate
    7. Collection letter document exists (bonus)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/ReadAthon_Data.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_readathon_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        criteria_passed = 0
        feedback_parts = []

        sheet_name = wb.sheetnames[0]  # Get first sheet name
        sheet = wb[sheet_name]

        # Criterion 1: File exists and is parseable (implicit - we got here)
        criteria_passed += 1
        feedback_parts.append("✅ Spreadsheet file exists and is parseable")

        # Get all data from sheet
        data = get_sheet_data(wb, sheet_name, max_rows=50, max_cols=15)

        # Find "Amount Owed" column
        amount_owed_col = None
        header_row = data[0] if data else []
        
        for col_idx, header in enumerate(header_row):
            if header and "amount" in str(header).lower() and "owed" in str(header).lower():
                amount_owed_col = col_idx
                break

        # Criterion 2: "Amount Owed" column present
        if amount_owed_col is not None:
            criteria_passed += 1
            feedback_parts.append(f"✅ 'Amount Owed' column found at position {amount_owed_col + 1}")
        else:
            feedback_parts.append("❌ 'Amount Owed' column not found")
            # Cannot verify further without this column
            return {
                "passed": False,
                "score": int((criteria_passed / 7) * 100),
                "feedback": " | ".join(feedback_parts)
            }

        # Extract column indices
        pledge_type_col = None
        pledge_amount_col = None
        books_read_col = None
        payment_status_col = None

        for col_idx, header in enumerate(header_row):
            if header:
                h_lower = str(header).lower()
                if "pledge" in h_lower and "type" in h_lower:
                    pledge_type_col = col_idx
                elif "pledge" in h_lower and "amount" in h_lower:
                    pledge_amount_col = col_idx
                elif "books" in h_lower and "read" in h_lower:
                    books_read_col = col_idx
                elif "payment" in h_lower or "status" in h_lower:
                    payment_status_col = col_idx

        if None in [pledge_type_col, pledge_amount_col, books_read_col]:
            feedback_parts.append("❌ Required columns (Pledge Type, Amount, Books Read) not found")
            return {
                "passed": False,
                "score": int((criteria_passed / 7) * 100),
                "feedback": " | ".join(feedback_parts)
            }

        # Criterion 3 & 4: Check formula correctness
        per_book_correct = 0
        per_book_checked = 0
        flat_correct = 0
        flat_checked = 0

        for row_idx in range(1, min(30, len(data))):  # Check rows 2-30
            row = data[row_idx]
            
            if row_idx >= len(data) or len(row) <= max(pledge_type_col, pledge_amount_col, 
                                                        books_read_col, amount_owed_col):
                continue

            pledge_type = row[pledge_type_col]
            pledge_amount_raw = row[pledge_amount_col]
            books_read = row[books_read_col]
            amount_owed = row[amount_owed_col]

            if not pledge_type or not pledge_amount_raw:
                continue

            pledge_amount = parse_currency(pledge_amount_raw)
            books = 0 if books_read is None or books_read == "" else float(books_read)
            calculated_owed = parse_currency(amount_owed)

            pledge_type_str = str(pledge_type).strip().lower()

            if "per book" in pledge_type_str or "per-book" in pledge_type_str:
                if per_book_checked < 5:  # Check up to 5 per-book entries
                    expected = pledge_amount * books
                    if abs(calculated_owed - expected) < 0.02:  # Allow 2 cent rounding
                        per_book_correct += 1
                    per_book_checked += 1

            elif "flat" in pledge_type_str:
                if flat_checked < 5:  # Check up to 5 flat entries
                    expected = pledge_amount
                    if abs(calculated_owed - expected) < 0.02:
                        flat_correct += 1
                    flat_checked += 1

        # Criterion 3: Per-book calculations
        if per_book_checked >= 3 and per_book_correct >= per_book_checked * 0.75:
            criteria_passed += 1
            feedback_parts.append(f"✅ Per-book formulas correct ({per_book_correct}/{per_book_checked})")
        else:
            feedback_parts.append(f"❌ Per-book formulas incorrect ({per_book_correct}/{per_book_checked} checked)")

        # Criterion 4: Flat calculations
        if flat_checked >= 3 and flat_correct >= flat_checked * 0.75:
            criteria_passed += 1
            feedback_parts.append(f"✅ Flat pledge formulas correct ({flat_correct}/{flat_checked})")
        else:
            feedback_parts.append(f"❌ Flat pledge formulas incorrect ({flat_correct}/{flat_checked} checked)")

        # Criterion 5 & 6: Check for summary statistics
        # Look for summary section (typically below data, around rows 30-45)
        summary_found = False
        total_pledged_value = None
        total_collected_value = None
        total_outstanding_value = None

        for row_idx in range(25, min(50, len(data))):
            if row_idx >= len(data):
                break
            
            row = data[row_idx]
            if not row or len(row) < 2:
                continue

            first_cell = str(row[0]).lower() if row[0] else ""
            second_cell = row[1] if len(row) > 1 else None

            if "total" in first_cell and ("pledge" in first_cell or "amount" in first_cell):
                if "outstanding" in first_cell or "owed" in first_cell:
                    total_outstanding_value = parse_currency(second_cell)
                elif "collect" in first_cell or "paid" in first_cell or "received" in first_cell:
                    total_collected_value = parse_currency(second_cell)
                else:
                    total_pledged_value = parse_currency(second_cell)
                summary_found = True

        # Criterion 5: Summary statistics present
        if summary_found and (total_pledged_value is not None or total_collected_value is not None):
            criteria_passed += 1
            feedback_parts.append("✅ Summary statistics section present")
        else:
            feedback_parts.append("❌ Summary statistics section not found")

        # Criterion 6: Verify summary accuracy
        # Calculate expected values from data
        expected_total_pledged = 0.0
        expected_total_collected = 0.0

        for row_idx in range(1, min(30, len(data))):
            row = data[row_idx]
            
            if row_idx >= len(data) or len(row) <= amount_owed_col:
                continue

            amount_owed = parse_currency(row[amount_owed_col])
            expected_total_pledged += amount_owed

            if payment_status_col is not None and len(row) > payment_status_col:
                status = str(row[payment_status_col]).lower() if row[payment_status_col] else ""
                if "paid" in status:
                    expected_total_collected += amount_owed

        expected_total_outstanding = expected_total_pledged - expected_total_collected

        # Check accuracy (allow 5% tolerance or $10 difference)
        summary_accurate = False
        if total_pledged_value is not None:
            pledged_diff = abs(total_pledged_value - expected_total_pledged)
            pledged_ok = pledged_diff < max(expected_total_pledged * 0.05, 10)
        else:
            pledged_ok = False

        if total_collected_value is not None:
            collected_diff = abs(total_collected_value - expected_total_collected)
            collected_ok = collected_diff < max(expected_total_collected * 0.05, 10)
        else:
            collected_ok = False

        if total_outstanding_value is not None:
            outstanding_diff = abs(total_outstanding_value - expected_total_outstanding)
            outstanding_ok = outstanding_diff < max(expected_total_outstanding * 0.05, 10)
        else:
            outstanding_ok = False

        accuracy_count = sum([pledged_ok, collected_ok, outstanding_ok])
        if accuracy_count >= 2:  # At least 2 out of 3 correct
            criteria_passed += 1
            summary_accurate = True
            feedback_parts.append(f"✅ Summary statistics mathematically accurate ({accuracy_count}/3)")
        else:
            feedback_parts.append(f"❌ Summary statistics inaccurate (Expected: Pledged=${expected_total_pledged:.2f}, Collected=${expected_total_collected:.2f}, Outstanding=${expected_total_outstanding:.2f})")

        # Criterion 7: Check for collection letter document (bonus)
        doc_path = "/home/ga/Documents/TextDocuments/Collection_Letters.docx"
        try:
            doc_success, doc, doc_error = copy_and_parse_document(doc_path, copy_from_env, 'docx')
            
            if doc_success:
                doc_text = get_document_text(doc)
                # Check for reasonable content
                has_sponsor_ref = any(word in doc_text.lower() for word in ["sponsor", "pledge", "donation"])
                has_amount_ref = any(word in doc_text.lower() for word in ["amount", "owed", "$", "payment"])
                has_professional_tone = any(word in doc_text.lower() for word in ["thank", "appreciate", "grateful"])
                
                if has_sponsor_ref and has_amount_ref and len(doc_text) > 50:
                    criteria_passed += 1
                    feedback_parts.append("✅ Collection letter document created with appropriate content")
                else:
                    feedback_parts.append("⚠️ Collection letter exists but missing expected content")
            else:
                feedback_parts.append("ℹ️ Collection letter not created (optional)")
        except Exception as e:
            feedback_parts.append("ℹ️ Collection letter not created (optional)")

        # Calculate final score
        score = int((criteria_passed / 7) * 100)
        passed = score >= 70  # Pass threshold: need 5/7 criteria (71%)

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)