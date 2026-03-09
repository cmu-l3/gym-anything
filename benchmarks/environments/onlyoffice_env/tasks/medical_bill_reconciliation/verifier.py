#!/usr/bin/env python3
"""
Verifier for Medical Bill Reconciliation task

This verifier checks that the agent:
1. Created a "Reconciliation" sheet
2. Identified duplicate charges (36415)
3. Flagged denied items (99285, 70470)
4. Marked legitimate charges correctly
5. Created summary calculations with formulas
6. Calculated correct amounts (~$381 owed, ~$1,398 disputed)
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_text(text):
    """Normalize text for comparison (lowercase, strip whitespace)"""
    if text is None:
        return ""
    return str(text).lower().strip()


def find_header_row(data, required_keywords):
    """Find header row by looking for required keywords"""
    for i, row in enumerate(data[:10]):  # Check first 10 rows
        row_text = " ".join([normalize_text(cell) for cell in row])
        if all(keyword in row_text for keyword in required_keywords):
            return i
    return None


def create_column_map(header_row):
    """Create mapping from normalized column names to indices"""
    col_map = {}
    for idx, cell in enumerate(header_row):
        if cell:
            # Normalize and create multiple possible keys
            normalized = normalize_text(cell).replace(" ", "_").replace("-", "_")
            col_map[normalized] = idx
            
            # Add common variations
            if "service" in normalized and "code" in normalized:
                col_map["service_code"] = idx
                col_map["code"] = idx
            if "status" in normalized:
                col_map["status"] = idx
            if "responsibility" in normalized or "patient" in normalized:
                col_map["my_responsibility"] = idx
                col_map["patient_resp"] = idx
    
    return col_map


def extract_status_value(cell_value):
    """Extract status from cell (handles mixed formats)"""
    text = normalize_text(cell_value)
    if not text:
        return None
    
    # Check for status keywords
    if "legit" in text or "ok" in text or "valid" in text or "approved" in text:
        return "LEGIT"
    elif "dup" in text:
        return "DUPLICATE"
    elif "deny" in text or "denied" in text or "reject" in text:
        return "DENIED"
    elif "disp" in text:
        return "DISPUTE"
    
    return text.upper()


def has_formula_in_range(sheet, start_row, end_row, start_col, end_col):
    """Check if any cell in range contains a formula"""
    for row in range(start_row, end_row + 1):
        for col in range(start_col, end_col + 1):
            cell = sheet.cell(row=row, column=col)
            if cell.value and isinstance(cell.value, str):
                if cell.value.startswith('='):
                    return True
            # Check if cell has a formula (openpyxl stores formulas differently)
            if hasattr(cell, 'data_type') and cell.data_type == 'f':
                return True
    return False


def find_summary_value(data, keywords, start_row=0):
    """Find a numeric value near keywords in data"""
    for i in range(start_row, len(data)):
        row = data[i]
        row_text = " ".join([normalize_text(cell) for cell in row])
        
        # Check if this row contains all keywords
        if all(keyword in row_text for keyword in keywords):
            # Look for numeric value in this row or next few rows
            for offset in range(0, 3):
                if i + offset >= len(data):
                    break
                check_row = data[i + offset]
                for cell in check_row:
                    if isinstance(cell, (int, float)) and cell > 0:
                        return cell, i + offset
    return None, None


def verify_medical_bill_reconciliation(traj, env_info, task_info):
    """
    Verify that medical bill reconciliation was completed correctly.
    
    Checks:
    1. "Reconciliation" sheet exists
    2. Contains data with status column
    3. Duplicate charge (36415) handled - appears only once
    4. Denied items (99285, 70470) flagged or excluded
    5. At least 4 items marked as LEGIT
    6. Summary calculations present
    7. Amount to pay is ~$381 (within tolerance)
    8. Disputed amount is at least $1,000
    9. Formulas used (not just hardcoded values)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/hospital_bill_raw.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_medbill_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0.0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Check if "Reconciliation" sheet exists
        recon_sheet_name = None
        for sheet_name in wb.sheetnames:
            if "recon" in normalize_text(sheet_name):
                recon_sheet_name = sheet_name
                break
        
        if not recon_sheet_name:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ No 'Reconciliation' sheet found. Available sheets: " + ", ".join(wb.sheetnames)
            }
        
        recon_sheet = wb[recon_sheet_name]
        data = get_sheet_data(recon_sheet, max_rows=100, max_cols=20)
        
        if not data or len(data) < 2:
            return {
                "passed": False,
                "score": 0.1,
                "feedback": f"❌ '{recon_sheet_name}' sheet exists but is empty or has insufficient data"
            }
        
        # Find header row (look for "status" or "service_code")
        header_row_idx = find_header_row(data, ["status"]) or find_header_row(data, ["code"])
        
        if header_row_idx is None:
            # Try to find any row that looks like headers
            for i in range(min(5, len(data))):
                row_text = " ".join([normalize_text(cell) for cell in data[i]])
                if len(row_text) > 10:  # Has some content
                    header_row_idx = i
                    break
        
        if header_row_idx is None:
            return {
                "passed": False,
                "score": 0.2,
                "feedback": "❌ Cannot identify header row in Reconciliation sheet"
            }
        
        # Create column mapping
        header_row = data[header_row_idx]
        col_map = create_column_map(header_row)
        
        # Extract data rows
        data_rows = data[header_row_idx + 1:]
        
        # Initialize scoring
        score = 0.0
        max_score = 1.0
        feedback_parts = []
        
        # === Criterion 1: Status column exists (0.1 points) ===
        status_col = col_map.get("status")
        if status_col is not None:
            score += 0.1
            feedback_parts.append("✓ Status column found")
        else:
            feedback_parts.append("✗ No 'Status' column found")
            # Try to infer from content
            for idx, cell in enumerate(header_row):
                cell_text = normalize_text(cell)
                if any(keyword in cell_text for keyword in ["flag", "type", "category"]):
                    status_col = idx
                    score += 0.05
                    feedback_parts[-1] = f"⚠ Status-like column found: '{cell}'"
                    break
        
        if status_col is None:
            # Cannot continue verification without status column
            return {
                "passed": False,
                "score": round(score, 2),
                "feedback": " | ".join(feedback_parts) + " | Cannot verify without status indicators"
            }
        
        # === Criterion 2: Service codes column exists (0.05 points) ===
        code_col = col_map.get("service_code") or col_map.get("code")
        if code_col is None:
            # Try to find code column by content
            for idx, cell in enumerate(header_row):
                if "code" in normalize_text(cell):
                    code_col = idx
                    break
        
        if code_col is not None:
            score += 0.05
        
        # Extract statuses and codes
        statuses = []
        codes = []
        for row in data_rows:
            if len(row) > status_col and row[status_col]:
                status = extract_status_value(row[status_col])
                if status:
                    statuses.append(status)
            
            if code_col is not None and len(row) > code_col and row[code_col]:
                codes.append(normalize_text(row[code_col]))
        
        if not statuses:
            return {
                "passed": False,
                "score": round(score, 2),
                "feedback": " | ".join(feedback_parts) + " | Status column is empty"
            }
        
        # === Criterion 3: Has DUPLICATE flag (0.15 points) ===
        has_duplicate = any("DUPLICATE" in s for s in statuses)
        if has_duplicate:
            score += 0.15
            feedback_parts.append("✓ Duplicate charges identified")
        else:
            feedback_parts.append("✗ No duplicate charges flagged")
        
        # === Criterion 4: Has DENIED flag (0.15 points) ===
        has_denied = any("DENIED" in s for s in statuses)
        if has_denied:
            score += 0.15
            feedback_parts.append("✓ Denied items identified")
        else:
            feedback_parts.append("✗ Denied items not identified")
        
        # === Criterion 5: Has DISPUTE flag (0.10 points) ===
        has_dispute = any("DISPUTE" in s for s in statuses)
        if has_dispute:
            score += 0.10
            feedback_parts.append("✓ Disputed items marked")
        else:
            # DISPUTE is optional if items are marked as DENIED
            if has_denied:
                score += 0.05
                feedback_parts.append("⚠ No explicit DISPUTE flag (acceptable if marked DENIED)")
            else:
                feedback_parts.append("✗ No disputed items marked")
        
        # === Criterion 6: Has LEGIT flags (0.15 points) ===
        legit_count = sum(1 for s in statuses if "LEGIT" in s)
        if legit_count >= 4:
            score += 0.15
            feedback_parts.append(f"✓ {legit_count} legitimate charges identified")
        elif legit_count >= 2:
            score += 0.08
            feedback_parts.append(f"⚠ Only {legit_count} legitimate charges (expected ≥4)")
        else:
            feedback_parts.append(f"✗ Only {legit_count} legitimate charges (expected ≥4)")
        
        # === Criterion 7: Duplicate 36415 handled correctly (0.15 points) ===
        code_36415_count = sum(1 for c in codes if "36415" in c)
        if code_36415_count == 1:
            score += 0.15
            feedback_parts.append("✓ Duplicate venipuncture (36415) deduplicated")
        elif code_36415_count == 0:
            score += 0.05
            feedback_parts.append("⚠ Venipuncture code not found (may have been excluded)")
        else:
            feedback_parts.append(f"✗ Duplicate not handled: 36415 appears {code_36415_count} times")
        
        # === Criterion 8: Denied codes (99285, 70470) handled (0.10 points) ===
        denied_codes = ["99285", "70470"]
        denied_in_recon = [code for code in denied_codes if any(code in c for c in codes)]
        
        if len(denied_in_recon) <= 1:  # At most 1 should appear (if marked DENIED)
            score += 0.10
            if len(denied_in_recon) == 0:
                feedback_parts.append("✓ Denied codes excluded from reconciliation")
            else:
                feedback_parts.append(f"✓ Denied code {denied_in_recon[0]} marked (not excluded)")
        else:
            feedback_parts.append(f"✗ Multiple denied codes present: {denied_in_recon}")
        
        # === Criterion 9: Summary calculations exist (0.05 points) ===
        # Look for summary section (usually after data rows, with keywords)
        summary_start_row = len([r for r in data_rows if any(r)])  # Find end of data
        
        amount_to_pay, pay_row = find_summary_value(
            data[header_row_idx:],
            ["amount", "pay"],
            start_row=max(5, summary_start_row)
        )
        
        potential_savings, savings_row = find_summary_value(
            data[header_row_idx:],
            ["saving"],
            start_row=max(5, summary_start_row)
        )
        
        # Also check for "dispute" keyword
        if potential_savings is None:
            potential_savings, savings_row = find_summary_value(
                data[header_row_idx:],
                ["dispute"],
                start_row=max(5, summary_start_row)
            )
        
        if amount_to_pay is not None or potential_savings is not None:
            score += 0.05
            feedback_parts.append("✓ Summary calculations present")
        else:
            feedback_parts.append("✗ No summary calculations found")
        
        # === Criterion 10: Amount to pay is correct ~$381 (0.10 points) ===
        if amount_to_pay is not None:
            # Expected: $125 (ER deductible) + $178 (CT copay) + $78 (medication) = $381
            expected_pay = 381
            tolerance = 50  # Allow some variation in calculation
            
            if abs(amount_to_pay - expected_pay) <= tolerance:
                score += 0.10
                feedback_parts.append(f"✓ Amount to pay correct: ${amount_to_pay:.2f}")
            else:
                score += 0.03
                feedback_parts.append(f"⚠ Amount to pay: ${amount_to_pay:.2f} (expected ~${expected_pay})")
        else:
            feedback_parts.append("✗ Amount to pay not calculated")
        
        # === Criterion 11: Disputed amount calculated (0.05 points) ===
        if potential_savings is not None:
            # Expected: At least $1,000 (duplicate $45 + denied ER $1,124 + denied CT $229 = $1,398)
            if potential_savings >= 1000:
                score += 0.05
                feedback_parts.append(f"✓ Disputed amount: ${potential_savings:.2f}")
            else:
                score += 0.02
                feedback_parts.append(f"⚠ Disputed amount low: ${potential_savings:.2f} (expected ≥$1,000)")
        else:
            feedback_parts.append("⚠ Disputed/savings amount not calculated")
        
        # === Criterion 12: Formulas used (not hardcoded) (0.05 points) ===
        # Check if sheet contains formulas
        has_formulas = False
        for row_idx in range(1, min(recon_sheet.max_row + 1, 100)):
            for col_idx in range(1, min(recon_sheet.max_column + 1, 20)):
                cell = recon_sheet.cell(row=row_idx, column=col_idx)
                if cell.data_type == 'f':  # Formula cell
                    has_formulas = True
                    break
            if has_formulas:
                break
        
        if has_formulas:
            score += 0.05
            feedback_parts.append("✓ Formulas used for calculations")
        else:
            feedback_parts.append("⚠ No formulas detected (may have used manual calculations)")
        
        # === Final scoring ===
        passed = score >= 0.70
        
        return {
            "passed": passed,
            "score": round(score, 2),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)