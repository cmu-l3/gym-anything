#!/usr/bin/env python3
"""
Verifier for Therapist Search Comparison task
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
    count_filled_cells,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_therapist_comparison(traj, env_info, task_info):
    """
    Verify that therapist comparison spreadsheet was created correctly.

    Checks:
    1. File exists and has at least 5 therapists with data
    2. Session costs are filled in (no blanks in cost column)
    3. Monthly cost formula exists and calculates correctly (Cost × 4)
    4. Priority score or ranking column exists with varied values
    5. Summary statistics present (averages for in-network and out-of-network)
    6. Organization: Status/decision column present and data appears sorted
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/therapist_comparison.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_therapist_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        criteria_passed = 0
        feedback_parts = []

        sheet_name = "Therapist Search"
        
        # Get all data to analyze
        sheet_data = get_sheet_data(wb, sheet_name, max_rows=30, max_cols=15)
        
        if len(sheet_data) < 6:  # Header + 5 therapists minimum
            return {"passed": False, "score": 0, 
                    "feedback": "Spreadsheet has insufficient data rows"}

        # Criterion 1: Verify at least 5 therapists with names
        therapist_count = 0
        for row_idx in range(1, min(8, len(sheet_data))):  # Rows 2-7 (index 1-6)
            if sheet_data[row_idx] and sheet_data[row_idx][0]:  # Column A (index 0)
                therapist_name = str(sheet_data[row_idx][0]).strip()
                if therapist_name and len(therapist_name) > 3:
                    therapist_count += 1
        
        if therapist_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Found {therapist_count} therapists with data")
        else:
            feedback_parts.append(f"❌ Only {therapist_count} therapists found (expected 5+)")

        # Criterion 2: Check if Session Cost column (D) is filled
        costs_filled = 0
        session_costs = []
        for row_idx in range(1, min(7, len(sheet_data))):  # Rows 2-6
            cost_value = sheet_data[row_idx][3] if len(sheet_data[row_idx]) > 3 else None  # Column D
            if cost_value is not None and isinstance(cost_value, (int, float)) and cost_value > 0:
                costs_filled += 1
                session_costs.append((row_idx, cost_value))
        
        if costs_filled >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Session costs filled ({costs_filled}/5 therapists)")
        else:
            feedback_parts.append(f"❌ Session costs incomplete ({costs_filled}/5 filled)")

        # Criterion 3: Check for Monthly Cost formula (should be around Session Cost × 4)
        # Look for a column that has values ~4x the session cost
        monthly_cost_col = None
        formula_correct_count = 0
        
        # Check columns E through K for monthly cost calculations
        for col_idx in range(4, min(12, len(sheet_data[0]) if sheet_data else 12)):
            correct_count = 0
            for row_idx, session_cost in session_costs[:3]:  # Check first 3 rows with costs
                if len(sheet_data[row_idx]) > col_idx:
                    cell_value = sheet_data[row_idx][col_idx]
                    if cell_value is not None and isinstance(cell_value, (int, float)):
                        expected_monthly = session_cost * 4
                        if abs(cell_value - expected_monthly) <= 5:  # Tolerance of $5
                            correct_count += 1
            
            if correct_count >= 2:  # At least 2 out of 3 match
                monthly_cost_col = col_idx
                formula_correct_count = correct_count
                break
        
        if monthly_cost_col is not None:
            criteria_passed += 1
            feedback_parts.append(f"✅ Monthly cost formula found and correct ({formula_correct_count} verified)")
        else:
            feedback_parts.append("❌ Monthly cost formula not found or incorrect")

        # Criterion 4: Check for Priority Score column with varied values
        priority_col = None
        priority_scores = []
        
        # Look for a column with numeric scores that vary
        for col_idx in range(4, min(12, len(sheet_data[0]) if sheet_data else 12)):
            scores = []
            for row_idx in range(1, min(7, len(sheet_data))):
                if len(sheet_data[row_idx]) > col_idx:
                    cell_value = sheet_data[row_idx][col_idx]
                    if cell_value is not None and isinstance(cell_value, (int, float)):
                        scores.append(cell_value)
            
            # Check if this looks like priority scores (3-12 range typically, and varied)
            if len(scores) >= 4:
                if min(scores) != max(scores) and 2 <= min(scores) <= 15 and 5 <= max(scores) <= 15:
                    priority_col = col_idx
                    priority_scores = scores
                    break
        
        if priority_col is not None and len(set(priority_scores)) >= 3:  # At least 3 different scores
            criteria_passed += 1
            feedback_parts.append(f"✅ Priority scoring system found (scores vary: {min(priority_scores)}-{max(priority_scores)})")
        else:
            feedback_parts.append("❌ Priority score column not found or lacks variation")

        # Criterion 5: Check for summary statistics (averages)
        # Look in rows 8-15 for summary calculations
        summary_found = False
        avg_in_network = None
        avg_out_network = None
        
        for row_idx in range(7, min(20, len(sheet_data))):
            for col_idx in range(0, min(6, len(sheet_data[row_idx]))):
                cell_value = sheet_data[row_idx][col_idx]
                if cell_value and isinstance(cell_value, str):
                    cell_lower = cell_value.lower()
                    # Look for average calculations
                    if 'average' in cell_lower or 'avg' in cell_lower:
                        # Check adjacent cells for numeric values
                        for check_col in range(col_idx, min(col_idx + 4, len(sheet_data[row_idx]))):
                            check_val = sheet_data[row_idx][check_col]
                            if check_val and isinstance(check_val, (int, float)) and 20 <= check_val <= 250:
                                if 'in-network' in cell_lower or 'in network' in cell_lower:
                                    avg_in_network = check_val
                                elif 'out' in cell_lower:
                                    avg_out_network = check_val
                                summary_found = True
        
        # Also check if there are any numeric summaries below the data
        if not summary_found:
            for row_idx in range(7, min(15, len(sheet_data))):
                numeric_in_row = [v for v in sheet_data[row_idx] if isinstance(v, (int, float)) and 20 <= v <= 250]
                if len(numeric_in_row) >= 2:
                    summary_found = True
                    break
        
        if summary_found or (avg_in_network is not None or avg_out_network is not None):
            criteria_passed += 1
            feedback_parts.append("✅ Summary statistics present (averages calculated)")
        else:
            feedback_parts.append("❌ Summary statistics missing (no averages found)")

        # Criterion 6: Check for organization - Status column and sorting evidence
        status_col = None
        status_values = []
        
        # Look for a column with text values like "Top Choice", "Backup", etc.
        for col_idx in range(4, min(13, len(sheet_data[0]) if sheet_data else 13)):
            statuses = []
            for row_idx in range(1, min(7, len(sheet_data))):
                if len(sheet_data[row_idx]) > col_idx:
                    cell_value = sheet_data[row_idx][col_idx]
                    if cell_value and isinstance(cell_value, str):
                        cell_lower = cell_value.lower()
                        if any(keyword in cell_lower for keyword in ['top', 'choice', 'backup', 'waiting', 'ruled', 'priority', 'consider']):
                            statuses.append(cell_value)
            
            if len(statuses) >= 3:
                status_col = col_idx
                status_values = statuses
                break
        
        # Check if data appears sorted (priority scores descending or organized)
        appears_sorted = False
        if priority_scores and len(priority_scores) >= 4:
            # Check if mostly descending (allowing one out-of-order)
            descending_count = sum(1 for i in range(len(priority_scores)-1) 
                                  if priority_scores[i] >= priority_scores[i+1])
            if descending_count >= len(priority_scores) - 2:
                appears_sorted = True
        
        if status_col is not None or appears_sorted:
            criteria_passed += 1
            if status_col is not None and appears_sorted:
                feedback_parts.append("✅ Well organized: Status column present and data sorted")
            elif status_col is not None:
                feedback_parts.append("✅ Status/decision column present")
            else:
                feedback_parts.append("✅ Data appears sorted by priority")
        else:
            feedback_parts.append("❌ Missing organization: No status column or sorting detected")

        # Calculate final score
        score = int((criteria_passed / 6) * 100)
        passed = score >= 70  # Pass threshold is 70% (4/6 criteria)

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