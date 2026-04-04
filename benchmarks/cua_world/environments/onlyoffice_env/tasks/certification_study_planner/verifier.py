#!/usr/bin/env python3
"""
Verifier for Certification Study Planner task

Checks for:
1. Header structure with title, exam date, and countdown
2. Table headers correctly labeled
3. At least 6 weeks of study data
4. Total study hours >= 40
5. Total practice questions >= 800
6. At least 3 formulas present
7. Summary section with calculations
"""

import sys
import os
import logging
import tempfile
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_study_planner(traj, env_info, task_info):
    """
    Verify that certification study planner was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/study_schedule.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_study_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Get the first sheet
        sheet_names = wb.sheetnames
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet = wb[sheet_name]

        criteria_passed = 0
        feedback_parts = []

        # Get data from sheet (first 25 rows, 10 columns)
        data = get_sheet_data(wb, sheet_name, max_rows=25, max_cols=10)

        # ============================================================
        # Criterion 1: Check header structure (title, exam date, countdown in first 4 rows)
        # ============================================================
        has_title = False
        has_date_reference = False
        has_countdown = False

        for i in range(min(4, len(data))):
            row = data[i]
            if not row:
                continue
            for cell in row:
                if cell and isinstance(cell, str):
                    cell_lower = cell.lower()
                    if any(keyword in cell_lower for keyword in ['study', 'schedule', 'certification', 'exam', 'plan']):
                        has_title = True
                    if any(keyword in cell_lower for keyword in ['exam date', 'test date', 'date:']):
                        has_date_reference = True
                    if any(keyword in cell_lower for keyword in ['days remaining', 'countdown', 'days left', 'remaining']):
                        has_countdown = True
                # Check if cell contains a date
                if isinstance(cell, datetime):
                    has_date_reference = True

        if has_title and (has_date_reference or has_countdown):
            criteria_passed += 1
            feedback_parts.append("✅ Header structure present with title and date information")
        else:
            feedback_parts.append(f"❌ Header incomplete (title:{has_title}, date:{has_date_reference}, countdown:{has_countdown})")

        # ============================================================
        # Criterion 2: Check table headers
        # ============================================================
        header_row_idx = -1
        header_keywords = [
            ['week'],
            ['knowledge', 'area', 'topic', 'subject'],
            ['hours', 'study'],
            ['questions', 'practice'],
            ['completed', 'done', 'status'],
            ['priority', 'importance']
        ]

        for i in range(min(10, len(data))):
            row = data[i]
            if not row:
                continue
            
            # Check if this row has multiple headers
            matches = 0
            for cell in row:
                if cell and isinstance(cell, str):
                    cell_lower = cell.lower().strip()
                    for keywords in header_keywords:
                        if any(kw in cell_lower for kw in keywords):
                            matches += 1
                            break
            
            if matches >= 4:  # At least 4 matching headers
                header_row_idx = i
                criteria_passed += 1
                feedback_parts.append(f"✅ Table headers found with {matches}/6 required columns")
                break
        
        if header_row_idx == -1:
            feedback_parts.append("❌ Table headers not found or incomplete")

        # ============================================================
        # Criterion 3: Check data completeness (at least 6 weeks of study data)
        # ============================================================
        data_row_start = header_row_idx + 1 if header_row_idx != -1 else 5
        data_rows_count = 0
        hour_cells = []
        question_cells = []

        if header_row_idx != -1:
            for i in range(data_row_start, min(data_row_start + 15, len(data))):
                if i >= len(data):
                    break
                row = data[i]
                if not row:
                    continue
                
                # Check if row has meaningful content
                non_empty_cells = sum(1 for cell in row[:6] if cell not in [None, ''])
                if non_empty_cells >= 3:
                    # Check if it's not a summary row
                    first_cell = str(row[0]).lower() if row[0] else ''
                    if not any(keyword in first_cell for keyword in ['total', 'summary', 'average', 'completed', 'percentage']):
                        data_rows_count += 1
                        # Collect numeric data for hours and questions
                        for j, cell in enumerate(row):
                            if isinstance(cell, (int, float)) and cell > 0:
                                if 5 <= cell <= 30:  # Likely study hours (reasonable range)
                                    hour_cells.append(cell)
                                elif cell >= 50:  # Likely practice questions
                                    question_cells.append(cell)

        if data_rows_count >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Data completeness: {data_rows_count} weeks of study data")
        else:
            feedback_parts.append(f"❌ Insufficient data: only {data_rows_count} weeks (expected >= 6)")

        # ============================================================
        # Criterion 4: Check total study hours >= 40
        # ============================================================
        total_hours = sum(hour_cells) if hour_cells else 0
        if total_hours >= 40:
            criteria_passed += 1
            feedback_parts.append(f"✅ Total study hours valid: {total_hours} hours")
        else:
            feedback_parts.append(f"❌ Insufficient study hours: {total_hours} (expected >= 40)")

        # ============================================================
        # Criterion 5: Check total practice questions >= 800
        # ============================================================
        total_questions = sum(question_cells) if question_cells else 0
        if total_questions >= 800:
            criteria_passed += 1
            feedback_parts.append(f"✅ Total practice questions valid: {total_questions} questions")
        else:
            feedback_parts.append(f"❌ Insufficient practice questions: {total_questions} (expected >= 800)")

        # ============================================================
        # Criterion 6: Check for formulas (at least 3)
        # ============================================================
        formula_count = 0
        has_sum = False
        has_date_formula = False

        for row in sheet.iter_rows(max_row=25, max_col=10):
            for cell in row:
                if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                    formula_count += 1
                    formula_upper = cell.value.upper()
                    if 'SUM' in formula_upper:
                        has_sum = True
                    if 'TODAY' in formula_upper:
                        has_date_formula = True

        if formula_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas present: {formula_count} formulas found")
        else:
            feedback_parts.append(f"❌ Insufficient formulas: {formula_count} (expected >= 3)")

        # ============================================================
        # Criterion 7: Check for summary section (at least 3 summary items)
        # ============================================================
        summary_rows = 0
        for i in range(len(data)):
            row = data[i]
            if not row:
                continue
            
            for cell in row:
                if cell and isinstance(cell, str):
                    cell_lower = cell.lower()
                    if any(keyword in cell_lower for keyword in ['total', 'summary', 'average', 'completed', 'percentage', 'weeks completed']):
                        summary_rows += 1
                        break

        if summary_rows >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Summary section present with {summary_rows} summary items")
        else:
            feedback_parts.append(f"❌ Summary section incomplete: {summary_rows} items (expected >= 3)")

        # ============================================================
        # Calculate final score and pass/fail
        # ============================================================
        score = int((criteria_passed / 7) * 100)
        passed = criteria_passed >= 5  # Need at least 5/7 criteria (71%)

        feedback = " | ".join(feedback_parts)

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