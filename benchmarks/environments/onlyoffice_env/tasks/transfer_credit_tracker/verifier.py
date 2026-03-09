#!/usr/bin/env python3
"""
Verifier for transfer_credit_tracker@1 task

Verifies that the agent correctly created a college transfer credit 
analysis spreadsheet with proper data entry, calculations, and GPA computations.
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


def verify_transfer_credit_tracker(traj, env_info, task_info):
    """
    Verify the transfer credit analysis spreadsheet.
    
    Scoring breakdown (100 points total):
    - File exists and sheet correct: 10 points
    - Course data entry (8 courses): 10 points  
    - Original credits accurate: 10 points
    - Transfer status correct: 20 points
    - Grade points calculated: 15 points
    - Quality points calculated: 15 points
    - Major courses identified: 10 points
    - Summary calculations: 10 points
    
    Pass threshold: 80 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/transfer_analysis.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_transfer_')

    # Expected course data
    expected_courses = {
        "BIOL151": {
            "name": "Cell Biology",
            "orig_credits": 4,
            "grade": "A",
            "transfers": True,
            "transfer_credits": 4,
            "grade_points": 4.0,
            "major": True
        },
        "CHEM110": {
            "name": "General Chemistry",
            "orig_credits": 4,
            "grade": "B+",
            "transfers": True,
            "transfer_credits": 4,
            "grade_points": 3.3,
            "major": True
        },
        "MATH210": {
            "name": "Calculus",
            "orig_credits": 4,
            "grade": "A-",
            "transfers": True,
            "transfer_credits": 4,
            "grade_points": 3.7,
            "major": False
        },
        "ENGL101": {
            "name": "Composition",
            "orig_credits": 3,
            "grade": "B",
            "transfers": True,
            "transfer_credits": 3,
            "grade_points": 3.0,
            "major": False
        },
        "BIOL152": {
            "name": "Genetics",
            "orig_credits": 2,
            "grade": "A",
            "transfers": True,
            "transfer_credits": 2,
            "grade_points": 4.0,
            "major": True
        },
        "PHYS105": {
            "name": "Physics",
            "orig_credits": 4,
            "grade": "C+",
            "transfers": True,
            "transfer_credits": 3,  # REDUCED!
            "grade_points": 2.3,
            "major": False
        },
        "ARTS120": {
            "name": "Drawing",
            "orig_credits": 3,
            "grade": "P",
            "transfers": False,  # Does NOT transfer!
            "transfer_credits": 0,
            "grade_points": None,  # P/F - no grade points
            "major": False
        },
        "COMM115": {
            "name": "Speaking",
            "orig_credits": 3,
            "grade": "B-",
            "transfers": True,
            "transfer_credits": 3,
            "grade_points": 2.7,
            "major": False
        }
    }

    try:
        # Parse the spreadsheet
        success, wb, error = copy_and_parse_document(
            container_path,
            copy_from_env,
            file_format='xlsx'
        )

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Could not load spreadsheet: {error}"
            }

        # Check sheet exists
        if "Transfer_Analysis" not in wb.sheetnames:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Sheet 'Transfer_Analysis' not found"
            }

        ws = wb["Transfer_Analysis"]
        
        points = 0
        max_points = 100
        feedback_parts = []

        # Award points for file existence and correct sheet
        points += 10
        feedback_parts.append("✅ File and sheet exist (10pts)")

        # Get all data from the sheet
        sheet_data = get_sheet_data(ws, max_rows=20, max_cols=9)

        # Build a map of courses found in the spreadsheet
        courses_in_sheet = {}
        for row_idx in range(1, min(10, len(sheet_data))):  # Check rows 2-9 (index 1-8)
            if row_idx >= len(sheet_data):
                break
            row = sheet_data[row_idx]
            if row and len(row) > 0:
                course_code = row[0]  # Column A
                if course_code and isinstance(course_code, str):
                    course_code = course_code.strip().upper()
                    # Check if it matches any expected course code
                    for expected_code in expected_courses.keys():
                        if expected_code in course_code or course_code in expected_code:
                            courses_in_sheet[expected_code] = {
                                'row_idx': row_idx,
                                'row_data': row
                            }
                            break

        # Criterion 1: Check that all 8 courses are present
        courses_found = len(courses_in_sheet)
        if courses_found == 8:
            points += 10
            feedback_parts.append(f"✅ All 8 courses entered (10pts)")
        elif courses_found >= 6:
            points += 5
            feedback_parts.append(f"⚠️ Only {courses_found}/8 courses found (5pts)")
        else:
            feedback_parts.append(f"❌ Only {courses_found}/8 courses found (0pts)")

        # Criterion 2: Check original credits accuracy
        credits_correct = 0
        for course_code, sheet_info in courses_in_sheet.items():
            row_data = sheet_info['row_data']
            expected = expected_courses[course_code]
            
            # Column C (index 2) should have original credits
            if len(row_data) > 2:
                orig_credits = row_data[2]
                if orig_credits == expected["orig_credits"]:
                    credits_correct += 1

        if credits_correct >= 7:
            points += 10
            feedback_parts.append(f"✅ Original credits accurate ({credits_correct}/8) (10pts)")
        elif credits_correct >= 5:
            points += 5
            feedback_parts.append(f"⚠️ Original credits partially correct ({credits_correct}/8) (5pts)")
        else:
            feedback_parts.append(f"❌ Original credits mostly incorrect ({credits_correct}/8) (0pts)")

        # Criterion 3: Check transfer status (ARTS120 must be "No", others "Yes")
        transfer_status_points = 0
        arts120_correct = False
        phys105_credits_correct = False

        for course_code, sheet_info in courses_in_sheet.items():
            row_data = sheet_info['row_data']
            expected = expected_courses[course_code]
            
            # Column E (index 4) - Transfers?
            # Column F (index 5) - Transfer Credits
            transfers_text = str(row_data[4]).lower() if len(row_data) > 4 else ""
            transfer_credits = row_data[5] if len(row_data) > 5 else None

            if course_code == "ARTS120":
                # Should have "No" or be marked as not transferring
                if "no" in transfers_text or transfers_text == "false" or transfers_text == "0":
                    transfer_status_points += 3
                    arts120_correct = True
                # Transfer credits should be 0 or blank
                if transfer_credits == 0 or transfer_credits is None or transfer_credits == "":
                    transfer_status_points += 2
            elif course_code == "PHYS105":
                # Should transfer but with reduced credits (3 instead of 4)
                if "yes" in transfers_text or transfers_text == "true" or transfers_text == "1":
                    transfer_status_points += 2
                if transfer_credits == 3:
                    transfer_status_points += 3
                    phys105_credits_correct = True
            else:
                # All other courses should transfer
                if "yes" in transfers_text or transfers_text == "true" or transfers_text == "1":
                    transfer_status_points += 1
                # Transfer credits should match original (except PHYS105)
                if transfer_credits == expected["transfer_credits"]:
                    transfer_status_points += 0.5

        # Award up to 20 points for transfer status
        if transfer_status_points >= 18:
            points += 20
            feedback_parts.append("✅ Transfer status accurate (20pts)")
        elif transfer_status_points >= 12:
            points += 12
            feedback_parts.append(f"⚠️ Transfer status partially correct (12pts)")
        elif transfer_status_points >= 6:
            points += 6
            feedback_parts.append(f"⚠️ Transfer status needs work (6pts)")
        else:
            feedback_parts.append(f"❌ Transfer status mostly incorrect (0pts)")

        # Criterion 4: Check grade points calculation
        grade_points_correct = 0
        for course_code, sheet_info in courses_in_sheet.items():
            row_data = sheet_info['row_data']
            expected = expected_courses[course_code]
            
            # Column G (index 6) - Grade Points
            if len(row_data) > 6:
                grade_points = row_data[6]
                
                if expected["grade_points"] is None:
                    # P/F course - should be blank or 0
                    if grade_points is None or grade_points == 0 or grade_points == "":
                        grade_points_correct += 1
                else:
                    # Should match expected grade points
                    if isinstance(grade_points, (int, float)):
                        if abs(float(grade_points) - expected["grade_points"]) < 0.2:
                            grade_points_correct += 1

        if grade_points_correct >= 7:
            points += 15
            feedback_parts.append(f"✅ Grade points calculated correctly ({grade_points_correct}/8) (15pts)")
        elif grade_points_correct >= 5:
            points += 10
            feedback_parts.append(f"⚠️ Grade points partially correct ({grade_points_correct}/8) (10pts)")
        elif grade_points_correct >= 3:
            points += 5
            feedback_parts.append(f"⚠️ Grade points need work ({grade_points_correct}/8) (5pts)")
        else:
            feedback_parts.append(f"❌ Grade points mostly incorrect ({grade_points_correct}/8) (0pts)")

        # Criterion 5: Check quality points calculation (Transfer Credits × Grade Points)
        quality_points_correct = 0
        for course_code, sheet_info in courses_in_sheet.items():
            row_data = sheet_info['row_data']
            expected = expected_courses[course_code]
            
            # Column H (index 7) - Quality Points
            if len(row_data) > 7:
                quality_points = row_data[7]
                
                # Only graded courses that transfer should have quality points
                if expected["grade_points"] is not None and expected["transfers"]:
                    expected_qp = expected["transfer_credits"] * expected["grade_points"]
                    if isinstance(quality_points, (int, float)):
                        if abs(float(quality_points) - expected_qp) < 0.5:
                            quality_points_correct += 1
                else:
                    # Should be blank or 0 for non-transferring or P/F courses
                    if quality_points is None or quality_points == 0 or quality_points == "":
                        quality_points_correct += 0.5

        if quality_points_correct >= 6.5:
            points += 15
            feedback_parts.append(f"✅ Quality points calculated correctly (15pts)")
        elif quality_points_correct >= 4:
            points += 10
            feedback_parts.append(f"⚠️ Quality points partially correct (10pts)")
        elif quality_points_correct >= 2:
            points += 5
            feedback_parts.append(f"⚠️ Quality points need work (5pts)")
        else:
            feedback_parts.append(f"❌ Quality points mostly incorrect (0pts)")

        # Criterion 6: Check major course identification
        major_correct = 0
        for course_code, sheet_info in courses_in_sheet.items():
            row_data = sheet_info['row_data']
            expected = expected_courses[course_code]
            
            # Column I (index 8) - Major Course?
            if len(row_data) > 8:
                major_text = str(row_data[8]).lower() if row_data[8] else ""
                
                if expected["major"]:
                    # Should be marked as "Yes"
                    if "yes" in major_text or major_text == "true" or major_text == "1":
                        major_correct += 1
                else:
                    # Should be marked as "No"
                    if "no" in major_text or major_text == "false" or major_text == "0" or major_text == "":
                        major_correct += 1

        if major_correct >= 7:
            points += 10
            feedback_parts.append(f"✅ Major courses identified correctly ({major_correct}/8) (10pts)")
        elif major_correct >= 5:
            points += 5
            feedback_parts.append(f"⚠️ Major courses partially identified ({major_correct}/8) (5pts)")
        else:
            feedback_parts.append(f"❌ Major course identification incorrect ({major_correct}/8) (0pts)")

        # Criterion 7: Check summary calculations
        # Scan rows 10-20 for numeric values that match expected totals
        expected_total_orig = 27
        expected_total_transfer = 24
        expected_overall_gpa = 3.48
        expected_major_gpa = 3.70

        found_values = {
            'total_orig': False,
            'total_transfer': False,
            'overall_gpa': False,
            'major_gpa': False
        }

        for row_idx in range(10, min(20, len(sheet_data))):
            if row_idx >= len(sheet_data):
                break
            row = sheet_data[row_idx]
            for cell_value in row:
                if isinstance(cell_value, (int, float)):
                    val = float(cell_value)
                    # Check if it matches any expected value
                    if abs(val - expected_total_orig) < 0.5 and not found_values['total_orig']:
                        found_values['total_orig'] = True
                    elif abs(val - expected_total_transfer) < 0.5 and not found_values['total_transfer']:
                        found_values['total_transfer'] = True
                    elif abs(val - expected_overall_gpa) < 0.15 and not found_values['overall_gpa']:
                        found_values['overall_gpa'] = True
                    elif abs(val - expected_major_gpa) < 0.15 and not found_values['major_gpa']:
                        found_values['major_gpa'] = True

        summary_score = sum(found_values.values())
        
        if summary_score >= 3:
            points += 10
            feedback_parts.append(f"✅ Summary calculations present ({summary_score}/4 found) (10pts)")
        elif summary_score >= 2:
            points += 6
            feedback_parts.append(f"⚠️ Some summary calculations found ({summary_score}/4) (6pts)")
        elif summary_score >= 1:
            points += 3
            feedback_parts.append(f"⚠️ Few summary calculations found ({summary_score}/4) (3pts)")
        else:
            feedback_parts.append(f"❌ Summary calculations missing or incorrect (0pts)")

        # Special mentions for critical requirements
        if arts120_correct:
            feedback_parts.append("🎯 ARTS120 correctly marked as non-transferring")
        else:
            feedback_parts.append("⚠️ ARTS120 transfer status incorrect")

        if phys105_credits_correct:
            feedback_parts.append("🎯 PHYS105 credit reduction handled correctly")
        else:
            feedback_parts.append("⚠️ PHYS105 credit reduction not handled")

        # Calculate final score
        score = points / max_points
        passed = points >= 80

        feedback = " | ".join(feedback_parts) + f" | TOTAL: {points}/{max_points} pts"

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
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)