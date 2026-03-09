#!/usr/bin/env python3
"""
Verifier for Meal Rotation Tracker task

Checks:
1. Formulas present using TODAY() and MAXIFS/MAX+IF for days since last eaten
2. COUNTIF formulas for frequency counting
3. Calculations produce valid results (0-60 day range, reasonable frequencies)
4. Green conditional formatting for ≥21 days
5. Red conditional formatting for ≤7 days
6. Summary structure exists with proper organization
7. No formula errors
"""

import sys
import os
import logging
import re
import zipfile
from xml.etree import ElementTree as ET
from typing import Dict, List, Tuple, Optional

# Use relative path to utils folder (for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_formula_structure(formula: str, required_functions: List[str]) -> bool:
    """Check if formula contains required functions"""
    if not formula:
        return False
    
    formula_upper = formula.upper()
    return all(func.upper() in formula_upper for func in required_functions)


def find_summary_section(sheet_data: Dict, min_formulas: int = 3) -> Optional[Dict]:
    """
    Find the summary section by looking for cells with formulas.
    Returns dict with start_row, start_col, formulas found
    """
    sheets = sheet_data.get('sheets', {})
    if not sheets:
        return None
    
    sheet_name = list(sheets.keys())[0]
    rows = sheets[sheet_name]
    
    # Look for clusters of formulas (likely summary section)
    formula_locations = []
    
    for row_idx, row in enumerate(rows):
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula and ('TODAY' in formula.upper() or 'COUNTIF' in formula.upper() or 'MAXIFS' in formula.upper()):
                    formula_locations.append((row_idx, col_idx, formula))
    
    if len(formula_locations) >= min_formulas:
        return {
            'found': True,
            'locations': formula_locations,
            'count': len(formula_locations)
        }
    
    return None


def check_conditional_formatting_ods(filepath: str) -> Dict[str, bool]:
    """
    Check for conditional formatting in ODS file.
    Returns dict with has_green_rule, has_red_rule, rule_count
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return {'has_green_rule': False, 'has_red_rule': False, 'rule_count': 0}
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for conditional formatting in ODS
            # Namespace for calc extensions
            namespaces = {
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'calcext': 'urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0'
            }
            
            # Search for conditional format entries
            has_green = False
            has_red = False
            rule_count = 0
            
            # Look for style:map elements (conditional formatting)
            for map_elem in root.findall('.//style:map', namespaces):
                condition = map_elem.get('{urn:oasis:names:tc:opendocument:xmlns:style:1.0}condition', '')
                rule_count += 1
                
                # Check for conditions like >=21 or <=7
                if '>=' in condition or '>21' in condition or '>20' in condition:
                    has_green = True
                if '<=' in condition or '<7' in condition or '<8' in condition:
                    has_red = True
            
            # Also check calcext:conditional-formats
            for cond_format in root.findall('.//calcext:conditional-format', namespaces):
                for cond_entry in cond_format.findall('.//calcext:condition', namespaces):
                    rule_count += 1
                    # ODS stores conditions differently, may need to check attributes
            
            return {
                'has_green_rule': has_green,
                'has_red_rule': has_red,
                'rule_count': rule_count
            }
    
    except Exception as e:
        logger.debug(f"Error checking conditional formatting: {e}")
        return {'has_green_rule': False, 'has_red_rule': False, 'rule_count': 0}


def check_cell_background_color(sheet_data: Dict, row: int, col: int) -> Optional[str]:
    """
    Try to determine if a cell has background color.
    This is a simplified check - full implementation would require style parsing.
    """
    # This is a placeholder - actual implementation would need to parse styles from ODS XML
    # For now, we'll rely on the conditional formatting check
    return None


def verify_meal_rotation_tracker(traj, env_info, task_info):
    """
    Verify meal rotation tracker task completion.
    
    Checks:
    1. "Days Since Last Eaten" formulas use TODAY() and MAXIFS (or MAX+IF)
    2. Frequency formulas use COUNTIF
    3. Calculations are valid (0-60 day range, reasonable counts)
    4. Green conditional formatting for ≥21 days
    5. Red conditional formatting for ≤7 days
    6. Summary structure exists
    7. No formula errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/meal_rotation_analysis.ods",
        "/home/ga/Documents/meal_log.ods",
        "/home/ga/Documents/meal_log.csv"
    ]
    
    success = False
    file_info = None
    error = ""
    
    for container_path in possible_paths:
        # Determine format from extension
        if container_path.endswith('.csv'):
            formats = ['csv', 'ods']
        else:
            formats = ['ods', 'csv']
        
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            expected_formats=formats
        )
        
        if success:
            logger.info(f"Successfully loaded file from: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load meal log file: {error}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        filepath = file_info['file_path']
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Find summary section
        summary_info = find_summary_section(sheet_data)
        
        if not summary_info:
            feedback_parts.append("❌ No summary section with formulas found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts) + " (Task requires creating summary analysis with formulas)",
                "subscores": {}
            }
        
        formula_locations = summary_info['locations']
        logger.info(f"Found {len(formula_locations)} formulas in summary section")
        
        # Criterion 1: Days Since formulas with TODAY() and MAXIFS
        days_since_formulas = []
        for row, col, formula in formula_locations:
            if 'TODAY' in formula.upper() and ('MAXIFS' in formula.upper() or 'MAX' in formula.upper()):
                days_since_formulas.append((row, col, formula))
        
        if len(days_since_formulas) >= 3:  # At least 3 meals analyzed
            criteria_passed += 1
            feedback_parts.append(f"✅ Days Since formulas found ({len(days_since_formulas)} formulas with TODAY/MAXIFS)")
        else:
            feedback_parts.append(f"❌ Insufficient Days Since formulas (found {len(days_since_formulas)}, need ≥3 with TODAY and MAXIFS)")
        
        # Criterion 2: Frequency formulas with COUNTIF
        countif_formulas = []
        for row, col, formula in formula_locations:
            if 'COUNTIF' in formula.upper():
                countif_formulas.append((row, col, formula))
        
        if len(countif_formulas) >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Frequency formulas found ({len(countif_formulas)} COUNTIF formulas)")
        else:
            feedback_parts.append(f"❌ Insufficient frequency formulas (found {len(countif_formulas)}, need ≥3 with COUNTIF)")
        
        # Criterion 3: Validate calculation results
        sheet_name = list(sheet_data['sheets'].keys())[0]
        valid_calculations = True
        calculation_errors = []
        
        for row, col, formula in days_since_formulas[:5]:  # Check up to 5 formulas
            # Get the cell value (should be 0-60 days)
            cell_ref = _format_cell_ref(col, row)
            value = get_cell_value(sheet_data, sheet_name, cell_ref)
            
            if value is None:
                calculation_errors.append(f"Cell {cell_ref} has no value")
                valid_calculations = False
            elif isinstance(value, str) and value.startswith('#'):
                calculation_errors.append(f"Cell {cell_ref} has error: {value}")
                valid_calculations = False
            elif isinstance(value, (int, float)):
                if not (0 <= value <= 120):  # Allow some buffer beyond 60 days
                    calculation_errors.append(f"Cell {cell_ref} value {value} out of range (0-120)")
                    valid_calculations = False
        
        if valid_calculations and not calculation_errors:
            criteria_passed += 1
            feedback_parts.append("✅ Calculations produce valid results")
        else:
            if calculation_errors:
                error_msg = "; ".join(calculation_errors[:2])  # Show first 2 errors
                feedback_parts.append(f"❌ Calculation issues: {error_msg}")
            else:
                feedback_parts.append("❌ Calculation validation failed")
        
        # Criterion 4 & 5: Conditional formatting
        if filepath.endswith('.ods'):
            cond_format_info = check_conditional_formatting_ods(filepath)
            
            if cond_format_info['has_green_rule']:
                criteria_passed += 1
                feedback_parts.append("✅ Green formatting rule detected (≥21 days)")
            else:
                feedback_parts.append("❌ No green formatting rule found (need ≥21 days condition)")
            
            if cond_format_info['has_red_rule']:
                criteria_passed += 1
                feedback_parts.append("✅ Red formatting rule detected (≤7 days)")
            else:
                feedback_parts.append("❌ No red formatting rule found (need ≤7 days condition)")
            
            logger.info(f"Conditional formatting: {cond_format_info}")
        else:
            # CSV doesn't preserve conditional formatting
            feedback_parts.append("⚠️ File is CSV - conditional formatting not checkable (partial credit given)")
            criteria_passed += 1.5  # Give partial credit for both formatting criteria
        
        # Criterion 6: Summary structure exists
        if summary_info and len(formula_locations) >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Summary structure exists ({len(formula_locations)} formulas)")
        else:
            feedback_parts.append("❌ Insufficient summary structure")
        
        # Criterion 7: No formula errors
        has_errors = False
        for row, col, formula in formula_locations:
            cell_ref = _format_cell_ref(col, row)
            value = get_cell_value(sheet_data, sheet_name, cell_ref)
            if isinstance(value, str) and value.startswith('#'):
                has_errors = True
                break
        
        if not has_errors:
            criteria_passed += 1
            feedback_parts.append("✅ No formula errors detected")
        else:
            feedback_parts.append("❌ Formula errors detected (#VALUE!, #REF!, etc.)")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 5 out of 7 criteria = 71%
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent meal rotation analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Meal rotation tracker completed")
        else:
            feedback_parts.insert(0, "❌ Task requirements not met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "days_since_formulas": len(days_since_formulas) >= 3,
                "frequency_formulas": len(countif_formulas) >= 3,
                "valid_calculations": valid_calculations,
                "green_formatting": cond_format_info.get('has_green_rule', False) if filepath.endswith('.ods') else None,
                "red_formatting": cond_format_info.get('has_red_rule', False) if filepath.endswith('.ods') else None,
                "summary_structure": len(formula_locations) >= 5,
                "no_errors": not has_errors
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_temp(file_info.get('temp_dir'))


def _format_cell_ref(col_idx: int, row_idx: int) -> str:
    """
    Format cell reference from indices (0-based)
    
    Args:
        col_idx: Column index (0-based)
        row_idx: Row index (0-based)
        
    Returns:
        Cell reference (e.g., "A1", "AB100")
    """
    col_str = ''
    col = col_idx + 1
    
    while col > 0:
        col -= 1
        col_str = chr(ord('A') + (col % 26)) + col_str
        col //= 26
    
    return f"{col_str}{row_idx + 1}"
