#!/usr/bin/env python3
"""
Verifier for Practice Log Analyzer task.
Validates formula creation, calculated values, status assignment, and conditional formatting.
"""

import sys
import os
import logging
import re
import zipfile
from xml.etree import ElementTree as ET

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    verify_cell_value
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_conditional_formatting_in_ods(filepath, sheet_name=None):
    """
    Check if conditional formatting exists in ODS file.
    
    Args:
        filepath: Path to ODS file
        sheet_name: Sheet name to check (optional)
    
    Returns:
        bool: True if conditional formatting detected
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for conditional formatting elements
            # In ODS, this is typically in style:map elements or calcext:conditional-formats
            namespaces = {
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'calcext': 'urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0'
            }
            
            # Check for conditional format elements
            cond_formats = root.findall('.//calcext:conditional-formats', namespaces)
            if cond_formats:
                logger.info(f"Found {len(cond_formats)} conditional format definitions")
                return True
            
            # Also check for style maps (older method)
            style_maps = root.findall('.//style:map', namespaces)
            if style_maps:
                logger.info(f"Found {len(style_maps)} style map definitions")
                return True
            
            # Check for cells with conditional styles
            cells = root.findall('.//table:table-cell', namespaces)
            for cell in cells:
                style_name = cell.get('{urn:oasis:names:tc:opendocument:xmlns:table:1.0}style-name', '')
                if 'condition' in style_name.lower() or 'conditional' in style_name.lower():
                    logger.info("Found cell with conditional style")
                    return True
            
            return False
            
    except Exception as e:
        logger.warning(f"Could not check conditional formatting: {e}")
        return False


def normalize_formula(formula):
    """Normalize formula for comparison (remove spaces, uppercase functions)"""
    if not formula:
        return ""
    # Remove spaces and convert to uppercase
    normalized = formula.replace(' ', '').upper()
    return normalized


def check_sum_formula(formula, expected_range_pattern=r'C\d+:F\d+'):
    """Check if formula is a valid SUM formula"""
    if not formula:
        return False
    normalized = normalize_formula(formula)
    # Check for SUM function with expected range
    if 'SUM' not in normalized:
        return False
    # Check for range pattern
    if not re.search(expected_range_pattern, normalized):
        return False
    return True


def check_percentage_formula(formula, row_num):
    """Check if formula calculates percentage correctly"""
    if not formula:
        return False
    normalized = normalize_formula(formula)
    # Should have division and multiplication by 100
    # Could be (F/G)*100 or similar
    has_division = '/' in normalized
    has_multiplication = '*100' in normalized
    # Should reference appropriate columns (F and G)
    has_f_ref = f'F{row_num}' in normalized or 'F' in normalized[:20]
    has_g_ref = f'G{row_num}' in normalized or 'G' in normalized[:20]
    
    return has_division and (has_multiplication or '100' in normalized) and has_f_ref and has_g_ref


def check_status_formula(formula, row_num):
    """Check if formula implements status logic with IF statements"""
    if not formula:
        return False
    normalized = normalize_formula(formula)
    
    # Must have IF statements
    if normalized.count('IF') < 2:  # Nested IFs needed
        return False
    
    # Should reference percentage column (H)
    if f'H{row_num}' not in normalized and 'H' not in normalized[:30]:
        return False
    
    # Check for threshold values (100, 80, 50)
    has_100 = '100' in normalized
    has_80 = '80' in normalized
    has_50 = '50' in normalized
    
    # Should have at least 2 of the 3 thresholds
    threshold_count = sum([has_100, has_80, has_50])
    
    # Check for status text
    has_status_text = any(text in normalized for text in ['EXCELLENT', 'ONTRACK', 'NEEDS', 'URGENT'])
    
    return threshold_count >= 2 and has_status_text


def check_counta_formula(formula, expected_range_pattern=r'C\d+:F\d+'):
    """Check if formula counts non-empty cells"""
    if not formula:
        return False
    normalized = normalize_formula(formula)
    return 'COUNTA' in normalized and re.search(expected_range_pattern, normalized)


def check_countif_formula(formula, row_num):
    """Check if formula counts cells meeting goal"""
    if not formula:
        return False
    normalized = normalize_formula(formula)
    # Should have COUNTIF with range and criteria referencing weekly goal
    has_countif = 'COUNTIF' in normalized
    has_range = re.search(r'C\d+:F\d+', normalized)
    has_criteria = f'B{row_num}' in normalized or '>=' in normalized
    
    return has_countif and has_range and has_criteria


def verify_practice_log_analyzer(traj, env_info, task_info):
    """
    Verify practice log analyzer task completion.
    
    Checks:
    1. Total Practice calculated with SUM formulas
    2. Goal Percentage calculated correctly
    3. Status assigned with IF formulas
    4. Consistency metrics (COUNTA, COUNTIF) present
    5. Conditional formatting applied
    6. Sample student calculations verified
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try both ODS and CSV formats
    success = False
    for container_path in ["/home/ga/Documents/practice_log.ods", 
                          "/home/ga/Documents/practice_log.csv"]:
        file_format = 'ods' if container_path.endswith('.ods') else 'csv'
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            [file_format]
        )
        if success:
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    try:
        data = file_info['sheet_data']
        sheet_name = list(data['sheets'].keys())[0]
        filepath = file_info['file_path']
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Sample students to verify (rows 2, 3, 4 = Emma, Marcus, Sophia)
        sample_students = [
            {
                'row': 2,
                'name': 'Emma Johnson',
                'weekly_goal': 120,
                'weeks': [130, 125, 115, 140],
                'expected_total': 510,
                'expected_pct': 106.25,
                'expected_status': 'EXCELLENT'
            },
            {
                'row': 3,
                'name': 'Marcus Lee',
                'weekly_goal': 90,
                'weeks': [95, 85, None, 80],  # Missing Week 3
                'expected_total': 260,
                'expected_pct': 72.22,
                'expected_status': 'NEEDS ENCOURAGEMENT'
            },
            {
                'row': 4,
                'name': 'Sophia Chen',
                'weekly_goal': 150,
                'weeks': [60, 55, 70, 65],
                'expected_total': 250,
                'expected_pct': 41.67,
                'expected_status': 'URGENT CHECK-IN'
            }
        ]
        
        # Criterion 1: Total Practice calculated with SUM
        sum_formulas_found = 0
        sum_values_correct = 0
        
        for student in sample_students:
            row = student['row']
            # Total Practice is likely in column F (index 5)
            # But let's search columns E-H for it
            total_formula = None
            total_value = None
            
            for col in ['F', 'G', 'H']:
                cell_ref = f'{col}{row}'
                formula = get_cell_formula(data, sheet_name, cell_ref)
                value = get_cell_value(data, sheet_name, cell_ref)
                
                if formula and check_sum_formula(formula):
                    total_formula = formula
                    total_value = value
                    break
            
            if total_formula:
                sum_formulas_found += 1
                # Verify the calculated value
                if total_value and abs(float(total_value) - student['expected_total']) <= 1:
                    sum_values_correct += 1
        
        if sum_formulas_found >= 2:
            criteria_passed += 1
            subscores['sum_formulas'] = True
            feedback_parts.append(f"✅ Total Practice SUM formulas found ({sum_formulas_found}/3 samples)")
        else:
            subscores['sum_formulas'] = False
            feedback_parts.append(f"❌ Total Practice SUM formulas missing or incorrect ({sum_formulas_found}/3)")
        
        # Criterion 2: Goal Percentage calculated
        pct_formulas_found = 0
        pct_values_correct = 0
        
        for student in sample_students:
            row = student['row']
            pct_formula = None
            pct_value = None
            
            # Percentage likely in columns G-J
            for col in ['G', 'H', 'I', 'J']:
                cell_ref = f'{col}{row}'
                formula = get_cell_formula(data, sheet_name, cell_ref)
                value = get_cell_value(data, sheet_name, cell_ref)
                
                if formula and check_percentage_formula(formula, row):
                    pct_formula = formula
                    pct_value = value
                    break
            
            if pct_formula:
                pct_formulas_found += 1
                # Verify calculated value (±2% tolerance for rounding)
                if pct_value and abs(float(pct_value) - student['expected_pct']) <= 2.0:
                    pct_values_correct += 1
        
        if pct_formulas_found >= 2:
            criteria_passed += 1
            subscores['percentage_formulas'] = True
            feedback_parts.append(f"✅ Goal percentage calculated correctly ({pct_formulas_found}/3 samples)")
        else:
            subscores['percentage_formulas'] = False
            feedback_parts.append(f"❌ Goal percentage formulas missing or incorrect ({pct_formulas_found}/3)")
        
        # Criterion 3: Status assigned with IF formulas
        status_formulas_found = 0
        status_values_correct = 0
        
        for student in sample_students:
            row = student['row']
            status_formula = None
            status_value = None
            
            # Status likely in columns H-K
            for col in ['H', 'I', 'J', 'K']:
                cell_ref = f'{col}{row}'
                formula = get_cell_formula(data, sheet_name, cell_ref)
                value = get_cell_value(data, sheet_name, cell_ref)
                
                if formula and check_status_formula(formula, row):
                    status_formula = formula
                    status_value = value
                    break
            
            if status_formula:
                status_formulas_found += 1
                # Check if status value matches expected (case-insensitive, partial match)
                if status_value:
                    status_str = str(status_value).upper().replace(' ', '')
                    expected_str = student['expected_status'].replace(' ', '')
                    if expected_str in status_str or status_str in expected_str:
                        status_values_correct += 1
        
        if status_formulas_found >= 2:
            criteria_passed += 1
            subscores['status_formulas'] = True
            feedback_parts.append(f"✅ Status IF formulas present ({status_formulas_found}/3 samples)")
        else:
            subscores['status_formulas'] = False
            feedback_parts.append(f"❌ Status IF formulas missing ({status_formulas_found}/3)")
        
        # Criterion 4: Consistency metrics (COUNTA or COUNTIF present)
        consistency_formulas_found = 0
        
        # Check row 2 for these formulas in columns I-M
        for col in ['I', 'J', 'K', 'L', 'M']:
            formula = get_cell_formula(data, sheet_name, f'{col}2')
            if formula:
                normalized = normalize_formula(formula)
                if 'COUNTA' in normalized or 'COUNTIF' in normalized:
                    consistency_formulas_found += 1
        
        if consistency_formulas_found >= 1:
            criteria_passed += 1
            subscores['consistency_metrics'] = True
            feedback_parts.append(f"✅ Consistency metrics found (COUNTA/COUNTIF)")
        else:
            subscores['consistency_metrics'] = False
            feedback_parts.append("❌ Consistency metrics missing (no COUNTA/COUNTIF)")
        
        # Criterion 5: Conditional formatting applied
        has_conditional_formatting = False
        if filepath.endswith('.ods'):
            has_conditional_formatting = check_conditional_formatting_in_ods(filepath, sheet_name)
        
        if has_conditional_formatting:
            criteria_passed += 1
            subscores['conditional_formatting'] = True
            feedback_parts.append("✅ Conditional formatting detected")
        else:
            subscores['conditional_formatting'] = False
            feedback_parts.append("⚠️ Conditional formatting not detected (check manually)")
            # Give partial credit since this is hard to detect
            criteria_passed += 0.3
        
        # Criterion 6: Sample validation - at least 2 students calculated correctly
        samples_correct = sum([
            1 if sum_values_correct >= 2 else 0,
            1 if pct_values_correct >= 2 else 0,
            1 if status_values_correct >= 2 else 0
        ])
        
        if samples_correct >= 2:
            criteria_passed += 1
            subscores['sample_validation'] = True
            feedback_parts.append("✅ Sample student calculations verified")
        else:
            subscores['sample_validation'] = False
            feedback_parts.append(f"❌ Sample validation failed (only {samples_correct}/3 types correct)")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold = 4.2/6 criteria
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent practice log analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Practice log analysis completed")
        else:
            feedback_parts.insert(0, "❌ Analysis incomplete or incorrect")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
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
        cleanup_verification_temp(file_info.get('temp_dir'))
