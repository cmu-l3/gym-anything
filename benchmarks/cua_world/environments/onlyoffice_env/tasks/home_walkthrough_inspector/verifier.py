#!/usr/bin/env python3
"""
Verifier for Home Walkthrough Inspector task

This verifies that the agent created a proper home inspection spreadsheet with:
- Correct column headers
- 8 inspection findings with room names, issues, severity, and cost estimates
- Summary formulas calculating total repair costs
- Budget comparison calculations
"""

import sys
import os
import logging
import tempfile
import re
from typing import Any, Dict, Tuple, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_text(text: Any) -> str:
    """Normalize text for comparison - lowercase, strip whitespace"""
    if text is None:
        return ""
    return str(text).lower().strip()


def check_numeric_value(value: Any, expected_min: float, expected_max: float) -> bool:
    """Check if a numeric value falls within expected range"""
    if value is None:
        return False
    try:
        num_val = float(value)
        return expected_min <= num_val <= expected_max
    except (ValueError, TypeError):
        return False


def check_cell_has_formula(sheet: Any, cell_ref: str) -> bool:
    """Check if a cell contains a formula (starts with =)"""
    try:
        cell = sheet[cell_ref]
        # Check if cell has a formula
        if hasattr(cell, 'value') and cell.value is not None:
            cell_str = str(cell.value)
            if cell_str.startswith('='):
                return True
        # Also check _value attribute which may contain the formula
        if hasattr(cell, '_value'):
            formula_str = str(cell._value) if cell._value else ""
            if formula_str.startswith('='):
                return True
        # Check data_type
        if hasattr(cell, 'data_type') and cell.data_type == 'f':
            return True
    except Exception as e:
        logger.debug(f"Error checking formula in {cell_ref}: {e}")
    return False


def verify_home_walkthrough_inspector(traj, env_info, task_info):
    """
    Verify home inspection walkthrough spreadsheet.
    
    Scoring breakdown (100 points total):
    - File existence & basic structure: 10 points
    - Column headers: 10 points (2 points each × 5 headers)
    - Data entry accuracy: 32 points (4 points each × 8 rows)
    - Formula implementation: 28 points (10 + 10 + 4 + 4 for D11, E11, D13, E13)
    - Summary calculations correct: 20 points (5 + 5 + 4 + 3 + 3)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available in environment"
        }

    container_path = "/home/ga/Documents/Spreadsheets/home_inspection_walkthrough.xlsx"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')

    try:
        # Copy file from container
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ File not found or empty: {container_path}"
            }
        
        # Parse workbook
        wb = parse_xlsx_file(temp_file.name)
        if wb is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Failed to parse XLSX file - file may be corrupted"
            }
        
        score = 0.0
        feedback_parts = []
        
        # File exists and is valid - 10 points
        score += 10
        feedback_parts.append("✅ File created and valid XLSX format")
        
        # Get first sheet
        sheet_name = wb.sheetnames[0]
        sheet = wb[sheet_name]
        
        # ========== CHECK HEADERS (10 points - 2 per header) ==========
        header_score = 0
        
        h_a1 = normalize_text(get_cell_value(wb, sheet_name, 'A1'))
        h_b1 = normalize_text(get_cell_value(wb, sheet_name, 'B1'))
        h_c1 = normalize_text(get_cell_value(wb, sheet_name, 'C1'))
        h_d1 = normalize_text(get_cell_value(wb, sheet_name, 'D1'))
        h_e1 = normalize_text(get_cell_value(wb, sheet_name, 'E1'))
        
        if 'room' in h_a1 or 'area' in h_a1:
            header_score += 2
        if 'issue' in h_b1 or 'observ' in h_b1 or 'problem' in h_b1:
            header_score += 2
        if 'severity' in h_c1 or 'level' in h_c1 or 'priority' in h_c1:
            header_score += 2
        if ('min' in h_d1 or 'minimum' in h_d1) and 'cost' in h_d1:
            header_score += 2
        elif 'est' in h_d1 and 'cost' in h_d1:
            header_score += 1  # Partial credit
        if ('max' in h_e1 or 'maximum' in h_e1) and 'cost' in h_e1:
            header_score += 2
        elif 'est' in h_e1 and 'cost' in h_e1:
            header_score += 1  # Partial credit
        
        score += header_score
        if header_score >= 8:
            feedback_parts.append(f"✅ Headers present and correct ({header_score}/10 points)")
        elif header_score >= 5:
            feedback_parts.append(f"⚠️ Headers partially correct ({header_score}/10 points)")
        else:
            feedback_parts.append(f"❌ Headers missing or incorrect ({header_score}/10 points)")
        
        # ========== CHECK DATA ROWS (32 points - 4 per row) ==========
        data_checks = [
            {
                'row': 2, 
                'room_keywords': ['living', 'room'],
                'issue_keywords': ['water', 'stain', 'ceiling', 'musty'],
                'min_range': (1000, 2000),
                'max_range': (3000, 5000),
                'name': 'Living Room'
            },
            {
                'row': 3,
                'room_keywords': ['kitchen'],
                'issue_keywords': ['dishwasher', 'drain', 'water'],
                'min_range': (100, 400),
                'max_range': (600, 1200),
                'name': 'Kitchen'
            },
            {
                'row': 4,
                'room_keywords': ['bath', 'bathroom', 'master'],
                'issue_keywords': ['tile', 'floor', 'crack', 'soft'],
                'min_range': (600, 1500),
                'max_range': (2000, 5000),
                'name': 'Master Bath'
            },
            {
                'row': 5,
                'room_keywords': ['basement', 'foundation'],
                'issue_keywords': ['foundation', 'crack', 'visible'],
                'min_range': (1500, 3500),
                'max_range': (6000, 10000),
                'name': 'Basement'
            },
            {
                'row': 6,
                'room_keywords': ['roof', 'exterior'],
                'issue_keywords': ['shingle', 'damage', 'missing'],
                'min_range': (300, 700),
                'max_range': (800, 1800),
                'name': 'Roof'
            },
            {
                'row': 7,
                'room_keywords': ['electric', 'electrical', 'panel'],
                'issue_keywords': ['panel', 'amp', 'service', 'rust', '100'],
                'min_range': (1000, 1800),
                'max_range': (2000, 4000),
                'name': 'Electrical Panel'
            },
            {
                'row': 8,
                'room_keywords': ['hvac', 'furnace', 'heating'],
                'issue_keywords': ['furnace', 'dated', '1998', 'old', 'loud'],
                'min_range': (2500, 4500),
                'max_range': (4500, 7500),
                'name': 'HVAC'
            },
            {
                'row': 9,
                'room_keywords': ['window', 'windows'],
                'issue_keywords': ['seal', 'fog', 'broken', 'foggy', 'broken'],
                'min_range': (700, 1300),
                'max_range': (1400, 2500),
                'name': 'Windows'
            },
        ]
        
        data_score = 0
        rows_correct = 0
        
        for check in data_checks:
            row_num = check['row']
            row_score = 0
            
            room_text = normalize_text(get_cell_value(wb, sheet_name, f'A{row_num}'))
            issue_text = normalize_text(get_cell_value(wb, sheet_name, f'B{row_num}'))
            severity_text = normalize_text(get_cell_value(wb, sheet_name, f'C{row_num}'))
            
            min_cost = get_cell_value(wb, sheet_name, f'D{row_num}')
            max_cost = get_cell_value(wb, sheet_name, f'E{row_num}')
            
            # Check room name (1 point)
            if any(keyword in room_text for keyword in check['room_keywords']):
                row_score += 1
            
            # Check issue description (1 point)
            if any(keyword in issue_text for keyword in check['issue_keywords']):
                row_score += 1
            
            # Check severity is present and valid (0.5 points)
            if severity_text and any(s in severity_text for s in ['minor', 'moderate', 'major', 'low', 'medium', 'high']):
                row_score += 0.5
            
            # Check min cost (0.75 points)
            if check_numeric_value(min_cost, check['min_range'][0], check['min_range'][1]):
                row_score += 0.75
            
            # Check max cost (0.75 points)
            if check_numeric_value(max_cost, check['max_range'][0], check['max_range'][1]):
                row_score += 0.75
            
            data_score += row_score
            if row_score >= 3.5:
                rows_correct += 1
        
        score += data_score
        if rows_correct >= 6:
            feedback_parts.append(f"✅ Inspection data entered correctly ({rows_correct}/8 rows complete, {data_score:.1f}/32 points)")
        elif rows_correct >= 4:
            feedback_parts.append(f"⚠️ Most inspection data present ({rows_correct}/8 rows, {data_score:.1f}/32 points)")
        else:
            feedback_parts.append(f"❌ Inspection data incomplete ({rows_correct}/8 rows, {data_score:.1f}/32 points)")
        
        # ========== CHECK FORMULAS (28 points) ==========
        formula_score = 0
        
        # Check D11 has SUM formula (10 points)
        has_d11_formula = check_cell_has_formula(sheet, 'D11')
        d11_value = get_cell_value(wb, sheet_name, 'D11')
        
        if has_d11_formula:
            formula_score += 10
            feedback_parts.append("✅ D11 has SUM formula for minimum costs")
        elif check_numeric_value(d11_value, 9700, 10200):
            formula_score += 6  # Partial credit for correct value without formula
            feedback_parts.append("⚠️ D11 has correct value (~9950) but may not be a formula")
        else:
            feedback_parts.append("❌ D11 missing SUM formula or incorrect value")
        
        # Check E11 has SUM formula (10 points)
        has_e11_formula = check_cell_has_formula(sheet, 'E11')
        e11_value = get_cell_value(wb, sheet_name, 'E11')
        
        if has_e11_formula:
            formula_score += 10
            feedback_parts.append("✅ E11 has SUM formula for maximum costs")
        elif check_numeric_value(e11_value, 27800, 28800):
            formula_score += 6  # Partial credit
            feedback_parts.append("⚠️ E11 has correct value (~28300) but may not be a formula")
        else:
            feedback_parts.append("❌ E11 missing SUM formula or incorrect value")
        
        # Check D13 has subtraction formula (4 points)
        has_d13_formula = check_cell_has_formula(sheet, 'D13')
        if has_d13_formula:
            formula_score += 4
            feedback_parts.append("✅ D13 has formula for budget calculation")
        else:
            d13_value = get_cell_value(wb, sheet_name, 'D13')
            if check_numeric_value(d13_value, 4700, 5500):
                formula_score += 2  # Partial credit
                feedback_parts.append("⚠️ D13 has plausible value but may not be a formula")
        
        # Check E13 has subtraction formula (4 points)
        has_e13_formula = check_cell_has_formula(sheet, 'E13')
        if has_e13_formula:
            formula_score += 4
            feedback_parts.append("✅ E13 has formula for budget calculation")
        else:
            e13_value = get_cell_value(wb, sheet_name, 'E13')
            if check_numeric_value(e13_value, -14000, -12500):
                formula_score += 2  # Partial credit
                feedback_parts.append("⚠️ E13 has plausible value but may not be a formula")
        
        score += formula_score
        
        # ========== CHECK SUMMARY CALCULATIONS (20 points) ==========
        calc_score = 0
        
        # Check D11 calculation result (5 points)
        if check_numeric_value(d11_value, 9700, 10200):  # Expected ~9950
            calc_score += 5
        elif check_numeric_value(d11_value, 9000, 11000):  # Wider tolerance
            calc_score += 3
        
        # Check E11 calculation result (5 points)
        if check_numeric_value(e11_value, 27800, 28800):  # Expected ~28300
            calc_score += 5
        elif check_numeric_value(e11_value, 26000, 30000):  # Wider tolerance
            calc_score += 3
        
        # Check D12 and E12 have budget values (4 points)
        d12_value = get_cell_value(wb, sheet_name, 'D12')
        e12_value = get_cell_value(wb, sheet_name, 'E12')
        
        if check_numeric_value(d12_value, 14500, 15500):  # Expected 15000
            calc_score += 2
        if check_numeric_value(e12_value, 14500, 15500):  # Expected 15000
            calc_score += 2
        
        # Check D13 calculation (3 points)
        d13_value = get_cell_value(wb, sheet_name, 'D13')
        if check_numeric_value(d13_value, 4700, 5500):  # Expected ~5050
            calc_score += 3
        elif check_numeric_value(d13_value, 3000, 7000):
            calc_score += 1.5
        
        # Check E13 calculation (3 points)
        e13_value = get_cell_value(wb, sheet_name, 'E13')
        if check_numeric_value(e13_value, -14000, -12500):  # Expected ~-13300
            calc_score += 3
        elif check_numeric_value(e13_value, -16000, -10000):
            calc_score += 1.5
        
        score += calc_score
        
        if calc_score >= 16:
            feedback_parts.append(f"✅ Budget calculations accurate ({calc_score:.1f}/20 points)")
        elif calc_score >= 10:
            feedback_parts.append(f"⚠️ Budget calculations mostly correct ({calc_score:.1f}/20 points)")
        else:
            feedback_parts.append(f"❌ Budget calculations need review ({calc_score:.1f}/20 points)")
        
        # ========== DETERMINE PASS/FAIL ==========
        passed = score >= 70
        
        # Add summary feedback
        if passed:
            feedback_parts.insert(0, f"🎉 Task completed successfully! Total score: {score:.1f}/100")
        else:
            feedback_parts.insert(0, f"❌ Task incomplete. Total score: {score:.1f}/100 (need 70+ to pass)")
        
        return {
            "passed": passed,
            "score": float(score),
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        # Clean up temp file
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except Exception as e:
                logger.warning(f"Failed to delete temp file: {e}")
