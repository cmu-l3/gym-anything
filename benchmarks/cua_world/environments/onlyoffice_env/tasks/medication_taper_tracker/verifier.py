#!/usr/bin/env python3
"""
Verifier for medication_taper_tracker@1

Checks that formulas are correctly implemented for:
- Dose-to-pill calculations (Column C)
- Cumulative pill tracking (Column D)
- Remaining pill inventory (Column E)
- Summary calculations with status alert
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


def verify_medication_taper_tracker(traj, env_info, task_info):
    """
    Verify the medication taper tracking spreadsheet.
    
    Checks:
    1. Column C: Pills to Take formula (dose / 5) - spot check multiple rows
    2. Column D: Cumulative pills used formula - check progression
    3. Column E: Pills remaining formula - check inventory tracking
    4. Column F: Symptom notes header exists
    5. Summary calculations: total needed, remaining, status
    6. Formulas produce correct numerical results
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/prednisone_taper_raw.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_taper_')
    
    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')
        
        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
        
        ws = wb.active
        feedback_parts = []
        score = 0.0
        max_score = 10.0
        
        # Get starting supply value
        starting_supply = ws['I1'].value
        if starting_supply is None:
            starting_supply = 120  # Default if missing
        
        # ============================================================
        # Check 1: Column C - Pills to Take (dose / 5)
        # ============================================================
        pills_checks_passed = 0
        pills_checks_total = 4
        
        # Day 1 (row 2): 20mg should = 4 tablets
        pills_day1 = ws['C2'].value
        if pills_day1 is not None and abs(float(pills_day1) - 4.0) < 0.01:
            pills_checks_passed += 1
        else:
            feedback_parts.append(f"❌ Pills Day 1 incorrect: expected 4, got {pills_day1}")
        
        # Day 4 (row 5): 17.5mg should = 3.5 tablets
        pills_day4 = ws['C5'].value
        if pills_day4 is not None and abs(float(pills_day4) - 3.5) < 0.01:
            pills_checks_passed += 1
        else:
            feedback_parts.append(f"❌ Pills Day 4 incorrect: expected 3.5, got {pills_day4}")
        
        # Day 10 (row 11): 15mg should = 3 tablets
        pills_day10 = ws['C11'].value
        if pills_day10 is not None and abs(float(pills_day10) - 3.0) < 0.01:
            pills_checks_passed += 1
        else:
            feedback_parts.append(f"❌ Pills Day 10 incorrect: expected 3, got {pills_day10}")
        
        # Day 28 (row 29): 2.5mg should = 0.5 tablets
        pills_day28 = ws['C29'].value
        if pills_day28 is not None and abs(float(pills_day28) - 0.5) < 0.01:
            pills_checks_passed += 1
        else:
            feedback_parts.append(f"❌ Pills Day 28 incorrect: expected 0.5, got {pills_day28}")
        
        if pills_checks_passed == pills_checks_total:
            score += 2.5
            feedback_parts.append(f"✅ Pills calculation formulas correct (4/4 spot checks)")
        elif pills_checks_passed >= 2:
            score += 1.5
            feedback_parts.append(f"⚠ Pills calculation partially correct ({pills_checks_passed}/4 spot checks)")
        else:
            feedback_parts.append(f"❌ Pills calculation formulas incorrect ({pills_checks_passed}/4 spot checks)")
        
        # ============================================================
        # Check 2: Column D - Cumulative pills used
        # ============================================================
        cumulative_checks_passed = 0
        cumulative_checks_total = 4
        
        # Day 1 (row 2): should equal C2 (4 tablets)
        cumulative_day1 = ws['D2'].value
        if cumulative_day1 is not None and abs(float(cumulative_day1) - 4.0) < 0.01:
            cumulative_checks_passed += 1
        else:
            feedback_parts.append(f"❌ Cumulative Day 1 incorrect: expected 4, got {cumulative_day1}")
        
        # Day 2 (row 3): should be cumulative (4+4=8)
        cumulative_day2 = ws['D3'].value
        if cumulative_day2 is not None and abs(float(cumulative_day2) - 8.0) < 0.01:
            cumulative_checks_passed += 1
        else:
            feedback_parts.append(f"❌ Cumulative Day 2 incorrect: expected 8, got {cumulative_day2}")
        
        # Day 3 (row 4): should be cumulative (8+4=12)
        cumulative_day3 = ws['D4'].value
        if cumulative_day3 is not None and abs(float(cumulative_day3) - 12.0) < 0.01:
            cumulative_checks_passed += 1
        else:
            feedback_parts.append(f"❌ Cumulative Day 3 incorrect: expected 12, got {cumulative_day3}")
        
        # Check that cumulative increases (monotonicity check)
        if cumulative_day1 and cumulative_day2 and cumulative_day3:
            if cumulative_day1 < cumulative_day2 < cumulative_day3:
                cumulative_checks_passed += 1
            else:
                feedback_parts.append(f"❌ Cumulative values not increasing properly")
        
        if cumulative_checks_passed == cumulative_checks_total:
            score += 2.0
            feedback_parts.append(f"✅ Cumulative pills tracking correct (4/4 checks)")
        elif cumulative_checks_passed >= 2:
            score += 1.0
            feedback_parts.append(f"⚠ Cumulative pills partially correct ({cumulative_checks_passed}/4 checks)")
        else:
            feedback_parts.append(f"❌ Cumulative pills tracking incorrect ({cumulative_checks_passed}/4 checks)")
        
        # ============================================================
        # Check 3: Column E - Pills remaining
        # ============================================================
        remaining_checks_passed = 0
        remaining_checks_total = 3
        
        # Day 1 (row 2): should be starting_supply - 4 = 116
        remaining_day1 = ws['E2'].value
        expected_remaining_day1 = starting_supply - 4
        if remaining_day1 is not None and abs(float(remaining_day1) - expected_remaining_day1) < 0.01:
            remaining_checks_passed += 1
        else:
            feedback_parts.append(f"❌ Remaining Day 1 incorrect: expected {expected_remaining_day1}, got {remaining_day1}")
        
        # Day 2 (row 3): should be starting_supply - 8 = 112
        remaining_day2 = ws['E3'].value
        expected_remaining_day2 = starting_supply - 8
        if remaining_day2 is not None and abs(float(remaining_day2) - expected_remaining_day2) < 0.01:
            remaining_checks_passed += 1
        else:
            feedback_parts.append(f"❌ Remaining Day 2 incorrect: expected {expected_remaining_day2}, got {remaining_day2}")
        
        # Check that remaining decreases (monotonicity check)
        if remaining_day1 and remaining_day2:
            if remaining_day1 > remaining_day2:
                remaining_checks_passed += 1
            else:
                feedback_parts.append(f"❌ Remaining pills not decreasing properly")
        
        if remaining_checks_passed == remaining_checks_total:
            score += 2.0
            feedback_parts.append(f"✅ Pills remaining tracking correct (3/3 checks)")
        elif remaining_checks_passed >= 2:
            score += 1.0
            feedback_parts.append(f"⚠ Pills remaining partially correct ({remaining_checks_passed}/3 checks)")
        else:
            feedback_parts.append(f"❌ Pills remaining tracking incorrect ({remaining_checks_passed}/3 checks)")
        
        # ============================================================
        # Check 4: Column F - Symptom notes header
        # ============================================================
        symptom_header = ws['F1'].value
        if symptom_header and ('symptom' in str(symptom_header).lower() or 'side effect' in str(symptom_header).lower()):
            score += 0.5
            feedback_parts.append("✅ Symptom notes header present")
        else:
            feedback_parts.append(f"❌ Symptom notes header missing or incorrect: {symptom_header}")
        
        # ============================================================
        # Check 5: Summary calculations
        # ============================================================
        summary_score = 0.0
        summary_max = 3.0
        
        # Row 31: Total pills needed label
        total_label = ws['A31'].value
        if total_label and 'total' in str(total_label).lower() and 'pill' in str(total_label).lower():
            summary_score += 0.5
        else:
            feedback_parts.append(f"❌ Total pills label missing/incorrect: {total_label}")
        
        # Row 31: Total pills calculation (should be ~124.5 for this schedule)
        total_needed = ws['B31'].value
        if total_needed is not None:
            # The actual sum should be around 124.5 tablets
            # Accept range 123-126 to account for different rounding methods
            if 123 <= float(total_needed) <= 126:
                summary_score += 1.0
                feedback_parts.append(f"✅ Total pills calculation correct ({total_needed})")
            else:
                feedback_parts.append(f"❌ Total pills calculation incorrect: expected ~124.5, got {total_needed}")
        else:
            feedback_parts.append(f"❌ Total pills calculation missing")
        
        # Row 32: Pills remaining after taper label
        remaining_label = ws['A32'].value
        if remaining_label and 'remain' in str(remaining_label).lower():
            summary_score += 0.3
        else:
            feedback_parts.append(f"❌ Remaining pills label missing/incorrect: {remaining_label}")
        
        # Row 32: Pills remaining calculation
        remaining_after = ws['B32'].value
        if remaining_after is not None:
            # Should be approximately starting_supply - total_needed
            # For 120 - 124.5 = -4.5 (approximately -3 to -6 is acceptable)
            if -6 <= float(remaining_after) <= 0:
                summary_score += 0.7
                feedback_parts.append(f"✅ Remaining pills calculation correct ({remaining_after})")
            else:
                feedback_parts.append(f"⚠ Remaining pills calculation may be incorrect: {remaining_after}")
        else:
            feedback_parts.append(f"❌ Remaining pills calculation missing")
        
        # Row 33: Taper status label
        status_label = ws['A33'].value
        if status_label and 'status' in str(status_label).lower():
            summary_score += 0.3
        else:
            feedback_parts.append(f"❌ Status label missing/incorrect: {status_label}")
        
        # Row 33: Status value (should indicate refill needed)
        status_value = ws['B33'].value
        if status_value:
            status_str = str(status_value).lower()
            # Check for keywords indicating refill needed
            if 'refill' in status_str or 'need' in status_str or '⚠' in status_str or 'insufficient' in status_str:
                summary_score += 0.2
                feedback_parts.append(f"✅ Status correctly indicates refill needed")
            # Or if it says sufficient/enough, that's wrong for this data
            elif 'sufficient' in status_str or '✓' in status_str or 'enough' in status_str:
                feedback_parts.append(f"❌ Status incorrectly shows sufficient supply: {status_value}")
            else:
                feedback_parts.append(f"⚠ Status value unclear: {status_value}")
        else:
            feedback_parts.append(f"❌ Status calculation missing")
        
        score += summary_score
        
        if summary_score >= 2.5:
            feedback_parts.append(f"✅ Summary section correct ({summary_score:.1f}/{summary_max})")
        elif summary_score >= 1.5:
            feedback_parts.append(f"⚠ Summary section partially correct ({summary_score:.1f}/{summary_max})")
        else:
            feedback_parts.append(f"❌ Summary section incorrect ({summary_score:.1f}/{summary_max})")
        
        # ============================================================
        # Final assessment
        # ============================================================
        percentage = (score / max_score) * 100
        passed = percentage >= 70  # Pass threshold: 70%
        
        feedback = " | ".join(feedback_parts)
        feedback += f" || Final score: {score:.1f}/{max_score} ({percentage:.0f}%)"
        
        return {
            "passed": passed,
            "score": percentage / 100,
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
        # Cleanup temporary directory
        cleanup_temp_dir(temp_dir)


# Entry point for gym-anything framework
def verify(traj, env_info, task_info):
    """Entry point called by gym-anything verification system"""
    return verify_medication_taper_tracker(traj, env_info, task_info)