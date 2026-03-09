#!/usr/bin/env python3
"""
Verifier for ISP Speed Dispute Task (isp_speed_dispute@1)

Verifies that user has:
1. Organized speed test data
2. Added percentage calculations
3. Calculated average speeds
4. Categorized by peak/off-peak times
5. Created summary section with key metrics
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


def verify_isp_speed_dispute(traj, env_info, task_info):
    """
    Verify that user has organized speed test data and created dispute summary
    
    Scoring breakdown:
    - File exists and readable: 10 points
    - Percentage calculation column: 20 points
    - Average speed calculation: 25 points
    - Peak/off-peak time analysis: 20 points
    - Summary section: 25 points
    
    Total: 100 points (pass threshold: 60)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available"
        }
    
    container_path = "/home/ga/Documents/Spreadsheets/speed_test_data.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_isp_')
    
    try:
        # Copy and parse the file
        success, workbook, error_msg = copy_and_parse_document(
            container_path,
            copy_from_env,
            file_format='xlsx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Could not open spreadsheet: {error_msg}"
            }
        
        feedback_parts = []
        score = 0
        max_score = 100
        
        # Check 1: File is accessible (10 points)
        score += 10
        feedback_parts.append("✅ Spreadsheet file exists and is readable")
        
        # Get all sheets and data
        sheet_names = workbook.sheetnames
        logger.info(f"Found sheets: {sheet_names}")
        
        # We'll search across all sheets for the required elements
        all_sheets_data = {}
        for sheet_name in sheet_names:
            all_sheets_data[sheet_name] = get_sheet_data(
                workbook, sheet_name, max_rows=100, max_cols=20
            )
        
        # Check 2: Look for percentage calculation column (20 points)
        found_percentage_col = False
        percentage_column_idx = -1
        sheet_with_percentage = None
        
        for sheet_name, sheet_data in all_sheets_data.items():
            if not sheet_data or len(sheet_data) == 0:
                continue
                
            # Search headers for percentage-related column
            headers = [str(cell).lower() if cell else "" for cell in sheet_data[0]]
            
            for idx, header in enumerate(headers):
                if any(keyword in header for keyword in ["percent", "%", "ratio", "advertised"]):
                    # Check if there are calculated percentage values in this column
                    col_values = []
                    for row_idx in range(1, min(20, len(sheet_data))):
                        if len(sheet_data[row_idx]) > idx:
                            val = sheet_data[row_idx][idx]
                            if val is not None and isinstance(val, (int, float)):
                                col_values.append(val)
                    
                    # Percentage values should typically be between 40-100 for this task
                    valid_percentages = [v for v in col_values if 40 <= v <= 100]
                    
                    if len(valid_percentages) >= 8:  # At least 8 of 14 tests calculated
                        found_percentage_col = True
                        percentage_column_idx = idx
                        sheet_with_percentage = sheet_name
                        score += 20
                        feedback_parts.append(
                            f"✅ Percentage calculations found in '{sheet_name}' "
                            f"(column {idx+1}, {len(valid_percentages)} values)"
                        )
                        break
            
            if found_percentage_col:
                break
        
        if not found_percentage_col:
            feedback_parts.append("❌ No percentage calculation column found (expected % of 300 Mbps)")
        
        # Check 3: Look for average speed calculation (25 points)
        found_average = False
        # Expected average based on sample data: mean of [287,245,298,156,201,178,198,289,165,187,276,144,291,152]
        # ≈ 219 Mbps
        expected_average_range = (200, 235)
        actual_average_found = None
        
        for sheet_name, sheet_data in all_sheets_data.items():
            if not sheet_data:
                continue
            
            for row_idx, row in enumerate(sheet_data):
                for col_idx, cell in enumerate(row):
                    if cell and isinstance(cell, (int, float)):
                        if expected_average_range[0] <= cell <= expected_average_range[1]:
                            # Check context - look for nearby "average", "mean", "actual" keywords
                            context_cells = []
                            
                            # Check cells to the left
                            if col_idx > 0:
                                for offset in range(1, min(3, col_idx + 1)):
                                    if row[col_idx - offset]:
                                        context_cells.append(str(row[col_idx - offset]))
                            
                            # Check cells above
                            if row_idx > 0:
                                for offset in range(1, min(3, row_idx + 1)):
                                    if len(sheet_data[row_idx - offset]) > col_idx:
                                        prev_cell = sheet_data[row_idx - offset][col_idx]
                                        if prev_cell:
                                            context_cells.append(str(prev_cell))
                            
                            context_text = " ".join(context_cells).lower()
                            
                            if any(word in context_text for word in 
                                   ["average", "mean", "actual", "avg", "overall", "total speed"]):
                                found_average = True
                                actual_average_found = cell
                                score += 25
                                feedback_parts.append(
                                    f"✅ Average speed calculation found: {cell:.1f} Mbps "
                                    f"(~{(cell/300)*100:.1f}% of advertised)"
                                )
                                break
                
                if found_average:
                    break
            
            if found_average:
                break
        
        if not found_average:
            feedback_parts.append(
                "❌ Average download speed calculation not found "
                "(expected ~215-220 Mbps)"
            )
        
        # Check 4: Look for peak/off-peak time analysis (20 points)
        found_time_analysis = False
        time_keywords = ["peak", "off-peak", "off peak", "offpeak", "evening", "morning", "time period"]
        
        for sheet_name, sheet_data in all_sheets_data.items():
            if not sheet_data:
                continue
            
            # Collect all text from sheet
            all_text = []
            for row in sheet_data:
                for cell in row:
                    if cell and isinstance(cell, str):
                        all_text.append(cell.lower())
            
            all_text_joined = " ".join(all_text)
            
            # Look for peak/off-peak mentions
            has_peak = any(keyword in all_text_joined for keyword in ["peak", "evening"])
            has_offpeak = any(keyword in all_text_joined for keyword in 
                             ["off-peak", "off peak", "offpeak", "morning", "daytime"])
            
            # Also look for a column that categorizes times
            for row in sheet_data[:20]:  # Check first 20 rows
                for cell in row:
                    if cell and isinstance(cell, str):
                        cell_lower = cell.lower()
                        if cell_lower in ["peak", "off-peak", "offpeak", "off peak"]:
                            has_peak = True
                            has_offpeak = True
                            break
            
            if has_peak and has_offpeak:
                found_time_analysis = True
                score += 20
                feedback_parts.append(
                    f"✅ Peak/off-peak time analysis present in '{sheet_name}'"
                )
                break
            elif has_peak or has_offpeak:
                # Partial credit
                score += 10
                feedback_parts.append(
                    f"⚠️ Partial time analysis found (only one category detected)"
                )
                found_time_analysis = True
                break
        
        if not found_time_analysis:
            feedback_parts.append(
                "❌ No peak/off-peak time analysis found "
                "(expected categorization and comparison)"
            )
        
        # Check 5: Look for summary section (25 points)
        found_summary_elements = {
            "advertised": False,
            "actual_or_average": False,
            "percentage_overall": False
        }
        
        summary_keywords = {
            "advertised": ["advertised", "promised", "contracted", "plan", "300"],
            "actual_or_average": ["actual", "measured", "average", "mean", "received"],
            "percentage_overall": ["percent", "%", "ratio", "delivered"]
        }
        
        for sheet_name, sheet_data in all_sheets_data.items():
            if not sheet_data:
                continue
            
            # Look for summary section indicators
            for row in sheet_data:
                row_text = " ".join([str(cell).lower() for cell in row if cell])
                
                # Check for advertised speed (300 Mbps)
                if not found_summary_elements["advertised"]:
                    if any(kw in row_text for kw in summary_keywords["advertised"]):
                        # Also check if 300 appears nearby
                        if "300" in row_text or any(
                            isinstance(cell, (int, float)) and abs(cell - 300) < 1 
                            for cell in row
                        ):
                            found_summary_elements["advertised"] = True
                
                # Check for actual/average speed
                if not found_summary_elements["actual_or_average"]:
                    if any(kw in row_text for kw in summary_keywords["actual_or_average"]):
                        # Check if there's a reasonable speed value in the row
                        if actual_average_found:
                            found_summary_elements["actual_or_average"] = True
                        else:
                            # Look for any value in expected range
                            for cell in row:
                                if isinstance(cell, (int, float)) and 150 <= cell <= 250:
                                    found_summary_elements["actual_or_average"] = True
                                    break
                
                # Check for percentage
                if not found_summary_elements["percentage_overall"]:
                    if any(kw in row_text for kw in summary_keywords["percentage_overall"]):
                        # Look for percentage value (60-80 range expected)
                        for cell in row:
                            if isinstance(cell, (int, float)) and 55 <= cell <= 85:
                                found_summary_elements["percentage_overall"] = True
                                break
        
        summary_count = sum(found_summary_elements.values())
        
        if summary_count == 3:
            score += 25
            feedback_parts.append(
                "✅ Complete summary section with advertised speed, "
                "actual average, and percentage metrics"
            )
        elif summary_count == 2:
            score += 17
            feedback_parts.append(
                f"⚠️ Partial summary section (2/3 required elements found)"
            )
        elif summary_count == 1:
            score += 8
            feedback_parts.append(
                f"⚠️ Incomplete summary section (1/3 required elements found)"
            )
        else:
            feedback_parts.append(
                "❌ No clear summary section found "
                "(expected: advertised speed, actual average, percentage received)"
            )
        
        # Determine pass/fail
        passed = score >= 60  # Need 60/100 to pass
        
        # Construct final feedback
        feedback = " | ".join(feedback_parts)
        feedback += f" || Final score: {score}/{max_score}"
        
        if passed:
            feedback += " || ✅ PASSED - Organized data suitable for ISP dispute"
        else:
            feedback += " || ❌ FAILED - Missing critical analysis components"
        
        return {
            "passed": passed,
            "score": score / max_score,
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
