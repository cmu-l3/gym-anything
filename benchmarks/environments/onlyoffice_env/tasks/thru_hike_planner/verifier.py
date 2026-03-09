#!/usr/bin/env python3
"""
Verifier for Thru-Hike Planner task

This verifier checks that the agent has created a comprehensive backpacking trip
planner with proper formulas for:
- Hiking duration (Naismith's Rule)
- Arrival times
- Water needs (with seasonal buffers)
- Food weight calculations
- Total pack weight
- Safety validations
"""

import sys
import os
import logging
import tempfile
from datetime import time, datetime, timedelta

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def time_to_hours(time_val):
    """Convert various time formats to decimal hours"""
    if isinstance(time_val, (int, float)):
        # If it's already a number, assume it's hours
        if time_val < 1:  # Likely Excel time format (fraction of day)
            return time_val * 24
        return time_val
    elif isinstance(time_val, time):
        return time_val.hour + time_val.minute / 60.0
    elif isinstance(time_val, datetime):
        return time_val.hour + time_val.minute / 60.0
    elif isinstance(time_val, str):
        # Try to parse string time formats
        try:
            parts = time_val.replace(':', ' ').split()
            if len(parts) >= 2:
                return float(parts[0]) + float(parts[1]) / 60.0
        except:
            pass
    return None


def verify_thru_hike_planner(traj, env_info, task_info):
    """
    Verify that the thru-hike planner spreadsheet was created correctly.

    Checks:
    1. Daily_Plan sheet exists with appropriate structure
    2. Hiking duration formulas (Naismith's Rule) are correct
    3. Arrival time calculations are reasonable
    4. Water calculations include seasonal buffers
    5. Pack weight decreases over days (food consumption)
    6. Weight safety checks are implemented
    7. After-dark warnings are implemented
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/trail_planning_data.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_trail_')
    temp_file = None

    try:
        # Copy file from container
        temp_file = os.path.join(temp_dir, 'trail_planning_data.xlsx')
        copy_from_env(container_path, temp_file)

        if not os.path.exists(temp_file) or os.path.getsize(temp_file) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ File not found or empty: trail_planning_data.xlsx"
            }

        # Parse the spreadsheet
        wb = parse_xlsx_file(temp_file)
        if not wb:
            return {"passed": False, "score": 0.0, "feedback": "❌ Failed to parse Excel file"}

        feedback_parts = []
        score = 0.0
        max_score = 10.0  # Total points available

        # ============================================================
        # Check 1: Daily_Plan sheet exists (1 point)
        # ============================================================
        if "Daily_Plan" not in wb.sheetnames:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Daily_Plan sheet not found. You need to create this sheet with your formulas."
            }

        sheet = wb["Daily_Plan"]
        score += 1.0
        feedback_parts.append("✅ Daily_Plan sheet exists")

        # ============================================================
        # Check 2: Headers are present (1 point)
        # ============================================================
        # Look for headers in first few rows
        header_found = False
        header_row_idx = None
        expected_keywords = ["day", "duration", "arrival", "water", "weight", "pack"]

        for row_idx in range(1, 6):  # Check first 5 rows
            row_vals = [str(cell.value).lower() if cell.value else "" for cell in sheet[row_idx]]
            row_text = " ".join(row_vals)
            
            keyword_matches = sum(1 for kw in expected_keywords if kw in row_text)
            if keyword_matches >= 4:  # At least 4 keywords found
                header_found = True
                header_row_idx = row_idx
                break

        if not header_found:
            feedback_parts.append("⚠️ Headers incomplete or missing (need: Day, Duration, Arrival, Water, Weight columns)")
        else:
            score += 1.0
            feedback_parts.append(f"✅ Headers present (row {header_row_idx})")

        # Determine data start row (first row after headers)
        data_start_row = (header_row_idx + 1) if header_row_idx else 2

        # ============================================================
        # Check 3: Hiking duration calculations (2 points)
        # ============================================================
        # Expected: Day 1 ~4.0 hrs (8.5/3 + 2400/2000 = 2.83 + 1.2 = 4.03)
        #           Day 2 ~4.6 hrs (9.2/3 + 3100/2000 = 3.07 + 1.55 = 4.62)
        
        duration_col = None
        # Try to find duration column (usually column B or C)
        if header_row_idx:
            for col_idx, cell in enumerate(sheet[header_row_idx], start=1):
                cell_text = str(cell.value).lower() if cell.value else ""
                if "duration" in cell_text or "hiking" in cell_text:
                    duration_col = col_idx
                    break

        if not duration_col:
            # Default to column B
            duration_col = 2

        try:
            duration_day1 = sheet.cell(row=data_start_row, column=duration_col).value
            duration_day2 = sheet.cell(row=data_start_row + 1, column=duration_col).value

            day1_correct = False
            day2_correct = False

            if duration_day1 is not None:
                dur1 = float(duration_day1) if not isinstance(duration_day1, str) else None
                if dur1 and 3.8 <= dur1 <= 4.3:
                    day1_correct = True
                    score += 1.0
                    feedback_parts.append(f"✅ Day 1 hiking duration correct (~4.0 hrs, got {dur1:.2f})")
                else:
                    feedback_parts.append(f"❌ Day 1 hiking duration incorrect (got {duration_day1}, expected ~4.0 hrs)")

            if duration_day2 is not None:
                dur2 = float(duration_day2) if not isinstance(duration_day2, str) else None
                if dur2 and 4.4 <= dur2 <= 4.9:
                    day2_correct = True
                    score += 1.0
                    feedback_parts.append(f"✅ Day 2 hiking duration correct (~4.6 hrs, got {dur2:.2f})")
                else:
                    feedback_parts.append(f"❌ Day 2 hiking duration incorrect (got {duration_day2}, expected ~4.6 hrs)")

            if not day1_correct and not day2_correct:
                feedback_parts.append("❌ Hiking duration formulas not working (check Naismith's Rule)")

        except Exception as e:
            feedback_parts.append(f"⚠️ Could not verify hiking durations: {str(e)}")

        # ============================================================
        # Check 4: Arrival time calculations (1 point)
        # ============================================================
        # Expected: Day 1 arrival ~12:00 PM (7:00 AM + 4 hrs + 1 hr lunch)
        arrival_col = duration_col + 1  # Usually next to duration

        try:
            arrival_day1 = sheet.cell(row=data_start_row, column=arrival_col).value
            
            if arrival_day1 is not None:
                # Try to interpret as time
                arrival_hours = None
                
                if isinstance(arrival_day1, (int, float)):
                    # Excel time format (fraction of day)
                    if 0 <= arrival_day1 <= 1:
                        arrival_hours = arrival_day1 * 24
                    else:
                        arrival_hours = arrival_day1
                elif isinstance(arrival_day1, (time, datetime)):
                    arrival_hours = arrival_day1.hour + arrival_day1.minute / 60.0
                
                if arrival_hours and 11.5 <= arrival_hours <= 13.0:  # Between 11:30 AM and 1:00 PM
                    score += 1.0
                    feedback_parts.append(f"✅ Day 1 arrival time reasonable (~12:00 PM)")
                else:
                    feedback_parts.append(f"⚠️ Day 1 arrival time unexpected (check formula: Start + Duration + 1hr)")
            else:
                feedback_parts.append("⚠️ Arrival time not calculated")

        except Exception as e:
            feedback_parts.append(f"⚠️ Could not verify arrival time: {str(e)}")

        # ============================================================
        # Check 5: Water calculations (1.5 points)
        # ============================================================
        # Expected: Day 1 should have buffer for seasonal source (~3.2 + 1.0 = 4.2L)
        water_col = None
        if header_row_idx:
            for col_idx, cell in enumerate(sheet[header_row_idx], start=1):
                cell_text = str(cell.value).lower() if cell.value else ""
                if "water" in cell_text:
                    water_col = col_idx
                    break

        if not water_col:
            water_col = duration_col + 3  # Estimate

        try:
            water_day1 = sheet.cell(row=data_start_row, column=water_col).value
            water_day3 = sheet.cell(row=data_start_row + 2, column=water_col).value

            if water_day1 is not None and isinstance(water_day1, (int, float)):
                # Base water need for Day 1: ~4.0hrs * 0.5 + 4hrs * 0.3 = 2.0 + 1.2 = 3.2L
                # With seasonal buffer: +1.0L = 4.2L
                if 4.0 <= water_day1 <= 5.0:
                    score += 0.75
                    feedback_parts.append(f"✅ Day 1 water includes seasonal buffer ({water_day1:.1f}L)")
                elif 3.0 <= water_day1 <= 4.0:
                    score += 0.5
                    feedback_parts.append(f"⚠️ Day 1 water calculated but may be missing seasonal buffer ({water_day1:.1f}L, expected ~4.2L)")
                else:
                    feedback_parts.append(f"❌ Day 1 water calculation incorrect ({water_day1:.1f}L)")

            if water_day3 is not None and isinstance(water_day3, (int, float)):
                # Day 3 also has seasonal source
                if 3.5 <= water_day3 <= 5.0:
                    score += 0.75
                    feedback_parts.append(f"✅ Day 3 water includes seasonal buffer ({water_day3:.1f}L)")
                else:
                    feedback_parts.append(f"⚠️ Day 3 water may need seasonal buffer ({water_day3:.1f}L)")

        except Exception as e:
            feedback_parts.append(f"⚠️ Could not verify water calculations: {str(e)}")

        # ============================================================
        # Check 6: Pack weight decreases over days (1.5 points)
        # ============================================================
        pack_weight_col = None
        if header_row_idx:
            for col_idx, cell in enumerate(sheet[header_row_idx], start=1):
                cell_text = str(cell.value).lower() if cell.value else ""
                if "total" in cell_text and "pack" in cell_text:
                    pack_weight_col = col_idx
                    break
                elif "pack" in cell_text and "weight" in cell_text:
                    pack_weight_col = col_idx
                    break

        if not pack_weight_col:
            pack_weight_col = duration_col + 5  # Estimate

        try:
            weights = []
            for day_offset in range(5):  # 5 days
                weight = sheet.cell(row=data_start_row + day_offset, column=pack_weight_col).value
                if weight is not None and isinstance(weight, (int, float)):
                    weights.append(weight)

            if len(weights) >= 4:
                # Check if weights generally decrease
                decreasing = True
                for i in range(len(weights) - 1):
                    if weights[i] <= weights[i + 1]:
                        # Allow small increases (up to 1 lb) for water weight variations
                        if weights[i + 1] - weights[i] > 1:
                            decreasing = False
                            break

                if decreasing and weights[0] > weights[-1]:
                    score += 1.5
                    feedback_parts.append(f"✅ Pack weight decreases correctly: Day1={weights[0]:.1f}lbs > Day5={weights[-1]:.1f}lbs")
                else:
                    feedback_parts.append(f"⚠️ Pack weight should decrease each day (food consumed): {[f'{w:.1f}' for w in weights]}")
            else:
                feedback_parts.append("⚠️ Pack weight calculations incomplete")

        except Exception as e:
            feedback_parts.append(f"⚠️ Could not verify pack weight trend: {str(e)}")

        # ============================================================
        # Check 7: Weight safety check logic (1 point)
        # ============================================================
        weight_ok_col = pack_weight_col + 1 if pack_weight_col else None

        if weight_ok_col:
            try:
                weight_ok_day1 = sheet.cell(row=data_start_row, column=weight_ok_col).value
                
                if weight_ok_day1 is not None:
                    weight_ok_str = str(weight_ok_day1).upper()
                    if "OK" in weight_ok_str or "OVER" in weight_ok_str or weight_ok_day1 in [True, False]:
                        score += 1.0
                        feedback_parts.append(f"✅ Weight safety check implemented (Day 1: {weight_ok_day1})")
                    else:
                        feedback_parts.append(f"⚠️ Weight safety check present but format unclear ({weight_ok_day1})")
                else:
                    feedback_parts.append("⚠️ Weight safety check (OK/OVER) not found")

            except Exception as e:
                feedback_parts.append(f"⚠️ Could not verify weight safety check: {str(e)}")
        else:
            feedback_parts.append("⚠️ Weight safety check column not found")

        # ============================================================
        # Check 8: After-dark warning logic (1 point)
        # ============================================================
        after_dark_col = weight_ok_col + 1 if weight_ok_col else None

        if after_dark_col:
            try:
                after_dark_values = []
                for day_offset in range(5):
                    val = sheet.cell(row=data_start_row + day_offset, column=after_dark_col).value
                    if val is not None:
                        after_dark_values.append(val)

                if len(after_dark_values) >= 3:
                    # Check if it contains YES/NO or TRUE/FALSE
                    valid_values = [str(v).upper() in ["YES", "NO", "TRUE", "FALSE"] or v in [True, False] 
                                  for v in after_dark_values]
                    
                    if sum(valid_values) >= 3:
                        score += 1.0
                        feedback_parts.append(f"✅ After-dark warnings implemented")
                    else:
                        feedback_parts.append(f"⚠️ After-dark warnings present but format unclear")
                else:
                    feedback_parts.append("⚠️ After-dark warnings incomplete")

            except Exception as e:
                feedback_parts.append(f"⚠️ Could not verify after-dark warnings: {str(e)}")
        else:
            feedback_parts.append("⚠️ After-dark warning column not found")

        # ============================================================
        # Final scoring
        # ============================================================
        normalized_score = score / max_score  # Convert to 0.0-1.0
        passed = normalized_score >= 0.75

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
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)