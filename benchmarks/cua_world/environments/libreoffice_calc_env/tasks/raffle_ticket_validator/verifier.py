#!/usr/bin/env python3
"""
Verifier for Raffle Ticket Validator task
Checks duplicate detection, count calculations, validation flags, top seller identification, and final totals
"""

import sys
import os
import re
import logging
from typing import Dict, List, Tuple, Any, Optional

# Add utils to path - use relative path for host machine execution
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_ticket_range(range_str: str) -> int:
    """
    Parse ticket range notation and return count.
    Examples:
      "0100-0125" -> 26 (inclusive: 125-100+1)
      "0045" -> 1
      "0010, 0011-0015" -> 6
    """
    if not range_str or range_str.strip() == '':
        return 0
    
    total = 0
    range_str = str(range_str).replace(';', ',')
    
    # Split by comma for mixed formats
    parts = [p.strip() for p in range_str.split(',')]
    
    for part in parts:
        if '-' in part and part.count('-') == 1:
            # Range notation
            try:
                left, right = part.split('-')
                start = int(left.strip())
                end = int(right.strip())
                count = max(0, end - start + 1)  # Inclusive
                total += count
            except (ValueError, AttributeError):
                continue
        elif part.strip():
            # Individual ticket
            try:
                int(part.strip())  # Validate it's a number
                total += 1
            except ValueError:
                continue
    
    return total


def expand_ticket_range(range_str: str) -> List[int]:
    """
    Expand ticket range into list of individual ticket numbers.
    "0100-0125" -> [100, 101, ..., 125]
    "0067" -> [67]
    """
    if not range_str or range_str.strip() == '':
        return []
    
    tickets = []
    range_str = str(range_str).replace(';', ',')
    parts = [p.strip() for p in range_str.split(',')]
    
    for part in parts:
        if '-' in part and part.count('-') == 1:
            try:
                left, right = part.split('-')
                start = int(left.strip())
                end = int(right.strip())
                if start <= end:
                    tickets.extend(range(start, end + 1))
            except (ValueError, AttributeError):
                continue
        elif part.strip():
            try:
                tickets.append(int(part.strip()))
            except ValueError:
                continue
    
    return tickets


def check_for_duplicates(seller_tickets: List[Tuple[str, str]]) -> Dict[str, List[str]]:
    """
    Check for duplicate tickets across all sellers.
    Returns dict mapping ticket number to list of sellers who have it.
    """
    ticket_to_sellers = {}
    
    for seller_name, tickets_str in seller_tickets:
        tickets = expand_ticket_range(tickets_str)
        for ticket in tickets:
            if ticket not in ticket_to_sellers:
                ticket_to_sellers[ticket] = []
            ticket_to_sellers[ticket].append(seller_name)
    
    # Return only duplicates
    return {t: sellers for t, sellers in ticket_to_sellers.items() if len(sellers) > 1}


def is_invalid_range(range_str: str) -> Tuple[bool, str]:
    """
    Check if a range is invalid.
    Returns (is_invalid, reason)
    """
    if not range_str or range_str.strip() == '':
        return True, "missing_data"
    
    range_str = str(range_str).replace(';', ',')
    parts = [p.strip() for p in range_str.split(',')]
    
    for part in parts:
        if '-' in part and part.count('-') == 1:
            try:
                left, right = part.split('-')
                start = int(left.strip())
                end = int(right.strip())
                
                if end < start:
                    return True, "backwards_range"
                if end > 500:  # Beyond max ticket
                    return True, "beyond_max"
                if (end - start + 1) > 100:  # Suspiciously large
                    return True, "too_large"
            except (ValueError, AttributeError):
                return True, "parse_error"
    
    return False, ""


def find_column_by_keywords(sheet_data: Dict, keywords: List[str]) -> Optional[int]:
    """
    Find column index by searching for keywords in header row.
    Returns 0-indexed column number or None.
    """
    if 'sheets' not in sheet_data:
        return None
    
    sheets = sheet_data['sheets']
    if not sheets:
        return None
    
    first_sheet = list(sheets.values())[0]
    if not first_sheet or len(first_sheet) == 0:
        return None
    
    header_row = first_sheet[0]
    
    for col_idx, cell in enumerate(header_row):
        cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
        cell_str = str(cell_value).lower().strip()
        
        for keyword in keywords:
            if keyword.lower() in cell_str:
                return col_idx
    
    return None


def verify_raffle_validator(traj, env_info, task_info):
    """
    Verify raffle ticket validator task completion.
    
    Checks:
    1. Duplicate detection column exists and identifies known duplicates
    2. Ticket count calculations are accurate
    3. Validation flags for invalid entries
    4. Top sellers correctly identified
    5. Final verified total is approximately correct
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file locations
    temp_dir = None
    success = False
    file_info = None
    
    for path in ["/home/ga/Documents/raffle_validated.ods",
                 "/home/ga/Documents/raffle_sales_raw.ods",
                 "/home/ga/Documents/raffle_sales_raw.csv"]:
        file_ext = path.split('.')[-1]
        formats = ['ods'] if file_ext == 'ods' else ['csv', 'ods']
        
        success, file_info, error = setup_calc_verification(
            copy_from_env, path, formats
        )
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load raffle data file: {error}"
        }
    
    try:
        sheet_data = file_info.get('sheet_data', {})
        sheets = sheet_data.get('sheets', {})
        
        if not sheets:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = list(sheets.keys())[0]
        sheet_rows = sheets[sheet_name]
        
        if len(sheet_rows) < 2:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Insufficient data rows in spreadsheet"
            }
        
        # Initialize scoring
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        subscores = {}
        
        # Extract original data from first 4 columns
        seller_data = []
        for i in range(1, min(len(sheet_rows), 13)):  # Skip header, max 12 sellers
            row = sheet_rows[i]
            if len(row) < 2:
                continue
            
            seller_name = row[0].get('value', '') if isinstance(row[0], dict) else str(row[0])
            tickets_sold = row[1].get('value', '') if isinstance(row[1], dict) else str(row[1])
            
            if seller_name and str(seller_name).strip():
                seller_data.append((str(seller_name).strip(), str(tickets_sold).strip()))
        
        # Known test data from original CSV
        known_duplicates = {
            'Martinez_0067': ('Martinez', '0067'),  # Overlaps with Johnson 0050-0075
            'Chen_duplicate': ('Chen', '0300-0324'),  # Appears twice
        }
        
        known_invalid = {
            'Lee_backwards': ('Lee', '0350-0295'),  # End before start
            'Davis_missing': ('Davis', ''),  # No ticket data
        }
        
        # Expected top sellers (by verified count)
        expected_top_sellers = ['Rodriguez', 'Patel', "O'Brien"]
        
        # ===== CRITERION 1: Duplicate Detection =====
        duplicate_col = find_column_by_keywords(sheet_data, [
            'duplicate', 'dup', 'overlap', 'duplicate flag', 'dup flag'
        ])
        
        duplicate_detected = False
        if duplicate_col is not None:
            # Check if known duplicates are flagged
            duplicates_found = 0
            
            # Check for Martinez (row 4, 0-indexed row 4)
            if len(sheet_rows) > 4 and duplicate_col < len(sheet_rows[4]):
                cell = sheet_rows[4][duplicate_col]
                cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).upper()
                if 'DUP' in cell_val or 'OVERLAP' in cell_val or 'YES' in cell_val:
                    duplicates_found += 1
            
            # Check for Chen duplicate (row 10, 0-indexed row 10)
            if len(sheet_rows) > 10 and duplicate_col < len(sheet_rows[10]):
                cell = sheet_rows[10][duplicate_col]
                cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).upper()
                if 'DUP' in cell_val or 'OVERLAP' in cell_val or 'YES' in cell_val:
                    duplicates_found += 1
            
            if duplicates_found >= 1:  # At least one duplicate found
                criteria_passed += 1
                duplicate_detected = True
                feedback_parts.append(f"✅ Duplicate detection column exists ({duplicates_found} known duplicates flagged)")
            else:
                feedback_parts.append("⚠️ Duplicate column exists but known duplicates not flagged")
        else:
            feedback_parts.append("❌ No duplicate detection column found")
        
        subscores['duplicate_detection'] = duplicate_detected
        
        # ===== CRITERION 2: Count Calculations =====
        count_col = find_column_by_keywords(sheet_data, [
            'ticket count', 'count', 'total tickets', 'num tickets', 'quantity'
        ])
        
        count_accurate = False
        if count_col is not None:
            correct_counts = 0
            test_cases = [
                (1, '0001-0078', 78),   # Rodriguez
                (2, '0050-0075', 26),   # Johnson
                (3, '0079-0099; 0150-0193', 65),  # Patel (21+44)
                (4, '0067; 0100-0120', 22),  # Martinez (1+21)
                (7, '0252-0276', 25),   # Thompson
                (8, '0277', 1),         # Wilson (single ticket)
            ]
            
            for row_idx, ticket_str, expected_count in test_cases:
                if row_idx < len(sheet_rows) and count_col < len(sheet_rows[row_idx]):
                    cell = sheet_rows[row_idx][count_col]
                    cell_val = cell.get('value', 0) if isinstance(cell, dict) else cell
                    
                    try:
                        actual_count = float(cell_val) if cell_val else 0
                        if abs(actual_count - expected_count) <= 1:  # ±1 tolerance
                            correct_counts += 1
                    except (ValueError, TypeError):
                        pass
            
            if correct_counts >= 4:  # At least 4 out of 6 correct
                criteria_passed += 1
                count_accurate = True
                feedback_parts.append(f"✅ Ticket count calculations accurate ({correct_counts}/6 test cases correct)")
            else:
                feedback_parts.append(f"⚠️ Count calculations need improvement ({correct_counts}/6 correct)")
        else:
            feedback_parts.append("❌ No ticket count column found")
        
        subscores['count_accuracy'] = count_accurate
        
        # ===== CRITERION 3: Validation Flags =====
        validation_col = find_column_by_keywords(sheet_data, [
            'validation', 'valid', 'status', 'flag', 'error', 'issue'
        ])
        
        validation_present = False
        if validation_col is not None:
            invalid_flagged = 0
            
            # Check Davis (row 9, no tickets)
            if len(sheet_rows) > 9 and validation_col < len(sheet_rows[9]):
                cell = sheet_rows[9][validation_col]
                cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).upper()
                if 'INVALID' in cell_val or 'MISSING' in cell_val or 'ERROR' in cell_val or 'FLAG' in cell_val:
                    invalid_flagged += 1
            
            # Check Lee (row 11, backwards range)
            if len(sheet_rows) > 11 and validation_col < len(sheet_rows[11]):
                cell = sheet_rows[11][validation_col]
                cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).upper()
                if 'INVALID' in cell_val or 'BACKWARDS' in cell_val or 'ERROR' in cell_val or 'FLAG' in cell_val:
                    invalid_flagged += 1
            
            if invalid_flagged >= 1:
                criteria_passed += 1
                validation_present = True
                feedback_parts.append(f"✅ Validation flags present ({invalid_flagged} invalid entries flagged)")
            else:
                feedback_parts.append("⚠️ Validation column exists but known issues not flagged")
        else:
            feedback_parts.append("❌ No validation status column found")
        
        subscores['validation_flags'] = validation_present
        
        # ===== CRITERION 4: Top Sellers Identified =====
        top_seller_col = find_column_by_keywords(sheet_data, [
            'top seller', 'top', 'rank', 'ranking', 'best'
        ])
        
        top_sellers_correct = False
        if top_seller_col is not None:
            top_found = 0
            
            # Check Rodriguez (row 1), Patel (row 3), O'Brien (row 6)
            top_indices = [1, 3, 6]
            for idx in top_indices:
                if idx < len(sheet_rows) and top_seller_col < len(sheet_rows[idx]):
                    cell = sheet_rows[idx][top_seller_col]
                    cell_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).upper()
                    if 'TOP' in cell_val or '★' in cell_val or 'RANK' in cell_val or cell_val.strip() in ['1', '2', '3']:
                        top_found += 1
            
            if top_found >= 2:  # At least 2 of 3 top sellers identified
                criteria_passed += 1
                top_sellers_correct = True
                feedback_parts.append(f"✅ Top sellers identified ({top_found}/3 marked)")
            else:
                feedback_parts.append(f"⚠️ Top sellers not adequately marked ({top_found}/3)")
        else:
            feedback_parts.append("❌ No top seller designation column found")
        
        subscores['top_sellers'] = top_sellers_correct
        
        # ===== CRITERION 5: Final Verified Total =====
        # Look for summary cell with total
        total_found = False
        calculated_total = 0
        expected_total = 387
        tolerance = 5
        
        # Search in multiple locations for the total
        # Check last few rows for summary
        for i in range(max(0, len(sheet_rows) - 5), len(sheet_rows)):
            row = sheet_rows[i]
            for j, cell in enumerate(row):
                cell_val = cell.get('value', '') if isinstance(cell, dict) else str(cell)
                cell_str = str(cell_val).lower()
                
                # Look for "total" label
                if any(keyword in cell_str for keyword in ['total', 'verified', 'final', 'drawing']):
                    # Check next cell for the number
                    if j + 1 < len(row):
                        next_cell = row[j + 1]
                        next_val = next_cell.get('value', 0) if isinstance(next_cell, dict) else next_cell
                        try:
                            calculated_total = float(next_val)
                            total_found = True
                            break
                        except (ValueError, TypeError):
                            pass
                
                # Or the cell itself might contain the total
                try:
                    val = float(cell_val)
                    if 350 <= val <= 450:  # Reasonable range
                        calculated_total = val
                        total_found = True
                        break
                except (ValueError, TypeError):
                    pass
            
            if total_found:
                break
        
        if total_found and abs(calculated_total - expected_total) <= tolerance:
            criteria_passed += 1
            feedback_parts.append(f"✅ Final verified total correct ({calculated_total} tickets, expected ~387)")
        elif total_found:
            feedback_parts.append(f"⚠️ Total found ({calculated_total}) but differs from expected (~387)")
        else:
            feedback_parts.append("❌ No summary total found for verified tickets")
        
        subscores['final_total'] = total_found and abs(calculated_total - expected_total) <= tolerance
        
        # ===== Calculate Final Score =====
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 3 out of 5 criteria
        
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent raffle validation!")
        elif passed:
            feedback_parts.insert(0, "✅ Raffle validation completed")
        else:
            feedback_parts.insert(0, "❌ Raffle validation incomplete")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        if file_info:
            cleanup_verification_temp(file_info.get('temp_dir'))
