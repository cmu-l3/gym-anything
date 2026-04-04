#!/usr/bin/env python3
"""
Verifier for Visa Document Timeline task

This verifies that the agent created a comprehensive visa document tracking spreadsheet
from messy text instructions, including proper organization, cost extraction, and
identification of time-sensitive items.
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    get_cell_value,
    count_filled_cells,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_visa_document_timeline(traj, env_info, task_info):
    """
    Verify the visa tracking spreadsheet has been properly created.

    Scoring breakdown (100 points total):
    - 20 pts: Proper column structure (at least 4 of 6 key columns)
    - 20 pts: Sufficient documents listed (12+ items)
    - 15 pts: Costs accurately extracted (5+ different costs)
    - 20 pts: Total cost formula exists (~£1600-2100)
    - 15 pts: Time-sensitive items identified (police cert, translations, TB test)
    - 10 pts: Overall organization quality
    
    Pass threshold: 65/100 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Copy function not available"
        }

    filepath = "/home/ga/Documents/Spreadsheets/visa_tracker.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_visa_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(filepath, copy_from_env, 'xlsx')
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Could not open spreadsheet: {error}"
            }

        # Get first sheet
        sheet_name = wb.sheetnames[0]
        data = get_sheet_data(wb, sheet_name, max_rows=60, max_cols=20)

        if not data or len(data) < 3:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Spreadsheet appears empty or has insufficient data (less than 3 rows)"
            }

        score = 0.0
        feedback_parts = []

        # === CHECK 1: Header row with relevant columns (20 points) ===
        # Find the most likely header row (first row with multiple non-empty cells)
        header_row_idx = None
        for i, row in enumerate(data[:10]):  # Check first 10 rows
            non_empty = sum(1 for cell in row if cell and str(cell).strip())
            if non_empty >= 3:
                header_row_idx = i
                break
        
        if header_row_idx is None:
            feedback_parts.append("❌ No clear header row found")
            header_row = []
        else:
            header_row = [str(cell).lower().strip() if cell else "" for cell in data[header_row_idx]]

        required_concepts = [
            ("document", ["document", "item", "requirement", "name", "description"]),
            ("status", ["status", "have", "complete", "progress", "done"]),
            ("cost", ["cost", "price", "£", "fee", "expense", "gbp", "pound"]),
            ("time", ["time", "weeks", "days", "duration", "lead", "obtain", "processing"]),
            ("deadline", ["deadline", "due", "by when", "date", "when"]),
            ("priority", ["priority", "critical", "urgent", "order", "dependencies", "depend", "important"])
        ]

        columns_found = 0
        found_concepts = []
        for concept_name, keywords in required_concepts:
            if any(any(keyword in col for keyword in keywords) for col in header_row):
                columns_found += 1
                found_concepts.append(concept_name)

        if columns_found >= 4:
            score += 20
            feedback_parts.append(f"✅ Good column structure ({columns_found}/6 key columns: {', '.join(found_concepts)})")
        elif columns_found >= 3:
            score += 12
            feedback_parts.append(f"⚠️  Partial column structure ({columns_found}/6 key columns found)")
        else:
            feedback_parts.append(f"❌ Insufficient column structure (only {columns_found}/6 key columns)")

        # === CHECK 2: Sufficient document entries (20 points) ===
        # Count non-empty rows after header (rows with at least 2 filled cells)
        start_row = (header_row_idx + 1) if header_row_idx is not None else 1
        filled_rows = 0
        
        for row in data[start_row:]:
            non_empty = sum(1 for cell in row if cell and str(cell).strip() and str(cell).strip() not in ["", "0"])
            if non_empty >= 2:  # Row has at least 2 filled cells
                filled_rows += 1

        if filled_rows >= 12:
            score += 20
            feedback_parts.append(f"✅ Comprehensive document list ({filled_rows} items tracked)")
        elif filled_rows >= 8:
            score += 12
            feedback_parts.append(f"⚠️  Partial document list ({filled_rows} items, expected 12+)")
        elif filled_rows >= 5:
            score += 6
            feedback_parts.append(f"⚠️  Minimal document list ({filled_rows} items, expected 12+)")
        else:
            feedback_parts.append(f"❌ Insufficient documents tracked ({filled_rows} items, expected 12+)")

        # === CHECK 3: Costs extracted (15 points) ===
        # Look for key costs from the text: 8, 85, 50, 40, 35, 15, 1410, 470
        expected_costs = [8, 85, 50, 40, 35, 15, 1410, 470, 1643]
        costs_found = []

        # Convert all data to string and search for numbers
        for row in data:
            for cell in row:
                if cell is not None:
                    cell_str = str(cell).replace('£', '').replace(',', '').replace('GBP', '').strip()
                    try:
                        # Try to extract number
                        val = float(cell_str)
                        # Check if it matches any expected cost (with small tolerance)
                        for expected in expected_costs:
                            if abs(val - expected) <= 1:
                                costs_found.append(expected)
                                break
                    except:
                        # Try to find numbers in text
                        numbers = re.findall(r'\d+', cell_str)
                        for num_str in numbers:
                            try:
                                val = float(num_str)
                                for expected in expected_costs:
                                    if abs(val - expected) <= 1:
                                        costs_found.append(expected)
                                        break
                            except:
                                pass

        unique_costs = len(set(costs_found))
        
        if unique_costs >= 5:
            score += 15
            feedback_parts.append(f"✅ Costs accurately extracted ({unique_costs} different costs found)")
        elif unique_costs >= 3:
            score += 9
            feedback_parts.append(f"⚠️  Some costs extracted ({unique_costs} costs found, expected 5+)")
        elif unique_costs >= 1:
            score += 4
            feedback_parts.append(f"⚠️  Few costs extracted ({unique_costs} costs found, expected 5+)")
        else:
            feedback_parts.append(f"❌ No valid costs extracted")

        # === CHECK 4: Total cost formula or calculation (20 points) ===
        # Look for cells with total value in range £1500-2200 (reasonable total)
        total_expected_min = 1500
        total_expected_max = 2200
        formula_found = False
        found_total = None

        for row in data:
            for cell_val in row:
                if cell_val is not None:
                    cell_str = str(cell_val).replace('£', '').replace(',', '').replace('GBP', '').strip()
                    try:
                        val = float(cell_str)
                        if total_expected_min <= val <= total_expected_max:
                            # This could be the total
                            found_total = val
                            score += 20
                            feedback_parts.append(f"✅ Total cost calculated (£{val:.0f})")
                            formula_found = True
                            break
                    except:
                        pass
            if formula_found:
                break

        if not formula_found:
            # Check if at least there are enough individual costs that could sum to total
            if len(costs_found) >= 4:
                score += 8
                feedback_parts.append("⚠️  Individual costs present but no total calculation found (expected ~£1600-2000)")
            else:
                feedback_parts.append("❌ No total cost calculation found (expected ~£1600-2000)")

        # === CHECK 5: Time-sensitive items identified (15 points) ===
        # Look for mentions of critical items: police certificate, translations, TB test
        # Convert all text content to lowercase for searching
        text_content = " ".join([
            str(cell).lower() 
            for row in data 
            for cell in row 
            if cell is not None
        ])

        critical_items_found = []
        
        # Check for police certificate mention with timing
        if "police" in text_content:
            if any(x in text_content for x in ["6", "8", "week", "long", "first", "urgent", "critical"]):
                critical_items_found.append("police certificate")
        
        # Check for translation mention with timing
        if any(x in text_content for x in ["translat", "birth", "degree", "certificate"]):
            if any(x in text_content for x in ["2", "week", "depend", "original", "need"]):
                critical_items_found.append("translations")
        
        # Check for TB test
        if any(x in text_content for x in ["tb", "tuberculos", "test"]):
            if any(x in text_content for x in ["3", "day", "85", "clinic", "valid"]):
                critical_items_found.append("TB test")
        
        # Check for bank statements (time-sensitive - must be recent)
        if any(x in text_content for x in ["bank", "statement", "financial"]):
            if any(x in text_content for x in ["31", "day", "recent", "last"]):
                critical_items_found.append("bank statements")

        critical_count = len(set(critical_items_found))
        
        if critical_count >= 3:
            score += 15
            feedback_parts.append(f"✅ Time-sensitive items identified: {', '.join(set(critical_items_found))}")
        elif critical_count == 2:
            score += 10
            feedback_parts.append(f"⚠️  Some time-sensitive items identified: {', '.join(set(critical_items_found))}")
        elif critical_count == 1:
            score += 5
            feedback_parts.append(f"⚠️  Minimal time-sensitive items identified: {', '.join(set(critical_items_found))}")
        else:
            feedback_parts.append("❌ Time-sensitive items not clearly identified (police cert, translations)")

        # === CHECK 6: Organization quality (10 points) ===
        # Multiple factors indicate good organization:
        # - Has header row
        # - Multiple columns used
        # - Sufficient rows
        # - Contains expected keywords
        
        organization_score = 0
        
        if header_row_idx is not None:
            organization_score += 3
        
        if columns_found >= 4:
            organization_score += 3
        
        if filled_rows >= 10:
            organization_score += 2
        
        # Check for organization keywords (priority, urgent, deadline, etc.)
        org_keywords = ["priority", "urgent", "first", "deadline", "critical", "depend", "important"]
        has_org_keywords = any(keyword in text_content for keyword in org_keywords)
        if has_org_keywords:
            organization_score += 2

        score += organization_score
        if organization_score >= 8:
            feedback_parts.append("✅ Spreadsheet appears well-organized")
        elif organization_score >= 5:
            feedback_parts.append("⚠️  Spreadsheet has basic organization")
        else:
            feedback_parts.append("⚠️  Spreadsheet organization could be improved")

        # === FINAL SCORING ===
        # Normalize score to 0-1 range
        final_score = min(score / 100.0, 1.0)
        passed = final_score >= 0.65

        # Add summary
        summary = f"Score: {score:.0f}/100 ({final_score*100:.0f}%) | Docs: {filled_rows} | Cols: {columns_found} | Costs: {unique_costs}"
        feedback = summary + " | " + " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": final_score,
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
        if temp_dir and os.path.exists(temp_dir):
            cleanup_temp_dir(temp_dir)