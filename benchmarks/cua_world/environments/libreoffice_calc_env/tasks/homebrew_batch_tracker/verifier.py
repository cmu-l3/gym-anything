#!/usr/bin/env python3
"""
Verifier for Homebrew Batch Tracker task

Checks:
1. ABV formulas present in column F for batches with complete data
2. Calculated ABV values are correct (within tolerance)
3. Conditional formatting applied to ABV column for target range
4. Original data integrity preserved
"""

import sys
import os
import logging
import re
import zipfile
from xml.etree import ElementTree as ET

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Expected ABV calculations
EXPECTED_BATCHES = {
    'Pale Ale #1': {'og': 1.055, 'fg': 1.012, 'abv': 5.64, 'row': 2},
    'Belgian Wit': {'og': 1.048, 'fg': 1.010, 'abv': 4.99, 'row': 3},
    'IPA Experiment': {'og': 1.062, 'fg': 1.014, 'abv': 6.30, 'row': 4},
    'Light Summer Ale': {'og': 1.045, 'fg': 1.008, 'abv': 4.86, 'row': 5},
    'Amber Ale': {'og': 1.058, 'fg': 1.015, 'abv': 5.64, 'row': 6},
    # Stout Attempt (row 7) has missing FG - should show error or blank
}

ABV_FORMULA_PATTERNS = [
    r'=\s*\(\s*[A-Z]+\d+\s*-\s*[A-Z]+\d+\s*\)\s*\*\s*131\.?25',  # Exact: (C2-D2)*131.25
    r'=\s*\(\s*[A-Z]+\d+\s*-\s*[A-Z]+\d+\s*\)\s*\*\s*131',       # Approximate: (C2-D2)*131
]


def verify_abv_formula(formula_string):
    """
    Check if formula matches ABV calculation pattern.
    Should be in format: =(OG_cell - FG_cell) * 131.25
    """
    if not formula_string:
        return False
    
    normalized = formula_string.upper().replace(' ', '')
    
    for pattern in ABV_FORMULA_PATTERNS:
        if re.match(pattern, normalized, re.IGNORECASE):
            return True
    
    return False


def check_conditional_formatting_in_ods(filepath):
    """
    Check if conditional formatting exists in the ODS file.
    Returns True if conditional formatting rules are detected.
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for conditional formatting in ODF format
            # Conditional formats are typically stored in table:conditional-formats elements
            namespaces = {
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'calcext': 'urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0'
            }
            
            # Check for conditional-formats element (LibreOffice extension)
            conditional_formats = root.findall('.//calcext:conditional-formats', namespaces)
            if conditional_formats:
                logger.info(f"Found {len(conditional_formats)} conditional format sections")
                return True
            
            # Alternative: check for data-pilot elements or style conditions
            data_pilots = root.findall('.//table:data-pilot-table', namespaces)
            if data_pilots:
                logger.info("Found data-pilot tables (possible conditional formatting)")
                return True
            
            # Check for automatic styles with conditions
            automatic_styles = root.findall('.//style:style', namespaces)
            for style in automatic_styles:
                map_elements = style.findall('.//style:map', namespaces)
                if map_elements:
                    logger.info("Found style maps (conditional formatting)")
                    return True
            
            return False
            
    except Exception as e:
        logger.warning(f"Could not check conditional formatting: {e}")
        return False


def verify_homebrew_tracker(traj, env_info, task_info):
    """
    Verify homebrew batch tracker task completion.
    
    Checks:
    1. ABV formulas present for complete batches
    2. Calculated values correct
    3. Conditional formatting applied
    4. Data integrity preserved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the spreadsheet
    container_path = "/home/ga/Documents/homebrew_tracker.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods']
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: ABV formulas present for batches with complete data
        formulas_found = 0
        formulas_correct = 0
        
        for batch_name, batch_data in EXPECTED_BATCHES.items():
            row = batch_data['row']
            abv_cell = f"F{row}"
            
            formula = get_cell_formula(data, sheet_name, abv_cell)
            
            if formula:
                formulas_found += 1
                if verify_abv_formula(formula):
                    formulas_correct += 1
                    logger.info(f"✅ Row {row} ({batch_name}): Valid ABV formula: {formula}")
                else:
                    logger.warning(f"⚠️ Row {row} ({batch_name}): Invalid formula pattern: {formula}")
            else:
                logger.warning(f"❌ Row {row} ({batch_name}): No formula found in {abv_cell}")
        
        if formulas_correct >= 4:  # At least 4 out of 5 complete batches
            criteria_passed += 1
            feedback_parts.append(f"✅ ABV formulas present ({formulas_correct}/5 batches)")
            subscores['formulas_present'] = True
        else:
            feedback_parts.append(f"❌ Missing ABV formulas ({formulas_correct}/5 found)")
            subscores['formulas_present'] = False
        
        # Criterion 2: Calculated ABV values correct
        calculations_correct = 0
        
        for batch_name, batch_data in EXPECTED_BATCHES.items():
            row = batch_data['row']
            expected_abv = batch_data['abv']
            abv_cell = f"F{row}"
            
            actual_abv = get_cell_value(data, sheet_name, abv_cell)
            
            if actual_abv is not None:
                try:
                    actual_abv_float = float(actual_abv)
                    if abs(actual_abv_float - expected_abv) <= 0.15:  # 0.15% tolerance
                        calculations_correct += 1
                        logger.info(f"✅ Row {row} ({batch_name}): ABV={actual_abv_float:.2f}% (expected {expected_abv}%)")
                    else:
                        logger.warning(f"❌ Row {row} ({batch_name}): ABV={actual_abv_float:.2f}% differs from expected {expected_abv}%")
                except (ValueError, TypeError):
                    logger.warning(f"⚠️ Row {row} ({batch_name}): Non-numeric ABV value: {actual_abv}")
            else:
                logger.warning(f"❌ Row {row} ({batch_name}): No ABV value calculated")
        
        if calculations_correct >= 4:  # At least 4 out of 5
            criteria_passed += 1
            feedback_parts.append(f"✅ ABV calculations correct ({calculations_correct}/5 batches)")
            subscores['calculations_correct'] = True
        else:
            feedback_parts.append(f"❌ ABV calculations incorrect ({calculations_correct}/5 correct)")
            subscores['calculations_correct'] = False
        
        # Criterion 3: Conditional formatting applied
        has_conditional_formatting = check_conditional_formatting_in_ods(file_info['file_path'])
        
        if has_conditional_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
            subscores['conditional_formatting'] = True
        else:
            feedback_parts.append("❌ No conditional formatting detected")
            subscores['conditional_formatting'] = False
        
        # Criterion 4: Data integrity - check that original data is preserved
        data_intact = True
        
        # Check header row
        header_check = [
            (get_cell_value(data, sheet_name, 'A1'), "Batch Name"),
            (get_cell_value(data, sheet_name, 'C1'), "Original Gravity (OG)"),
            (get_cell_value(data, sheet_name, 'D1'), "Final Gravity (FG)"),
        ]
        
        for actual, expected in header_check:
            if actual is None or expected.lower() not in str(actual).lower():
                data_intact = False
                logger.warning(f"Header mismatch: expected '{expected}', got '{actual}'")
                break
        
        # Check first batch data
        if data_intact:
            first_batch_name = get_cell_value(data, sheet_name, 'A2')
            first_og = get_cell_value(data, sheet_name, 'C2')
            first_fg = get_cell_value(data, sheet_name, 'D2')
            
            if first_batch_name != "Pale Ale #1":
                data_intact = False
                logger.warning(f"First batch name changed: expected 'Pale Ale #1', got '{first_batch_name}'")
            
            if first_og is None or abs(float(first_og) - 1.055) > 0.001:
                data_intact = False
                logger.warning(f"First batch OG changed: expected 1.055, got {first_og}")
        
        if data_intact:
            criteria_passed += 1
            feedback_parts.append("✅ Original data preserved")
            subscores['data_integrity'] = True
        else:
            feedback_parts.append("❌ Original data corrupted or modified")
            subscores['data_integrity'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🍺 Excellent homebrew tracking!")
        elif passed:
            feedback_parts.append("✅ Homebrew tracker task completed")
        else:
            feedback_parts.append("❌ Task requirements not met")
        
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
        cleanup_verification_environment(file_info.get('temp_dir'))
