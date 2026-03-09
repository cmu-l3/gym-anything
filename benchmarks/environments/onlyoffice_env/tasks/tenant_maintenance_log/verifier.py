#!/usr/bin/env python3
"""
Verifier for Tenant Maintenance Log task

Verifies that a maintenance request log document was created with:
- A table with 6 columns
- At least 5 maintenance entries
- Proper formatting and content
- Notes section
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_tenant_maintenance_log(traj, env_info, task_info):
    """
    Verify that tenant maintenance log was created correctly.

    Scoring:
    - Table exists: 30 points
    - 6 columns: 20 points
    - At least 5 entries (6+ rows): 20 points
    - Headers formatted bold: 10 points
    - Contains dates: 5 points
    - Contains priorities: 5 points
    - Contains statuses: 5 points
    - Notes section: 5 points
    
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/Maintenance_Log_Unit2B.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_maintenance_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        score = 0
        feedback_parts = []

        # Check document has content
        doc_text = get_document_text(doc)
        if not doc_text or len(doc_text.strip()) < 10:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Document is empty or has minimal content"
            }

        # Criterion 1: Check for table existence (30 points)
        table_count = count_tables(doc)
        if table_count == 0:
            feedback_parts.append("❌ No table found in document")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        score += 30
        feedback_parts.append(f"✅ Table found")
        
        # Get the first table for analysis
        table = doc.tables[0]
        
        # Criterion 2: Check column count - should be 6 (20 points)
        col_count = len(table.columns)
        if col_count >= 6:
            score += 20
            feedback_parts.append(f"✅ Table has {col_count} columns")
        elif col_count >= 4:
            score += 10
            feedback_parts.append(f"⚠️ Table has {col_count} columns (expected 6)")
        else:
            feedback_parts.append(f"❌ Table has only {col_count} columns (need 6)")
        
        # Criterion 3: Check row count - at least 6 rows (1 header + 5 entries) (20 points)
        row_count = len(table.rows)
        if row_count >= 6:
            score += 20
            feedback_parts.append(f"✅ Table has {row_count-1} entry rows")
        elif row_count >= 4:
            score += 10
            feedback_parts.append(f"⚠️ Table has only {row_count-1} entry rows (need 5+)")
        else:
            feedback_parts.append(f"❌ Table has only {row_count-1} entry rows (need 5+)")
        
        # Criterion 4: Check if headers are formatted (bold) (10 points)
        header_bold = False
        if row_count > 0:
            header_row = table.rows[0]
            for cell in header_row.cells:
                for para in cell.paragraphs:
                    for run in para.runs:
                        if run.bold and len(run.text.strip()) > 0:
                            header_bold = True
                            break
                    if header_bold:
                        break
                if header_bold:
                    break
        
        if header_bold:
            score += 10
            feedback_parts.append("✅ Headers formatted (bold)")
        else:
            feedback_parts.append("⚠️ Headers not bold")
        
        # Extract all table text for content analysis
        table_text_lower = ""
        for row in table.rows:
            for cell in row.cells:
                table_text_lower += cell.text.lower() + " "
        
        # Criterion 5: Check for date content (5 points)
        # Look for date patterns in table
        has_dates = False
        date_patterns = [
            r'\d{1,2}[-/]\d{1,2}[-/]\d{2,4}',  # MM/DD/YYYY or similar
            r'\d{4}[-/]\d{1,2}[-/]\d{1,2}',    # YYYY-MM-DD
            r'\d{1,2}\s+\d{1,2}\s+\d{2,4}',    # Space-separated dates
        ]
        
        for pattern in date_patterns:
            if re.search(pattern, table_text_lower):
                has_dates = True
                break
        
        # Also check if first column (typical date column) has date-like content
        if not has_dates and row_count > 1:
            for row_idx in range(1, min(row_count, 4)):
                cell_text = table.rows[row_idx].cells[0].text.strip()
                if any(char.isdigit() for char in cell_text) and len(cell_text) >= 6:
                    has_dates = True
                    break
        
        if has_dates:
            score += 5
            feedback_parts.append("✅ Dates documented")
        else:
            feedback_parts.append("⚠️ No dates found")
        
        # Criterion 6: Check for priority keywords (5 points)
        priority_keywords = ['low', 'medium', 'high', 'urgent', 'critical']
        has_priorities = any(kw in table_text_lower for kw in priority_keywords)
        
        if has_priorities:
            score += 5
            feedback_parts.append("✅ Priority levels present")
        else:
            feedback_parts.append("⚠️ No priority levels found")
        
        # Criterion 7: Check for status keywords (5 points)
        status_keywords = ['pending', 'resolved', 'ignored', 'progress', 'complete', 'fixed', 'open', 'closed']
        has_statuses = any(kw in table_text_lower for kw in status_keywords)
        
        if has_statuses:
            score += 5
            feedback_parts.append("✅ Status tracking present")
        else:
            feedback_parts.append("⚠️ No status tracking found")
        
        # Criterion 8: Check for Notes section outside table (5 points)
        full_doc_text = get_document_text(doc).lower()
        has_notes = 'note' in full_doc_text or 'summary' in full_doc_text
        
        # More sophisticated check: look for "notes" followed by content
        if has_notes:
            score += 5
            feedback_parts.append("✅ Notes section found")
        else:
            feedback_parts.append("⚠️ No Notes section found")
        
        # Additional validation: Check for substantial content in entries
        # Look for issue descriptions that are meaningful (not just placeholders)
        has_substantial_content = False
        if row_count > 1 and col_count > 1:
            for row_idx in range(1, min(row_count, 7)):
                for col_idx in range(min(col_count, 6)):
                    cell_text = table.rows[row_idx].cells[col_idx].text.strip()
                    # Check if any cell has substantial text (more than 20 chars)
                    if len(cell_text) > 20:
                        has_substantial_content = True
                        break
                if has_substantial_content:
                    break
        
        if has_substantial_content:
            feedback_parts.append("✅ Entries contain detailed information")
        else:
            feedback_parts.append("⚠️ Entries may lack detail")
        
        # Determine pass/fail
        passed = score >= 70
        
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
