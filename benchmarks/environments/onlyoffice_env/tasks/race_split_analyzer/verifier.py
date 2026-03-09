#!/usr/bin/env python3
"""
Verifier for Race Split Analyzer task
Validates that runner's pace analysis spreadsheet was created correctly
"""

import sys
import os
import logging
import tempfile
from datetime import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def time_to_seconds(time_value):
    """Convert various time representations to seconds"""
    if time_value is None:
        return None
    
    # If it's already a number (seconds or decimal minutes)
    if isinstance(time_value, (int, float)):
        # If it's in the range 7-11, it's probably decimal minutes
        if 7 <= time_value <= 11:
            return time_value * 60
        # Otherwise assume it's already seconds or a fraction of a day
        elif time_value < 1:  # Excel time format (fraction of day)
            return time_value * 86400
        return time_value
    
    # If it's a time object
    if isinstance(time_value, time):
        return time_value.hour * 3600 + time_value.minute * 60 + time_value.second
    
    # If it's a string like "8:15"
    if isinstance(time_value, str) and ':' in time_value:
        parts = time_value.split(':')
        if len(parts) == 2:
            minutes, seconds = map(int, parts)
            return minutes * 60 + seconds
    
    return None


def verify_race_split_analyzer(traj, env_info, task_info):
    """
    Verify that race split analysis spreadsheet was created correctly.

    Checks:
    1. Analysis sheet exists with proper structure
    2. Headers are correct and formatted
    3. Mile numbers 1-13 in column A
    4. Race 1 and Race 2 pace data linked
    5. Average pace calculated
    6. Slowdown flags present (at least some SLOW flags)
    7. Summary statistics: MIN, MAX, variation, consistency score
    8. Reasonable data values
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/race_data_raw.xlsx"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')

    try:
        # Copy file from container
        copy_from_env(container_path, temp_file.name)

        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "File not found or empty: race_data_raw.xlsx"
            }

        # Parse workbook
        wb = parse_xlsx_file(temp_file.name)
        if wb is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Failed to parse spreadsheet"
            }

        feedback_parts = []
        score = 0.0
        max_score = 14.0

        # Check Analysis sheet exists
        if "Analysis" not in wb.sheetnames:
            feedback_parts.append("❌ 'Analysis' sheet not found")
            return {
                "passed": False,
                "score": 0.0,
                "feedback": " | ".join(feedback_parts)
            }

        sheet = wb["Analysis"]

        # 1. Check headers (2 points)
        expected_headers = {
            1: "mile",
            2: "race 1 pace",
            3: "race 2 pace", 
            4: "average pace",
            5: "slowdown flag"
        }
        
        headers_correct = True
        for col_idx, expected_text in expected_headers.items():
            cell_value = sheet.cell(1, col_idx).value
            if cell_value is None or expected_text not in str(cell_value).lower():
                headers_correct = False
                break

        if headers_correct:
            score += 2.0
            feedback_parts.append("✅ Headers correct")
        else:
            feedback_parts.append("❌ Headers missing or incorrect")

        # 2. Check header formatting - bold (1 point)
        try:
            header_bold = sheet.cell(1, 1).font.bold or sheet.cell(1, 2).font.bold
            if header_bold:
                score += 0.5
                feedback_parts.append("✅ Headers formatted bold")
            else:
                feedback_parts.append("⚠️ Headers not bold")
        except:
            feedback_parts.append("⚠️ Could not check header formatting")

        # 3. Check header has background color (0.5 points)
        try:
            has_fill = (sheet.cell(1, 1).fill.start_color.index not in ['00000000', None] or
                       sheet.cell(1, 2).fill.start_color.index not in ['00000000', None])
            if has_fill:
                score += 0.5
                feedback_parts.append("✅ Headers have background color")
            else:
                feedback_parts.append("⚠️ Headers missing background color")
        except:
            feedback_parts.append("⚠️ Could not check header colors")

        # 4. Check mile numbers in column A (1.5 points)
        mile_numbers_correct = True
        for row in range(2, 15):
            expected_mile = row - 1
            actual_mile = sheet.cell(row, 1).value
            if actual_mile != expected_mile:
                mile_numbers_correct = False
                break

        if mile_numbers_correct:
            score += 1.5
            feedback_parts.append("✅ Mile numbers 1-13 present in column A")
        else:
            feedback_parts.append("❌ Mile numbers incorrect in column A")

        # 5. Check Race 1 data linked (column B has values) (1.5 points)
        race1_values_present = 0
        for row in range(2, 15):
            val = sheet.cell(row, 2).value
            if val is not None:
                race1_values_present += 1

        if race1_values_present >= 10:
            score += 1.5
            feedback_parts.append(f"✅ Race 1 pace data linked ({race1_values_present}/13 values)")
        else:
            feedback_parts.append(f"❌ Race 1 pace data missing ({race1_values_present}/13 values)")

        # 6. Check Race 2 data linked (column C has values) (1.5 points)
        race2_values_present = 0
        for row in range(2, 15):
            val = sheet.cell(row, 3).value
            if val is not None:
                race2_values_present += 1

        if race2_values_present >= 10:
            score += 1.5
            feedback_parts.append(f"✅ Race 2 pace data linked ({race2_values_present}/13 values)")
        else:
            feedback_parts.append(f"❌ Race 2 pace data missing ({race2_values_present}/13 values)")

        # 7. Check average pace calculated (column D) (1.5 points)
        avg_values_present = 0
        avg_values_reasonable = 0
        for row in range(2, 15):
            val = sheet.cell(row, 4).value
            if val is not None:
                avg_values_present += 1
                # Check if value is reasonable (between 7:30 and 11:00 pace)
                seconds = time_to_seconds(val)
                if seconds and 450 <= seconds <= 660:  # 7:30 to 11:00 in seconds
                    avg_values_reasonable += 1

        if avg_values_present >= 10:
            score += 1.0
            feedback_parts.append(f"✅ Average pace calculated ({avg_values_present}/13 values)")
            if avg_values_reasonable >= 8:
                score += 0.5
                feedback_parts.append(f"✅ Average values reasonable ({avg_values_reasonable}/13)")
            else:
                feedback_parts.append(f"⚠️ Some average values seem incorrect ({avg_values_reasonable}/13 reasonable)")
        else:
            feedback_parts.append(f"❌ Average pace not calculated ({avg_values_present}/13 values)")

        # 8. Check slowdown flags (column E) (1.5 points)
        flags_present = 0
        slow_count = 0
        ok_count = 0
        for row in range(2, 15):
            val = sheet.cell(row, 5).value
            if val and isinstance(val, str):
                flags_present += 1
                if "SLOW" in val.upper():
                    slow_count += 1
                elif "OK" in val.upper():
                    ok_count += 1

        if flags_present >= 10:
            score += 1.0
            feedback_parts.append(f"✅ Slowdown flags present ({flags_present}/13)")
            # Should have at least 3 SLOW flags (miles 9-12 should be slow)
            if slow_count >= 3:
                score += 0.5
                feedback_parts.append(f"✅ Slowdown detection working (found {slow_count} SLOW miles)")
            else:
                feedback_parts.append(f"⚠️ Expected more SLOW flags ({slow_count} found, expected ~4-5)")
        else:
            feedback_parts.append(f"❌ Slowdown flags missing ({flags_present}/13)")

        # 9. Check summary statistics - Fastest Mile (MIN) at B16 (1 point)
        min_val = sheet.cell(16, 2).value
        if min_val is not None:
            score += 1.0
            feedback_parts.append("✅ Fastest Mile (MIN) calculated")
        else:
            feedback_parts.append("❌ Fastest Mile (MIN) not calculated at B16")

        # 10. Check summary statistics - Slowest Mile (MAX) at B17 (1 point)
        max_val = sheet.cell(17, 2).value
        if max_val is not None:
            score += 1.0
            feedback_parts.append("✅ Slowest Mile (MAX) calculated")
        else:
            feedback_parts.append("❌ Slowest Mile (MAX) not calculated at B17")

        # 11. Check summary statistics - Pace Variation at B18 (0.5 points)
        variation_val = sheet.cell(18, 2).value
        if variation_val is not None:
            score += 0.5
            feedback_parts.append("✅ Pace Variation calculated")
        else:
            feedback_parts.append("⚠️ Pace Variation not calculated at B18")

        # 12. Check summary statistics - Consistency Score at B19 (1 point)
        consistency_val = sheet.cell(19, 2).value
        if consistency_val is not None:
            # Should be between 0 and 1 (or 0-100 if percentage)
            if isinstance(consistency_val, (int, float)):
                if 0 <= consistency_val <= 1 or 0 <= consistency_val <= 100:
                    score += 1.0
                    consistency_pct = consistency_val * 100 if consistency_val <= 1 else consistency_val
                    feedback_parts.append(f"✅ Consistency Score calculated ({consistency_pct:.0f}%)")
                else:
                    score += 0.5
                    feedback_parts.append(f"⚠️ Consistency Score present but value unusual: {consistency_val}")
            else:
                feedback_parts.append(f"⚠️ Consistency Score present but not numeric: {consistency_val}")
        else:
            feedback_parts.append("❌ Consistency Score not calculated at B19")

        # Normalize score
        normalized_score = score / max_score
        passed = normalized_score >= 0.70

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
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)