#!/usr/bin/env python3
"""
Verifier for Shelf Cut Optimizer task
"""

import sys
import os
import logging
import tempfile
import re
from collections import Counter

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_shelf_cut_optimizer(traj, env_info, task_info):
    """
    Verify that shelf cutting plan optimization was completed correctly.

    Checks:
    1. All required pieces are accounted for (3×34", 6×9", 2×32")
    2. Cutting plan with formulas (evidence of calculation, not just typing)
    3. Kerf (0.125") is accounted for in calculations
    4. Waste calculation present
    5. Minimum boards determined (optimal is 3 boards)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/shelf_project.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_shelf_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        sheet = wb.active
        data = get_sheet_data(wb, sheet.title, max_rows=100, max_cols=15)

        score = 0
        max_score = 100
        feedback_parts = []

        # Extract all text for searching
        all_text_lower = []
        all_numbers = []
        
        for row in data:
            for cell in row:
                if cell is not None:
                    cell_str = str(cell).strip()
                    all_text_lower.append(cell_str.lower())
                    # Extract numbers
                    numbers = re.findall(r'\b\d+\.?\d*\b', cell_str)
                    all_numbers.extend([float(n) for n in numbers])

        all_text_combined = ' '.join(all_text_lower)

        # ===================================================================
        # Criterion 1: All pieces accounted for (30 points)
        # ===================================================================
        required_pieces = {34: 3, 9: 6, 32: 2}
        
        # Count occurrences of each length in the working area (rows 25+)
        working_area_text = []
        working_area_numbers = []
        
        for row_idx, row in enumerate(data[25:], start=25):
            for cell in row:
                if cell is not None:
                    cell_str = str(cell).strip()
                    working_area_text.append(cell_str.lower())
                    numbers = re.findall(r'\b\d+\.?\d*\b', cell_str)
                    working_area_numbers.extend([float(n) for n in numbers])

        # Count occurrences of required lengths
        found_pieces = {34: 0, 9: 0, 32: 0}
        
        for length in required_pieces.keys():
            found_pieces[length] = working_area_numbers.count(float(length))
        
        pieces_score = 0
        missing_pieces = []
        
        for length, required_qty in required_pieces.items():
            if found_pieces[length] >= required_qty:
                pieces_score += 10
            else:
                deficit = required_qty - found_pieces[length]
                missing_pieces.append(f"{deficit}×{length}\"")
        
        score += pieces_score
        
        if pieces_score == 30:
            feedback_parts.append("✅ All required pieces accounted for (3×34\", 6×9\", 2×32\")")
        else:
            feedback_parts.append(f"❌ Missing pieces in cutting plan: {', '.join(missing_pieces) if missing_pieces else 'quantities incorrect'} (scored {pieces_score}/30)")

        # ===================================================================
        # Criterion 2: Valid cutting plan with formulas (25 points)
        # ===================================================================
        formula_count = 0
        has_addition_formulas = False
        max_board_length = 0
        board_length_violations = []
        
        # Check for formulas in working area
        for row_idx, row in enumerate(data[25:], start=25):
            for col_idx, cell_val in enumerate(row):
                if cell_val is None:
                    continue
                    
                cell_ref = f"{chr(65 + col_idx % 26)}{row_idx + 1}"
                try:
                    cell = sheet[cell_ref]
                    
                    # Check if it's a formula
                    if hasattr(cell, 'data_type') and cell.data_type == 'f':
                        formula_count += 1
                        # Check if formula contains addition (sum of pieces)
                        if hasattr(cell, 'value') and cell.value:
                            formula_str = str(cell.value).lower()
                            if '+' in formula_str or 'sum' in formula_str:
                                has_addition_formulas = True
                    
                    # Check for numbers that might represent board totals
                    if isinstance(cell.value, (int, float)):
                        if 50 <= cell.value <= 96:  # Likely a board length calculation
                            max_board_length = max(max_board_length, cell.value)
                            if cell.value > 96.5:  # Small tolerance for rounding
                                board_length_violations.append(f"{cell.value:.2f}")
                except Exception as e:
                    logger.debug(f"Error checking cell {cell_ref}: {e}")

        formula_score = 0
        
        if formula_count >= 3 and has_addition_formulas:
            formula_score = 25
            feedback_parts.append(f"✅ Valid cutting plan with formulas ({formula_count} formulas found)")
        elif formula_count >= 1:
            formula_score = 15
            feedback_parts.append(f"⚠️ Some formulas present ({formula_count}) but may be incomplete (scored 15/25)")
        else:
            feedback_parts.append("❌ No formulas detected - plan should use calculations (scored 0/25)")
        
        score += formula_score

        # ===================================================================
        # Criterion 3: Kerf accounted for (20 points)
        # ===================================================================
        kerf_score = 0
        kerf_mentioned = False
        kerf_in_formula = False
        
        # Check if 0.125 appears in working area or in formulas
        if 0.125 in working_area_numbers:
            kerf_mentioned = True
        
        # Check for 0.125 in text (formula reference)
        if '0.125' in all_text_combined or 'kerf' in all_text_combined:
            kerf_mentioned = True
        
        # More sophisticated check: look for evidence of kerf in calculations
        # If we see formulas with multiplication or addition involving small decimals
        for row_idx, row in enumerate(data[25:], start=25):
            for col_idx, cell_val in enumerate(row):
                if cell_val is None:
                    continue
                cell_ref = f"{chr(65 + col_idx % 26)}{row_idx + 1}"
                try:
                    cell = sheet[cell_ref]
                    if hasattr(cell, 'data_type') and cell.data_type == 'f':
                        if hasattr(cell, 'value') and cell.value:
                            formula_str = str(cell.value).lower()
                            if '0.125' in formula_str or 'b11' in formula_str or '$b$11' in formula_str:
                                kerf_in_formula = True
                                break
                except:
                    pass
        
        if kerf_in_formula:
            kerf_score = 20
            feedback_parts.append("✅ Kerf (0.125\") properly accounted for in formulas")
        elif kerf_mentioned:
            kerf_score = 10
            feedback_parts.append("⚠️ Kerf mentioned but may not be in calculations (scored 10/20)")
        else:
            feedback_parts.append("❌ Kerf (saw blade width) not accounted for (scored 0/20)")
        
        score += kerf_score

        # ===================================================================
        # Criterion 4: Waste calculation (15 points)
        # ===================================================================
        waste_score = 0
        has_waste_calc = False
        waste_keywords = ['waste', 'leftover', 'remainder', 'scrap', 'unused']
        
        # Check if waste-related keywords appear
        for keyword in waste_keywords:
            if keyword in all_text_combined:
                has_waste_calc = True
                break
        
        # Look for calculations that might be waste: 96 - something
        waste_formula_found = False
        for row_idx, row in enumerate(data[25:], start=25):
            for col_idx, cell_val in enumerate(row):
                if cell_val is None:
                    continue
                cell_ref = f"{chr(65 + col_idx % 26)}{row_idx + 1}"
                try:
                    cell = sheet[cell_ref]
                    if hasattr(cell, 'data_type') and cell.data_type == 'f':
                        if hasattr(cell, 'value') and cell.value:
                            formula_str = str(cell.value).lower()
                            if '96' in formula_str and '-' in formula_str:
                                waste_formula_found = True
                                break
                except:
                    pass
        
        if waste_formula_found or (has_waste_calc and formula_count > 0):
            waste_score = 15
            feedback_parts.append("✅ Waste calculation present")
        elif has_waste_calc:
            waste_score = 8
            feedback_parts.append("⚠️ Waste mentioned but calculation unclear (scored 8/15)")
        else:
            feedback_parts.append("❌ No waste calculation found (scored 0/15)")
        
        score += waste_score

        # ===================================================================
        # Criterion 5: Minimum boards determined (10 points)
        # ===================================================================
        boards_score = 0
        boards_needed = None
        
        # Look for "board" or "boards" followed by a number 2-5
        board_keywords = ['board', 'boards', 'needed', 'required', 'total', 'buy', 'purchase']
        
        for row in data:
            row_text = ' '.join([str(cell) for cell in row if cell is not None]).lower()
            if any(keyword in row_text for keyword in board_keywords):
                # Extract number from this row
                numbers = re.findall(r'\b([2-5])\b', row_text)
                if numbers:
                    potential_board_count = int(numbers[0])
                    # Verify it's likely the board count (not a piece dimension)
                    if '34' not in row_text and '32' not in row_text:
                        boards_needed = potential_board_count
                        break
        
        if boards_needed == 3:
            boards_score = 10
            feedback_parts.append("✅ Correct minimum boards determined: 3 boards (optimal)")
        elif boards_needed == 4:
            boards_score = 7
            feedback_parts.append("⚠️ Solution uses 4 boards (suboptimal but valid) (scored 7/10)")
        elif boards_needed in [2, 5]:
            boards_score = 3
            feedback_parts.append(f"⚠️ Found {boards_needed} boards (may be incorrect) (scored 3/10)")
        else:
            feedback_parts.append("❌ Minimum boards not clearly determined (scored 0/10)")
        
        score += boards_score

        # ===================================================================
        # Final evaluation
        # ===================================================================
        normalized_score = score / max_score
        passed = score >= 65  # 65% threshold for passing

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
