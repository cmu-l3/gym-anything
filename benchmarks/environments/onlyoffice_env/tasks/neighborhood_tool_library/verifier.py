#!/usr/bin/env python3
"""
Verifier for neighborhood_tool_library@1

Checks that the tool library tracker is properly structured with:
- Correct column headers
- All 10 required tools with correct owners
- 4 items checked out with correct borrowers and dates
- Days Out calculation using TODAY()
- Overdue detection for items >7 days
"""

import sys
import os
import logging
import tempfile
from datetime import datetime, timedelta
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
    """Normalize text for comparison (lowercase, strip, remove extra spaces)"""
    if text is None:
        return ""
    return str(text).lower().strip().replace("  ", " ")


def fuzzy_match(text, target, threshold=0.7):
    """Check if text contains most of the target words"""
    text_norm = normalize_text(text)
    target_norm = normalize_text(target)
    
    # Direct substring match
    if target_norm in text_norm:
        return True
    
    # Check if most words from target are in text
    target_words = target_norm.split()
    if not target_words:
        return False
    
    matches = sum(1 for word in target_words if word in text_norm)
    return matches / len(target_words) >= threshold


def find_header_row(data, required_keywords):
    """Find the row that likely contains column headers"""
    for row_idx, row in enumerate(data[:10]):  # Check first 10 rows
        row_text = " ".join([normalize_text(cell) for cell in row if cell])
        keyword_matches = sum(1 for kw in required_keywords if kw in row_text)
        if keyword_matches >= len(required_keywords) * 0.6:  # At least 60% of keywords
            return row_idx
    return -1


def verify_neighborhood_tool_library(traj, env_info, task_info):
    """
    Verify the neighborhood tool library tracker spreadsheet
    
    Scoring breakdown (10 points total):
    1. File exists and valid (1 pt)
    2. Has appropriate column headers (1 pt)
    3. Contains all 10 tools (1 pt)
    4. Correct owners assigned (1 pt)
    5. 4 items marked as checked out (1 pt)
    6. Correct borrowers for checked out items (1 pt)
    7. Days Out calculation exists (1 pt)
    8. Days Out uses formula (TODAY() or similar) (1 pt)
    9. Overdue item (Power Drill) correctly shows >7 days (1 pt)
    10. Available items properly marked (1 pt)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}
    
    file_path = "/home/ga/Documents/Spreadsheets/neighborhood_tool_library.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_tool_lib_')
    
    feedback_parts = []
    score = 0.0
    max_score = 10.0
    
    try:
        # Checkpoint 1: File exists and can be parsed
        success, workbook, error = copy_and_parse_document(
            file_path,
            copy_from_env,
            'xlsx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Failed to open spreadsheet: {error}"
            }
        
        feedback_parts.append("✅ Spreadsheet file valid")
        score += 1.0
        
        # Get the active sheet
        sheet_name = workbook.sheetnames[0]
        sheet = workbook[sheet_name]
        
        # Get all data
        data = get_sheet_data(workbook, sheet_name, max_rows=30, max_cols=15)
        
        if len(data) < 2:
            return {
                "passed": False,
                "score": score / max_score,
                "feedback": " | ".join(feedback_parts) + " | ❌ Spreadsheet appears empty"
            }
        
        # Checkpoint 2: Find and verify column headers
        header_keywords = ['tool', 'owner', 'status', 'borrow', 'date', 'days']
        header_row_idx = find_header_row(data, header_keywords)
        
        if header_row_idx >= 0:
            feedback_parts.append(f"✅ Column headers found at row {header_row_idx + 1}")
            score += 1.0
            headers = data[header_row_idx]
            data_start_idx = header_row_idx + 1
        else:
            feedback_parts.append("⚠️ Column headers unclear, attempting to parse data")
            headers = data[0] if data else []
            data_start_idx = 1
            score += 0.5  # Partial credit
        
        # Identify column indices (flexible to different orderings)
        headers_norm = [normalize_text(h) for h in headers]
        
        col_tool = next((i for i, h in enumerate(headers_norm) if 'tool' in h or 'name' in h or 'item' in h), 0)
        col_owner = next((i for i, h in enumerate(headers_norm) if 'owner' in h or 'contributed' in h), 1)
        col_status = next((i for i, h in enumerate(headers_norm) if 'status' in h or 'available' in h), 2)
        col_borrowed_by = next((i for i, h in enumerate(headers_norm) if 'borrow' in h or 'checked' in h), 3)
        col_checkout = next((i for i, h in enumerate(headers_norm) if 'checkout' in h or 'date' in h), 4)
        col_days = next((i for i, h in enumerate(headers_norm) if 'days' in h or 'out' in h), 5)
        
        # Expected tools and their owners
        expected_tools = {
            'chainsaw': 'martinez',
            'pressure washer': 'chen',
            'tile saw': 'johnson',
            'extension ladder': 'park',
            'power drill set': 'rodriguez',
            'leaf blower': 'martinez',
            'wet/dry vacuum': 'thompson',
            'wet dry vacuum': 'thompson',  # Alternative spelling
            'circular saw': 'chen',
            'hedge trimmer': 'park',
            'post hole digger': 'johnson'
        }
        
        # Expected checkouts
        expected_checkouts = {
            'pressure washer': {'borrower': 'rodriguez', 'days_ago': 3, 'tolerance': 1},
            'extension ladder': {'borrower': 'thompson', 'days_ago': 5, 'tolerance': 1},
            'power drill set': {'borrower': 'martinez', 'days_ago': 9, 'tolerance': 1},
            'circular saw': {'borrower': 'johnson', 'days_ago': 2, 'tolerance': 1}
        }
        
        # Parse data rows
        tools_found = {}
        available_count = 0
        checked_out_count = 0
        
        for row_idx in range(data_start_idx, min(data_start_idx + 20, len(data))):
            row = data[row_idx]
            if not row or len(row) <= col_tool or not row[col_tool]:
                continue
            
            tool_name_raw = str(row[col_tool]) if col_tool < len(row) else ""
            tool_name = normalize_text(tool_name_raw)
            
            # Skip if it's an instruction or empty row
            if not tool_name or '[' in tool_name or 'instruction' in tool_name:
                continue
            
            owner = normalize_text(row[col_owner]) if col_owner < len(row) else ""
            status = normalize_text(row[col_status]) if col_status < len(row) else ""
            borrowed_by = normalize_text(row[col_borrowed_by]) if col_borrowed_by < len(row) else ""
            checkout_date = row[col_checkout] if col_checkout < len(row) else None
            days_out = row[col_days] if col_days < len(row) else None
            
            # Match against expected tools
            matched_tool = None
            for expected_tool in expected_tools.keys():
                if fuzzy_match(tool_name, expected_tool, threshold=0.6):
                    matched_tool = expected_tool
                    break
            
            if matched_tool:
                tools_found[matched_tool] = {
                    'owner': owner,
                    'status': status,
                    'borrowed_by': borrowed_by,
                    'checkout_date': checkout_date,
                    'days_out': days_out,
                    'raw_tool': tool_name_raw
                }
        
        # Checkpoint 3: All 10 tools present
        unique_tools = len(tools_found)
        if unique_tools >= 10:
            feedback_parts.append(f"✅ All tools present ({unique_tools}/10)")
            score += 1.0
        elif unique_tools >= 8:
            feedback_parts.append(f"⚠️ Most tools present ({unique_tools}/10)")
            score += 0.7
        else:
            feedback_parts.append(f"❌ Many tools missing ({unique_tools}/10)")
            score += 0.3
        
        # Checkpoint 4: Owners are correct
        correct_owners = 0
        total_checkable = 0
        for tool, expected_owner in expected_tools.items():
            if tool in tools_found:
                total_checkable += 1
                actual_owner = tools_found[tool]['owner']
                if expected_owner in actual_owner or fuzzy_match(actual_owner, expected_owner):
                    correct_owners += 1
        
        if total_checkable > 0:
            owner_ratio = correct_owners / total_checkable
            if owner_ratio >= 0.8:
                feedback_parts.append(f"✅ Tool owners correct ({correct_owners}/{total_checkable})")
                score += 1.0
            elif owner_ratio >= 0.5:
                feedback_parts.append(f"⚠️ Some owners incorrect ({correct_owners}/{total_checkable})")
                score += 0.5
            else:
                feedback_parts.append(f"❌ Many owners incorrect ({correct_owners}/{total_checkable})")
        
        # Checkpoint 5 & 6: Checkouts recorded correctly
        checkout_status_correct = 0
        checkout_borrower_correct = 0
        checkout_date_reasonable = 0
        
        for tool, checkout_info in expected_checkouts.items():
            if tool in tools_found:
                info = tools_found[tool]
                
                # Check if marked as checked out
                is_checked_out = ('checked' in info['status'] or 'out' in info['status'] or 
                                 'borrowed' in info['status']) and 'available' not in info['status']
                
                if is_checked_out:
                    checkout_status_correct += 1
                    
                    # Check borrower
                    if fuzzy_match(info['borrowed_by'], checkout_info['borrower']):
                        checkout_borrower_correct += 1
                    
                    # Check date/days calculation
                    days_val = info['days_out']
                    expected_days = checkout_info['days_ago']
                    tolerance = checkout_info['tolerance']
                    
                    if isinstance(days_val, (int, float)) and days_val >= 0:
                        if abs(days_val - expected_days) <= tolerance + 1:  # Allow some flexibility
                            checkout_date_reasonable += 1
        
        # Score checkpoint 5: checkout status
        if checkout_status_correct >= 4:
            feedback_parts.append(f"✅ All 4 checkouts recorded")
            score += 1.0
        elif checkout_status_correct >= 3:
            feedback_parts.append(f"⚠️ Most checkouts recorded ({checkout_status_correct}/4)")
            score += 0.7
        else:
            feedback_parts.append(f"❌ Checkouts incomplete ({checkout_status_correct}/4)")
        
        # Score checkpoint 6: correct borrowers
        if checkout_borrower_correct >= 3:
            feedback_parts.append(f"✅ Borrowers correct ({checkout_borrower_correct}/4)")
            score += 1.0
        elif checkout_borrower_correct >= 2:
            feedback_parts.append(f"⚠️ Some borrowers incorrect ({checkout_borrower_correct}/4)")
            score += 0.5
        else:
            feedback_parts.append(f"❌ Borrowers mostly incorrect ({checkout_borrower_correct}/4)")
        
        # Checkpoint 7: Days Out calculation exists
        has_days_calculation = False
        valid_days_values = 0
        
        for tool, info in tools_found.items():
            days_val = info['days_out']
            if isinstance(days_val, (int, float)) and days_val >= 0:
                valid_days_values += 1
                has_days_calculation = True
        
        if has_days_calculation and valid_days_values >= 3:
            feedback_parts.append(f"✅ Days Out calculated ({valid_days_values} items)")
            score += 1.0
        elif valid_days_values > 0:
            feedback_parts.append(f"⚠️ Days Out partially calculated ({valid_days_values} items)")
            score += 0.5
        else:
            feedback_parts.append("❌ Days Out not calculated")
        
        # Checkpoint 8: Formula detection (check if it's using TODAY() or similar)
        # We check if the calculated days match expected days from checkout dates
        formula_likely_used = checkout_date_reasonable >= 2
        
        if formula_likely_used:
            feedback_parts.append("✅ Date calculations appear correct (formula likely used)")
            score += 1.0
        elif has_days_calculation:
            feedback_parts.append("⚠️ Days calculated but may not use TODAY() formula")
            score += 0.5
        else:
            feedback_parts.append("❌ No evidence of formula-based calculation")
        
        # Checkpoint 9: Overdue detection (Power Drill Set should be >7 days)
        if 'power drill set' in tools_found or 'power drill' in tools_found:
            drill_key = 'power drill set' if 'power drill set' in tools_found else 'power drill'
            drill_info = tools_found[drill_key]
            drill_days = drill_info['days_out']
            
            if isinstance(drill_days, (int, float)):
                if drill_days >= 7:
                    feedback_parts.append(f"✅ Overdue item correctly shows {int(drill_days)} days (>7)")
                    score += 1.0
                elif drill_days >= 8:  # The task says 9 days ago
                    feedback_parts.append(f"✅ Overdue calculation correct ({int(drill_days)} days)")
                    score += 1.0
                else:
                    feedback_parts.append(f"⚠️ Power Drill days calculation may be off ({drill_days} days, expected ~9)")
                    score += 0.3
            else:
                feedback_parts.append("❌ Power Drill days not calculated")
        else:
            feedback_parts.append("⚠️ Power Drill Set not found in tracker")
        
        # Checkpoint 10: Available items properly marked
        available_tools_expected = [t for t in expected_tools.keys() if t not in expected_checkouts]
        available_marked = 0
        
        for tool in available_tools_expected:
            if tool in tools_found:
                info = tools_found[tool]
                if 'available' in info['status'] or 'avail' in info['status']:
                    available_marked += 1
                elif 'n/a' in info['borrowed_by'] or not info['borrowed_by'] or info['borrowed_by'] == '':
                    available_marked += 0.5  # Partial credit if status unclear but borrower is empty
        
        if available_marked >= 5:
            feedback_parts.append(f"✅ Available items marked ({int(available_marked)}/6)")
            score += 1.0
        elif available_marked >= 3:
            feedback_parts.append(f"⚠️ Some available items marked ({int(available_marked)}/6)")
            score += 0.6
        else:
            feedback_parts.append(f"⚠️ Available status unclear ({int(available_marked)}/6)")
            score += 0.3
        
        # Final assessment
        passed = score >= 6.0  # Need 60% to pass
        final_score = min(score / max_score, 1.0)
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": score / max_score if score > 0 else 0.0,
            "feedback": " | ".join(feedback_parts) + f" | ❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)


def main():
    """Test verifier locally"""
    print("✅ Neighborhood Tool Library verifier loaded successfully")
    return 0
