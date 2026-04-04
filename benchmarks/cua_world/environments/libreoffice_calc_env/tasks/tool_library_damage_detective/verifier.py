#!/usr/bin/env python3
"""
Verifier for Tool Library Damage Detective task.
Validates investigation of damaged tool return, including member identification,
status updates, and proper use of lookup formulas.
"""

import sys
import os
import logging
from datetime import datetime, timedelta
import re

# Do not use /workspace/utils, since verification runs on host machine
# Use relative path to the utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_cell_with_value(sheet_data, search_value, partial_match=True):
    """
    Find cells containing a specific value.
    Returns list of (row_idx, col_idx, cell_value, formula) tuples.
    """
    matches = []
    for row_idx, row in enumerate(sheet_data):
        for col_idx, cell in enumerate(row):
            cell_value = cell.get('value', '') if isinstance(cell, dict) else cell
            cell_formula = cell.get('formula', '') if isinstance(cell, dict) else ''
            
            cell_str = str(cell_value).strip()
            search_str = str(search_value).strip()
            
            if partial_match:
                if search_str.lower() in cell_str.lower():
                    matches.append((row_idx, col_idx, cell_value, cell_formula))
            else:
                if cell_str.lower() == search_str.lower():
                    matches.append((row_idx, col_idx, cell_value, cell_formula))
    
    return matches


def check_for_lookup_formula(workbook):
    """
    Check if any VLOOKUP or XLOOKUP formulas are present in the workbook.
    Returns True and formula details if found.
    """
    for sheet_name, sheet_data in workbook.get('sheets', {}).items():
        for row_idx, row in enumerate(sheet_data):
            for col_idx, cell in enumerate(row):
                formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                if formula:
                    formula_upper = formula.upper()
                    if 'VLOOKUP' in formula_upper or 'XLOOKUP' in formula_upper or 'INDEX' in formula_upper:
                        return True, sheet_name, row_idx, col_idx, formula
    return False, None, None, None, None


def verify_tool_library_investigation(traj, env_info, task_info):
    """
    Verify tool library damage investigation task completion.
    
    Checks:
    1. Correct last borrower identified (M-023, Sarah Chen)
    2. VLOOKUP/XLOOKUP formula used for member lookup
    3. Tool T-047 status updated to damaged
    4. Member M-023 flagged for contact
    5. Borrowing duration calculated (9 days)
    6. Overdue status detected (YES - exceeded 7 day limit)
    7. Contact info retrieved (sarah.chen@email.com)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/tool_library.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Get sheet names
        sheet_names = list(workbook['sheets'].keys())
        logger.info(f"Found sheets: {sheet_names}")
        
        # Identify sheets (handle different naming)
        inventory_sheet = None
        borrowing_sheet = None
        members_sheet = None
        
        for sheet_name in sheet_names:
            name_lower = sheet_name.lower()
            if 'inventory' in name_lower:
                inventory_sheet = workbook['sheets'][sheet_name]
            elif 'borrow' in name_lower or 'log' in name_lower:
                borrowing_sheet = workbook['sheets'][sheet_name]
            elif 'member' in name_lower:
                members_sheet = workbook['sheets'][sheet_name]
        
        # If sheets not found by name, use first three sheets
        if not inventory_sheet or not borrowing_sheet or not members_sheet:
            logger.warning("Sheets not found by name, using positional detection")
            if len(sheet_names) >= 3:
                inventory_sheet = workbook['sheets'][sheet_names[0]]
                borrowing_sheet = workbook['sheets'][sheet_names[1]]
                members_sheet = workbook['sheets'][sheet_names[2]]
        
        # ===== CRITERION 1: Correct member identified (M-023 or Sarah Chen) =====
        found_correct_member = False
        
        # Search all sheets for M-023 or "Sarah Chen"
        for sheet_name, sheet_data in workbook['sheets'].items():
            m023_matches = find_cell_with_value(sheet_data, 'M-023', partial_match=False)
            sarah_matches = find_cell_with_value(sheet_data, 'Sarah Chen', partial_match=True)
            
            if m023_matches or sarah_matches:
                # Check if it's in a result/investigation area (not just source data)
                # Look for cells near investigation keywords
                for row_idx, row in enumerate(sheet_data):
                    for col_idx, cell in enumerate(row):
                        cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
                        if any(keyword in cell_value for keyword in ['borrower', 'last', 'member', 'investigation', 'responsible']):
                            # Check nearby cells for M-023 or Sarah Chen
                            for r in range(max(0, row_idx-2), min(len(sheet_data), row_idx+3)):
                                for c in range(max(0, col_idx-2), min(len(sheet_data[r]), col_idx+3)):
                                    nearby_value = str(sheet_data[r][c].get('value', '') if isinstance(sheet_data[r][c], dict) else sheet_data[r][c])
                                    if 'M-023' in nearby_value or 'Sarah Chen' in nearby_value:
                                        found_correct_member = True
                                        break
        
        if found_correct_member:
            criteria_passed += 1
            feedback_parts.append("✅ Correct last borrower identified (M-023, Sarah Chen)")
        else:
            feedback_parts.append("❌ Last borrower not correctly identified (expected M-023/Sarah Chen)")
        
        # ===== CRITERION 2: VLOOKUP/XLOOKUP formula used =====
        has_lookup, lookup_sheet, lookup_row, lookup_col, lookup_formula = check_for_lookup_formula(workbook)
        
        if has_lookup:
            criteria_passed += 1
            feedback_parts.append(f"✅ Lookup formula used: {lookup_formula[:50]}...")
            logger.info(f"Found lookup formula in {lookup_sheet} at R{lookup_row}C{lookup_col}: {lookup_formula}")
        else:
            feedback_parts.append("❌ No lookup formula detected (VLOOKUP/XLOOKUP/INDEX expected)")
        
        # ===== CRITERION 3: Tool T-047 status updated to damaged =====
        tool_status_updated = False
        
        if inventory_sheet:
            for row_idx, row in enumerate(inventory_sheet):
                # Find T-047 row
                if len(row) > 0:
                    first_cell = row[0].get('value', '') if isinstance(row[0], dict) else row[0]
                    if 'T-047' in str(first_cell):
                        # Check condition column (typically column 3 or 4)
                        for cell_idx in range(1, min(len(row), 6)):
                            cell_value = str(row[cell_idx].get('value', '') if isinstance(row[cell_idx], dict) else row[cell_idx]).lower()
                            if any(keyword in cell_value for keyword in ['damage', 'repair', 'broken', 'bent', 'bad']):
                                tool_status_updated = True
                                logger.info(f"Found damaged status for T-047: {cell_value}")
                                break
        
        if tool_status_updated:
            criteria_passed += 1
            feedback_parts.append("✅ Tool T-047 status updated to damaged")
        else:
            feedback_parts.append("❌ Tool status not updated (T-047 should be marked damaged)")
        
        # ===== CRITERION 4: Member M-023 flagged for contact =====
        member_flagged = False
        
        if members_sheet:
            for row_idx, row in enumerate(members_sheet):
                # Find M-023 row
                if len(row) > 0:
                    first_cell = row[0].get('value', '') if isinstance(row[0], dict) else row[0]
                    if 'M-023' in str(first_cell):
                        # Check for YES or contact flag in this row
                        for cell_idx in range(1, len(row)):
                            cell_value = str(row[cell_idx].get('value', '') if isinstance(row[cell_idx], dict) else row[cell_idx]).upper()
                            if 'YES' in cell_value or 'PENDING' in cell_value or 'CONTACT' in cell_value or 'FLAG' in cell_value:
                                member_flagged = True
                                logger.info(f"Found contact flag for M-023: {cell_value}")
                                break
        
        if member_flagged:
            criteria_passed += 1
            feedback_parts.append("✅ Member M-023 flagged for follow-up contact")
        else:
            feedback_parts.append("❌ Member not flagged for contact (M-023 PendingContact should be YES)")
        
        # ===== CRITERION 5: Borrowing duration calculated (9 days) =====
        found_duration = False
        
        # Look for value 9 in investigation area or calculated cells
        for sheet_name, sheet_data in workbook['sheets'].items():
            for row_idx, row in enumerate(sheet_data):
                for col_idx, cell in enumerate(row):
                    cell_value = cell.get('value', '') if isinstance(cell, dict) else cell
                    cell_formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                    
                    # Check if value is 9 and either has formula or is near duration-related text
                    if cell_value == 9 or cell_value == '9':
                        # Check if it's calculated or near duration keywords
                        if cell_formula or any(keyword in str(sheet_data[row_idx]).lower() for keyword in ['day', 'duration', 'borrow', 'period']):
                            found_duration = True
                            logger.info(f"Found duration calculation: {cell_value} (formula: {cell_formula})")
                            break
                    
                    # Also check for date arithmetic formulas
                    if cell_formula and ('-' in cell_formula or 'DAYS' in cell_formula.upper()):
                        found_duration = True
                        logger.info(f"Found date calculation formula: {cell_formula}")
        
        if found_duration:
            criteria_passed += 1
            feedback_parts.append("✅ Borrowing duration calculated (9 days)")
        else:
            feedback_parts.append("❌ Duration not calculated (checkout to return = 9 days)")
        
        # ===== CRITERION 6: Overdue status detected =====
        found_overdue = False
        
        # Look for "overdue", "late", "YES" in context of overdue
        for sheet_name, sheet_data in workbook['sheets'].items():
            for row_idx, row in enumerate(sheet_data):
                row_text = ' '.join([str(cell.get('value', '') if isinstance(cell, dict) else cell) for cell in row]).lower()
                if 'overdue' in row_text or ('late' in row_text and 'yes' in row_text):
                    found_overdue = True
                    logger.info(f"Found overdue indicator in row: {row_text[:100]}")
                    break
        
        if found_overdue:
            criteria_passed += 1
            feedback_parts.append("✅ Overdue status correctly identified")
        else:
            feedback_parts.append("❌ Overdue status not detected (borrowed 9 days > 7 day limit)")
        
        # ===== CRITERION 7: Contact info retrieved =====
        found_email = False
        
        # Look for sarah.chen@email.com or similar
        for sheet_name, sheet_data in workbook['sheets'].items():
            email_matches = find_cell_with_value(sheet_data, 'sarah.chen@email.com', partial_match=True)
            if email_matches:
                found_email = True
                logger.info(f"Found email address: {email_matches[0][2]}")
                break
        
        if found_email:
            criteria_passed += 1
            feedback_parts.append("✅ Contact information retrieved (sarah.chen@email.com)")
        else:
            feedback_parts.append("❌ Contact info not retrieved (expected sarah.chen@email.com)")
        
        # ===== Calculate final score =====
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold is 70%
        
        # Add summary
        feedback_parts.append(f"\n📊 Investigation Results: {criteria_passed}/{total_criteria} criteria met")
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent investigation work!")
        elif passed:
            feedback_parts.append("✅ Investigation completed successfully")
        else:
            feedback_parts.append("❌ Investigation incomplete - review requirements")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "correct_member_identified": found_correct_member,
                "lookup_formula_used": has_lookup,
                "tool_status_updated": tool_status_updated,
                "member_flagged": member_flagged,
                "duration_calculated": found_duration,
                "overdue_detected": found_overdue,
                "contact_retrieved": found_email
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
