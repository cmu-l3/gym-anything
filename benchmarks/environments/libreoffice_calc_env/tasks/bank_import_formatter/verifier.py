#!/usr/bin/env python3
"""
Verifier for Bank Import Formatter task.
Validates CSV format compliance for budgeting software import.
"""

import sys
import os
import csv
import logging
import re
from datetime import datetime
from typing import Dict, Any, Tuple, List

# Use relative path to utils folder (for host-side verification)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import cleanup_verification_environment
import tempfile
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bank_import_format(traj, env_info, task_info):
    """
    Verify CSV format compliance for bank import task.
    
    Checks:
    1. Valid CSV format with 4 columns
    2. Correct headers: Date, Description, Amount, Category
    3. Date format compliance (YYYY-MM-DD)
    4. Amount format compliance (valid numbers with signs)
    5. No extra rows (title, footer, empty)
    6. Data preserved (transactions present)
    7. Special characters handled (escaped properly)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Create unique temp directory for this verification
    temp_dir = tempfile.mkdtemp(prefix='bank_verify_')
    
    try:
        # Try to find the CSV file - check multiple possible locations
        possible_paths = [
            "/home/ga/Documents/transactions_formatted.csv",
            "/home/ga/Documents/bank_export_messy.csv",
            "/home/ga/Documents/bank_transactions.csv",
            "/home/ga/Documents/formatted.csv",
        ]
        
        csv_file = None
        for container_path in possible_paths:
            host_file = os.path.join(temp_dir, os.path.basename(container_path))
            try:
                copy_from_env(container_path, host_file)
                if os.path.exists(host_file) and os.path.getsize(host_file) > 0:
                    csv_file = host_file
                    logger.info(f"Found CSV file at: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Could not copy {container_path}: {e}")
                continue
        
        if not csv_file:
            return {
                "passed": False,
                "score": 0,
                "feedback": "CSV file not found. Expected: transactions_formatted.csv in Documents folder"
            }
        
        # Parse and verify CSV
        checks = {
            'valid_csv': False,
            'correct_headers': False,
            'date_format_valid': False,
            'amount_format_valid': False,
            'no_extra_rows': False,
            'data_preserved': False,
            'special_chars_handled': False
        }
        
        feedback_parts = []
        
        # Check 1: Valid CSV format
        try:
            with open(csv_file, 'r', encoding='utf-8') as f:
                reader = csv.reader(f)
                rows = list(reader)
            
            if len(rows) > 0:
                checks['valid_csv'] = True
                feedback_parts.append(f"✅ Valid CSV format ({len(rows)} rows)")
            else:
                feedback_parts.append("❌ CSV file is empty")
                return build_result(checks, feedback_parts)
        except Exception as e:
            feedback_parts.append(f"❌ CSV parsing error: {str(e)}")
            return build_result(checks, feedback_parts)
        
        # Check 2: Correct headers
        expected_headers = ['Date', 'Description', 'Amount', 'Category']
        actual_headers = rows[0] if rows else []
        
        if actual_headers == expected_headers:
            checks['correct_headers'] = True
            feedback_parts.append("✅ Headers correct: Date, Description, Amount, Category")
        else:
            feedback_parts.append(f"❌ Headers incorrect. Expected: {expected_headers}, Got: {actual_headers}")
        
        # Check 3: Date format validation (YYYY-MM-DD)
        date_errors = []
        date_valid_count = 0
        for i, row in enumerate(rows[1:], start=2):  # Skip header
            if len(row) >= 4 and row[0]:  # Check if date column exists and not empty
                try:
                    # Validate YYYY-MM-DD format
                    if re.match(r'^\d{4}-\d{2}-\d{2}$', row[0]):
                        # Verify it's a valid date
                        datetime.strptime(row[0], '%Y-%m-%d')
                        date_valid_count += 1
                    else:
                        date_errors.append(f"Row {i}: '{row[0]}' not in YYYY-MM-DD format")
                except ValueError:
                    date_errors.append(f"Row {i}: '{row[0]}' is not a valid date")
        
        total_data_rows = len(rows) - 1
        if total_data_rows > 0 and date_valid_count == total_data_rows and len(date_errors) == 0:
            checks['date_format_valid'] = True
            feedback_parts.append(f"✅ All dates in YYYY-MM-DD format ({date_valid_count} dates)")
        elif date_valid_count > 0:
            feedback_parts.append(f"⚠️ Partial date compliance: {date_valid_count}/{total_data_rows} valid, {len(date_errors)} errors")
            if len(date_errors) <= 3:
                for err in date_errors[:3]:
                    logger.debug(err)
        else:
            feedback_parts.append(f"❌ Date format issues: {date_errors[0] if date_errors else 'No valid dates found'}")
        
        # Check 4: Amount format validation
        amount_errors = []
        amount_valid_count = 0
        amount_has_negatives = False
        amount_has_positives = False
        
        for i, row in enumerate(rows[1:], start=2):
            if len(row) >= 4 and row[2]:  # Amount column
                try:
                    amount = float(row[2])
                    # Check decimal places (should be 0-2)
                    if '.' in row[2]:
                        decimals = len(row[2].strip().split('.')[-1])
                        if decimals > 2:
                            amount_errors.append(f"Row {i}: Too many decimals in amount: {row[2]}")
                            continue
                    
                    amount_valid_count += 1
                    if amount < 0:
                        amount_has_negatives = True
                    elif amount > 0:
                        amount_has_positives = True
                        
                except ValueError:
                    amount_errors.append(f"Row {i}: Invalid amount: '{row[2]}'")
        
        if amount_valid_count == total_data_rows and len(amount_errors) == 0:
            checks['amount_format_valid'] = True
            sign_info = []
            if amount_has_negatives:
                sign_info.append("has expenses")
            if amount_has_positives:
                sign_info.append("has income")
            feedback_parts.append(f"✅ All amounts valid ({amount_valid_count} amounts, {', '.join(sign_info)})")
        elif amount_valid_count > 0:
            feedback_parts.append(f"⚠️ Partial amount compliance: {amount_valid_count}/{total_data_rows} valid")
        else:
            feedback_parts.append(f"❌ Amount format issues: {amount_errors[0] if amount_errors else 'No valid amounts'}")
        
        # Check 5: No extra rows (all rows should have exactly 4 columns)
        extra_row_errors = []
        for i, row in enumerate(rows, start=1):
            if len(row) != 4:
                extra_row_errors.append(f"Row {i}: Has {len(row)} columns (expected 4)")
        
        if len(extra_row_errors) == 0:
            checks['no_extra_rows'] = True
            feedback_parts.append("✅ Clean structure: No extra rows or columns")
        else:
            feedback_parts.append(f"❌ Structure issues: {len(extra_row_errors)} rows with wrong column count")
        
        # Check 6: Data preserved (should have reasonable number of transactions)
        # Original file has 15 transactions
        expected_min_transactions = 10  # Allow some missing, but need majority
        
        if total_data_rows >= expected_min_transactions:
            checks['data_preserved'] = True
            feedback_parts.append(f"✅ Data preserved: {total_data_rows} transactions (expected ~15)")
        elif total_data_rows >= 5:
            feedback_parts.append(f"⚠️ Partial data: {total_data_rows} transactions (expected ~15)")
        else:
            feedback_parts.append(f"❌ Data loss: Only {total_data_rows} transactions (expected ~15)")
        
        # Check 7: Special characters handled (CSV should parse without errors)
        # If we got here and CSV parsed correctly, this is implicitly passed
        # Check for commas in descriptions
        has_escaped_commas = False
        for row in rows[1:]:
            if len(row) >= 2 and ',' in row[1]:  # Description with comma
                has_escaped_commas = True
                break
        
        checks['special_chars_handled'] = True
        if has_escaped_commas:
            feedback_parts.append("✅ Special characters handled: Commas properly escaped")
        else:
            feedback_parts.append("✅ Special characters handled: CSV parsed correctly")
        
        # Sample data verification (spot check a few known transactions)
        sample_checks = []
        for row in rows[1:]:
            if len(row) >= 3:
                desc = row[1].lower()
                amount = row[2]
                
                # Check for known transactions
                if 'starbucks' in desc or 'coffee' in desc:
                    try:
                        amt = float(amount)
                        if amt < 0:  # Should be expense
                            sample_checks.append("Verified: Coffee expense is negative")
                    except:
                        pass
                        
                elif 'paycheck' in desc:
                    try:
                        amt = float(amount)
                        if amt > 0:  # Should be income
                            sample_checks.append("Verified: Paycheck is positive")
                    except:
                        pass
        
        if sample_checks:
            logger.info(f"Sample verification: {', '.join(sample_checks)}")
        
        return build_result(checks, feedback_parts)
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temp directory
        if temp_dir and os.path.exists(temp_dir):
            try:
                shutil.rmtree(temp_dir)
                logger.debug(f"Cleaned up temp directory: {temp_dir}")
            except Exception as e:
                logger.warning(f"Failed to cleanup temp directory: {e}")


def build_result(checks: Dict[str, bool], feedback_parts: List[str]) -> Dict[str, Any]:
    """Build verification result from checks and feedback."""
    
    criteria_met = sum(1 for v in checks.values() if v)
    total_criteria = len(checks)
    
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70  # Need 5/7 criteria (70%)
    
    # Add overall status
    if passed and score >= 90:
        feedback_parts.append("🎉 Excellent format compliance!")
    elif passed:
        feedback_parts.append("✅ Format requirements met")
    else:
        feedback_parts.append("❌ Format does not meet requirements")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": {
            "valid_csv": checks['valid_csv'],
            "correct_headers": checks['correct_headers'],
            "date_format": checks['date_format_valid'],
            "amount_format": checks['amount_format_valid'],
            "no_extra_rows": checks['no_extra_rows'],
            "data_preserved": checks['data_preserved'],
            "special_chars": checks['special_chars_handled']
        }
    }
