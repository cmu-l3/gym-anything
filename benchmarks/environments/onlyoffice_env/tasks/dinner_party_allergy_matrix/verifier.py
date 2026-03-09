#!/usr/bin/env python3
"""
Verifier for Dinner Party Allergy Matrix task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_text(text):
    """Normalize text for comparison"""
    if text is None:
        return ""
    return str(text).lower().strip()


def contains_any(text, keywords):
    """Check if text contains any of the keywords"""
    text_norm = normalize_text(text)
    return any(keyword.lower() in text_norm for keyword in keywords)


def is_safe_indicator(cell_value, cell_obj=None):
    """Check if cell indicates SAFE (green color, checkmark, or safe text)"""
    # Check text content
    text_norm = normalize_text(cell_value)
    safe_texts = ['safe', 'ok', 'yes', '✓', '✔', 'pass']
    if any(indicator in text_norm for indicator in safe_texts):
        return True
    
    # Check cell background color (green variants)
    if cell_obj and hasattr(cell_obj, 'fill') and cell_obj.fill:
        try:
            if hasattr(cell_obj.fill, 'start_color') and cell_obj.fill.start_color:
                color = cell_obj.fill.start_color.rgb if hasattr(cell_obj.fill.start_color, 'rgb') else None
                if color and isinstance(color, str):
                    # Check for green colors (various shades)
                    color_lower = color.lower()
                    green_patterns = ['00ff00', '90ee90', '00c000', '92d050', 'c6e0b4', '00b050']
                    if any(pattern in color_lower for pattern in green_patterns):
                        return True
        except:
            pass
    
    return False


def is_unsafe_indicator(cell_value, cell_obj=None):
    """Check if cell indicates UNSAFE (red/orange/yellow color, X mark, or unsafe text)"""
    # Check text content
    text_norm = normalize_text(cell_value)
    unsafe_texts = ['unsafe', 'no', 'avoid', '✗', '✘', 'x', 'fail', 'danger']
    if any(indicator in text_norm for indicator in unsafe_texts):
        # Make sure it's not a name like "Max" or "Alex"
        if text_norm not in ['max', 'alex', 'rex', 'fox']:
            return True
    
    # Check cell background color (red, orange, yellow variants)
    if cell_obj and hasattr(cell_obj, 'fill') and cell_obj.fill:
        try:
            if hasattr(cell_obj.fill, 'start_color') and cell_obj.fill.start_color:
                color = cell_obj.fill.start_color.rgb if hasattr(cell_obj.fill.start_color, 'rgb') else None
                if color and isinstance(color, str):
                    color_lower = color.lower()
                    warning_patterns = ['ff0000', 'ffc000', 'ffff00', 'ff6600', 'ffc7ce', 'f4b084']
                    if any(pattern in color_lower for pattern in warning_patterns):
                        return True
        except:
            pass
    
    return False


def is_highlighted(cell_obj):
    """Check if cell is highlighted (bold, colored background, or border)"""
    if not cell_obj:
        return False
    
    # Check for bold font
    try:
        if hasattr(cell_obj, 'font') and cell_obj.font and cell_obj.font.bold:
            return True
    except:
        pass
    
    # Check for background color
    try:
        if hasattr(cell_obj, 'fill') and cell_obj.fill:
            if hasattr(cell_obj.fill, 'start_color') and cell_obj.fill.start_color:
                color = cell_obj.fill.start_color.rgb if hasattr(cell_obj.fill.start_color, 'rgb') else None
                if color and color.lower() not in ['ffffff', '00000000', 'ffffffff']:
                    return True
    except:
        pass
    
    return False


def verify_allergy_matrix(traj, env_info, task_info):
    """
    Verify that allergy matrix was created correctly.

    Checks:
    1. File exists and is non-empty
    2. All 6 guest names present
    3. All 5 dish names present
    4. Matrix has safety markings (at least 20 cells with indicators)
    5. Known unsafe combinations marked correctly (Emma + dairy/nut dishes)
    6. Emma identified as having limited options (highlighted or noted)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/party_planning/allergy_matrix.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_allergy_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        criteria_passed = 0
        feedback_parts = []
        total_criteria = 7

        # Get the active sheet
        ws = wb.active

        # Get all data from the sheet
        all_data = get_sheet_data(wb, ws.title, max_rows=100, max_cols=20)
        
        # Flatten all cell values for searching
        all_text = ' '.join([str(cell) for row in all_data for cell in row if cell])
        all_text_lower = all_text.lower()

        # Criterion 1: Check for all 6 guest names
        guests = ['Sarah', 'Mike', 'Jennifer', 'David', 'Emma', 'Tom']
        guests_found = []
        for guest in guests:
            if guest.lower() in all_text_lower:
                guests_found.append(guest)
        
        if len(guests_found) >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ All 6 guests present: {', '.join(guests_found)}")
        elif len(guests_found) >= 4:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Only {len(guests_found)}/6 guests found: {', '.join(guests_found)}")
        else:
            feedback_parts.append(f"❌ Only {len(guests_found)}/6 guests found")

        # Criterion 2: Check for all 5 dish names
        dishes = ['Caprese', 'Salmon', 'Risotto', 'Cake', 'Fruit']
        dishes_found = []
        for dish in dishes:
            if dish.lower() in all_text_lower:
                dishes_found.append(dish)
        
        if len(dishes_found) >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ All 5 dishes present: {', '.join(dishes_found)}")
        elif len(dishes_found) >= 3:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Only {len(dishes_found)}/5 dishes found: {', '.join(dishes_found)}")
        else:
            feedback_parts.append(f"❌ Only {len(dishes_found)}/5 dishes found")

        # Criterion 3: Check for matrix structure (sufficient filled cells)
        filled_cells = sum(1 for row in all_data for cell in row if cell is not None and str(cell).strip())
        
        if filled_cells >= 30:
            criteria_passed += 1
            feedback_parts.append(f"✅ Matrix structure present ({filled_cells} filled cells)")
        elif filled_cells >= 20:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Sparse matrix ({filled_cells} filled cells, expected 30+)")
        else:
            feedback_parts.append(f"❌ Insufficient data ({filled_cells} filled cells)")

        # Criterion 4: Check for safety markings
        safe_count = 0
        unsafe_count = 0
        
        for row_idx, row in enumerate(ws.iter_rows(max_row=50, max_col=20)):
            for cell in row:
                if is_safe_indicator(cell.value, cell):
                    safe_count += 1
                elif is_unsafe_indicator(cell.value, cell):
                    unsafe_count += 1
        
        total_markings = safe_count + unsafe_count
        
        if total_markings >= 20:
            criteria_passed += 1
            feedback_parts.append(f"✅ Safety markings present ({safe_count} safe, {unsafe_count} unsafe)")
        elif total_markings >= 10:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Limited markings ({safe_count} safe, {unsafe_count} unsafe, expected 20+)")
        else:
            feedback_parts.append(f"❌ Insufficient markings ({total_markings} total, expected 20+)")

        # Criterion 5: Check logical accuracy - Emma's known conflicts
        # Emma should be marked UNSAFE for: Caprese (dairy), Risotto (dairy), Cake (dairy), Fruit (nuts)
        # Emma should be marked SAFE for: Salmon only
        
        emma_conflicts_correct = 0
        emma_conflicts_checked = 0
        
        # Find Emma's row or column
        emma_found = False
        for row_idx, row in enumerate(ws.iter_rows(max_row=50, max_col=20), start=1):
            for col_idx, cell in enumerate(row, start=1):
                if cell.value and 'emma' in normalize_text(cell.value):
                    emma_found = True
                    # Check surrounding cells for dish names and safety indicators
                    # This is complex because we don't know the exact matrix layout
                    # We'll check if Emma is associated with multiple unsafe indicators
                    
                    # Check row for Emma (dishes in columns)
                    for offset in range(-2, 10):
                        check_cell = ws.cell(row=row_idx, column=col_idx + offset)
                        if is_unsafe_indicator(check_cell.value, check_cell):
                            emma_conflicts_checked += 1
                    
                    # Check column for Emma (dishes in rows)
                    for offset in range(-2, 10):
                        check_cell = ws.cell(row=row_idx + offset, column=col_idx)
                        if is_unsafe_indicator(check_cell.value, check_cell):
                            emma_conflicts_checked += 1
                    
                    break
            if emma_found:
                break
        
        # Emma should have at least 3-4 unsafe markings (out of 5 dishes, 4 are unsafe)
        if emma_conflicts_checked >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Emma's allergen conflicts marked ({emma_conflicts_checked} unsafe items)")
        elif emma_conflicts_checked >= 2:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some Emma conflicts marked ({emma_conflicts_checked} found)")
        else:
            feedback_parts.append(f"❌ Emma's allergen conflicts not properly marked")

        # Criterion 6: Check if Emma is highlighted as problematic
        emma_highlighted = False
        for row in ws.iter_rows(max_row=50, max_col=20):
            for cell in row:
                if cell.value and 'emma' in normalize_text(cell.value):
                    if is_highlighted(cell):
                        emma_highlighted = True
                        break
                # Also check for notes about Emma or "limited" or "warning"
                if cell.value:
                    cell_text = normalize_text(cell.value)
                    if 'emma' in cell_text and ('limited' in cell_text or 'warning' in cell_text or 
                                                  'only' in cell_text or 'problem' in cell_text):
                        emma_highlighted = True
                        break
        
        if emma_highlighted:
            criteria_passed += 1
            feedback_parts.append("✅ Emma identified as having limited options")
        else:
            feedback_parts.append("⚠️ Emma not explicitly flagged as problematic (optional)")

        # Criterion 7: Check for any notes or recommendations
        has_notes = any('note' in normalize_text(cell) or 'recommend' in normalize_text(cell) 
                       or 'modify' in normalize_text(cell) or 'alternative' in normalize_text(cell)
                       for row in all_data for cell in row if cell)
        
        if has_notes:
            criteria_passed += 1
            feedback_parts.append("✅ Includes recommendations or notes")
        else:
            # This is optional, so don't penalize too much
            feedback_parts.append("ℹ️ No recommendations noted (optional)")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

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