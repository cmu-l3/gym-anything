#!/usr/bin/env python3
"""
Verifier for Home Daycare Licensing Tracker task
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_home_daycare_licensing_tracker(traj, env_info, task_info):
    """
    Verify home daycare licensing compliance tracker task
    
    Checks:
    1. File exists and is valid XLSX
    2. At least 15 total requirements present (8 original + 7 new)
    3. All required columns present
    4. Status column contains only valid values
    5. Priority column contains only valid values
    6. Completion percentage formula exists and calculates correctly
    7. Requirements span all 5 required categories
    8. At least 4 requirements marked "Complete"
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/daycare_licensing_tracker.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_licensing_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to open spreadsheet: {error}"
            }

        # Get the active sheet
        sheet = wb.active

        # Get all data
        data = get_sheet_data(wb, sheet.title, max_rows=50, max_cols=10)

        if not data or len(data) < 2:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Spreadsheet is empty or has no data rows"
            }

        feedback_parts = []
        score = 0.0

        # Check 1: Headers present (10 points)
        headers = [str(cell).lower() if cell else "" for cell in data[0]]
        required_headers = ['requirement', 'category', 'status', 'priority']

        missing_headers = [h for h in required_headers if not any(h in header for header in headers)]

        if not missing_headers:
            score += 10
            feedback_parts.append("✅ All required column headers present")
        else:
            feedback_parts.append(f"❌ Missing headers: {', '.join(missing_headers)}")

        # Find column indices
        req_col = next((i for i, h in enumerate(headers) if 'requirement' in h), -1)
        cat_col = next((i for i, h in enumerate(headers) if 'category' in h), -1)
        status_col = next((i for i, h in enumerate(headers) if 'status' in h), -1)
        priority_col = next((i for i, h in enumerate(headers) if 'priority' in h), -1)
        completion_col = next((i for i, h in enumerate(headers) if 'completion' in h or '%' in h), -1)

        # Extract data rows (non-empty first column)
        data_rows = []
        for row in data[1:]:
            if row and len(row) > 0 and row[0] and str(row[0]).strip():
                data_rows.append(row)

        num_requirements = len(data_rows)

        # Check 2: At least 15 requirements (20 points)
        if num_requirements >= 15:
            score += 20
            feedback_parts.append(f"✅ Has {num_requirements} requirements (≥15 required)")
        elif num_requirements >= 12:
            score += 10
            feedback_parts.append(f"⚠️ Has {num_requirements} requirements (15 recommended, partial credit)")
        else:
            feedback_parts.append(f"❌ Only {num_requirements} requirements (need 15)")

        # Check 3: Valid status values (15 points)
        if status_col >= 0:
            valid_statuses = {'complete', 'in progress', 'not started', 'in-progress', 'notstarted', ''}
            statuses = []
            for row in data_rows:
                if len(row) > status_col and row[status_col]:
                    statuses.append(str(row[status_col]).lower().strip())
                else:
                    statuses.append("")
            
            invalid_statuses = [s for s in statuses if s and s not in valid_statuses]

            if not invalid_statuses:
                score += 15
                feedback_parts.append("✅ All status values valid (Complete/In Progress/Not Started)")
            else:
                feedback_parts.append(f"❌ Invalid status values found: {set(invalid_statuses)}")
        else:
            feedback_parts.append("❌ Status column not found")

        # Check 4: Valid priority values (10 points)
        if priority_col >= 0:
            valid_priorities = {'high', 'medium', 'low', ''}
            priorities = []
            for row in data_rows:
                if len(row) > priority_col and row[priority_col]:
                    priorities.append(str(row[priority_col]).lower().strip())
                else:
                    priorities.append("")

            invalid_priorities = [p for p in priorities if p and p not in valid_priorities]

            if not invalid_priorities:
                score += 10
                feedback_parts.append("✅ All priority values valid (High/Medium/Low)")
            else:
                feedback_parts.append(f"❌ Invalid priority values: {set(invalid_priorities)}")
        else:
            feedback_parts.append("❌ Priority column not found")

        # Check 5: Category diversity (15 points)
        if cat_col >= 0:
            categories = []
            for row in data_rows:
                if len(row) > cat_col and row[cat_col]:
                    categories.append(str(row[cat_col]).lower().strip())
                else:
                    categories.append("")

            required_categories = {'safety', 'training', 'legal', 'facility', 'operations'}
            found_categories = set()

            for cat in categories:
                for req_cat in required_categories:
                    if req_cat in cat:
                        found_categories.add(req_cat)

            if len(found_categories) >= 5:
                score += 15
                feedback_parts.append(f"✅ Requirements span all 5 categories: {', '.join(sorted(found_categories))}")
            elif len(found_categories) >= 3:
                score += 8
                feedback_parts.append(f"⚠️ Requirements span {len(found_categories)} categories (need 5)")
            else:
                feedback_parts.append(f"❌ Only {len(found_categories)} categories represented")
        else:
            feedback_parts.append("❌ Category column not found")

        # Check 6: Completion percentage formula (20 points)
        if completion_col >= 0 and status_col >= 0:
            # Look for percentage in completion column (any row, typically in header area or summary)
            completion_values = []
            
            # Check all rows including potential summary rows
            for row_idx, row in enumerate(data, start=1):
                if len(row) > completion_col and row[completion_col] is not None:
                    val = row[completion_col]
                    # Check if it's a percentage or formula result
                    if isinstance(val, (int, float)) and val >= 0:
                        completion_values.append((row_idx, val))
            
            if completion_values:
                # Calculate expected completion percentage
                complete_count = 0
                for row in data_rows:
                    if len(row) > status_col and row[status_col]:
                        status_val = str(row[status_col]).lower().strip()
                        if 'complete' in status_val:
                            complete_count += 1
                
                expected_pct = (complete_count / num_requirements * 100) if num_requirements > 0 else 0

                # Check if any calculated value is close to expected
                found_match = False
                for row_idx, actual_pct in completion_values:
                    # Handle both percentage (0-100) and decimal (0-1) formats
                    if actual_pct <= 1:
                        actual_pct = actual_pct * 100
                    
                    if abs(actual_pct - expected_pct) < 5:  # Within 5% tolerance
                        score += 20
                        feedback_parts.append(f"✅ Completion percentage calculated correctly (~{actual_pct:.0f}%)")
                        found_match = True
                        break
                
                if not found_match:
                    # Give partial credit for having a percentage
                    score += 10
                    actual_pct = completion_values[0][1]
                    if actual_pct <= 1:
                        actual_pct = actual_pct * 100
                    feedback_parts.append(f"⚠️ Completion percentage present ({actual_pct:.0f}%) but may be inaccurate (expected ~{expected_pct:.0f}%)")
            else:
                feedback_parts.append("❌ No completion percentage formula found")
        else:
            if completion_col < 0:
                feedback_parts.append("❌ Completion percentage column missing")

        # Check 7: At least 4 items marked complete (10 points)
        if status_col >= 0:
            complete_count = 0
            for row in data_rows:
                if len(row) > status_col and row[status_col]:
                    status_val = str(row[status_col]).lower().strip()
                    if 'complete' in status_val:
                        complete_count += 1

            if complete_count >= 4:
                score += 10
                feedback_parts.append(f"✅ {complete_count} requirements marked Complete")
            elif complete_count >= 2:
                score += 5
                feedback_parts.append(f"⚠️ Only {complete_count} requirements marked Complete (need ≥4)")
            else:
                feedback_parts.append(f"❌ Only {complete_count} requirements marked Complete (need ≥4)")

        # Determine pass/fail
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score / 100.0,
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