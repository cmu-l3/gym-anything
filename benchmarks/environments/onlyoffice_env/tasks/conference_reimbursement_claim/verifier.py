#!/usr/bin/env python3
"""
Verifier for Conference Reimbursement Claim task

Verifies that the agent created a properly formatted reimbursement spreadsheet
with currency conversion, categorization, caps applied, non-reimbursable items
flagged, and summary calculations.
"""

import sys
import os
import logging
import tempfile
import re
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_number(value: Any) -> Optional[float]:
    """
    Extract numeric value from cell, handling $, CAD, commas, and various formats
    """
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        # Remove $, CAD, commas, and convert
        cleaned = value.replace('$', '').replace('CAD', '').replace(',', '').strip()
        try:
            return float(cleaned)
        except:
            return None
    return None


def find_column_index(headers: List[str], keywords: List[str]) -> Optional[int]:
    """
    Find column index that contains any of the keywords (case-insensitive)
    """
    headers_lower = [str(h).lower() if h else '' for h in headers]
    for i, header in enumerate(headers_lower):
        for keyword in keywords:
            if keyword.lower() in header:
                return i
    return None


def contains_formula(sheet: Any, row: int, col: int) -> bool:
    """
    Check if a cell contains a formula
    """
    try:
        cell = sheet.cell(row=row, column=col)
        # Check if cell has a formula (starts with =)
        if hasattr(cell, 'value') and isinstance(cell.value, str) and cell.value.startswith('='):
            return True
        # For openpyxl, check if it's a formula cell
        if hasattr(cell, 'data_type') and cell.data_type == 'f':
            return True
        return False
    except:
        return False


def verify_conference_reimbursement(traj, env_info, task_info):
    """
    Verify conference reimbursement claim spreadsheet.
    
    Scoring (100 points total):
    - File existence and structure: 10 pts
    - Currency conversion accuracy: 15 pts
    - Categorization correctness: 15 pts
    - Cap logic applied: 20 pts
    - Non-reimbursable items handling: 20 pts
    - Summary calculations: 15 pts
    - Receipt cross-referencing: 5 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    # First try the expected output file, then fall back to raw file (in case agent modified in place)
    filepath = "/home/ga/Documents/Spreadsheets/reimbursement_claim_final.xlsx"
    fallback_path = "/home/ga/Documents/Spreadsheets/conference_receipts_raw.xlsx"
    
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_reimbursement_')

    try:
        # Try main file first
        success, wb, error = copy_and_parse_document(filepath, copy_from_env, 'xlsx')
        
        if not success:
            # Try fallback
            logger.info(f"Primary file not found, trying fallback: {fallback_path}")
            success, wb, error = copy_and_parse_document(fallback_path, copy_from_env, 'xlsx')
            if not success:
                return {
                    "passed": False,
                    "score": 0.0,
                    "feedback": f"Could not open reimbursement file: {error}"
                }
        
        score = 0
        feedback = []
        
        # Get active sheet and data
        sheet = wb.active
        
        # Get all data (first 50 rows, 15 columns should be enough)
        all_data = []
        for row in sheet.iter_rows(min_row=1, max_row=50, max_col=15, values_only=True):
            if any(cell is not None for cell in row):
                all_data.append(row)
        
        if len(all_data) < 2:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Spreadsheet appears empty or has insufficient data"
            }
        
        # Extract headers (first row)
        headers = [str(cell).lower() if cell else '' for cell in all_data[0]]
        
        # ===================================================================
        # CHECK 1: File Structure (10 points)
        # ===================================================================
        structure_score = 0
        
        # Look for required column types
        required_keywords = {
            'date': ['date', 'day'],
            'vendor': ['vendor', 'description', 'desc', 'merchant'],
            'category': ['category', 'type', 'cat'],
            'amount_cad': ['cad', 'amount cad', 'amt cad'],
            'amount_usd': ['usd', 'amount usd', 'amt usd', 'us dollar'],
            'eligible': ['eligible', 'reimburs', 'approved', 'allowed'],
            'receipt': ['receipt', 'receipt#', 'receipt id', 'ref']
        }
        
        found_columns = {}
        for key, keywords in required_keywords.items():
            idx = find_column_index(headers, keywords)
            found_columns[key] = idx
        
        # Count how many required columns found
        required_found = sum(1 for v in found_columns.values() if v is not None)
        
        if required_found >= 5:
            structure_score = 10
            feedback.append(f"✅ Required columns present ({required_found}/7)")
        elif required_found >= 3:
            structure_score = 5
            feedback.append(f"⚠️ Some required columns present ({required_found}/7)")
        else:
            feedback.append(f"❌ Missing required columns (found {required_found}/7)")
        
        # Check for sufficient data rows (at least 10 receipts)
        data_rows = [row for row in all_data[1:30] if any(cell for cell in row)]
        if len(data_rows) >= 10:
            feedback.append(f"✅ Sufficient data rows ({len(data_rows)})")
        else:
            feedback.append(f"⚠️ Only {len(data_rows)} data rows (expected ~15)")
        
        score += structure_score
        
        # ===================================================================
        # CHECK 2: Currency Conversion Accuracy (15 points)
        # ===================================================================
        conversion_score = 0
        
        cad_col = found_columns.get('amount_cad')
        usd_col = found_columns.get('amount_usd')
        
        if cad_col is not None and usd_col is not None:
            conversion_checks = 0
            conversion_passed = 0
            
            for row_data in data_rows[:10]:  # Check first 10 rows
                if len(row_data) > max(cad_col, usd_col):
                    cad_val = extract_number(row_data[cad_col])
                    usd_val = extract_number(row_data[usd_col])
                    
                    if cad_val is not None and usd_val is not None and cad_val > 0:
                        conversion_checks += 1
                        expected_usd = cad_val * 0.74
                        
                        # Allow 2% tolerance for rounding
                        if abs(usd_val - expected_usd) <= max(0.50, expected_usd * 0.02):
                            conversion_passed += 1
            
            if conversion_checks > 0:
                conversion_rate = conversion_passed / conversion_checks
                if conversion_rate >= 0.8:
                    conversion_score = 15
                    feedback.append(f"✅ Currency conversion accurate ({conversion_passed}/{conversion_checks})")
                elif conversion_rate >= 0.5:
                    conversion_score = 10
                    feedback.append(f"⚠️ Most conversions correct ({conversion_passed}/{conversion_checks})")
                else:
                    conversion_score = 5
                    feedback.append(f"❌ Currency conversion has errors ({conversion_passed}/{conversion_checks})")
            else:
                feedback.append("⚠️ Could not verify currency conversion (no valid data)")
        else:
            feedback.append("❌ Missing CAD or USD columns for conversion check")
        
        score += conversion_score
        
        # ===================================================================
        # CHECK 3: Categorization Correctness (15 points)
        # ===================================================================
        categorization_score = 0
        
        cat_col = found_columns.get('category')
        vendor_col = found_columns.get('vendor')
        
        if cat_col is not None:
            categories_found = set()
            airfare_found = False
            lodging_found = False
            transport_found = False
            meals_found = False
            conference_found = False
            
            for row_data in data_rows:
                if len(row_data) > cat_col and row_data[cat_col]:
                    cat = str(row_data[cat_col]).lower()
                    categories_found.add(cat)
                    
                    # Check for specific categories
                    if any(keyword in cat for keyword in ['air', 'flight']):
                        airfare_found = True
                    if any(keyword in cat for keyword in ['lodg', 'hotel', 'accommodation']):
                        lodging_found = True
                    if any(keyword in cat for keyword in ['transport', 'taxi', 'ground']):
                        transport_found = True
                    if any(keyword in cat for keyword in ['meal', 'food', 'breakfast', 'lunch', 'dinner']):
                        meals_found = True
                    if any(keyword in cat for keyword in ['conference', 'registration', 'fee']):
                        conference_found = True
            
            required_categories = [airfare_found, lodging_found, transport_found, meals_found]
            categories_present = sum(required_categories)
            
            if categories_present >= 4:
                categorization_score = 15
                feedback.append(f"✅ Proper categorization (all 4 main categories present)")
            elif categories_present >= 3:
                categorization_score = 10
                feedback.append(f"⚠️ Most categories present ({categories_present}/4)")
            elif categories_present >= 2:
                categorization_score = 5
                feedback.append(f"⚠️ Incomplete categorization ({categories_present}/4)")
            else:
                feedback.append(f"❌ Categorization missing or incorrect")
        else:
            feedback.append("❌ Category column not found")
        
        score += categorization_score
        
        # ===================================================================
        # CHECK 4: Cap Logic Applied (20 points)
        # ===================================================================
        cap_score = 0
        
        eligible_col = found_columns.get('eligible')
        
        if cat_col is not None and eligible_col is not None and usd_col is not None:
            # Check lodging caps ($180 per night)
            lodging_rows = []
            meal_rows = []
            
            for i, row_data in enumerate(data_rows):
                if len(row_data) > max(cat_col, eligible_col, usd_col):
                    cat = str(row_data[cat_col]).lower() if row_data[cat_col] else ''
                    eligible_val = extract_number(row_data[eligible_col])
                    usd_val = extract_number(row_data[usd_col])
                    
                    if 'lodg' in cat or 'hotel' in cat:
                        lodging_rows.append({
                            'usd': usd_val,
                            'eligible': eligible_val
                        })
                    elif 'meal' in cat or 'breakfast' in cat or 'lunch' in cat or 'dinner' in cat or 'food' in cat:
                        meal_rows.append({
                            'usd': usd_val,
                            'eligible': eligible_val
                        })
            
            # Check lodging cap ($180/night)
            lodging_cap_applied = True
            for lodging in lodging_rows:
                if lodging['eligible'] is not None:
                    # Eligible should not exceed $180 or the USD amount (whichever is smaller)
                    if lodging['usd'] is not None:
                        expected_max = min(180.0, lodging['usd'])
                        if lodging['eligible'] > expected_max + 1:  # 1 dollar tolerance
                            lodging_cap_applied = False
                            break
            
            if lodging_cap_applied and len(lodging_rows) > 0:
                cap_score += 10
                feedback.append(f"✅ Lodging caps applied correctly ({len(lodging_rows)} lodging entries)")
            elif len(lodging_rows) > 0:
                cap_score += 5
                feedback.append(f"⚠️ Lodging cap logic may have issues")
            else:
                feedback.append("⚠️ No lodging entries found to verify cap")
            
            # Check meal total cap ($45/day × 4 days = $180)
            meal_total_eligible = sum(m['eligible'] for m in meal_rows if m['eligible'] is not None)
            
            if meal_total_eligible > 0:
                # Should be at most $180 (4 days × $45)
                if meal_total_eligible <= 185:  # Small tolerance
                    cap_score += 10
                    feedback.append(f"✅ Meal per-diem cap respected (${meal_total_eligible:.2f} ≤ $180)")
                else:
                    cap_score += 3
                    feedback.append(f"⚠️ Meal total ${meal_total_eligible:.2f} may exceed $180 cap")
            else:
                feedback.append("⚠️ No meal eligible amounts found")
        else:
            feedback.append("❌ Cannot verify caps (missing columns)")
        
        score += cap_score
        
        # ===================================================================
        # CHECK 5: Non-Reimbursable Items Handling (20 points)
        # ===================================================================
        non_reimb_score = 0
        
        # Look for notes/flags column
        notes_col = find_column_index(headers, ['note', 'notes', 'flag', 'flags', 'comment', 'reason'])
        
        # Items that should be flagged or excluded:
        # 1. Dinner with alcohol (Bistro Laurent)
        # 2. Sunday night hotel (May 21, personal)
        # 3. Book purchase
        # 4. Dinner with missing receipt
        
        flagged_items = []
        sunday_hotel_handled = False
        alcohol_handled = False
        book_handled = False
        
        for i, row_data in enumerate(data_rows):
            if len(row_data) > vendor_col if vendor_col is not None else 0:
                vendor = str(row_data[vendor_col]).lower() if vendor_col and row_data[vendor_col] else ''
                notes = str(row_data[notes_col]).lower() if notes_col and len(row_data) > notes_col and row_data[notes_col] else ''
                eligible = extract_number(row_data[eligible_col]) if eligible_col and len(row_data) > eligible_col else None
                
                # Check if this row has a non-reimbursable flag
                is_flagged = any(keyword in notes for keyword in [
                    'non-reimb', 'not reimb', 'excluded', 'personal', 'alcohol', 'wine', 'not eligible'
                ])
                
                # Or if eligible amount is 0 or blank (indicating exclusion)
                is_excluded = eligible is None or eligible == 0
                
                # Check specific cases
                if 'sunday' in vendor or 'may 21' in vendor or 'night 4' in vendor:
                    if 'hotel' in vendor or 'bonaventure' in vendor:
                        if is_flagged or is_excluded or 'personal' in notes:
                            sunday_hotel_handled = True
                            flagged_items.append('Sunday hotel')
                
                if 'bistro' in vendor or 'laurent' in vendor or ('dinner' in vendor and 'may 18' in vendor):
                    if 'wine' in notes or 'alcohol' in notes or is_flagged:
                        alcohol_handled = True
                        flagged_items.append('Alcohol dinner')
                
                if 'book' in vendor or 'textbook' in vendor:
                    if is_flagged or is_excluded or 'non-reimb' in notes:
                        book_handled = True
                        flagged_items.append('Book purchase')
        
        # Count how many non-reimbursable items were properly handled
        non_reimb_handled = sum([sunday_hotel_handled, alcohol_handled, book_handled])
        
        if non_reimb_handled >= 3:
            non_reimb_score = 20
            feedback.append(f"✅ All 3 non-reimbursable items handled: {', '.join(flagged_items)}")
        elif non_reimb_handled == 2:
            non_reimb_score = 13
            feedback.append(f"⚠️ 2/3 non-reimbursable items handled: {', '.join(flagged_items)}")
        elif non_reimb_handled == 1:
            non_reimb_score = 7
            feedback.append(f"⚠️ Only 1/3 non-reimbursable item handled: {', '.join(flagged_items)}")
        else:
            feedback.append("❌ Non-reimbursable items not properly identified")
        
        score += non_reimb_score
        
        # ===================================================================
        # CHECK 6: Summary Calculations (15 points)
        # ===================================================================
        summary_score = 0
        
        # Look for summary section (usually in bottom rows or specific cells)
        summary_found = False
        total_eligible = None
        total_cad = None
        total_usd = None
        total_non_reimb = None
        
        # Search all rows for summary keywords
        for i, row_data in enumerate(all_data):
            if row_data and row_data[0]:
                cell_text = str(row_data[0]).lower()
                
                # Look for various summary labels
                if 'total eligible' in cell_text or 'eligible total' in cell_text or 'reimbursement total' in cell_text:
                    # Value should be in next column
                    if len(row_data) > 1:
                        total_eligible = extract_number(row_data[1])
                        summary_found = True
                
                if 'total cad' in cell_text or 'cad total' in cell_text:
                    if len(row_data) > 1:
                        total_cad = extract_number(row_data[1])
                
                if 'total usd' in cell_text or 'usd total' in cell_text:
                    if len(row_data) > 1:
                        total_usd = extract_number(row_data[1])
                
                if 'non-reimb' in cell_text or 'not eligible' in cell_text or 'excluded' in cell_text:
                    if 'total' in cell_text and len(row_data) > 1:
                        total_non_reimb = extract_number(row_data[1])
        
        if summary_found and total_eligible is not None:
            # Expected eligible: approximately $1,050-$1,150 USD
            # Airfare: $895 CAD * 0.74 = $662 USD
            # Hotel: 3 nights capped at $180 = $540 USD (night 1 over cap, night 4 personal)
            # Transport: $22.50 CAD * 0.74 = $16.65 USD
            # Meals: ~$134.50 CAD * 0.74 = ~$100 USD (within $180 cap)
            # Conference: $350 CAD * 0.74 = $259 USD
            # Total: ~$1,077 USD (reasonable range: $1,000-$1,200)
            
            if 1000 <= total_eligible <= 1200:
                summary_score += 15
                feedback.append(f"✅ Summary total ${total_eligible:.2f} in expected range ($1,000-$1,200)")
            elif 900 <= total_eligible <= 1300:
                summary_score += 10
                feedback.append(f"⚠️ Summary total ${total_eligible:.2f} close to expected range")
            else:
                summary_score += 5
                feedback.append(f"⚠️ Summary total ${total_eligible:.2f} outside expected range ($1,000-$1,200)")
        else:
            feedback.append("❌ Summary section not found or incomplete")
        
        score += summary_score
        
        # ===================================================================
        # CHECK 7: Receipt Cross-Referencing (5 points)
        # ===================================================================
        receipt_score = 0
        
        receipt_col = found_columns.get('receipt')
        
        if receipt_col is not None:
            receipts_present = 0
            receipts_checked = 0
            
            for row_data in data_rows:
                if len(row_data) > receipt_col:
                    receipts_checked += 1
                    if row_data[receipt_col] and str(row_data[receipt_col]).strip():
                        receipt_val = str(row_data[receipt_col])
                        # Check if it looks like a receipt ID (R001, R002, etc.)
                        if 'R' in receipt_val or receipt_val.isdigit() or len(receipt_val) >= 3:
                            receipts_present += 1
            
            if receipts_checked > 0:
                receipt_rate = receipts_present / receipts_checked
                if receipt_rate >= 0.85:  # At least 85% have receipt IDs
                    receipt_score = 5
                    feedback.append(f"✅ Receipt IDs documented ({receipts_present}/{receipts_checked})")
                elif receipt_rate >= 0.60:
                    receipt_score = 3
                    feedback.append(f"⚠️ Most receipt IDs present ({receipts_present}/{receipts_checked})")
                else:
                    receipt_score = 1
                    feedback.append(f"⚠️ Many missing receipt IDs ({receipts_present}/{receipts_checked})")
        else:
            feedback.append("⚠️ Receipt ID column not found")
        
        score += receipt_score
        
        # ===================================================================
        # Final Evaluation
        # ===================================================================
        passed = score >= 70
        feedback_str = " | ".join(feedback)
        
        return {
            "passed": passed,
            "score": score / 100.0,
            "feedback": f"Score: {score}/100. {feedback_str}"
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
