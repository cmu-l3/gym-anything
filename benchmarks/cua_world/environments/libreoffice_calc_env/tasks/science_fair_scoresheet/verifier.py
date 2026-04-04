#!/usr/bin/env python3
"""
Verifier for Science Fair Score Sheet task.
Validates form design, content presence, formatting, and usability.
"""

import sys
import os
import logging
import re
import zipfile
from xml.etree import ElementTree as ET
from typing import Dict, List, Tuple, Any

# Add utils to path - use relative path since verification runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def scan_for_required_content(workbook: Dict[str, Any]) -> Dict[str, bool]:
    """
    Scan all cells in the spreadsheet for required text elements.
    
    Returns dict with boolean flags for each required element.
    """
    required_elements = {
        'form_title': False,           # Some kind of header/title
        'student_name': False,         # Student Name field
        'project_number': False,       # Project Number field
        'creativity': False,           # Creativity category
        'scientific_method': False,    # Scientific Method category
        'presentation': False,         # Presentation Quality category
        'clarity': False,              # Clarity/Explanation category
        'total_score': False,          # Total score field
        'judge_name': False,           # Judge Name field
        'date_field': False,           # Date field
        'signature': False,            # Signature field
    }
    
    # Collect all text from all cells
    all_text_lower = []
    
    sheets = workbook.get('sheets', {})
    for sheet_name, rows in sheets.items():
        for row_idx, row in enumerate(rows):
            for col_idx, cell in enumerate(row):
                if isinstance(cell, dict):
                    value = cell.get('value')
                else:
                    value = cell
                
                if value:
                    text = str(value).strip().lower()
                    if text:
                        all_text_lower.append(text)
    
    # Combine all text for pattern matching
    combined_text = ' '.join(all_text_lower)
    
    # Check for required elements using pattern matching
    if any(term in combined_text for term in ['science fair', 'score sheet', 'judge sheet', 'evaluation']):
        required_elements['form_title'] = True
    
    if 'student' in combined_text and 'name' in combined_text:
        required_elements['student_name'] = True
    
    if 'project' in combined_text and ('number' in combined_text or '#' in combined_text or 'id' in combined_text):
        required_elements['project_number'] = True
    
    if 'creativity' in combined_text:
        required_elements['creativity'] = True
    
    if 'scientific' in combined_text and 'method' in combined_text:
        required_elements['scientific_method'] = True
    
    if 'presentation' in combined_text:
        required_elements['presentation'] = True
    
    if 'clarity' in combined_text or 'explanation' in combined_text:
        required_elements['clarity'] = True
    
    if 'total' in combined_text and 'score' in combined_text:
        required_elements['total_score'] = True
    
    if 'judge' in combined_text and 'name' in combined_text:
        required_elements['judge_name'] = True
    
    if 'date' in combined_text:
        required_elements['date_field'] = True
    
    if 'signature' in combined_text:
        required_elements['signature'] = True
    
    return required_elements


def check_point_values(workbook: Dict[str, Any]) -> Tuple[bool, List[int]]:
    """
    Check if point values (25, 100) are present in the spreadsheet.
    Returns (has_correct_values, list_of_found_values)
    """
    found_values = []
    
    sheets = workbook.get('sheets', {})
    for sheet_name, rows in sheets.items():
        for row in rows:
            for cell in row:
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                # Check for numeric values 25 or 100
                if value == 25 or value == '25':
                    found_values.append(25)
                elif value == 100 or value == '100':
                    found_values.append(100)
                
                # Check for text like "0-25" or "25 points" or "/ 100"
                if isinstance(value, str):
                    if '25' in value:
                        found_values.append(25)
                    if '100' in value:
                        found_values.append(100)
    
    # Should have at least 4 instances of "25" (4 categories) and 1 instance of "100" (total)
    count_25 = found_values.count(25)
    count_100 = found_values.count(100)
    
    has_correct = (count_25 >= 4 and count_100 >= 1)
    
    return has_correct, found_values


def analyze_ods_formatting(filepath: str) -> Dict[str, Any]:
    """
    Analyze ODS file for formatting elements (merged cells, borders, bold text).
    Returns dict with formatting metrics.
    """
    formatting_info = {
        'has_merged_cells': False,
        'has_borders': False,
        'has_bold_text': False,
        'merged_cell_count': 0,
        'bold_cell_count': 0,
    }
    
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            # Read content.xml
            if 'content.xml' not in ods_zip.namelist():
                return formatting_info
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Convert to string for easier searching
            content_str = ET.tostring(root, encoding='unicode')
            
            # Check for merged cells (number-columns-spanned or number-rows-spanned)
            if 'number-columns-spanned' in content_str or 'number-rows-spanned' in content_str:
                formatting_info['has_merged_cells'] = True
                # Count approximate merged cells
                formatting_info['merged_cell_count'] = content_str.count('number-columns-spanned')
            
            # Check for borders (border styles in content)
            if 'fo:border' in content_str or 'style:border' in content_str:
                formatting_info['has_borders'] = True
            
            # Check for bold text (font-weight="bold")
            if 'font-weight="bold"' in content_str or 'fo:font-weight="bold"' in content_str:
                formatting_info['has_bold_text'] = True
                formatting_info['bold_cell_count'] = content_str.count('font-weight="bold"')
    
    except Exception as e:
        logger.warning(f"Could not analyze ODS formatting: {e}")
    
    return formatting_info


def check_layout_dimensions(workbook: Dict[str, Any]) -> Tuple[bool, int, int]:
    """
    Check if the content fits within reasonable printable dimensions.
    Returns (fits_on_page, used_rows, used_columns)
    """
    sheets = workbook.get('sheets', {})
    if not sheets:
        return False, 0, 0
    
    # Get first sheet
    first_sheet = list(sheets.values())[0]
    
    # Count used rows (rows with at least one non-empty cell)
    used_rows = 0
    max_used_col = 0
    
    for row_idx, row in enumerate(first_sheet):
        has_content = False
        for col_idx, cell in enumerate(row):
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value:
                has_content = True
                max_used_col = max(max_used_col, col_idx)
        
        if has_content:
            used_rows = row_idx + 1
    
    used_columns = max_used_col + 1
    
    # A typical printed page can fit about 50-60 rows and 8-10 columns
    # with reasonable sizing. Allow some flexibility.
    fits_on_page = (used_rows <= 70 and used_columns <= 12)
    
    return fits_on_page, used_rows, used_columns


def check_adequate_spacing(workbook: Dict[str, Any]) -> bool:
    """
    Check if there's adequate spacing for handwriting.
    Heuristic: Look for some empty rows/cells that indicate spacing.
    """
    sheets = workbook.get('sheets', {})
    if not sheets:
        return False
    
    first_sheet = list(sheets.values())[0]
    
    # Count rows that have content
    content_rows = 0
    total_rows_scanned = min(len(first_sheet), 70)
    
    for row in first_sheet[:total_rows_scanned]:
        if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
            content_rows += 1
    
    # If content is spread across many rows, it suggests adequate spacing
    # A cramped form would have content in <20 rows
    # A well-spaced form would use 25-50 rows
    has_spacing = (content_rows >= 15)
    
    return has_spacing


def verify_total_formula(workbook: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if there's a formula that sums to 100.
    Returns (is_correct, formula_text)
    """
    sheets = workbook.get('sheets', {})
    if not sheets:
        return False, ""
    
    sheet_name = list(sheets.keys())[0]
    
    # Scan all cells for formulas
    for row_idx, row in enumerate(sheets[sheet_name]):
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                formula = cell.get('formula')
                value = cell.get('value')
                
                if formula:
                    # Check if it's a SUM formula
                    if 'SUM' in formula.upper():
                        # Check if the result is 100
                        if value == 100 or value == '100':
                            return True, formula
                    
                    # Check if it adds up to 100 (e.g., =25+25+25+25)
                    if value == 100 or value == '100':
                        return True, formula
    
    return False, ""


def verify_scoresheet(traj, env_info, task_info):
    """
    Main verification function for Science Fair Score Sheet task.
    
    Checks:
    1. All required content fields present (10+ elements)
    2. Proper formatting (merged cells, borders, bold)
    3. Logical layout structure (fits on page, adequate spacing)
    4. Calculation correctness (if formula used)
    5. Point values present (25 for each category, 100 total)
    6. Professional appearance indicators
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to copy and parse the spreadsheet
    container_path = "/home/ga/Documents/science_fair_scoresheet.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load score sheet: {error}"}
    
    try:
        workbook = file_info['sheet_data']
        filepath = file_info['file_path']
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Required content fields present
        required_content = scan_for_required_content(workbook)
        content_count = sum(required_content.values())
        required_count = len(required_content)
        
        if content_count >= 9:  # At least 9 of 11 elements
            criteria_passed += 1
            feedback_parts.append(f"✅ Required fields present ({content_count}/{required_count})")
            subscores['content_complete'] = True
        else:
            missing = [k for k, v in required_content.items() if not v]
            feedback_parts.append(f"❌ Missing fields ({content_count}/{required_count}): {', '.join(missing[:3])}")
            subscores['content_complete'] = False
        
        # Criterion 2: Point values present
        has_points, point_values = check_point_values(workbook)
        if has_points:
            criteria_passed += 1
            feedback_parts.append("✅ Point values correct (25 pts × 4, 100 total)")
            subscores['point_values'] = True
        else:
            feedback_parts.append(f"❌ Point values missing or incorrect (found: {len(point_values)} values)")
            subscores['point_values'] = False
        
        # Criterion 3: Formatting applied (merged cells, borders, bold)
        formatting = analyze_ods_formatting(filepath)
        formatting_score = sum([
            formatting['has_merged_cells'],
            formatting['has_borders'],
            formatting['has_bold_text']
        ])
        
        if formatting_score >= 2:  # At least 2 of 3 formatting types
            criteria_passed += 1
            fmt_details = []
            if formatting['has_merged_cells']:
                fmt_details.append(f"merged cells ({formatting['merged_cell_count']})")
            if formatting['has_borders']:
                fmt_details.append("borders")
            if formatting['has_bold_text']:
                fmt_details.append(f"bold text ({formatting['bold_cell_count']})")
            feedback_parts.append(f"✅ Formatting applied: {', '.join(fmt_details)}")
            subscores['formatting'] = True
        else:
            feedback_parts.append(f"❌ Insufficient formatting (needs borders, merged cells, bold)")
            subscores['formatting'] = False
        
        # Criterion 4: Layout fits on page
        fits_page, used_rows, used_cols = check_layout_dimensions(workbook)
        if fits_page:
            criteria_passed += 1
            feedback_parts.append(f"✅ Layout fits on page ({used_rows} rows × {used_cols} cols)")
            subscores['print_ready'] = True
        else:
            feedback_parts.append(f"⚠️  Layout may not fit on one page ({used_rows} rows × {used_cols} cols)")
            subscores['print_ready'] = False
        
        # Criterion 5: Adequate spacing for writing
        has_spacing = check_adequate_spacing(workbook)
        if has_spacing:
            criteria_passed += 1
            feedback_parts.append("✅ Adequate spacing for handwriting")
            subscores['spacing'] = True
        else:
            feedback_parts.append("⚠️  Form may be too cramped")
            subscores['spacing'] = False
        
        # Criterion 6: Total formula (if used) is correct
        has_formula, formula_text = verify_total_formula(workbook)
        if has_formula:
            criteria_passed += 1
            feedback_parts.append(f"✅ Total formula correct: {formula_text}")
            subscores['formula'] = True
        else:
            # This is optional, so don't penalize too much
            # Give partial credit if the total field exists
            if required_content['total_score']:
                criteria_passed += 0.5
                feedback_parts.append("⚠️  Total field present but no formula detected")
                subscores['formula'] = False
            else:
                feedback_parts.append("❌ Total score field or formula missing")
                subscores['formula'] = False
        
        # Criterion 7: Professional appearance (holistic check)
        # Combination of multiple factors
        professional_score = sum([
            content_count >= 9,           # Has most required fields
            formatting_score >= 2,        # Has good formatting
            fits_page,                    # Fits on page
            has_spacing,                  # Has adequate spacing
            formatting['has_merged_cells'] and formatting['has_borders']  # Has key formatting
        ])
        
        if professional_score >= 3:
            criteria_passed += 1
            feedback_parts.append("✅ Professional appearance")
            subscores['professional'] = True
        else:
            feedback_parts.append("⚠️  Could be more professional in appearance")
            subscores['professional'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 5/7 criteria (70%)
        
        # Add summary feedback
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent score sheet design!")
        elif passed:
            feedback_parts.insert(0, "✅ Score sheet meets requirements")
        else:
            feedback_parts.insert(0, "❌ Score sheet needs improvement")
        
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
