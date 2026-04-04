#!/usr/bin/env python3
"""
Verifier for Birthday RSVP Tracker task
Checks data updates, formula presence, calculation accuracy, and conditional formatting
"""

import sys
import os
import logging
import zipfile
from xml.etree import ElementTree as ET

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_ods_has_conditional_styles(filepath, sheet_name):
    """
    Check if ODS file has conditional formatting by examining XML.
    This is a heuristic check for style:map elements which indicate conditional formatting.
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for style:map elements which indicate conditional formatting
            namespaces = {
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
            }
            
            style_maps = root.findall('.//style:map', namespaces)
            
            # If we find style maps with conditions, conditional formatting likely exists
            has_conditions = len(style_maps) > 0
            
            if has_conditions:
                logger.info(f"Found {len(style_maps)} conditional style mappings")
            
            return has_conditions
            
    except Exception as e:
        logger.debug(f"Could not check conditional formatting: {e}")
        return False


def find_summary_formulas(workbook, sheet_name):
    """
    Search for summary formulas in the sheet (typically in rows 10+).
    Returns dict with formula locations and content.
    """
    formulas_found = {
        'sumif_adults': None,
        'sumif_kids': None,
        'countif_pending': None,
        'total_formula': None,
        'locations': []
    }
    
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Search rows 10-20 for formulas (summary section)
        for row_idx in range(9, min(20, len(sheet_rows))):
            row = sheet_rows[row_idx]
            
            for col_idx, cell in enumerate(row):
                if isinstance(cell, dict):
                    formula = cell.get('formula', '')
                else:
                    formula = ''
                
                if formula:
                    formula_upper = formula.upper()
                    
                    # Check for SUMIF with "Yes" and column D (adults)
                    if 'SUMIF' in formula_upper and 'YES' in formula_upper and 'D:D' in formula_upper:
                        formulas_found['sumif_adults'] = formula
                        formulas_found['locations'].append((row_idx, col_idx, 'SUMIF_ADULTS'))
                    
                    # Check for SUMIF with "Yes" and column E (kids)
                    elif 'SUMIF' in formula_upper and 'YES' in formula_upper and 'E:E' in formula_upper:
                        formulas_found['sumif_kids'] = formula
                        formulas_found['locations'].append((row_idx, col_idx, 'SUMIF_KIDS'))
                    
                    # Check for COUNTIF with "Pending"
                    elif 'COUNTIF' in formula_upper and 'PENDING' in formula_upper:
                        formulas_found['countif_pending'] = formula
                        formulas_found['locations'].append((row_idx, col_idx, 'COUNTIF_PENDING'))
                    
                    # Check for any SUM or addition formula in summary area
                    elif 'SUM(' in formula_upper or '+' in formula:
                        formulas_found['total_formula'] = formula
                        formulas_found['locations'].append((row_idx, col_idx, 'TOTAL'))
        
    except Exception as e:
        logger.error(f"Error searching for formulas: {e}")
    
    return formulas_found


def calculate_expected_totals(workbook, sheet_name):
    """
    Calculate expected totals based on current RSVP data.
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        total_adults = 0
        total_kids = 0
        pending_count = 0
        
        # Analyze rows 2-8 (data rows, skip header row 1)
        for row_idx in range(1, min(9, len(sheet_rows))):
            row = sheet_rows[row_idx]
            
            if len(row) < 5:
                continue
            
            # Get RSVP status (column C, index 2)
            status_cell = row[2]
            status = status_cell.get('value', '').strip() if isinstance(status_cell, dict) else str(status_cell).strip()
            
            # Get # Adults (column D, index 3)
            adults_cell = row[3]
            adults = adults_cell.get('value', 0) if isinstance(adults_cell, dict) else adults_cell
            adults = int(adults) if adults else 0
            
            # Get # Kids (column E, index 4)
            kids_cell = row[4]
            kids = kids_cell.get('value', 0) if isinstance(kids_cell, dict) else kids_cell
            kids = int(kids) if kids else 0
            
            if status.lower() == "yes":
                total_adults += adults
                total_kids += kids
            elif status.lower() == "pending":
                pending_count += 1
        
        return {
            'expected_adults': total_adults,
            'expected_kids': total_kids,
            'expected_total': total_adults + total_kids,
            'expected_pending': pending_count
        }
        
    except Exception as e:
        logger.error(f"Error calculating expected totals: {e}")
        return {
            'expected_adults': 0,
            'expected_kids': 0,
            'expected_total': 0,
            'expected_pending': 0
        }


def verify_birthday_rsvp_tracker(traj, env_info, task_info):
    """
    Verify birthday RSVP tracker task completion.
    
    Checks:
    1. Jake's row updated (Row 3: Status="Yes", Adults=2, Kids=1)
    2. Sarah's row updated (Row 4: Status="No")
    3. Summary formulas present (SUMIF, COUNTIF)
    4. Calculations correct
    5. Conditional formatting applied (bonus)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible filenames
    temp_dir = None
    success = False
    workbook = None
    
    for filepath in [
        "/home/ga/Documents/birthday_rsvp_final.ods",
        "/home/ga/Documents/birthday_rsvp.ods",
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            filepath,
            copy_from_env,
            file_format='ods'
        )
        if success:
            logger.info(f"Successfully loaded file: {filepath}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        sheet_rows = workbook['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        subscores = {}
        
        # CRITERION 1: Jake's row updated (Row 3: index 2)
        jake_correct = False
        try:
            if len(sheet_rows) > 2:
                jake_row = sheet_rows[2]  # Row 3 (0-indexed)
                
                # Check RSVP Status (column C, index 2)
                jake_status = jake_row[2].get('value', '') if isinstance(jake_row[2], dict) else str(jake_row[2])
                # Check # Adults (column D, index 3)
                jake_adults = jake_row[3].get('value', 0) if isinstance(jake_row[3], dict) else jake_row[3]
                jake_adults = int(jake_adults) if jake_adults else 0
                # Check # Kids (column E, index 4)
                jake_kids = jake_row[4].get('value', 0) if isinstance(jake_row[4], dict) else jake_row[4]
                jake_kids = int(jake_kids) if jake_kids else 0
                
                if str(jake_status).strip().lower() == "yes" and jake_adults == 2 and jake_kids == 1:
                    criteria_passed += 1
                    jake_correct = True
                    feedback_parts.append("✅ Jake's family updated correctly (Yes, 2 adults, 1 kid)")
                else:
                    feedback_parts.append(f"❌ Jake's row incorrect: Status='{jake_status}', Adults={jake_adults}, Kids={jake_kids} (expected: Yes, 2, 1)")
        except Exception as e:
            feedback_parts.append(f"❌ Error checking Jake's row: {e}")
        
        subscores['jake_updated'] = jake_correct
        
        # CRITERION 2: Sarah's row updated (Row 4: index 3)
        sarah_correct = False
        try:
            if len(sheet_rows) > 3:
                sarah_row = sheet_rows[3]  # Row 4 (0-indexed)
                
                # Check RSVP Status (column C, index 2)
                sarah_status = sarah_row[2].get('value', '') if isinstance(sarah_row[2], dict) else str(sarah_row[2])
                
                if str(sarah_status).strip().lower() == "no":
                    criteria_passed += 1
                    sarah_correct = True
                    feedback_parts.append("✅ Sarah's family updated correctly (No)")
                else:
                    feedback_parts.append(f"❌ Sarah's row incorrect: Status='{sarah_status}' (expected: No)")
        except Exception as e:
            feedback_parts.append(f"❌ Error checking Sarah's row: {e}")
        
        subscores['sarah_updated'] = sarah_correct
        
        # CRITERION 3: Formulas present
        formulas = find_summary_formulas(workbook, sheet_name)
        formula_count = sum([
            1 if formulas['sumif_adults'] else 0,
            1 if formulas['sumif_kids'] else 0,
            1 if formulas['countif_pending'] else 0,
        ])
        
        formulas_correct = formula_count >= 2  # At least 2 key formulas
        if formula_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Summary formulas present ({formula_count}/3: SUMIF adults, SUMIF kids, COUNTIF pending)")
        elif formula_count >= 2:
            criteria_passed += 0.75  # Partial credit
            feedback_parts.append(f"⚠️ Partial formulas present ({formula_count}/3)")
        else:
            feedback_parts.append(f"❌ Missing formulas (found {formula_count}/3)")
        
        subscores['formulas_present'] = formulas_correct
        
        # CRITERION 4: Calculations correct
        expected = calculate_expected_totals(workbook, sheet_name)
        
        # Find cells with formula results in summary area
        calculations_correct = False
        found_adults_value = None
        found_kids_value = None
        found_pending_value = None
        
        for row_idx in range(9, min(20, len(sheet_rows))):
            row = sheet_rows[row_idx]
            for col_idx in range(1, 3):  # Check columns B and C for values
                if col_idx < len(row):
                    cell = row[col_idx]
                    value = cell.get('value', None) if isinstance(cell, dict) else cell
                    
                    if value is not None:
                        try:
                            num_value = int(float(value))
                            
                            # Match against expected values
                            if abs(num_value - expected['expected_adults']) <= 1:
                                found_adults_value = num_value
                            if abs(num_value - expected['expected_kids']) <= 1:
                                found_kids_value = num_value
                            if abs(num_value - expected['expected_pending']) <= 1:
                                found_pending_value = num_value
                        except (ValueError, TypeError):
                            pass
        
        # Check if at least 2 calculations match
        matches = sum([
            1 if found_adults_value is not None else 0,
            1 if found_kids_value is not None else 0,
            1 if found_pending_value is not None else 0,
        ])
        
        if matches >= 2:
            criteria_passed += 1
            calculations_correct = True
            feedback_parts.append(f"✅ Calculations correct (Expected: Adults={expected['expected_adults']}, Kids={expected['expected_kids']}, Pending={expected['expected_pending']})")
        else:
            feedback_parts.append(f"❌ Calculations incorrect or missing (Expected: Adults={expected['expected_adults']}, Kids={expected['expected_kids']}, Pending={expected['expected_pending']})")
        
        subscores['calculations_correct'] = calculations_correct
        
        # CRITERION 5: Conditional formatting (bonus, less critical)
        has_formatting = False
        try:
            # Get file path from temp location
            file_path = None
            if temp_dir:
                import glob
                ods_files = glob.glob(os.path.join(temp_dir, "*.ods"))
                if ods_files:
                    file_path = ods_files[0]
            
            if file_path:
                has_formatting = check_ods_has_conditional_styles(file_path, sheet_name)
                
                if has_formatting:
                    criteria_passed += 1
                    feedback_parts.append("✅ Conditional formatting detected")
                else:
                    feedback_parts.append("⚠️ No conditional formatting detected (optional bonus)")
        except Exception as e:
            logger.debug(f"Could not check conditional formatting: {e}")
            feedback_parts.append("⚠️ Conditional formatting check skipped (optional)")
        
        subscores['conditional_formatting'] = has_formatting
        
        # Calculate final score
        # Adjust total criteria based on core requirements
        # Core: Jake update, Sarah update, Formulas, Calculations (4 criteria = 75% threshold)
        # Bonus: Conditional formatting (5th criterion)
        
        score = int((criteria_passed / total_criteria) * 100)
        
        # Pass if at least 3 core criteria OR 75% overall
        core_passed = (jake_correct + sarah_correct + formulas_correct + calculations_correct) >= 3
        passed = score >= 75 or core_passed
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent RSVP tracker completion!")
        elif passed:
            feedback_parts.append("✅ RSVP tracker task completed successfully")
        else:
            feedback_parts.append("❌ RSVP tracker requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_temp(temp_dir)
