#!/usr/bin/env python3
"""
Verifier for Creek Monitoring Dataset task

This verifier checks that the water quality monitoring spreadsheet was created correctly:
1. Proper headers in row 1
2. All 12 samples entered correctly
3. Summary calculations with formulas
4. Conditional formatting applied
5. Data validation on pH column
"""

import sys
import os
import logging
import tempfile
import re
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_creek_monitoring_dataset(traj, env_info, task_info):
    """
    Verify the Mill Creek water quality monitoring spreadsheet.
    
    Scoring:
    - Structure (headers): 20 points
    - Data entry: 30 points
    - Summary calculations: 25 points
    - Conditional formatting: 15 points
    - Data validation: 10 points
    Total: 100 points, passing threshold: 70
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Copy function not available"
        }

    container_path = "/home/ga/Documents/Spreadsheets/mill_creek_data.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_creek_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Could not open spreadsheet: {error}"
            }

        # Get the active sheet (should be named something like "Mill Creek Data" or "Sheet1")
        sheet = wb.active
        feedback_parts = []
        score = 0.0

        # ===================================================================
        # CRITERION 1: Check headers (20 points)
        # ===================================================================
        logger.info("Checking headers...")
        
        expected_header_keywords = [
            'date', 'time', 'location', 'ph', 
            'dissolved oxygen', 'nitrate', 
            'temp', 'weather', 'note'
        ]
        
        # Read first row
        row1_values = []
        for col in range(1, 12):  # Check first 11 columns
            cell_val = sheet.cell(1, col).value
            if cell_val:
                row1_values.append(str(cell_val).strip().lower())
            else:
                row1_values.append('')
        
        row1_text = ' '.join(row1_values)
        logger.info(f"Row 1 content: {row1_values[:6]}")
        
        # Check if key header terms are present
        headers_found = sum(1 for keyword in expected_header_keywords if keyword in row1_text)
        
        if headers_found >= 7:  # At least 7 out of 9 keywords present
            score += 20
            feedback_parts.append(f"✅ Headers correct ({headers_found}/9 key terms found)")
        elif headers_found >= 5:
            score += 10
            feedback_parts.append(f"⚠️ Headers partially correct ({headers_found}/9 key terms)")
        else:
            feedback_parts.append(f"❌ Headers missing or incorrect ({headers_found}/9 key terms found)")

        # ===================================================================
        # CRITERION 2: Check data entry (30 points)
        # ===================================================================
        logger.info("Checking data entry...")
        
        # Define critical data points to verify (row, col, expected_value, tolerance, label)
        # Columns: A=1(Date), B=2(Time), C=3(Location), D=4(pH), E=5(DO), F=6(Nitrates), G=7(Temp), H=8(Weather), I=9(Notes)
        critical_checks = [
            # Sample 1 (row 2)
            (2, 4, 6.8, 0.1, "Sample 1 pH"),
            (2, 5, 7.2, 0.2, "Sample 1 DO"),
            (2, 6, 2.1, 0.2, "Sample 1 Nitrates"),
            
            # Sample 3 (row 4)
            (4, 4, 6.2, 0.1, "Sample 3 pH"),
            (4, 5, 5.8, 0.2, "Sample 3 DO"),
            
            # Sample 5 (row 6) - critical pollution indicator
            (6, 4, 5.9, 0.1, "Sample 5 pH"),
            (6, 6, 12.7, 0.3, "Sample 5 Nitrates"),
            
            # Sample 7 (row 8) - kit malfunction, but value should still be entered
            (8, 4, 11.2, 0.2, "Sample 7 pH (malfunction)"),
            
            # Sample 9 (row 10) - heavy rain event
            (10, 5, 3.9, 0.2, "Sample 9 DO"),
            (10, 6, 18.5, 0.3, "Sample 9 Nitrates"),
            
            # Sample 12 (row 13) - source found
            (13, 4, 8.9, 0.2, "Sample 12 pH"),
            (13, 6, 45.3, 1.0, "Sample 12 Nitrates"),
        ]
        
        data_points_correct = 0
        data_total = len(critical_checks)
        
        for row, col, expected, tolerance, label in critical_checks:
            cell_val = sheet.cell(row, col).value
            try:
                if cell_val is not None:
                    cell_float = float(cell_val)
                    if abs(cell_float - expected) <= tolerance:
                        data_points_correct += 1
                        logger.debug(f"✓ {label}: {cell_float} ≈ {expected}")
                    else:
                        logger.debug(f"✗ {label}: {cell_float} != {expected}")
                else:
                    logger.debug(f"✗ {label}: empty cell")
            except (ValueError, TypeError):
                logger.debug(f"✗ {label}: non-numeric value: {cell_val}")
        
        # Check date format (at least first date should be a date or contain "april" or "2025")
        date_cell = sheet.cell(2, 1).value
        is_date_format = False
        if isinstance(date_cell, datetime):
            is_date_format = True
        elif isinstance(date_cell, str):
            date_str_lower = date_cell.lower()
            if any(month in date_str_lower for month in ['april', 'may']) and '2025' in date_cell:
                is_date_format = True
        
        # Scoring for data entry
        data_score_ratio = data_points_correct / data_total
        if data_score_ratio >= 0.9 and is_date_format:
            score += 30
            feedback_parts.append(f"✅ Data entry correct ({data_points_correct}/{data_total} checks passed)")
        elif data_score_ratio >= 0.7:
            score += 20
            feedback_parts.append(f"⚠️ Data entry mostly correct ({data_points_correct}/{data_total} checks)")
        elif data_score_ratio >= 0.5:
            score += 10
            feedback_parts.append(f"⚠️ Data entry partially correct ({data_points_correct}/{data_total} checks)")
        else:
            feedback_parts.append(f"❌ Data entry incomplete ({data_points_correct}/{data_total} checks)")
        
        if not is_date_format:
            feedback_parts.append("⚠️ Date formatting may be incorrect")

        # ===================================================================
        # CRITERION 3: Check summary calculations (25 points)
        # ===================================================================
        logger.info("Checking summary calculations...")
        
        # Search for summary section (look for "average" keywords in cells below data)
        summary_locations = {}
        for row in range(14, 26):  # Search rows 14-25 for summaries
            for col in range(1, 5):  # Check first 4 columns
                cell_val = sheet.cell(row, col).value
                if cell_val and isinstance(cell_val, str):
                    cell_lower = cell_val.lower()
                    if 'average' in cell_lower or 'avg' in cell_lower:
                        if 'ph' in cell_lower:
                            summary_locations['avg_ph'] = (row, col)
                        elif 'do' in cell_lower or 'oxygen' in cell_lower:
                            summary_locations['avg_do'] = (row, col)
                        elif 'nitrate' in cell_lower:
                            summary_locations['avg_nitrate'] = (row, col)
                    if 'max' in cell_lower and 'nitrate' in cell_lower:
                        summary_locations['max_nitrate'] = (row, col)
                    if 'count' in cell_lower and ('do' in cell_lower or 'oxygen' in cell_lower):
                        summary_locations['count_low_do'] = (row, col)
        
        logger.info(f"Found summary locations: {summary_locations}")
        
        # Expected values for summary calculations
        # Average pH (excluding sample 7): (6.8+6.7+6.2+7.1+5.9+6.0+7.0+6.1+6.3+6.4+8.9)/11 = 6.673
        # Average DO: (7.2+7.4+5.8+7.8+5.1+4.8+6.2+7.9+3.9+4.2+4.5+9.2)/12 = 6.167
        # Average Nitrates: (2.1+2.3+8.4+1.9+12.7+15.2+14.8+2.0+18.5+16.1+14.9+45.3)/12 = 12.85
        # Max Nitrates: 45.3
        # Count DO < 5.0: 4 samples (5, 6, 9, 10)
        
        expected_summaries = {
            'avg_ph': (6.67, 0.15, "Average pH should be ~6.67 (excluding sample 7)"),
            'avg_do': (6.17, 0.5, "Average DO should be ~6.17"),
            'avg_nitrate': (12.85, 1.0, "Average Nitrates should be ~12.85"),
            'max_nitrate': (45.3, 1.0, "Max Nitrates should be 45.3"),
            'count_low_do': (4, 1, "Count of DO < 5.0 should be 4"),
        }
        
        formulas_correct = 0
        formulas_total = len(expected_summaries)
        
        for key, (expected_val, tolerance, description) in expected_summaries.items():
            if key in summary_locations:
                row, label_col = summary_locations[key]
                # Value is typically in the cell to the right of the label
                value_col = label_col + 1
                result_val = sheet.cell(row, value_col).value
                
                # Also check same cell in case label and value are together
                if result_val is None:
                    result_val = sheet.cell(row, label_col).value
                    # Try to extract number from text like "Average pH: 6.67"
                    if result_val and isinstance(result_val, str):
                        numbers = re.findall(r'\d+\.?\d*', result_val)
                        if numbers:
                            try:
                                result_val = float(numbers[-1])
                            except:
                                pass
                
                try:
                    if result_val is not None:
                        result_float = float(result_val)
                        if abs(result_float - expected_val) <= tolerance:
                            formulas_correct += 1
                            logger.debug(f"✓ {key}: {result_float} ≈ {expected_val}")
                        else:
                            logger.debug(f"✗ {key}: {result_float} != {expected_val} ({description})")
                    else:
                        logger.debug(f"✗ {key}: no value found")
                except (ValueError, TypeError):
                    logger.debug(f"✗ {key}: non-numeric result: {result_val}")
            else:
                logger.debug(f"✗ {key}: summary label not found")
        
        # Scoring for summary calculations
        if formulas_correct >= 4:
            score += 25
            feedback_parts.append(f"✅ Summary calculations correct ({formulas_correct}/{formulas_total} formulas)")
        elif formulas_correct >= 3:
            score += 18
            feedback_parts.append(f"⚠️ Most summary calculations correct ({formulas_correct}/{formulas_total})")
        elif formulas_correct >= 2:
            score += 10
            feedback_parts.append(f"⚠️ Some summary calculations present ({formulas_correct}/{formulas_total})")
        else:
            feedback_parts.append(f"❌ Summary calculations missing or incorrect ({formulas_correct}/{formulas_total})")

        # ===================================================================
        # CRITERION 4: Check conditional formatting (15 points)
        # ===================================================================
        logger.info("Checking conditional formatting...")
        
        # Count cells with formatting in the data columns (pH, DO, Nitrates)
        # pH column: D (col 4), DO column: E (col 5), Nitrates column: F (col 6)
        formatted_cells = 0
        
        for row in range(2, 14):  # Rows 2-13 (12 samples)
            for col in [4, 5, 6]:  # pH, DO, Nitrates
                cell = sheet.cell(row, col)
                
                # Check for fill color
                if hasattr(cell, 'fill') and hasattr(cell.fill, 'start_color'):
                    try:
                        rgb = cell.fill.start_color.rgb
                        # Check if it's not the default white/transparent (00000000, FFFFFFFF, or None)
                        if rgb and rgb not in ['00000000', 'FFFFFFFF', None]:
                            formatted_cells += 1
                            logger.debug(f"Cell {row},{col} has fill color: {rgb}")
                    except:
                        pass
                
                # Check for font color (red/orange/yellow text)
                if hasattr(cell, 'font') and hasattr(cell.font, 'color'):
                    try:
                        if cell.font.color and hasattr(cell.font.color, 'rgb'):
                            rgb = cell.font.color.rgb
                            if rgb and rgb not in ['00000000', 'FF000000', None]:
                                formatted_cells += 1
                                logger.debug(f"Cell {row},{col} has font color: {rgb}")
                    except:
                        pass
                
                # Check for bold font (another way to highlight)
                if hasattr(cell, 'font') and cell.font.bold:
                    # Don't count bold in header row
                    if row > 1:
                        formatted_cells += 1
                        logger.debug(f"Cell {row},{col} is bold")
        
        logger.info(f"Total formatted cells found: {formatted_cells}")
        
        # Expected: At least 10-15 cells should be formatted
        # pH violations: samples 3,5,6,7,9,12 = 6 cells
        # DO violations: samples 5,6,9,10 = 4 cells  
        # Nitrate violations: samples 5,6,7,9,10,11,12 = 7 cells
        # Total expected: ~17 formatted cells (with some overlap possible)
        
        if formatted_cells >= 12:
            score += 15
            feedback_parts.append(f"✅ Conditional formatting applied ({formatted_cells} formatted cells)")
        elif formatted_cells >= 8:
            score += 10
            feedback_parts.append(f"⚠️ Some conditional formatting ({formatted_cells} formatted cells)")
        elif formatted_cells >= 4:
            score += 5
            feedback_parts.append(f"⚠️ Minimal conditional formatting ({formatted_cells} formatted cells)")
        else:
            feedback_parts.append("❌ Conditional formatting not detected or insufficient")

        # ===================================================================
        # CRITERION 5: Check data validation (10 points)
        # ===================================================================
        logger.info("Checking data validation...")
        
        # Check if pH column (column D, col 4) has data validation
        ph_col_has_validation = False
        
        try:
            # Method 1: Check data_validations collection
            if hasattr(sheet, 'data_validations'):
                for dv in sheet.data_validations.dataValidation:
                    # Check if validation applies to pH column (column D)
                    if hasattr(dv, 'sqref') and dv.sqref:
                        sqref_str = str(dv.sqref)
                        # Check if it includes column D and rows 2-13
                        if 'D' in sqref_str:
                            ph_col_has_validation = True
                            logger.debug(f"Found data validation on: {sqref_str}")
                            break
            
            # Method 2: Check individual cells in pH column
            if not ph_col_has_validation:
                for row in range(2, 8):  # Check first few rows
                    cell = sheet.cell(row, 4)  # Column D (pH)
                    if hasattr(cell, 'data_validation') and cell.data_validation:
                        ph_col_has_validation = True
                        logger.debug(f"Found data validation on cell D{row}")
                        break
        except Exception as e:
            logger.warning(f"Error checking data validation: {e}")
        
        if ph_col_has_validation:
            score += 10
            feedback_parts.append("✅ Data validation detected on pH column")
        else:
            feedback_parts.append("❌ Data validation not detected (check pH column D2:D13)")

        # ===================================================================
        # Final Assessment
        # ===================================================================
        passed = score >= 70
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final score: {score}/100, Passed: {passed}")
        
        return {
            "passed": passed,
            "score": score / 100.0,  # Normalize to 0-1
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
