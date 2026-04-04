#!/usr/bin/env python3
"""Verifier for create_data_table task."""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_text_formatting,
    check_paragraph_alignment,
    count_tables,
    get_table_dimensions,
    get_table_content,
    check_table_header_formatting,
    check_table_cell_alignment,
    check_table_alternating_colors,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_data_table(traj, env_info, task_info):
    """
    Verify that the data table was created correctly.

    Checks:
    1. Title is present and formatted (centered, bold)
    2. Table exists in the document
    3. Table has correct dimensions (5 rows x 4 columns)
    4. Header row contains expected column names
    5. Data rows contain expected values
    6. Content completeness (percentages present)
    7. Header row formatting (bold and/or shading)
    8. Numeric columns are right-aligned
    9. Alternating row colors
    10. VLM visual verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Try multiple possible paths for the saved document
    container_paths = [
        "/tmp/amazon_q4_report.docx",
        "/home/ga/Documents/amazon_q4_report.docx",
        "/home/ga/amazon_q4_report.docx",
        "/tmp/sales_report.docx",
        "/home/ga/Documents/sales_report.docx",
    ]

    success = False
    doc = None
    error = "Document not found in any expected location"
    temp_dir = None

    for container_path in container_paths:
        success, doc, error, temp_dir = copy_and_parse_document(
            container_path, copy_from_env, file_format='docx'
        )
        if success:
            break
        if temp_dir:
            cleanup_verification_temp(temp_dir)
            temp_dir = None

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        metadata = task_info.get('metadata', {})
        expected_title = metadata.get('title_text', 'Amazon Q4 2023 Regional Net Sales Report')
        expected_rows = metadata.get('expected_rows', 5)
        expected_cols = metadata.get('expected_columns', 4)
        expected_headers = metadata.get('header_row', ['Region', 'Q4 2023 Net Sales', 'Year-over-Year Growth', '% of Total'])
        expected_data = metadata.get('data_rows', [])

        feedback_parts = []
        full_text = get_document_text(doc).lower()

        # ================================================================
        # PREREQUISITE CHECK: Must have Amazon-related content
        # If document doesn't mention Amazon or have sales data, score is 0
        # This prevents gaming by creating random tables
        # ================================================================
        has_amazon = 'amazon' in full_text
        has_sales_context = any(term in full_text for term in ['q4', 'sales', 'revenue', 'report', 'regional'])
        has_expected_data = any(val in full_text for val in ['north america', 'international', 'aws', '105', '40', '24', '170'])

        prerequisite_passed = has_amazon or (has_sales_context and has_expected_data)

        if not prerequisite_passed:
            feedback_parts.append("PREREQUISITE FAILED: No Amazon/sales content found - agent must create Amazon sales report")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
            }

        feedback_parts.append("Prerequisite: Amazon/sales content present")

        criteria_passed = 0
        total_criteria = 10  # 9 document checks + VLM

        # Criterion 1: Title is present - require more specific title content
        # Must have at least "Amazon" AND either "Q4 2023" or "Sales" or "Report"
        has_amazon = 'amazon' in full_text
        has_q4_or_sales = ('q4 2023' in full_text or 'q4' in full_text or
                          'sales' in full_text or 'report' in full_text)
        title_present = has_amazon and has_q4_or_sales
        title_bold = check_text_formatting(doc, expected_title, bold=True)
        title_centered = check_paragraph_alignment(doc, expected_title, 'center')

        # Task REQUIRES: "centered and bold" - must have BOTH
        if title_present and title_bold and title_centered:
            criteria_passed += 1
            feedback_parts.append("Title: present, centered, and bold")
        elif title_present and (title_bold or title_centered):
            # Partial formatting - give specific feedback but NO credit
            fmt_status = []
            if title_bold:
                fmt_status.append("bold")
            if title_centered:
                fmt_status.append("centered")
            feedback_parts.append(f"Title: present but only {' and '.join(fmt_status)} (need BOTH centered AND bold)")
        elif title_present:
            feedback_parts.append("Title: present but NOT formatted (need centered AND bold)")
        else:
            feedback_parts.append("Title: NOT found (need 'Amazon' + sales/report context)")

        # Criterion 2: Table exists
        table_count = count_tables(doc)
        if table_count >= 1:
            criteria_passed += 1
            feedback_parts.append(f"Table: found ({table_count} tables)")
        else:
            feedback_parts.append("Table: NOT found")
            # If no table, we can't check other criteria
            score = int((criteria_passed / total_criteria) * 100)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | Cannot verify table details without a table",
            }

        # Criterion 3: Table dimensions - require EXACT dimensions
        rows, cols = get_table_dimensions(doc, 0)
        if rows == expected_rows and cols == expected_cols:
            criteria_passed += 1
            feedback_parts.append(f"Dimensions: {rows}x{cols} (correct)")
        elif rows >= expected_rows and cols >= expected_cols:
            # Slightly larger is acceptable
            criteria_passed += 1
            feedback_parts.append(f"Dimensions: {rows}x{cols} (acceptable, expected {expected_rows}x{expected_cols})")
        else:
            feedback_parts.append(f"Dimensions: {rows}x{cols} (WRONG: expected {expected_rows}x{expected_cols})")

        # Criterion 4: Header row content
        table_content = get_table_content(doc, 0)
        if table_content:
            header_row = table_content[0] if table_content else []
            headers_found = 0
            for expected_header in expected_headers:
                for cell in header_row:
                    if expected_header.lower() in cell.lower():
                        headers_found += 1
                        break

            if headers_found >= 3:  # At least 3 of 4 headers
                criteria_passed += 1
                feedback_parts.append(f"Headers: {headers_found}/{len(expected_headers)} found")
            else:
                feedback_parts.append(f"Headers: only {headers_found}/{len(expected_headers)} found")
        else:
            feedback_parts.append("Headers: could not read table content")

        # Criterion 5: Data row content - using real Amazon Q4 2023 data
        data_values_found = 0
        expected_values = ['north america', 'international', 'aws', 'total', '105.5', '40.2', '24.2', '170']

        for row in table_content[1:] if len(table_content) > 1 else []:
            row_text = ' '.join(row).lower()
            for val in expected_values:
                if val in row_text:
                    data_values_found += 1
                    break

        if data_values_found >= 3:  # At least 3 of 4 data rows have expected data
            criteria_passed += 1
            feedback_parts.append(f"Data content: {data_values_found} rows verified")
        else:
            feedback_parts.append(f"Data content: only {data_values_found} rows have expected data")

        # Criterion 6: Content completeness (percentages present)
        percentage_count = 0
        for row in table_content:
            for cell in row:
                if '%' in cell:
                    percentage_count += 1

        if percentage_count >= 6:  # At least 6 percentage values (2 per data row)
            criteria_passed += 1
            feedback_parts.append(f"Numeric data: {percentage_count} percentages found")
        else:
            feedback_parts.append(f"Numeric data: only {percentage_count} percentages found")

        # Criterion 7: Header row formatting - Task REQUIRES: "bold text with blue background" (BOTH)
        header_fmt = check_table_header_formatting(doc, 0)
        has_bold = header_fmt['has_bold']
        has_shading = header_fmt['has_shading']

        if has_bold and has_shading:
            criteria_passed += 1
            feedback_parts.append(f"Header formatting: bold with shading({header_fmt['shading_color']})")
        elif has_bold or has_shading:
            # Partial formatting - give specific feedback but NO credit
            fmt_details = []
            if has_bold:
                fmt_details.append("bold")
            if has_shading:
                fmt_details.append(f"shading({header_fmt['shading_color']})")
            feedback_parts.append(f"Header formatting: only {', '.join(fmt_details)} (need BOTH bold AND blue background)")
        else:
            feedback_parts.append("Header formatting: NO bold or shading detected (need BOTH)")

        # Criterion 8: Numeric columns are right-aligned
        # Task requires: "Right-align the numeric columns"
        alignment_result = check_table_cell_alignment(doc, 0)
        # Numeric columns are columns 1, 2, 3 (0-indexed) - Net Sales, Growth, % of Total
        right_aligned_cols = 0
        total_numeric_cols = 3

        # Note: check_table_cell_alignment returns {'columns': ['left', 'right', ...], 'has_right_aligned_numbers': bool}
        if alignment_result and 'columns' in alignment_result:
            col_alignments = alignment_result['columns']  # List of strings: 'left', 'right', 'center', 'unknown'
            # Check columns 1, 2, 3 (the numeric columns)
            for col_idx in [1, 2, 3]:
                if col_idx < len(col_alignments):
                    col_align = col_alignments[col_idx]  # This is a STRING like 'right', 'left', etc.
                    # Check if this column is right-aligned
                    if col_align == 'right':
                        right_aligned_cols += 1

        if right_aligned_cols >= 2:  # At least 2 of 3 numeric columns right-aligned
            criteria_passed += 1
            feedback_parts.append(f"Right-alignment: {right_aligned_cols}/{total_numeric_cols} numeric columns")
        else:
            feedback_parts.append(f"Right-alignment: only {right_aligned_cols}/{total_numeric_cols} numeric columns aligned")

        # Criterion 9: Alternating row colors
        # Task requires: "Add alternating row colors (white and light gray) to the data rows"
        # Must have TRUE alternation pattern - not just "some rows have shading"
        # Note: check_table_alternating_colors returns {'has_alternating': bool, 'row_shadings': [...]}
        alt_colors_result = check_table_alternating_colors(doc, 0)
        if alt_colors_result and alt_colors_result.get('has_alternating', False):
            criteria_passed += 1
            row_shadings = alt_colors_result.get('row_shadings', [])
            unique_colors = set(s for s in row_shadings if s)
            feedback_parts.append(f"Alternating colors: YES ({len(unique_colors)} different colors in alternating pattern)")
        else:
            # NO partial credit - either has true alternation or not
            row_shadings = alt_colors_result.get('row_shadings', []) if alt_colors_result else []
            rows_with_shading = sum(1 for s in row_shadings if s)
            if rows_with_shading > 0:
                feedback_parts.append(f"Alternating colors: NO alternation pattern ({rows_with_shading} rows have some shading but not alternating)")
            else:
                feedback_parts.append("Alternating colors: NOT found (no row shading detected)")

        # Criterion 10: VLM visual verification
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Writer screenshot showing a sales report table. Answer in JSON:
{
    "has_title": true/false,
    "has_table": true/false,
    "table_has_headers": true/false,
    "table_has_data_rows": true/false,
    "header_appears_formatted": true/false,
    "has_alternating_row_colors": true/false
}
Does the document show:
1. A title mentioning sales report?
2. A visible table structure?
3. A header row with column names?
4. Multiple data rows with regions and numbers?
5. Header row with different formatting (bold, colored background)?
6. Alternating row colors or shading in the data rows?
""")
        if vlm_result is not None:
            has_table = vlm_result.get("has_table", False)
            has_headers = vlm_result.get("table_has_headers", False)
            has_data = vlm_result.get("table_has_data_rows", False)

            if has_table and (has_headers or has_data):
                criteria_passed += 1
                feedback_parts.append("VLM: table structure confirmed")
            else:
                feedback_parts.append("VLM: table structure not confirmed")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM: unavailable (skipped)")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 55  # ~5.5/10 criteria

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
