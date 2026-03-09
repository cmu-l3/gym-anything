#!/usr/bin/env python3
"""
Verifier for Band Chord Chart task

Verifies that a musician created a properly formatted 16-bar chord chart
in spreadsheet format with simplified chord notation.
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_chord(chord_str):
    """
    Normalize a chord string for comparison.
    
    Handles:
    - Case insensitivity
    - Whitespace removal
    - Chord equivalences (Cmaj = C, Dmin = Dm, etc.)
    
    Args:
        chord_str: Raw chord string from spreadsheet
        
    Returns:
        Lowercase normalized chord string
    """
    if chord_str is None:
        return ""
    
    # Convert to string and strip whitespace
    chord = str(chord_str).strip().lower()
    
    # Remove common separators and punctuation
    chord = chord.replace(" ", "").replace("_", "")
    chord = chord.replace("(", "").replace(")", "")
    
    # Normalize major chord representations
    chord = chord.replace("major", "")
    chord = chord.replace("maj", "")
    
    # Normalize minor chord representations  
    chord = chord.replace("minor", "m")
    chord = chord.replace("min", "m")
    
    # Normalize flat/sharp symbols
    chord = chord.replace("flat", "b")
    chord = chord.replace("sharp", "#")
    
    return chord


def chord_matches(actual, expected_variants):
    """
    Check if actual chord matches any of the expected variants.
    
    Args:
        actual: The chord string from the spreadsheet
        expected_variants: List of acceptable chord notations
        
    Returns:
        True if match found, False otherwise
    """
    actual_norm = normalize_chord(actual)
    
    if not actual_norm:
        return False
    
    for expected in expected_variants:
        expected_norm = normalize_chord(expected)
        
        # Direct match
        if actual_norm == expected_norm:
            return True
        
        # Check if actual starts with expected (handles extensions)
        # e.g., "cmaj7" matches expected "c"
        if actual_norm.startswith(expected_norm) and len(expected_norm) >= 1:
            # Make sure we're matching the root note, not just first letter
            if len(expected_norm) >= 2 or actual_norm == expected_norm:
                return True
    
    return False


def find_chord_grid(sheet_data):
    """
    Find the chord grid in the spreadsheet data.
    
    Looks for a 4×4 or 5×5 region containing chord-like content.
    
    Args:
        sheet_data: 2D list of cell values
        
    Returns:
        Tuple of (start_row, start_col) of the grid
    """
    chord_pattern = re.compile(r'^[A-G][#b]?(?:m|maj|min|dim|aug|sus|\d|/|\+|-|ø)*$', re.IGNORECASE)
    
    # Look for regions with high concentration of chord-like cells
    best_score = 0
    best_position = (3, 0)  # Default fallback
    
    for row_idx in range(len(sheet_data)):
        for col_idx in range(len(sheet_data[row_idx]) if row_idx < len(sheet_data) else 0):
            score = 0
            
            # Check 4×5 region (4 rows, 5 cols including measure labels)
            for r in range(row_idx, min(row_idx + 4, len(sheet_data))):
                if r >= len(sheet_data):
                    break
                for c in range(col_idx, min(col_idx + 5, len(sheet_data[r]))):
                    if c >= len(sheet_data[r]):
                        continue
                    cell = sheet_data[r][c]
                    if cell and isinstance(cell, str):
                        cell_str = cell.strip()
                        if chord_pattern.match(cell_str):
                            score += 2  # Chord-like cells get high score
                        elif re.match(r'^\d+(-\d+)?$', cell_str):
                            score += 1  # Measure labels get some score
            
            if score > best_score:
                best_score = score
                best_position = (row_idx, col_idx)
    
    return best_position


def extract_chords_from_grid(sheet_data, start_row, start_col):
    """
    Extract chord values from the grid.
    
    Returns a list of 4 lists (rows), each containing up to 4 chords.
    Skips the first column if it contains measure labels.
    
    Args:
        sheet_data: 2D list of cell values
        start_row: Starting row index
        start_col: Starting column index
        
    Returns:
        List of 4 lists, each containing 4 chord values
    """
    chords = []
    
    for row_offset in range(4):
        row_idx = start_row + row_offset
        if row_idx >= len(sheet_data):
            chords.append([None, None, None, None])
            continue
        
        row_chords = []
        
        # Determine if first column is measure labels
        first_col = start_col
        if first_col < len(sheet_data[row_idx]):
            first_cell = sheet_data[row_idx][first_col]
            
            # If first cell looks like a measure label, skip it
            if first_cell and isinstance(first_cell, (str, int)):
                first_cell_str = str(first_cell).strip()
                if re.match(r'^\d+(-\d+)?$', first_cell_str):
                    first_col += 1
                elif re.match(r'^(measure|m|bar)?\s*\d+', first_cell_str, re.IGNORECASE):
                    first_col += 1
        
        # Extract up to 4 chords from this row
        for col_offset in range(4):
            col_idx = first_col + col_offset
            if col_idx >= len(sheet_data[row_idx]):
                row_chords.append(None)
            else:
                row_chords.append(sheet_data[row_idx][col_idx])
        
        chords.append(row_chords)
    
    return chords


def verify_band_chord_chart(traj, env_info, task_info):
    """
    Verify that band chord chart was created correctly.
    
    Verification criteria (5 total, need 4+ to pass):
    1. File exists and is parseable
    2. Grid structure exists (4 rows of chord data)
    3. Chord accuracy (at least 12/16 correct = 75%)
    4. Text formatting (bold and/or large font ≥14pt)
    5. Layout (centered alignment or reasonable column widths)
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info containing copy_from_env function
        task_info: Task info (unused)
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/autumn_breeze_chart.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_chords_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        criteria_passed = 0
        feedback_parts = []

        # Get the active sheet
        sheet_name = wb.sheetnames[0]
        
        # Get all sheet data
        sheet_data = get_sheet_data(wb, sheet_name, max_rows=50, max_cols=10)
        
        if not sheet_data or len(sheet_data) < 4:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Spreadsheet is empty or too small"
            }
        
        # Criterion 1: File is valid and has content
        criteria_passed += 1
        feedback_parts.append("✅ Spreadsheet loaded successfully")
        
        # Find the chord grid
        grid_start = find_chord_grid(sheet_data)
        chords = extract_chords_from_grid(sheet_data, grid_start[0], grid_start[1])
        
        # Expected chords with acceptable variants
        expected_chords = [
            # Row 1: Measures 1-4 (Cmaj9, Dm7, G7sus, Cmaj7)
            [
                ["C", "Cmaj", "CM", "Cmaj7", "Cmaj9"],
                ["Dm", "Dm7", "Dmin", "Dminor", "D-"],
                ["G7", "G", "G7sus", "Gsus7"],
                ["C", "Cmaj", "CM", "Cmaj7"]
            ],
            # Row 2: Measures 5-8 (Am7, Dm7, G7, C6/9)
            [
                ["Am", "Am7", "Amin", "Aminor", "A-"],
                ["Dm", "Dm7", "Dmin", "D-"],
                ["G7", "G"],
                ["C", "Cmaj", "CM", "C6", "C69", "C6/9"]
            ],
            # Row 3: Measures 9-12 (Fmaj7, Bm7b5, E7b9, Am7)
            [
                ["F", "Fmaj", "FM", "Fmaj7"],
                ["Bm7b5", "Bm", "Bdim", "Bø", "Bm7-5", "B-7b5"],
                ["E7", "E", "E7b9", "E7-9"],
                ["Am", "Am7", "Amin", "A-"]
            ],
            # Row 4: Measures 13-16 (Dm7, G7, Cmaj7, Cmaj7)
            [
                ["Dm", "Dm7", "Dmin", "D-"],
                ["G7", "G"],
                ["C", "Cmaj", "CM", "Cmaj7"],
                ["C", "Cmaj", "CM", "Cmaj7"]
            ]
        ]
        
        # Criterion 2: Check grid structure (4 rows with chord data)
        non_empty_rows = sum(1 for row in chords if any(cell for cell in row))
        
        if non_empty_rows >= 4:
            criteria_passed += 1
            feedback_parts.append("✅ Grid structure found (4 rows)")
        else:
            feedback_parts.append(f"❌ Grid structure incomplete ({non_empty_rows}/4 rows)")
        
        # Criterion 3: Check chord accuracy
        correct_chords = 0
        total_chords = 16
        chord_details = []
        
        for row_idx in range(min(len(chords), 4)):
            actual_row = chords[row_idx]
            expected_row = expected_chords[row_idx]
            
            for col_idx in range(min(len(actual_row), 4)):
                actual_chord = actual_row[col_idx]
                expected_variants = expected_row[col_idx]
                
                if chord_matches(actual_chord, expected_variants):
                    correct_chords += 1
                else:
                    # Log mismatch for debugging
                    actual_str = str(actual_chord) if actual_chord else "empty"
                    chord_details.append(f"R{row_idx+1}C{col_idx+1}:{actual_str}≠{expected_variants[0]}")
        
        chord_accuracy = (correct_chords / total_chords) * 100
        
        if correct_chords >= 12:  # 75% threshold
            criteria_passed += 1
            feedback_parts.append(f"✅ Chord accuracy: {correct_chords}/16 ({chord_accuracy:.0f}%)")
        else:
            feedback_parts.append(f"❌ Chord accuracy too low: {correct_chords}/16 ({chord_accuracy:.0f}%)")
            if chord_details[:3]:  # Show first 3 mismatches
                feedback_parts.append(f"Issues: {', '.join(chord_details[:3])}")
        
        # Criterion 4: Check text formatting (bold and/or large font)
        ws = wb[sheet_name]
        
        bold_count = 0
        large_font_count = 0
        sample_cells = []
        
        # Determine sample cell references (Excel is 1-indexed)
        for row_offset in range(min(4, len(chords))):
            row_num = grid_start[0] + row_offset + 1
            # Skip first column (measure labels), sample columns B-E
            for col_offset in range(1, 5):
                col_num = grid_start[1] + col_offset + 1
                sample_cells.append((row_num, col_num))
        
        for row_num, col_num in sample_cells[:8]:  # Check first 8 chord cells
            try:
                cell = ws.cell(row=row_num, column=col_num)
                
                # Check bold
                if cell.font and cell.font.bold:
                    bold_count += 1
                
                # Check font size (≥14pt is readable from music stand)
                if cell.font and cell.font.size:
                    if cell.font.size >= 14:
                        large_font_count += 1
            except Exception as e:
                logger.debug(f"Error checking cell ({row_num}, {col_num}): {e}")
                pass
        
        # Consider formatting good if at least half the sampled cells are formatted
        if bold_count >= 4 or large_font_count >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Text formatting applied (bold:{bold_count}/8, ≥14pt:{large_font_count}/8)")
        else:
            feedback_parts.append(f"⚠️ Limited formatting (bold:{bold_count}/8, ≥14pt:{large_font_count}/8)")
        
        # Criterion 5: Check layout (centered alignment or reasonable widths)
        centered_count = 0
        
        for row_num, col_num in sample_cells[:8]:
            try:
                cell = ws.cell(row=row_num, column=col_num)
                
                # Check alignment
                if cell.alignment and cell.alignment.horizontal:
                    if cell.alignment.horizontal == 'center':
                        centered_count += 1
            except Exception as e:
                logger.debug(f"Error checking alignment ({row_num}, {col_num}): {e}")
                pass
        
        # Also check column widths
        reasonable_width_count = 0
        try:
            # Check if columns B-E have reasonable widths (≥10)
            for col_letter in ['B', 'C', 'D', 'E']:
                if col_letter in ws.column_dimensions:
                    col_dim = ws.column_dimensions[col_letter]
                    if hasattr(col_dim, 'width') and col_dim.width:
                        if col_dim.width >= 10:
                            reasonable_width_count += 1
        except Exception as e:
            logger.debug(f"Error checking column widths: {e}")
            pass
        
        if centered_count >= 4 or reasonable_width_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Readable layout (centered:{centered_count}/8, wide_cols:{reasonable_width_count}/4)")
        else:
            feedback_parts.append(f"⚠️ Layout could be improved")
        
        # Calculate final score
        score = int((criteria_passed / 5) * 100)
        passed = score >= 75

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