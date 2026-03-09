#!/usr/bin/env python3
"""
Verifier for Youth Soccer Tracker task
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


def verify_soccer_tracker(traj, env_info, task_info):
    """
    Verify that the youth soccer tracker was completed correctly.

    Checks:
    1. File exists and is valid XLSX format
    2. Correct attendance data entered for all 8 players
    3. Attendance % formulas present and calculate correctly
    4. Skill ratings entered for all players (1-5 range)
    5. At least 6 out of 8 players have correct skill ratings
    6. Coach notes column populated (at least 5 players)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/soccer_progress_final.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_soccer_')

    # Expected data based on the coaching notes
    expected_attendance = {
        'Emma Rodriguez': 6,
        'Marcus Johnson': 8,
        'Aisha Patel': 5,
        'Tyler Kim': 7,
        'Sofia Martinez': 7,
        'Jordan Lee': 6,
        'Mia Thompson': 8,
        'Carlos Santos': 4
    }
    
    expected_skills = {
        'Emma Rodriguez': (4, 2, 5),
        'Marcus Johnson': (4, 5, 2),
        'Aisha Patel': (3, 2, 4),
        'Tyler Kim': (4, 3, 4),
        'Sofia Martinez': (2, 4, 3),
        'Jordan Lee': (3, 3, 4),
        'Mia Thompson': (5, 4, 5),
        'Carlos Santos': (2, 2, 5)
    }

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Get the active sheet
        sheet = wb.active
        
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 6
        
        # Criterion 1: File exists and is valid (already passed if we're here)
        criteria_passed += 1
        feedback_parts.append("✅ File exists and is valid XLSX")
        
        # Read player data from spreadsheet (row 1 is headers, rows 2-9 are players)
        players_data = {}
        for row_idx in range(2, 10):  # 8 players in rows 2-9
            player_name = get_cell_value(wb, sheet.title, f'A{row_idx}')
            if player_name and isinstance(player_name, str):
                players_data[player_name.strip()] = {
                    'attended': get_cell_value(wb, sheet.title, f'B{row_idx}'),
                    'total': get_cell_value(wb, sheet.title, f'C{row_idx}'),
                    'percentage': get_cell_value(wb, sheet.title, f'D{row_idx}'),
                    'passing': get_cell_value(wb, sheet.title, f'E{row_idx}'),
                    'shooting': get_cell_value(wb, sheet.title, f'F{row_idx}'),
                    'teamwork': get_cell_value(wb, sheet.title, f'G{row_idx}'),
                    'notes': get_cell_value(wb, sheet.title, f'H{row_idx}')
                }
        
        logger.info(f"Found {len(players_data)} players in spreadsheet")
        
        # Criterion 2: Correct attendance data
        attendance_errors = []
        for player, expected in expected_attendance.items():
            if player in players_data:
                actual = players_data[player]['attended']
                if actual is None:
                    attendance_errors.append(f"{player}: missing attendance")
                elif not isinstance(actual, (int, float)):
                    attendance_errors.append(f"{player}: invalid attendance format")
                elif int(actual) != expected:
                    attendance_errors.append(f"{player}: expected {expected}, got {actual}")
            else:
                attendance_errors.append(f"{player}: not found in sheet")
        
        if len(attendance_errors) == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Attendance data correct for all 8 players")
        else:
            feedback_parts.append(f"❌ Attendance errors: {'; '.join(attendance_errors[:3])}")
            if len(attendance_errors) > 3:
                feedback_parts[-1] += f" (and {len(attendance_errors)-3} more)"
        
        # Criterion 3: Attendance % formulas and calculations
        percentage_errors = []
        for player, data in players_data.items():
            if player in expected_attendance:
                expected_pct = (expected_attendance[player] / 8) * 100
                actual_pct = data['percentage']
                
                if actual_pct is None:
                    percentage_errors.append(f"{player}: missing percentage")
                elif not isinstance(actual_pct, (int, float)):
                    percentage_errors.append(f"{player}: invalid percentage format")
                else:
                    # Handle both percentage (0-100) and decimal (0-1) formats
                    if actual_pct <= 1.0:
                        # Decimal format (0.75 for 75%)
                        expected_decimal = expected_attendance[player] / 8
                        if abs(actual_pct - expected_decimal) > 0.03:  # 3% tolerance
                            percentage_errors.append(f"{player}: expected ~{expected_decimal:.2f}, got {actual_pct:.2f}")
                    else:
                        # Percentage format (75 for 75%)
                        if abs(actual_pct - expected_pct) > 3:  # 3% tolerance
                            percentage_errors.append(f"{player}: expected ~{expected_pct:.1f}%, got {actual_pct:.1f}%")
        
        if len(percentage_errors) == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Attendance percentages calculated correctly")
        else:
            feedback_parts.append(f"❌ Percentage errors: {'; '.join(percentage_errors[:3])}")
            if len(percentage_errors) > 3:
                feedback_parts[-1] += f" (and {len(percentage_errors)-3} more)"
        
        # Criterion 4: Skill ratings entered (all players, all categories, 1-5 range)
        skill_entry_errors = []
        for player, data in players_data.items():
            if player in expected_skills:
                for skill_name, skill_key in [('Passing', 'passing'), ('Shooting', 'shooting'), ('Teamwork', 'teamwork')]:
                    value = data[skill_key]
                    if value is None:
                        skill_entry_errors.append(f"{player} missing {skill_name}")
                    elif not isinstance(value, (int, float)):
                        skill_entry_errors.append(f"{player} {skill_name} invalid format")
                    elif value < 1 or value > 5:
                        skill_entry_errors.append(f"{player} {skill_name} out of range (1-5): {value}")
        
        if len(skill_entry_errors) == 0:
            criteria_passed += 1
            feedback_parts.append("✅ All skill ratings entered in valid range (1-5)")
        else:
            feedback_parts.append(f"❌ Skill entry errors: {'; '.join(skill_entry_errors[:3])}")
            if len(skill_entry_errors) > 3:
                feedback_parts[-1] += f" (and {len(skill_entry_errors)-3} more)"
        
        # Criterion 5: At least 6/8 players have correct skill ratings
        correct_skill_count = 0
        skill_mismatches = []
        for player, expected_vals in expected_skills.items():
            if player in players_data:
                data = players_data[player]
                passing = data['passing']
                shooting = data['shooting']
                teamwork = data['teamwork']
                
                # Check if all three values are present and correct
                if all(isinstance(v, (int, float)) for v in [passing, shooting, teamwork]):
                    actual_vals = (int(passing), int(shooting), int(teamwork))
                    if actual_vals == expected_vals:
                        correct_skill_count += 1
                    else:
                        skill_mismatches.append(f"{player}: expected {expected_vals}, got {actual_vals}")
        
        if correct_skill_count >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Skill ratings accurate ({correct_skill_count}/8 players match exactly)")
        else:
            feedback_parts.append(f"❌ Only {correct_skill_count}/8 players have correct skills (need 6+)")
            if skill_mismatches:
                feedback_parts.append(f"   Mismatches: {'; '.join(skill_mismatches[:2])}")
        
        # Criterion 6: Coach notes present for at least 5 players
        notes_count = 0
        for player, data in players_data.items():
            if player in expected_skills:
                notes = data['notes']
                if notes and isinstance(notes, str) and notes.strip() and len(notes.strip()) > 3:
                    notes_count += 1
        
        if notes_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Coach notes present ({notes_count}/8 players have notes)")
        else:
            feedback_parts.append(f"❌ Only {notes_count}/8 players have notes (need 5+)")
        
        # Final verdict
        passed = (criteria_passed == total_criteria)
        score = 1.0 if passed else 0.0
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification result: {criteria_passed}/{total_criteria} criteria passed")
        
        return {
            "passed": passed,
            "score": score,
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
        cleanup_temp_dir(temp_dir)