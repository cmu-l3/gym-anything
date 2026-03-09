#!/usr/bin/env python3
"""
Verifier for Student Loan Refinancing Comparison task
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
    count_filled_cells,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_student_loan_refi_comparison(traj, env_info, task_info):
    """
    Verify that student loan refinancing comparison spreadsheet was created correctly.

    Checks:
    1. File exists and has 3 sheets with correct names
    2. Sheet 1 has 6 loan entries with correct data structure
    3. Sheet 1 has SUM formulas for totals
    4. Sheet 2 has 3 refinancing offers
    5. Sheet 2 has formulas for total cost calculations
    6. Sheet 3 has comparison matrix with 4+ rows
    7. Sheet 3 has comparison/savings calculations
    8. Proper formatting (currency, bold headers)
    9. Contains formulas (not just hardcoded values)
    10. Reasonable calculated values
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/refi_comparison.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_refi_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Could not open refi_comparison.xlsx: {error}"
            }

        feedback = []
        score = 0.0
        max_score = 10.0

        sheet_names = wb.sheetnames
        logger.info(f"Found sheets: {sheet_names}")

        # Criterion 1: Check for required sheets (3 points - 1 per sheet)
        required_sheets = ["Current Loans Analysis", "Refinancing Offers", "Decision Matrix"]
        sheets_found = {}
        
        for required_sheet in required_sheets:
            # Flexible matching (case-insensitive, allows minor variations)
            found = False
            matched_name = None
            for sheet_name in sheet_names:
                if required_sheet.lower().replace(" ", "") in sheet_name.lower().replace(" ", ""):
                    found = True
                    matched_name = sheet_name
                    break
            
            sheets_found[required_sheet] = matched_name if found else None
            
            if found:
                score += 1.0
                feedback.append(f"✅ Sheet '{matched_name}' exists")
            else:
                feedback.append(f"❌ Missing sheet: '{required_sheet}'")

        if score < 2.0:
            # Can't verify further without basic structure
            return {
                "passed": False,
                "score": score / max_score,
                "feedback": " | ".join(feedback)
            }

        # Sheet 1: Current Loans Analysis
        sheet1_name = sheets_found["Current Loans Analysis"]
        if sheet1_name:
            sheet1 = wb[sheet1_name]
            sheet1_data = get_sheet_data(wb, sheet1_name, max_rows=20, max_cols=10)
            
            # Count loan entries (rows with data in first few columns)
            loan_count = 0
            total_balance = 0
            for row_idx in range(1, 15):  # Skip header, check up to row 15
                try:
                    # Check if row has balance data (column B typically)
                    balance_val = sheet1.cell(row_idx + 1, 2).value
                    if balance_val and isinstance(balance_val, (int, float)) and 1000 < balance_val < 20000:
                        loan_count += 1
                        total_balance += balance_val
                except:
                    continue
            
            if loan_count >= 6:
                score += 1.0
                feedback.append(f"✅ Sheet 1 has {loan_count} loan entries")
            elif loan_count >= 4:
                score += 0.5
                feedback.append(f"⚠️ Sheet 1 has {loan_count} loan entries (expected 6)")
            else:
                feedback.append(f"❌ Sheet 1 has only {loan_count} loan entries (need 6)")
            
            # Check for SUM formulas
            has_sum_formula = False
            for row_idx in range(1, 20):
                for col_idx in range(1, 8):
                    try:
                        cell = sheet1.cell(row_idx, col_idx)
                        if cell.data_type == 'f':  # Formula cell
                            formula_str = str(cell.value).upper()
                            if 'SUM' in formula_str:
                                has_sum_formula = True
                                logger.info(f"Found SUM formula at row {row_idx}, col {col_idx}: {formula_str}")
                                break
                    except:
                        continue
                if has_sum_formula:
                    break
            
            if has_sum_formula:
                score += 1.0
                feedback.append("✅ Sheet 1 contains SUM formula(s)")
            else:
                feedback.append("❌ Sheet 1 missing SUM formulas for totals")
            
            # Check if total balance is approximately correct ($63,300)
            if 60000 < total_balance < 66000:
                score += 0.5
                feedback.append(f"✅ Total loan balance is reasonable: ${total_balance:,.0f}")
            else:
                feedback.append(f"⚠️ Total balance seems incorrect: ${total_balance:,.0f}")

        # Sheet 2: Refinancing Offers
        sheet2_name = sheets_found["Refinancing Offers"]
        if sheet2_name:
            sheet2 = wb[sheet2_name]
            
            # Count offer entries
            offer_count = 0
            for row_idx in range(1, 10):
                try:
                    cell_val = sheet2.cell(row_idx + 1, 1).value
                    if cell_val:
                        cell_str = str(cell_val).lower()
                        if 'offer' in cell_str or 'credible' in cell_str or 'sofi' in cell_str or 'common' in cell_str:
                            offer_count += 1
                except:
                    continue
            
            if offer_count >= 3:
                score += 1.0
                feedback.append(f"✅ Sheet 2 has {offer_count} refinancing offers")
            elif offer_count >= 2:
                score += 0.5
                feedback.append(f"⚠️ Sheet 2 has {offer_count} offers (expected 3)")
            else:
                feedback.append(f"❌ Sheet 2 has only {offer_count} offers (need 3)")
            
            # Check for calculation formulas (multiplication for total cost)
            has_formula = False
            for row_idx in range(1, 10):
                for col_idx in range(1, 10):
                    try:
                        cell = sheet2.cell(row_idx, col_idx)
                        if cell.data_type == 'f':  # Formula cell
                            has_formula = True
                            logger.info(f"Found formula in Sheet 2 at row {row_idx}, col {col_idx}")
                            break
                    except:
                        continue
                if has_formula:
                    break
            
            if has_formula:
                score += 1.0
                feedback.append("✅ Sheet 2 contains calculation formulas")
            else:
                feedback.append("❌ Sheet 2 missing formulas (may have hardcoded values)")

        # Sheet 3: Decision Matrix
        sheet3_name = sheets_found["Decision Matrix"]
        if sheet3_name:
            sheet3 = wb[sheet3_name]
            
            # Count comparison rows (should have current + 3 offers = 4 rows minimum)
            row_count = 0
            for row_idx in range(1, 15):
                try:
                    if sheet3.cell(row_idx + 1, 1).value:
                        row_count += 1
                except:
                    continue
            
            if row_count >= 4:
                score += 1.0
                feedback.append(f"✅ Sheet 3 has comparison rows ({row_count} rows)")
            elif row_count >= 3:
                score += 0.5
                feedback.append(f"⚠️ Sheet 3 has {row_count} rows (expected 4+)")
            else:
                feedback.append(f"❌ Sheet 3 incomplete ({row_count} rows, need 4+)")
            
            # Check for comparison calculations (savings, differences)
            has_comparison_calc = False
            for row_idx in range(1, 15):
                for col_idx in range(1, 10):
                    try:
                        cell_val = sheet3.cell(row_idx, col_idx).value
                        # Look for negative numbers (savings) or formulas
                        if isinstance(cell_val, (int, float)) and cell_val < -100:
                            has_comparison_calc = True
                            logger.info(f"Found comparison value: {cell_val}")
                            break
                        # Check for formula cells
                        cell = sheet3.cell(row_idx, col_idx)
                        if cell.data_type == 'f':
                            has_comparison_calc = True
                            break
                    except:
                        continue
                if has_comparison_calc:
                    break
            
            if has_comparison_calc:
                score += 1.0
                feedback.append("✅ Sheet 3 contains comparison calculations")
            else:
                feedback.append("⚠️ Sheet 3 may be missing comparison calculations")

        # Check for currency formatting across all sheets
        has_currency = False
        for sheet_name in [s for s in sheets_found.values() if s]:
            try:
                sheet = wb[sheet_name]
                for row in sheet.iter_rows(max_row=15, max_col=10):
                    for cell in row:
                        if cell.number_format and ('$' in cell.number_format or 'currency' in str(cell.number_format).lower() or '#,##0' in cell.number_format):
                            has_currency = True
                            logger.info(f"Found currency formatting: {cell.number_format}")
                            break
                    if has_currency:
                        break
            except:
                continue
            if has_currency:
                break
        
        if has_currency:
            score += 0.5
            feedback.append("✅ Currency formatting applied")
        else:
            feedback.append("⚠️ No currency formatting detected")

        # Check for bold headers
        has_formatted_headers = False
        for sheet_name in [s for s in sheets_found.values() if s]:
            try:
                sheet = wb[sheet_name]
                for col_idx in range(1, 8):
                    cell = sheet.cell(1, col_idx)
                    if cell.font and cell.font.bold:
                        has_formatted_headers = True
                        logger.info(f"Found bold header in {sheet_name}")
                        break
            except:
                continue
            if has_formatted_headers:
                break
        
        if has_formatted_headers:
            score += 0.5
            feedback.append("✅ Headers are formatted (bold)")
        else:
            feedback.append("⚠️ Headers not formatted")

        # Bonus: Check for note about federal protections
        if sheet3_name:
            has_fed_note = False
            sheet3 = wb[sheet3_name]
            for row_idx in range(1, 20):
                for col_idx in range(1, 10):
                    try:
                        cell_val = sheet3.cell(row_idx, col_idx).value
                        if cell_val and isinstance(cell_val, str):
                            cell_lower = cell_val.lower()
                            if 'federal' in cell_lower and ('protection' in cell_lower or 'refinanc' in cell_lower or 'los' in cell_lower):
                                has_fed_note = True
                                score += 0.5
                                feedback.append("✅ Includes note about federal loan protections")
                                break
                    except:
                        continue
                if has_fed_note:
                    break

        # Final scoring
        passed = score >= 7.0  # Need 70% to pass
        final_feedback = " | ".join(feedback)
        
        logger.info(f"Final score: {score}/{max_score} ({score/max_score*100:.1f}%)")
        logger.info(f"Passed: {passed}")

        return {
            "passed": passed,
            "score": score / max_score,
            "feedback": final_feedback
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