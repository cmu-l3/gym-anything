#!/usr/bin/env python3
"""
Verifier for Sleep Pattern Analyzer task

This verifier checks that the agent has:
1. Created a spreadsheet with proper structure (10 columns, 14 data rows)
2. Correctly extracted data from messy text notes
3. Calculated hours in bed from bedtime/wake time
4. Categorized caffeine, exercise, and stress data
5. Created summary statistics with formulas
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


def verify_sleep_pattern_analyzer(traj, env_info, task_info):
    """
    Verify that sleep diary has been organized into analyzable spreadsheet.
    
    Checks:
    1. File exists and can be parsed
    2. Has appropriate column headers (at least 8/10 expected)
    3. Has 14 rows of data (or close to it)
    4. Spot-check specific data points for accuracy
    5. Hours calculation present and reasonable
    6. Summary statistics section exists
    7. Data interpretation (caffeine categorization) is correct
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/sleep_analysis.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_sleep_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Spreadsheet not found or couldn't be opened: {error}"
            }

        feedback_parts = []
        score = 0.0
        
        # Get the active sheet
        sheet = wb.active
        data = get_sheet_data(wb, sheet.title, max_rows=40, max_cols=15)
        
        if not data or len(data) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Spreadsheet is empty"
            }
        
        # Check 1: Headers present (15 points)
        expected_headers = ['date', 'bed', 'wake', 'awoke', 'quality', 'hour', 'caff', 'exercise', 'screen', 'stress']
        header_row = [str(cell).lower() if cell else '' for cell in data[0][:12]]
        
        headers_found = 0
        for exp in expected_headers:
            if any(exp in h for h in header_row):
                headers_found += 1
        
        if headers_found >= 8:
            score += 15
            feedback_parts.append(f"✅ Headers: {headers_found}/10 core columns found")
        elif headers_found >= 6:
            score += 10
            feedback_parts.append(f"⚠️ Headers: only {headers_found}/10 found (partial credit)")
        else:
            feedback_parts.append(f"❌ Headers incomplete: only {headers_found}/10 found")
        
        # Check 2: Data rows present (15 points)
        non_empty_rows = 0
        for row_idx in range(1, min(20, len(data))):
            if len(data[row_idx]) > 0:
                # Count rows with at least 3 non-empty cells in first 5 columns
                non_empty_cells = sum(1 for cell in data[row_idx][:5] if cell is not None and str(cell).strip() != '')
                if non_empty_cells >= 3:
                    non_empty_rows += 1
        
        if non_empty_rows >= 13:
            score += 15
            feedback_parts.append(f"✅ Data rows: {non_empty_rows} entries (expected 14)")
        elif non_empty_rows >= 10:
            score += 10
            feedback_parts.append(f"⚠️ Data rows: {non_empty_rows} entries (expected 14, partial credit)")
        else:
            feedback_parts.append(f"❌ Insufficient data: only {non_empty_rows} rows (need 14)")
        
        # Check 3: Spot check specific data points (25 points)
        # Find quality and awoke columns
        quality_col_idx = None
        awoke_col_idx = None
        
        for idx, header in enumerate(header_row):
            if 'quality' in header or 'felt' in header:
                quality_col_idx = idx
            if 'awoke' in header or 'woke' in header or 'waking' in header:
                awoke_col_idx = idx
        
        spot_checks_passed = 0
        spot_checks_total = 0
        
        if quality_col_idx is not None and len(data) > 14:
            # Day 1 quality should be 4
            spot_checks_total += 1
            day1_quality = data[1][quality_col_idx] if len(data[1]) > quality_col_idx else None
            if day1_quality in [4, 4.0, '4', '4/10']:
                spot_checks_passed += 1
            
            # Day 7 quality should be 7
            spot_checks_total += 1
            day7_quality = data[7][quality_col_idx] if len(data) > 7 and len(data[7]) > quality_col_idx else None
            if day7_quality in [7, 7.0, '7', '7/10']:
                spot_checks_passed += 1
            
            # Day 14 quality should be 8
            spot_checks_total += 1
            day14_quality = data[14][quality_col_idx] if len(data) > 14 and len(data[14]) > quality_col_idx else None
            if day14_quality in [8, 8.0, '8', '8/10']:
                spot_checks_passed += 1
        
        if awoke_col_idx is not None and len(data) > 14:
            # Day 1 awoke should be 3
            spot_checks_total += 1
            day1_awoke = data[1][awoke_col_idx] if len(data[1]) > awoke_col_idx else None
            if day1_awoke in [3, 3.0, '3', '3x']:
                spot_checks_passed += 1
            
            # Day 14 awoke should be 0
            spot_checks_total += 1
            day14_awoke = data[14][awoke_col_idx] if len(data) > 14 and len(data[14]) > awoke_col_idx else None
            if day14_awoke in [0, 0.0, '0', '0x', None]:  # 0 or empty might indicate zero
                spot_checks_passed += 1
        
        if spot_checks_total > 0:
            spot_check_score = (spot_checks_passed / spot_checks_total) * 25
            score += spot_check_score
            if spot_checks_passed >= spot_checks_total * 0.8:
                feedback_parts.append(f"✅ Data accuracy: {spot_checks_passed}/{spot_checks_total} spot checks passed")
            elif spot_checks_passed >= spot_checks_total * 0.5:
                feedback_parts.append(f"⚠️ Data accuracy: {spot_checks_passed}/{spot_checks_total} spot checks passed (partial)")
            else:
                feedback_parts.append(f"❌ Data accuracy issues: only {spot_checks_passed}/{spot_checks_total} correct")
        else:
            feedback_parts.append("⚠️ Could not locate columns for spot checks")
        
        # Check 4: Hours calculation (15 points)
        hours_col_idx = None
        for idx, header in enumerate(header_row):
            if 'hour' in header:
                hours_col_idx = idx
                break
        
        if hours_col_idx is not None and len(data) > 1:
            # Check if hours column has reasonable values
            hours_values = []
            for row_idx in range(1, min(15, len(data))):
                if len(data[row_idx]) > hours_col_idx:
                    val = data[row_idx][hours_col_idx]
                    if isinstance(val, (int, float)) and 5 <= val <= 12:
                        hours_values.append(val)
            
            if len(hours_values) >= 10:
                score += 15
                avg_hours = sum(hours_values) / len(hours_values)
                feedback_parts.append(f"✅ Hours calculation present ({len(hours_values)} valid entries, avg={avg_hours:.1f}hrs)")
            elif len(hours_values) >= 5:
                score += 10
                feedback_parts.append(f"⚠️ Hours calculation partial ({len(hours_values)} valid entries)")
            else:
                feedback_parts.append(f"❌ Hours calculation missing or invalid")
        else:
            feedback_parts.append("❌ Hours in Bed column not found")
        
        # Check 5: Summary statistics section (20 points)
        # Look for summary section (usually after row 15)
        has_summary = False
        summary_start_row = None
        
        for row_idx in range(15, min(35, len(data))):
            if row_idx >= len(data):
                break
            row_text = ' '.join([str(cell).lower() for cell in data[row_idx] if cell])
            if 'average' in row_text or 'avg' in row_text or 'summary' in row_text or 'statistics' in row_text:
                has_summary = True
                summary_start_row = row_idx
                break
        
        if has_summary:
            score += 10
            feedback_parts.append(f"✅ Summary statistics section found (row {summary_start_row})")
            
            # Check for multiple summary calculations
            summary_calcs = 0
            for row_idx in range(summary_start_row, min(summary_start_row + 10, len(data))):
                if row_idx >= len(data):
                    break
                # Check if row has numeric values (indicating calculations)
                for cell in data[row_idx]:
                    if isinstance(cell, (int, float)) and 0 < cell < 15:
                        summary_calcs += 1
                        break
            
            if summary_calcs >= 4:
                score += 10
                feedback_parts.append(f"✅ Multiple summary calculations found ({summary_calcs} rows)")
            elif summary_calcs >= 2:
                score += 5
                feedback_parts.append(f"⚠️ Some summary calculations found ({summary_calcs} rows)")
        else:
            feedback_parts.append("❌ Summary statistics section not found")
        
        # Check 6: Caffeine categorization logic (10 points)
        caffeine_col_idx = None
        for idx, header in enumerate(header_row):
            if 'caff' in header:
                caffeine_col_idx = idx
                break
        
        if caffeine_col_idx is not None and len(data) > 7:
            caff_correct = 0
            caff_total = 0
            
            # Day 1 should be "Yes" (4pm coffee)
            caff_total += 1
            day1_caff = str(data[1][caffeine_col_idx]).lower() if len(data[1]) > caffeine_col_idx else ''
            if 'y' in day1_caff or 'true' in day1_caff or '1' == day1_caff:
                caff_correct += 1
            
            # Day 6 should be "No" (no caffeine)
            caff_total += 1
            day6_caff = str(data[6][caffeine_col_idx]).lower() if len(data) > 6 and len(data[6]) > caffeine_col_idx else ''
            if 'n' in day6_caff or 'false' in day6_caff or '0' == day6_caff or day6_caff.strip() == '':
                caff_correct += 1
            
            if caff_correct == 2:
                score += 10
                feedback_parts.append("✅ Caffeine categorization correct")
            elif caff_correct >= 1:
                score += 5
                feedback_parts.append(f"⚠️ Caffeine categorization partially correct ({caff_correct}/2)")
            else:
                feedback_parts.append("❌ Caffeine categorization incorrect")
        else:
            feedback_parts.append("⚠️ Could not verify caffeine categorization")
        
        # Normalize score to 0-100
        score = min(100, score)
        passed = score >= 65
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)