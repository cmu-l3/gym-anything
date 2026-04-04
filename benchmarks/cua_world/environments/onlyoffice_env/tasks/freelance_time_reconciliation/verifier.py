#!/usr/bin/env python3
"""
Verifier for Freelance Time Reconciliation task
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


def verify_freelance_timesheet(traj, env_info, task_info):
    """
    Verify the freelance time tracking spreadsheet.

    Checks:
    1. File exists and can be opened
    2. Contains time entries (at least 12 rows of data)
    3. All three clients mentioned (TechStart, GreenLeaf, MarketPro)
    4. Numeric calculations present:
       - Total hours ≈ 47.5 (±2)
       - Total amount ≈ 3685 (±50)
       - TechStart total ≈ 1232.50 (±30)
       - GreenLeaf total ≈ 1312.50 (±30)
       - MarketPro total ≈ 1155 (±30)
    5. Contains formulas (not just hardcoded values)
    6. GreenLeaf identified as exceeding budget or total shown > 1200
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/freelance_timesheet_dec.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_freelance_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        criteria_passed = 0
        total_criteria = 10
        feedback_parts = []

        # Get the first sheet
        sheet_names = wb.sheetnames
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Workbook has no sheets"
            }

        sheet = wb[sheet_names[0]]

        # Get all data
        data = get_sheet_data(wb, sheet_names[0], max_rows=100, max_cols=15)

        # Convert all data to string for searching
        data_str_lower = ' '.join([
            ' '.join([str(cell).lower() if cell is not None else '' for cell in row])
            for row in data
        ])

        # Criterion 1: Check for sufficient data rows (non-empty rows)
        non_empty_rows = sum(1 for row in data if any(cell for cell in row if cell))
        if non_empty_rows >= 15:  # At least headers + 14 entries
            criteria_passed += 1
            feedback_parts.append(f"✅ Sufficient data rows ({non_empty_rows})")
        else:
            feedback_parts.append(f"❌ Too few data rows ({non_empty_rows}), expected 15+")

        # Criterion 2-4: Check for all three clients
        clients_found = []
        if 'techstart' in data_str_lower:
            clients_found.append('TechStart')
            criteria_passed += 1
        if 'greenleaf' in data_str_lower or 'green leaf' in data_str_lower:
            clients_found.append('GreenLeaf')
            criteria_passed += 1
        if 'marketpro' in data_str_lower or 'market pro' in data_str_lower:
            clients_found.append('MarketPro')
            criteria_passed += 1

        if len(clients_found) == 3:
            feedback_parts.append(f"✅ All three clients present: {', '.join(clients_found)}")
        else:
            missing = set(['TechStart', 'GreenLeaf', 'MarketPro']) - set(clients_found)
            feedback_parts.append(f"❌ Missing clients: {', '.join(missing)}")

        # Extract all numeric values from the spreadsheet
        numeric_values = []
        for row in data:
            for cell in row:
                if isinstance(cell, (int, float)) and cell > 0:
                    numeric_values.append(float(cell))

        # Criterion 5: Check for total hours (around 47.5)
        # Expected: 3.5 + 5 + 2.5 + 4 + 3 + 4 + 2.5 + 3.5 + 3 + 4 + 5 + 3 + 1.5 + 4 = 47.5
        hours_candidates = [v for v in numeric_values if 45 <= v <= 50]
        if hours_candidates:
            criteria_passed += 1
            feedback_parts.append(f"✅ Total hours found (~{hours_candidates[0]:.1f}, expected ~47.5)")
        else:
            feedback_parts.append("❌ Total hours calculation not found or incorrect")

        # Criterion 6: Check for total amount (around 3685)
        # TechStart: (3.5 + 2.5 + 4 + 3 + 1.5) * 85 = 14.5 * 85 = 1232.50
        # GreenLeaf: (5 + 3 + 2.5 + 4 + 3) * 75 = 17.5 * 75 = 1312.50
        # MarketPro: (4 + 3.5 + 5 + 4) * 70 = 16.5 * 70 = 1155
        # Total: 1232.50 + 1312.50 + 1155 = 3700
        amount_candidates = [v for v in numeric_values if 3600 <= v <= 3750]
        if amount_candidates:
            criteria_passed += 1
            feedback_parts.append(f"✅ Total amount found (~${amount_candidates[0]:.2f}, expected ~$3,685)")
        else:
            feedback_parts.append("❌ Total amount calculation not found or incorrect")

        # Criterion 7: Check for TechStart total (around 1232.50)
        techstart_candidates = [v for v in numeric_values if 1200 <= v <= 1280]
        if techstart_candidates:
            criteria_passed += 1
            feedback_parts.append(f"✅ TechStart total found (~${techstart_candidates[0]:.2f})")
        else:
            feedback_parts.append("⚠️ TechStart total not clearly identified")

        # Criterion 8: Check for GreenLeaf total (around 1312.50, exceeds $1200)
        greenleaf_candidates = [v for v in numeric_values if 1280 <= v <= 1350]
        if greenleaf_candidates:
            criteria_passed += 1
            feedback_parts.append(f"✅ GreenLeaf total found (~${greenleaf_candidates[0]:.2f}, exceeds $1,200 budget)")
        else:
            feedback_parts.append("⚠️ GreenLeaf total not clearly identified")

        # Criterion 9: Check for MarketPro total (around 1155)
        marketpro_candidates = [v for v in numeric_values if 1100 <= v <= 1200]
        if marketpro_candidates:
            criteria_passed += 1
            feedback_parts.append(f"✅ MarketPro total found (~${marketpro_candidates[0]:.2f})")
        else:
            feedback_parts.append("⚠️ MarketPro total not clearly identified")

        # Criterion 10: Check for presence of formulas (Amount should be calculated)
        has_formulas = False
        formula_count = 0
        for row_idx in range(1, min(50, sheet.max_row + 1)):
            for col_idx in range(1, min(15, sheet.max_column + 1)):
                try:
                    cell = sheet.cell(row=row_idx, column=col_idx)
                    if hasattr(cell, 'data_type') and cell.data_type == 'f':
                        has_formulas = True
                        formula_count += 1
                except:
                    pass

        if has_formulas and formula_count >= 3:  # At least a few formulas
            criteria_passed += 1
            feedback_parts.append(f"✅ Contains formulas ({formula_count} found)")
        else:
            feedback_parts.append("⚠️ Few or no formulas detected - amounts might be hardcoded")

        # Additional check: Look for budget-related keywords
        budget_keywords = ['budget', 'exceed', 'over', 'cap', '1200', '1,200']
        budget_mentioned = any(keyword in data_str_lower for keyword in budget_keywords)
        if budget_mentioned:
            feedback_parts.append("✅ Budget awareness indicated (GreenLeaf $1,200 cap noted)")

        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score / 100,  # Normalize to 0-1
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"❌ Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
