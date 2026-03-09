#!/usr/bin/env python3
"""
Verifier for Classroom Seating Chart task

Verifies that a teacher has created an optimized seating chart with:
- Required IEP/504 placements
- Separation constraints for behavior conflicts
- Proper wheelchair accessibility
- Color-coding for special needs
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_name(name):
    """Normalize a student name for comparison"""
    if not name or not isinstance(name, str):
        return ""
    # Convert to lowercase, remove extra spaces
    return re.sub(r'\s+', ' ', name.strip().lower())


def find_student_position(grid, student_patterns):
    """
    Find a student's position in the grid using pattern matching
    
    Args:
        grid: Dictionary mapping (row, col) -> student_name
        student_patterns: List of possible name patterns to match
    
    Returns:
        (row, col) tuple or None if not found
    """
    for pos, name in grid.items():
        name_normalized = normalize_name(name)
        for pattern in student_patterns:
            if pattern in name_normalized:
                return pos
    return None


def are_adjacent(pos1, pos2, rows_list):
    """
    Check if two positions are adjacent (including diagonally)
    
    Args:
        pos1: (row_letter, col_num) tuple
        pos2: (row_letter, col_num) tuple
        rows_list: List of row letters in order
    
    Returns:
        True if adjacent, False otherwise
    """
    if pos1 is None or pos2 is None:
        return False
    
    row1, col1 = pos1
    row2, col2 = pos2
    
    # Calculate row and column differences
    try:
        row1_idx = rows_list.index(row1)
        row2_idx = rows_list.index(row2)
    except ValueError:
        return False
    
    row_diff = abs(row1_idx - row2_idx)
    col_diff = abs(col1 - col2)
    
    # Adjacent if within 1 step in any direction (including diagonal)
    # But not if it's the same position
    return (row_diff <= 1 and col_diff <= 1 and (row_diff + col_diff) > 0)


def verify_classroom_seating_chart(traj, env_info, task_info):
    """
    Verify the classroom seating chart task.
    
    Checks:
    1. Required front-row placements (40 pts)
       - Marcus Chen in Row A (10 pts)
       - Emma Kowalski in Row A (10 pts)
       - Aisha Williams in columns 4-5 (10 pts)
       - Ethan Brown in column 5 (10 pts)
    2. Separation constraints (30 pts)
       - Jordan Blake and Taylor Morrison not adjacent (10 pts)
       - Jordan Blake and Sofia Martinez not adjacent (10 pts)
       - Marcus Chen and Ava Johnson not adjacent (10 pts)
    3. Chart completeness (20 pts)
       - All 27 students placed (10 pts)
       - No duplicate names (5 pts)
       - B5 remains empty (5 pts)
    4. Visual formatting (10 pts)
       - At least 3 cells color-coded (5 pts)
       - Readable text formatting (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/seating_template.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_seating_')

    try:
        # Copy file from container
        temp_file = os.path.join(temp_dir, 'seating_template.xlsx')
        copy_from_env(container_path, temp_file)

        if not os.path.exists(temp_file) or os.path.getsize(temp_file) == 0:
            return {"passed": False, "score": 0, "feedback": "❌ File not found or empty: seating_template.xlsx"}

        # Parse the spreadsheet
        wb = parse_xlsx_file(temp_file)
        if not wb:
            return {"passed": False, "score": 0, "feedback": "❌ Could not parse seating_template.xlsx"}

        sheet = wb.active
        
        # Define grid structure
        ROWS = ['A', 'B', 'C', 'D', 'E', 'F']
        COLS = [1, 2, 3, 4, 5]
        
        # Build grid dictionary: {(row_letter, col_num): student_name}
        # Sheet structure: Column A is row labels, Columns B-F are the 5 desk columns
        grid = {}
        all_students = []
        
        for row_idx, row_letter in enumerate(ROWS, start=2):
            for col_idx, col_num in enumerate(COLS, start=2):
                # Get cell value from sheet
                cell = sheet.cell(row=row_idx, column=col_idx)
                cell_value = cell.value
                
                if cell_value and isinstance(cell_value, str):
                    # Clean up the value
                    name = cell_value.strip()
                    # Skip if it's the "EMPTY" marker or just whitespace
                    if name and name.upper() not in ["EMPTY", "EMPTY\n(NO DESK)", "(NO DESK)", "NO DESK"]:
                        # Remove newlines and extra spaces
                        name = re.sub(r'\s+', ' ', name.replace('\n', ' ')).strip()
                        if name:  # Final check after cleanup
                            grid[(row_letter, col_num)] = name
                            all_students.append(name)
        
        logger.info(f"Found {len(all_students)} students in grid")
        logger.info(f"Grid contents: {grid}")
        
        score = 0
        feedback_parts = []
        
        # ===== CRITERION 1: REQUIRED PLACEMENTS (40 pts) =====
        
        # Marcus Chen - front row (Row A)
        marcus_pos = find_student_position(grid, ["marcus chen", "marcus c", "chen"])
        logger.info(f"Marcus position: {marcus_pos}")
        if marcus_pos and marcus_pos[0] == 'A':
            score += 10
            feedback_parts.append("✅ Marcus Chen in front row (Row A)")
        else:
            feedback_parts.append(f"❌ Marcus Chen should be in Row A (IEP). Found: {marcus_pos if marcus_pos else 'not found'}")
        
        # Emma Kowalski - front row (Row A)
        emma_pos = find_student_position(grid, ["emma kowalski", "emma k", "kowalski", "emma"])
        logger.info(f"Emma position: {emma_pos}")
        if emma_pos and emma_pos[0] == 'A':
            score += 10
            feedback_parts.append("✅ Emma Kowalski in front row (Row A)")
        else:
            feedback_parts.append(f"❌ Emma Kowalski should be in Row A (IEP). Found: {emma_pos if emma_pos else 'not found'}")
        
        # Aisha Williams - right side (columns 4-5, away from HVAC)
        aisha_pos = find_student_position(grid, ["aisha williams", "aisha w", "williams", "aisha"])
        logger.info(f"Aisha position: {aisha_pos}")
        if aisha_pos and aisha_pos[1] in [4, 5]:
            score += 10
            feedback_parts.append("✅ Aisha Williams on right side (hearing accommodation)")
        else:
            feedback_parts.append(f"❌ Aisha Williams should be in columns 4-5 (504 plan). Found: {aisha_pos if aisha_pos else 'not found'}")
        
        # Ethan Brown - wheelchair accessible (column 5, end of row)
        ethan_pos = find_student_position(grid, ["ethan brown", "ethan b", "brown", "ethan"])
        logger.info(f"Ethan position: {ethan_pos}")
        if ethan_pos and ethan_pos[1] == 5:
            score += 10
            feedback_parts.append("✅ Ethan Brown in wheelchair-accessible position (Column 5)")
        else:
            feedback_parts.append(f"❌ Ethan Brown should be in Column 5 (wheelchair). Found: {ethan_pos if ethan_pos else 'not found'}")
        
        # ===== CRITERION 2: SEPARATION CONSTRAINTS (30 pts) =====
        
        # Jordan Blake and Taylor Morrison - NOT adjacent
        jordan_pos = find_student_position(grid, ["jordan blake", "jordan b", "blake"])
        taylor_pos = find_student_position(grid, ["taylor morrison", "taylor m", "morrison"])
        logger.info(f"Jordan position: {jordan_pos}, Taylor position: {taylor_pos}")
        
        if jordan_pos and taylor_pos:
            if not are_adjacent(jordan_pos, taylor_pos, ROWS):
                score += 10
                feedback_parts.append("✅ Jordan Blake and Taylor Morrison properly separated")
            else:
                feedback_parts.append(f"❌ Jordan ({jordan_pos}) and Taylor ({taylor_pos}) are adjacent - should be separated")
        else:
            missing = []
            if not jordan_pos:
                missing.append("Jordan Blake")
            if not taylor_pos:
                missing.append("Taylor Morrison")
            feedback_parts.append(f"⚠️ Cannot verify Jordan/Taylor separation - missing: {', '.join(missing)}")
        
        # Jordan Blake and Sofia Martinez - NOT adjacent
        sofia_pos = find_student_position(grid, ["sofia martinez", "sofia m", "martinez", "sofia"])
        logger.info(f"Sofia position: {sofia_pos}")
        
        if jordan_pos and sofia_pos:
            if not are_adjacent(jordan_pos, sofia_pos, ROWS):
                score += 10
                feedback_parts.append("✅ Jordan Blake and Sofia Martinez properly separated")
            else:
                feedback_parts.append(f"❌ Jordan ({jordan_pos}) and Sofia ({sofia_pos}) are adjacent - should be separated")
        else:
            missing = []
            if not jordan_pos:
                missing.append("Jordan Blake")
            if not sofia_pos:
                missing.append("Sofia Martinez")
            feedback_parts.append(f"⚠️ Cannot verify Jordan/Sofia separation - missing: {', '.join(missing)}")
        
        # Marcus Chen and Ava Johnson - NOT adjacent (behavior conflict)
        ava_pos = find_student_position(grid, ["ava johnson", "ava j", "johnson", "ava"])
        logger.info(f"Ava position: {ava_pos}")
        
        if marcus_pos and ava_pos:
            if not are_adjacent(marcus_pos, ava_pos, ROWS):
                score += 10
                feedback_parts.append("✅ Marcus Chen and Ava Johnson properly separated")
            else:
                feedback_parts.append(f"❌ Marcus ({marcus_pos}) and Ava ({ava_pos}) are adjacent - behavior conflict!")
        else:
            missing = []
            if not marcus_pos:
                missing.append("Marcus Chen")
            if not ava_pos:
                missing.append("Ava Johnson")
            feedback_parts.append(f"⚠️ Cannot verify Marcus/Ava separation - missing: {', '.join(missing)}")
        
        # ===== CRITERION 3: CHART COMPLETENESS (20 pts) =====
        
        # Should have 27 students (28 desks - 1 empty at B5)
        expected_count = 27
        actual_count = len(all_students)
        
        if actual_count >= expected_count:
            score += 10
            feedback_parts.append(f"✅ All students placed ({actual_count} students)")
        elif actual_count >= 25:
            score += 5
            feedback_parts.append(f"⚠️ Most students placed ({actual_count}/{expected_count})")
        else:
            feedback_parts.append(f"❌ Too few students placed ({actual_count}/{expected_count})")
        
        # Check for duplicates
        normalized_students = [normalize_name(s) for s in all_students]
        unique_students = set(normalized_students)
        if len(unique_students) == len(all_students):
            score += 5
            feedback_parts.append("✅ No duplicate names")
        else:
            duplicates = len(all_students) - len(unique_students)
            feedback_parts.append(f"❌ Found {duplicates} duplicate name(s)")
        
        # Check that B5 is empty or marked as EMPTY
        b5_cell = sheet.cell(row=3, column=6)  # Row B (idx 3), Column 5 (sheet col 6)
        b5_value = b5_cell.value
        if b5_value is None or (isinstance(b5_value, str) and 
                                any(marker in b5_value.upper() for marker in ["EMPTY", "NO DESK"])):
            score += 5
            feedback_parts.append("✅ Position B5 correctly marked as empty")
        else:
            # Check if it's in our grid as a student
            if ('B', 5) not in grid:
                score += 5
                feedback_parts.append("✅ Position B5 is empty")
            else:
                feedback_parts.append(f"❌ Position B5 should be empty (found: {b5_value})")
        
        # ===== CRITERION 4: VISUAL FORMATTING (10 pts) =====
        
        # Check for color-coding (at least 3 cells with non-default background color)
        colored_cells = 0
        for row_idx, row_letter in enumerate(ROWS, start=2):
            for col_idx in range(2, 7):  # Columns B-F in sheet
                cell = sheet.cell(row=row_idx, column=col_idx)
                if cell.fill and cell.fill.start_color:
                    color = cell.fill.start_color.rgb if hasattr(cell.fill.start_color, 'rgb') else cell.fill.start_color.index
                    # Check if it's not white (FFFFFF) or the default gray for B5 (D3D3D3)
                    if color and isinstance(color, str):
                        color_upper = color.upper()
                        if (color_upper not in ['00000000', 'FFFFFFFF', '00FFFFFF', 'FFFFFF'] and
                            not color_upper.endswith('D3D3D3')):
                            colored_cells += 1
        
        logger.info(f"Found {colored_cells} colored cells")
        if colored_cells >= 3:
            score += 5
            feedback_parts.append(f"✅ Color-coding applied ({colored_cells} cells)")
        else:
            feedback_parts.append(f"❌ Need at least 3 color-coded cells for IEP/504 students (found: {colored_cells})")
        
        # Check font size readability (sample a few student cells)
        readable_count = 0
        checked_count = 0
        for row_idx in range(2, 5):  # Check first 3 rows
            for col_idx in range(2, 5):  # Check first 3 columns
                cell = sheet.cell(row=row_idx, column=col_idx)
                if cell.value and isinstance(cell.value, str) and len(cell.value.strip()) > 3:
                    checked_count += 1
                    if cell.font and cell.font.size:
                        if 9 <= cell.font.size <= 14:
                            readable_count += 1
                    else:
                        # Default font size is usually 11, which is acceptable
                        readable_count += 1
        
        if checked_count > 0 and readable_count / checked_count >= 0.7:
            score += 5
            feedback_parts.append("✅ Text formatting is readable")
        elif checked_count == 0:
            # No text to check, give benefit of doubt
            score += 5
            feedback_parts.append("✅ Text formatting acceptable")
        else:
            feedback_parts.append("⚠️ Some text may be too small or large for readability")
        
        # ===== FINAL SCORING =====
        
        passed = score >= 70
        feedback = " | ".join(feedback_parts)
        
        if passed:
            feedback = f"🎉 PASSED ({score}/100) | " + feedback
        else:
            feedback = f"❌ FAILED ({score}/100) | " + feedback
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"❌ Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)


# Entry point for gym-anything
def verify(copy_from_env_fn):
    """Compatibility wrapper for gym-anything framework"""
    # Create mock env_info and task_info
    env_info = {'copy_from_env': copy_from_env_fn}
    task_info = {}
    return verify_classroom_seating_chart(None, env_info, task_info)