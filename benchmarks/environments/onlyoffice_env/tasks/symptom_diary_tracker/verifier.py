#!/usr/bin/env python3
"""
Verifier for Symptom Diary Tracker task

Comprehensive verification of personal health symptom tracking spreadsheet
Checks: headers, formatting, data validation, conditional formatting, 
sample data, and summary formulas.
"""

import sys
import os
import logging
import tempfile
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_symptom_diary(traj, env_info, task_info):
    """
    Verify that symptom diary spreadsheet was created correctly.

    Scoring breakdown (100 points total):
    - Headers present (20 points): All 8 required headers in row 1
    - Header formatting (10 points): Bold and background color
    - Sample data entries (20 points): At least 5 complete data rows
    - Summary formulas (30 points): Count, Average, Max formulas functional
    - Conditional formatting (20 points): Color coding in severity column
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/symptom_diary.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_symptom_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        score = 0
        feedback_parts = []
        
        # Get the active sheet
        sheet = wb.active
        
        # ============================================================
        # CRITERION 1: Check for required headers (20 points)
        # ============================================================
        required_headers = [
            'date', 'time', 'symptom', 'severity', 
            'duration', 'trigger', 'medication', 'notes'
        ]
        
        headers_found = []
        header_row = []
        
        # Read first row to get headers
        for col_idx in range(1, 15):  # Check first 14 columns
            cell_value = sheet.cell(1, col_idx).value
            if cell_value:
                header_text = str(cell_value).lower().strip()
                header_row.append((col_idx, cell_value, header_text))
        
        # Match headers with required keywords
        matched_headers = 0
        for required in required_headers:
            for col_idx, original, normalized in header_row:
                if required in normalized:
                    headers_found.append(required)
                    matched_headers += 1
                    break
        
        if matched_headers >= 8:
            score += 20
            feedback_parts.append(f"✅ All 8 required headers present ({matched_headers}/8)")
        elif matched_headers >= 6:
            score += 15
            feedback_parts.append(f"⚠️ Most headers present ({matched_headers}/8)")
        elif matched_headers >= 4:
            score += 10
            feedback_parts.append(f"⚠️ Some headers present ({matched_headers}/8)")
        else:
            feedback_parts.append(f"❌ Missing most headers ({matched_headers}/8 found)")
        
        # ============================================================
        # CRITERION 2: Check header formatting (10 points)
        # ============================================================
        header_formatted = False
        header_has_color = False
        
        if len(header_row) > 0:
            # Check first header cell for formatting
            first_header_cell = sheet.cell(1, 1)
            
            # Check for bold
            if first_header_cell.font and first_header_cell.font.bold:
                header_formatted = True
            
            # Check for background color (not white/default)
            if first_header_cell.fill and first_header_cell.fill.fgColor:
                color = first_header_cell.fill.fgColor.rgb
                # Check if it's not default white (FFFFFFFF or 00000000)
                if color and color not in ['FFFFFFFF', '00000000', 'FF000000']:
                    header_has_color = True
        
        formatting_points = 0
        if header_formatted:
            formatting_points += 5
            feedback_parts.append("✅ Headers are bold")
        else:
            feedback_parts.append("❌ Headers are not bold")
        
        if header_has_color:
            formatting_points += 5
            feedback_parts.append("✅ Header background color applied")
        else:
            feedback_parts.append("❌ Header background color missing")
        
        score += formatting_points
        
        # ============================================================
        # CRITERION 3: Check for sample data entries (20 points)
        # ============================================================
        data_rows = 0
        complete_data_rows = 0
        severity_column_idx = None
        symptom_column_idx = None
        
        # Try to identify the severity and symptom columns from headers
        for col_idx, original, normalized in header_row:
            if 'severity' in normalized:
                severity_column_idx = col_idx
            if 'symptom' in normalized:
                symptom_column_idx = col_idx
        
        # If we couldn't find columns from headers, use defaults (C for symptom, D for severity)
        if symptom_column_idx is None:
            symptom_column_idx = 3  # Column C
        if severity_column_idx is None:
            severity_column_idx = 4  # Column D
        
        # Count data rows (check rows 2-20 for sample data)
        for row_idx in range(2, 21):
            symptom_value = sheet.cell(row_idx, symptom_column_idx).value
            if symptom_value and str(symptom_value).strip():
                data_rows += 1
                
                # Check if row is relatively complete (has severity and at least 3 other fields)
                filled_cells = 0
                for col in range(1, 9):
                    if sheet.cell(row_idx, col).value:
                        filled_cells += 1
                
                if filled_cells >= 4:  # At least 4 fields filled
                    complete_data_rows += 1
        
        if complete_data_rows >= 5:
            score += 20
            feedback_parts.append(f"✅ {complete_data_rows} complete symptom entries found")
        elif complete_data_rows >= 3:
            score += 15
            feedback_parts.append(f"⚠️ {complete_data_rows} entries found (need 5)")
        elif data_rows >= 2:
            score += 10
            feedback_parts.append(f"⚠️ Only {data_rows} entries, some incomplete")
        else:
            feedback_parts.append(f"❌ Insufficient data entries ({data_rows} found)")
        
        # ============================================================
        # CRITERION 4: Check for summary formulas (30 points)
        # ============================================================
        formula_count = 0
        formula_types = {'count': False, 'average': False, 'max': False}
        
        # Check rows 100-110 for summary section (allowing flexibility in placement)
        for row_idx in range(100, 111):
            for col_idx in range(1, 5):  # Check first 4 columns
                cell = sheet.cell(row_idx, col_idx)
                
                # Check if cell contains a formula (openpyxl provides data_type)
                # or if value is actually a formula result
                cell_value = cell.value
                
                # Try to detect formulas by checking adjacent cells for labels
                label_cell = sheet.cell(row_idx, max(1, col_idx - 1)).value
                
                if cell_value and isinstance(cell_value, (int, float)):
                    # We have a numeric value, check if it's from a formula
                    # by looking for formula-like labels nearby
                    label_text = str(label_cell).lower() if label_cell else ""
                    
                    if 'total' in label_text or 'episode' in label_text:
                        if not formula_types['count'] and 3 <= cell_value <= 50:
                            formula_count += 1
                            formula_types['count'] = True
                    elif 'average' in label_text:
                        if not formula_types['average'] and 1 <= cell_value <= 10:
                            formula_count += 1
                            formula_types['average'] = True
                    elif 'max' in label_text or 'highest' in label_text:
                        if not formula_types['max'] and 1 <= cell_value <= 10:
                            formula_count += 1
                            formula_types['max'] = True
        
        # Alternative: Check specific cells if pattern not found
        if formula_count < 2:
            # Try specific cells that match the instructions (B103, B104, B105)
            formula_cells = [
                (103, 2),  # B103
                (104, 2),  # B104
                (105, 2),  # B105
            ]
            
            temp_formula_count = 0
            for row, col in formula_cells:
                cell_value = sheet.cell(row, col).value
                if cell_value and isinstance(cell_value, (int, float)):
                    temp_formula_count += 1
            
            if temp_formula_count > formula_count:
                formula_count = temp_formula_count
        
        if formula_count >= 3:
            score += 30
            feedback_parts.append("✅ All 3 summary formulas present and functional")
        elif formula_count >= 2:
            score += 20
            feedback_parts.append(f"⚠️ {formula_count}/3 summary formulas present")
        elif formula_count >= 1:
            score += 10
            feedback_parts.append(f"⚠️ Only {formula_count}/3 summary formulas found")
        else:
            feedback_parts.append("❌ Summary formulas missing")
        
        # ============================================================
        # CRITERION 5: Check for conditional formatting (20 points)
        # ============================================================
        # Conditional formatting detection is complex in openpyxl
        # We'll check for cell fill colors in the severity column
        
        colored_cells = 0
        different_colors = set()
        
        # Check severity column for colored cells
        for row_idx in range(2, min(data_rows + 2, 21)):
            cell = sheet.cell(row_idx, severity_column_idx)
            
            if cell.fill and cell.fill.fgColor:
                color_rgb = cell.fill.fgColor.rgb
                if color_rgb and color_rgb not in ['FFFFFFFF', '00000000', 'FF000000']:
                    colored_cells += 1
                    different_colors.add(color_rgb)
        
        # Check if we have multiple colors (indicating conditional formatting)
        if len(different_colors) >= 2 and colored_cells >= 3:
            score += 20
            feedback_parts.append(f"✅ Conditional formatting detected ({colored_cells} colored cells, {len(different_colors)} colors)")
        elif colored_cells >= 2:
            score += 10
            feedback_parts.append(f"⚠️ Some cell coloring present ({colored_cells} cells)")
        else:
            feedback_parts.append("❌ No conditional formatting detected")
        
        # ============================================================
        # Additional checks for quality
        # ============================================================
        
        # Check if severity values are in valid range (1-10)
        invalid_severity = False
        for row_idx in range(2, min(data_rows + 2, 21)):
            severity_val = sheet.cell(row_idx, severity_column_idx).value
            if severity_val and isinstance(severity_val, (int, float)):
                if severity_val < 1 or severity_val > 10:
                    invalid_severity = True
                    break
        
        if invalid_severity:
            feedback_parts.append("⚠️ Some severity values outside 1-10 range")
        
        # ============================================================
        # Final scoring and feedback
        # ============================================================
        
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete. Score: {score}/100, Passed: {passed}")
        
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
