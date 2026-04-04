#!/usr/bin/env python3
"""
Verifier for Seed Inventory Spring Exchange task

This task verifies that the agent created a seed inventory spreadsheet with:
- Correct headers in row 1
- Three rows of seed data with proper values and types
- Numeric columns containing actual numbers (not text)
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_text(text):
    """Normalize text for comparison: lowercase and strip whitespace"""
    if text is None:
        return ""
    return str(text).strip().lower()


def verify_seed_inventory(traj, env_info, task_info):
    """
    Verify that seed inventory spreadsheet was created correctly.

    Checks 4 main criteria:
    1. All 5 headers are correct
    2. Row 2 (Brandywine Tomato) data is complete and correct
    3. Row 3 (Detroit Dark Red Beet) data is complete and correct
    4. Row 4 (Scarlet Nantes Carrot) data is complete and correct
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/seed_exchange_inventory.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_seed_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Get the active sheet
        if wb.active:
            sheet = wb.active
        else:
            sheet = wb.worksheets[0] if wb.worksheets else None
        
        if sheet is None:
            return {"passed": False, "score": 0, "feedback": "No worksheet found in spreadsheet"}

        sheet_name = sheet.title
        criteria_passed = 0
        feedback_parts = []

        # ===== Criterion 1: Check all 5 headers are correct =====
        expected_headers = [
            ('A1', 'variety name'),
            ('B1', 'plant type'),
            ('C1', 'seeds available'),
            ('D1', 'year saved'),
            ('E1', 'germination notes')
        ]

        headers_correct = True
        header_issues = []
        
        for cell_ref, expected_text in expected_headers:
            cell_value = get_cell_value(wb, sheet_name, cell_ref)
            normalized_value = normalize_text(cell_value)
            
            if normalized_value != expected_text:
                headers_correct = False
                header_issues.append(f"{cell_ref}='{cell_value}'")

        if headers_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Headers correct")
        else:
            feedback_parts.append(f"❌ Headers incorrect: {', '.join(header_issues)}")

        # ===== Criterion 2: Check Row 2 (Brandywine Tomato) =====
        row2_data = {
            'A2': ('Brandywine Tomato', str),
            'B2': ('Tomato', str),
            'C2': (45, int),
            'D2': (2024, int),
            'E2': ('Good germination last year', str)
        }

        row2_correct = True
        row2_issues = []

        for cell_ref, (expected_val, expected_type) in row2_data.items():
            cell_value = get_cell_value(wb, sheet_name, cell_ref)
            
            if expected_type == str:
                normalized_actual = normalize_text(cell_value)
                normalized_expected = normalize_text(expected_val)
                
                if normalized_actual != normalized_expected:
                    row2_correct = False
                    row2_issues.append(f"{cell_ref} text mismatch")
            
            elif expected_type == int:
                if cell_value is None:
                    row2_correct = False
                    row2_issues.append(f"{cell_ref} empty")
                elif not isinstance(cell_value, (int, float)):
                    row2_correct = False
                    row2_issues.append(f"{cell_ref} not numeric")
                elif int(cell_value) != expected_val:
                    row2_correct = False
                    row2_issues.append(f"{cell_ref}={cell_value} (expected {expected_val})")

        if row2_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Row 2 (Brandywine Tomato) correct")
        else:
            feedback_parts.append(f"❌ Row 2 issues: {', '.join(row2_issues)}")

        # ===== Criterion 3: Check Row 3 (Detroit Dark Red Beet) =====
        row3_data = {
            'A3': ('Detroit Dark Red Beet', str),
            'B3': ('Beet', str),
            'C3': (30, int),
            'D3': (2023, int),
            'E3': ('Older seeds - test before trading', str)
        }

        row3_correct = True
        row3_issues = []

        for cell_ref, (expected_val, expected_type) in row3_data.items():
            cell_value = get_cell_value(wb, sheet_name, cell_ref)
            
            if expected_type == str:
                normalized_actual = normalize_text(cell_value)
                normalized_expected = normalize_text(expected_val)
                
                if normalized_actual != normalized_expected:
                    row3_correct = False
                    row3_issues.append(f"{cell_ref} text mismatch")
            
            elif expected_type == int:
                if cell_value is None:
                    row3_correct = False
                    row3_issues.append(f"{cell_ref} empty")
                elif not isinstance(cell_value, (int, float)):
                    row3_correct = False
                    row3_issues.append(f"{cell_ref} not numeric")
                elif int(cell_value) != expected_val:
                    row3_correct = False
                    row3_issues.append(f"{cell_ref}={cell_value} (expected {expected_val})")

        if row3_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Row 3 (Detroit Dark Red Beet) correct")
        else:
            feedback_parts.append(f"❌ Row 3 issues: {', '.join(row3_issues)}")

        # ===== Criterion 4: Check Row 4 (Scarlet Nantes Carrot) =====
        row4_data = {
            'A4': ('Scarlet Nantes Carrot', str),
            'B4': ('Carrot', str),
            'C4': (60, int),
            'D4': (2024, int),
            'E4': ('Fresh seeds, high confidence', str)
        }

        row4_correct = True
        row4_issues = []

        for cell_ref, (expected_val, expected_type) in row4_data.items():
            cell_value = get_cell_value(wb, sheet_name, cell_ref)
            
            if expected_type == str:
                normalized_actual = normalize_text(cell_value)
                normalized_expected = normalize_text(expected_val)
                
                if normalized_actual != normalized_expected:
                    row4_correct = False
                    row4_issues.append(f"{cell_ref} text mismatch")
            
            elif expected_type == int:
                if cell_value is None:
                    row4_correct = False
                    row4_issues.append(f"{cell_ref} empty")
                elif not isinstance(cell_value, (int, float)):
                    row4_correct = False
                    row4_issues.append(f"{cell_ref} not numeric")
                elif int(cell_value) != expected_val:
                    row4_correct = False
                    row4_issues.append(f"{cell_ref}={cell_value} (expected {expected_val})")

        if row4_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Row 4 (Scarlet Nantes Carrot) correct")
        else:
            feedback_parts.append(f"❌ Row 4 issues: {', '.join(row4_issues)}")

        # Calculate final score
        score = int((criteria_passed / 4) * 100)
        passed = score >= 75

        feedback = " | ".join(feedback_parts)

        logger.info(f"Verification result: {criteria_passed}/4 criteria passed, score={score}, passed={passed}")

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)