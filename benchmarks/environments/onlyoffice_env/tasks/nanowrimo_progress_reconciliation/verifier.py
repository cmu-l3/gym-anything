#!/usr/bin/env python3
"""
Verifier for NaNoWriMo Progress Reconciliation task
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_nanowrimo_dashboard(traj, env_info, task_info):
    """
    Verify the NaNoWriMo progress dashboard.
    
    Checks:
    1. Total words written calculated correctly (~24,450)
    2. Required daily pace calculated (~2,130 words/day for 12 remaining days)
    3. Status assessment present (BEHIND or ON TRACK)
    4. Bold headers used
    5. Colored cells for visual emphasis
    6. Cumulative total column exists
    7. Formulas used (not hardcoded values)
    8. Clear section organization
    9. Days remaining shown (12)
    10. Proper consolidation of data
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/nano_wordcount_raw.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_nano_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0.0, "feedback": f"Failed to load spreadsheet: {error}"}

        feedback = []
        score = 0.0
        
        # Expected values based on setup
        EXPECTED_TOTAL_MIN = 23000
        EXPECTED_TOTAL_MAX = 26000
        EXPECTED_TOTAL_IDEAL = 24450
        
        EXPECTED_PACE_MIN = 2000
        EXPECTED_PACE_MAX = 2300
        
        THRESHOLD = 30000  # Words needed by Day 18 to be "on track"
        DAYS_REMAINING = 12
        CURRENT_DAY = 18
        
        # Check all sheets for the dashboard (could be on any sheet)
        all_sheets = wb.sheetnames
        dashboard_found = False
        
        for sheet_name in all_sheets:
            if sheet_name == "TASK INSTRUCTIONS":
                continue  # Skip instructions sheet
                
            sheet = wb[sheet_name]
            
            # Check 1: Find total words written (should be ~24,450, range 23,000-26,000)
            total_found = False
            total_value = None
            for row in sheet.iter_rows(min_row=1, max_row=100, min_col=1, max_col=20):
                for cell in row:
                    if cell.value and isinstance(cell.value, (int, float)):
                        if EXPECTED_TOTAL_MIN <= cell.value <= EXPECTED_TOTAL_MAX:
                            total_found = True
                            total_value = cell.value
                            feedback.append(f"✅ Total words found: {cell.value} (expected ~24,450)")
                            score += 12
                            break
                if total_found:
                    break
            
            if not total_found and not dashboard_found:
                continue  # Try next sheet
            else:
                dashboard_found = True
                
            if not total_found:
                feedback.append(f"❌ Total words written not found or incorrect (expected {EXPECTED_TOTAL_MIN}-{EXPECTED_TOTAL_MAX})")
            
            # Check 2: Find required daily pace (should be ~2,130, range 2,000-2,300)
            pace_found = False
            pace_value = None
            for row in sheet.iter_rows(min_row=1, max_row=100, min_col=1, max_col=20):
                for cell in row:
                    if cell.value and isinstance(cell.value, (int, float)):
                        if EXPECTED_PACE_MIN <= cell.value <= EXPECTED_PACE_MAX:
                            pace_found = True
                            pace_value = cell.value
                            feedback.append(f"✅ Required daily pace calculated: {cell.value} words/day")
                            score += 15
                            break
                if pace_found:
                    break
            
            if not pace_found:
                feedback.append(f"❌ Required daily pace not found or incorrect (expected {EXPECTED_PACE_MIN}-{EXPECTED_PACE_MAX})")
            
            # Check 3: Look for status text ("BEHIND" or "ON TRACK")
            status_found = False
            status_cell = None
            for row in sheet.iter_rows(min_row=1, max_row=100, min_col=1, max_col=20):
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        cell_upper = cell.value.upper()
                        if "BEHIND" in cell_upper or "ON TRACK" in cell_upper:
                            status_found = True
                            status_cell = cell
                            # Check if status is correct based on total
                            if total_value and total_value < THRESHOLD and "BEHIND" in cell_upper:
                                feedback.append(f"✅ Status correctly shows 'BEHIND' ({total_value} < {THRESHOLD})")
                                score += 12
                            elif total_value and total_value >= THRESHOLD and "ON TRACK" in cell_upper:
                                feedback.append(f"✅ Status correctly shows 'ON TRACK' ({total_value} >= {THRESHOLD})")
                                score += 12
                            else:
                                feedback.append(f"⚠️ Status found but may be incorrect: {cell.value}")
                                score += 6
                            break
                if status_found:
                    break
            
            if not status_found:
                feedback.append("❌ Status assessment ('ON TRACK' or 'BEHIND') not found")
            
            # Check 4: Verify bold headers exist
            bold_count = 0
            for row in sheet.iter_rows(min_row=1, max_row=50, min_col=1, max_col=20):
                for cell in row:
                    if cell.font and cell.font.bold:
                        bold_count += 1
            
            if bold_count >= 3:
                feedback.append(f"✅ Found {bold_count} bold headers/labels")
                score += 8
            else:
                feedback.append(f"❌ Insufficient bold headers (found {bold_count}, need at least 3)")
            
            # Check 5: Verify colored cells (status indicator or section highlighting)
            colored_cells = 0
            status_colored = False
            for row in sheet.iter_rows(min_row=1, max_row=100, min_col=1, max_col=20):
                for cell in row:
                    if cell.fill and cell.fill.start_color:
                        rgb = cell.fill.start_color.rgb
                        if rgb and rgb not in ["00000000", "FFFFFFFF", None]:
                            colored_cells += 1
                            # Check if status cell is colored
                            if status_cell and cell == status_cell:
                                status_colored = True
            
            if colored_cells >= 1:
                feedback.append(f"✅ Visual formatting applied ({colored_cells} colored cells)")
                score += 8
                if status_colored:
                    feedback.append("✅ Status cell has distinctive color")
                    score += 2
            else:
                feedback.append("❌ No visual formatting (colored backgrounds) found")
            
            # Check 6: Verify cumulative total column exists
            cumulative_found = False
            for col in sheet.iter_cols(min_row=1, max_row=50, min_col=1, max_col=20):
                values = [cell.value for cell in col if isinstance(cell.value, (int, float))]
                # Check if values are increasing (cumulative) and reach a reasonable total
                if len(values) >= 8:  # At least 8 days of data
                    # Check if generally increasing
                    increasing_count = sum(1 for i in range(len(values)-1) if values[i] <= values[i+1])
                    if increasing_count >= len(values) * 0.7 and max(values) >= 20000:
                        cumulative_found = True
                        feedback.append(f"✅ Cumulative total column found (max: {max(values)})")
                        score += 12
                        break
            
            if not cumulative_found:
                feedback.append("❌ Cumulative total column not found or incorrect")
            
            # Check 7: Verify formulas are used (not hardcoded)
            formula_count = 0
            for row in sheet.iter_rows(min_row=1, max_row=100, min_col=1, max_col=20):
                for cell in row:
                    # Check if cell has a formula
                    if hasattr(cell, 'value') and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula_count += 1
                    # Also check the internal representation
                    elif hasattr(cell, '_value') and isinstance(cell._value, str) and cell._value.startswith('='):
                        formula_count += 1
            
            if formula_count >= 5:
                feedback.append(f"✅ Formulas used for calculations (found {formula_count})")
                score += 12
            elif formula_count >= 2:
                feedback.append(f"⚠️ Some formulas detected ({formula_count}), but may have hardcoded values")
                score += 6
            else:
                feedback.append(f"❌ Very few or no formulas detected ({formula_count})")
            
            # Check 8: Verify section organization (look for header text keywords)
            section_keywords = ["summary", "progress", "status", "pace", "daily", "average", 
                              "remaining", "total", "dashboard", "required", "track"]
            headers_found = 0
            for row in sheet.iter_rows(min_row=1, max_row=50, min_col=1, max_col=20):
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        cell_lower = cell.value.lower()
                        if any(keyword in cell_lower for keyword in section_keywords):
                            headers_found += 1
            
            if headers_found >= 4:
                feedback.append(f"✅ Clear section organization (found {headers_found} section indicators)")
                score += 8
            elif headers_found >= 2:
                feedback.append(f"⚠️ Some section organization ({headers_found} indicators)")
                score += 4
            else:
                feedback.append(f"❌ Limited section organization ({headers_found} indicators)")
            
            # Check 9: Verify days remaining calculation (should be 12)
            days_remaining_found = False
            for row in sheet.iter_rows(min_row=1, max_row=100, min_col=1, max_col=20):
                for cell in row:
                    if cell.value == DAYS_REMAINING:
                        days_remaining_found = True
                        feedback.append(f"✅ Days remaining calculated correctly (12)")
                        score += 5
                        break
                if days_remaining_found:
                    break
            
            if not days_remaining_found:
                feedback.append("⚠️ Days remaining (12) not explicitly shown")
            
            # Check 10: Verify data consolidation (no duplicate days)
            # Look for a Day column with unique values
            consolidation_checked = False
            for col in sheet.iter_cols(min_row=2, max_row=50, min_col=1, max_col=20):
                values = [cell.value for cell in col if isinstance(cell.value, int) and 1 <= cell.value <= 30]
                if len(values) >= 10:  # Looks like a Day column
                    unique_days = len(set(values))
                    total_entries = len(values)
                    if unique_days == total_entries:
                        feedback.append(f"✅ Data properly consolidated (no duplicate days)")
                        score += 6
                        consolidation_checked = True
                        break
                    elif unique_days >= total_entries * 0.8:
                        feedback.append(f"⚠️ Mostly consolidated (some duplicates may remain)")
                        score += 3
                        consolidation_checked = True
                        break
            
            if not consolidation_checked:
                feedback.append("ℹ️ Could not verify data consolidation")
            
            # If we found the dashboard on this sheet, don't check other sheets
            if dashboard_found:
                break
        
        if not dashboard_found:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "No dashboard found. Please create the progress summary with calculations."
            }
        
        # Determine pass/fail (need at least 65/100 to pass)
        passed = score >= 65
        
        return {
            "passed": passed,
            "score": score / 100.0,
            "feedback": " | ".join(feedback)
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
