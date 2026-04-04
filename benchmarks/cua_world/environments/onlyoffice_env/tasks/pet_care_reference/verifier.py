#!/usr/bin/env python3
"""
Verifier for Pet Care Reference task
"""

import sys
import os
import logging
import tempfile
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_pet_care_reference(traj, env_info, task_info):
    """
    Verify the pet care reference spreadsheet.
    
    Checks:
    1. File exists and is parseable (20 points)
    2. Has header row with required columns (20 points)
    3. Has at least 2 data rows for 2 pets (20 points)
    4. Contains at least one formula (20 points)
    5. Header row has formatting (10 points)
    6. Contains realistic pet data (10 points)
    
    Pass threshold: 70/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/pet_care_reference.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_pet_')

    try:
        # Check 1: File exists and can be parsed (20 points)
        success, workbook, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            file_format='xlsx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ File not found or cannot be parsed: {error}"
            }
        
        score = 20
        feedback_parts = []
        feedback_parts.append("✅ File exists and is valid XLSX format")
        
        # Get the first sheet
        if not workbook.sheetnames:
            return {
                "passed": False,
                "score": 0.2,
                "feedback": "❌ Spreadsheet has no sheets"
            }
        
        sheet_name = workbook.sheetnames[0]
        sheet = workbook[sheet_name]
        
        # Get all data
        data = get_sheet_data(workbook, sheet_name, max_rows=20, max_cols=15)
        
        if not data or len(data) == 0:
            return {
                "passed": False,
                "score": 0.2,
                "feedback": "❌ Spreadsheet is empty"
            }
        
        # Check 2: Has header row with required keywords (20 points)
        header_row = [str(cell).lower() if cell else "" for cell in data[0]]
        header_row_str = " ".join(header_row)
        
        required_keywords = ["name", "medication", "feeding", "appointment"]
        found_keywords = []
        
        for keyword in required_keywords:
            if any(keyword in col for col in header_row):
                found_keywords.append(keyword)
        
        keyword_score = (len(found_keywords) / len(required_keywords)) * 20
        score += keyword_score
        
        if len(found_keywords) >= 3:
            feedback_parts.append(f"✅ Header row contains key columns ({len(found_keywords)}/4 keywords)")
        else:
            feedback_parts.append(f"⚠️ Header row missing some expected columns (found {len(found_keywords)}/4)")
        
        # Check 3: Has at least 2 data rows (20 points)
        non_empty_rows = 0
        data_rows = []
        
        for row_idx, row in enumerate(data[1:], start=2):  # Skip header
            # Check if row has at least 3 non-empty cells
            filled_cells = sum(1 for cell in row if cell is not None and str(cell).strip() != "")
            if filled_cells >= 3:
                non_empty_rows += 1
                data_rows.append(row_idx)
        
        if non_empty_rows >= 2:
            score += 20
            feedback_parts.append(f"✅ Contains {non_empty_rows} pet records (minimum 2 required)")
        elif non_empty_rows == 1:
            score += 10
            feedback_parts.append(f"⚠️ Only {non_empty_rows} pet record found, need at least 2")
        else:
            feedback_parts.append(f"❌ No complete pet records found")
        
        # Check 4: Contains at least one formula (20 points)
        has_formula = False
        formula_cells = []
        formula_count = 0
        
        # Check for formulas in the sheet
        for row_idx, row in enumerate(sheet.iter_rows(max_row=10, max_col=15), start=1):
            for col_idx, cell in enumerate(row, start=1):
                # Check if cell has a formula
                if hasattr(cell, 'value') and cell.value:
                    # Check for formula string (starts with =)
                    if isinstance(cell.value, str) and cell.value.startswith('='):
                        has_formula = True
                        formula_count += 1
                        col_letter = chr(64 + col_idx) if col_idx <= 26 else f"A{chr(64 + col_idx - 26)}"
                        formula_cells.append(f"{col_letter}{row_idx}")
                # Also check data_type for formula
                if hasattr(cell, 'data_type') and cell.data_type == 'f':
                    has_formula = True
                    formula_count += 1
                    col_letter = chr(64 + col_idx) if col_idx <= 26 else f"A{chr(64 + col_idx - 26)}"
                    if f"{col_letter}{row_idx}" not in formula_cells:
                        formula_cells.append(f"{col_letter}{row_idx}")
        
        if has_formula:
            score += 20
            feedback_parts.append(f"✅ Contains {formula_count} formula(s): {', '.join(formula_cells[:3])}")
        else:
            feedback_parts.append("❌ No formulas detected (expected date calculation)")
        
        # Check 5: Header formatting (10 points)
        header_cells = [sheet.cell(1, col) for col in range(1, min(9, sheet.max_column + 1))]
        bold_count = sum(1 for cell in header_cells if cell.font and cell.font.bold)
        
        if bold_count >= 3:
            score += 10
            feedback_parts.append(f"✅ Header row is formatted ({bold_count} cells bold)")
        elif bold_count > 0:
            score += 5
            feedback_parts.append(f"⚠️ Header row partially formatted ({bold_count} cells bold)")
        else:
            feedback_parts.append("⚠️ Header row not formatted (consider making it bold)")
        
        # Check 6: Contains realistic pet data (10 points)
        # Collect all text from data rows
        data_text = " ".join([
            str(cell).lower() 
            for row in data[1:] 
            for cell in row 
            if cell is not None
        ])
        
        # Check for pet-related indicators
        pet_indicators = {
            "pet_names": ["bella", "max"],
            "dog_breeds": ["golden", "retriever", "mixed", "rescue", "breed"],
            "medications": ["carprofen", "apoquel", "mg", "medication"],
            "feeding": ["cup", "daily", "twice"],
            "dates": any(isinstance(cell, datetime) for row in data[1:] for cell in row)
        }
        
        indicator_score = 0
        found_categories = []
        
        # Check pet names
        if any(name in data_text for name in pet_indicators["pet_names"]):
            indicator_score += 2
            found_categories.append("pet names")
        
        # Check breeds
        if any(breed in data_text for breed in pet_indicators["dog_breeds"]):
            indicator_score += 2
            found_categories.append("breed info")
        
        # Check medications
        if any(med in data_text for med in pet_indicators["medications"]):
            indicator_score += 2
            found_categories.append("medications")
        
        # Check feeding info
        if any(feed in data_text for feed in pet_indicators["feeding"]):
            indicator_score += 2
            found_categories.append("feeding info")
        
        # Check dates
        if pet_indicators["dates"]:
            indicator_score += 2
            found_categories.append("appointment dates")
        
        score += indicator_score
        
        if indicator_score >= 6:
            feedback_parts.append(f"✅ Contains realistic pet care data ({', '.join(found_categories)})")
        elif indicator_score > 0:
            feedback_parts.append(f"⚠️ Some pet data present ({', '.join(found_categories)})")
        else:
            feedback_parts.append("⚠️ Missing expected pet information")
        
        # Determine pass/fail
        passed = score >= 70
        normalized_score = score / 100.0
        
        feedback = " | ".join(feedback_parts)
        final_feedback = f"Score: {score}/100 - {feedback}"
        
        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": final_feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if temp_dir and os.path.exists(temp_dir):
            cleanup_temp_dir(temp_dir)
