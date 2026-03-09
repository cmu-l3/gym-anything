#!/usr/bin/env python3
"""
Verifier for Workplace Incident Documentation task

Verifies that a formal OSHA complaint document was created with:
1. Proper header section (centered, bold, with facility info)
2. Executive summary with key statistics
3. Incident timeline table with chronological ordering
4. Pattern analysis section with calculations
"""

import sys
import os
import logging
import tempfile
import re
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    check_text_formatting,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_dates_from_table(table):
    """
    Extract dates from table to verify chronological ordering.
    Returns list of dates found.
    """
    dates = []
    for row_idx, row in enumerate(table.rows):
        if row_idx == 0:  # Skip header row
            continue
        for cell_idx, cell in enumerate(row.cells):
            if cell_idx == 0:  # First column should have dates
                cell_text = cell.text.strip()
                # Try to parse dates in various formats
                # Expected formats: 3/8/24, 3/8, March 8, etc.
                date_patterns = [
                    r'(\d{1,2})/(\d{1,2})/(\d{2,4})',  # 3/8/24
                    r'(\d{1,2})/(\d{1,2})',  # 3/8
                    r'(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2})',
                ]
                
                for pattern in date_patterns:
                    match = re.search(pattern, cell_text, re.IGNORECASE)
                    if match:
                        dates.append((row_idx, cell_text, match.group(0)))
                        break
    
    return dates


def check_chronological_order(dates_info):
    """
    Check if dates are in chronological order.
    Returns (is_ordered, feedback)
    """
    if len(dates_info) < 2:
        return False, "Not enough dates found in table"
    
    # Simple heuristic: check if March dates come before April dates come before May dates
    march_rows = []
    april_rows = []
    may_rows = []
    
    for row_idx, cell_text, date_str in dates_info:
        if '3/' in date_str or 'march' in cell_text.lower():
            march_rows.append(row_idx)
        elif '4/' in date_str or 'april' in cell_text.lower():
            april_rows.append(row_idx)
        elif '5/' in date_str or 'may' in cell_text.lower():
            may_rows.append(row_idx)
    
    # Check that March rows come before April rows come before May rows
    max_march = max(march_rows) if march_rows else 0
    min_april = min(april_rows) if april_rows else float('inf')
    max_april = max(april_rows) if april_rows else 0
    min_may = min(may_rows) if may_rows else float('inf')
    
    if march_rows and april_rows:
        if max_march > min_april:
            return False, "March dates not before April dates"
    
    if april_rows and may_rows:
        if max_april > min_may:
            return False, "April dates not before May dates"
    
    return True, "Dates appear chronologically ordered"


def verify_workplace_incident_documentation(traj, env_info, task_info):
    """
    Verify that the workplace incident documentation was created correctly.

    Scoring breakdown (100 points total):
    - Header section: 20 points
    - Executive summary: 20 points
    - Table structure: 25 points
    - Chronological ordering: 15 points
    - Pattern analysis: 15 points
    - Formatting: 5 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/OSHA_complaint_timeline.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_incident_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Document not found or invalid: {error}"
            }

        feedback_parts = []
        score = 0

        # Get full text (lowercase for easier matching)
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()

        # ============================================================
        # CRITERION 1: Header Section (20 points)
        # ============================================================
        header_score = 0
        
        # Check for report title (5 points)
        if "workplace safety violation report" in full_text_lower:
            header_score += 5
            # Bonus if it's bold (3 points)
            if check_text_formatting(doc, "WORKPLACE SAFETY VIOLATION REPORT", bold=True) or \
               check_text_formatting(doc, "Workplace Safety Violation Report", bold=True):
                header_score += 3
        
        # Check for facility name (4 points)
        if "riverside logistics" in full_text_lower:
            header_score += 4
        
        # Check for address (4 points)
        if "450 industrial" in full_text_lower and ("pkwy" in full_text_lower or "parkway" in full_text_lower):
            header_score += 4
        
        # Check for date range (4 points)
        has_march = "march" in full_text_lower or "3/" in full_text or "3/8" in full_text
        has_may = "may" in full_text_lower or "5/" in full_text or "5/20" in full_text
        if has_march and has_may:
            header_score += 4
        
        score += header_score
        if header_score >= 15:
            feedback_parts.append(f"✅ Header section complete ({header_score}/20)")
        else:
            feedback_parts.append(f"⚠️ Header incomplete ({header_score}/20 points)")

        # ============================================================
        # CRITERION 2: Executive Summary (20 points)
        # ============================================================
        summary_score = 0
        
        # Check for "summary" heading (5 points)
        if "summary" in full_text_lower or "executive" in full_text_lower:
            summary_score += 5
        
        # Check for "9" incidents mention (5 points)
        if "9" in full_text or "nine" in full_text_lower:
            summary_score += 5
        
        # Check for "74" days mention (5 points)
        if "74" in full_text or "seventy-four" in full_text_lower or "2.5 month" in full_text_lower:
            summary_score += 5
        
        # Check for supervisor notification (5 points)
        if "supervisor" in full_text_lower or "notified" in full_text_lower or "tom reynolds" in full_text_lower:
            summary_score += 5
        
        score += summary_score
        if summary_score >= 15:
            feedback_parts.append(f"✅ Executive summary present ({summary_score}/20)")
        else:
            feedback_parts.append(f"⚠️ Executive summary incomplete ({summary_score}/20 points)")

        # ============================================================
        # CRITERION 3: Table Structure (25 points)
        # ============================================================
        table_score = 0
        num_tables = count_tables(doc)
        
        if num_tables > 0:
            table_score += 10
            
            # Check table structure
            table = doc.tables[0]
            num_cols = len(table.columns)
            num_rows = len(table.rows)
            
            # Should have 4 columns: Date, Type, Description, Witness (5 points)
            if num_cols >= 4:
                table_score += 5
            
            # Should have at least 9 data rows + 1 header = 10 rows (10 points)
            if num_rows >= 9:
                table_score += 10
                feedback_parts.append(f"✅ Found table with {num_rows} rows, {num_cols} columns ({table_score}/25)")
            else:
                feedback_parts.append(f"⚠️ Table has only {num_rows} rows, expected at least 9 ({table_score}/25)")
        else:
            feedback_parts.append("❌ No table found (0/25 points)")
        
        score += table_score

        # ============================================================
        # CRITERION 4: Chronological Ordering (15 points)
        # ============================================================
        chronological_score = 0
        
        if num_tables > 0:
            table = doc.tables[0]
            dates_info = extract_dates_from_table(table)
            
            if len(dates_info) >= 5:  # Found at least 5 dates
                chronological_score += 5
                
                # Check if chronologically ordered
                is_ordered, order_feedback = check_chronological_order(dates_info)
                if is_ordered:
                    chronological_score += 10
                    feedback_parts.append(f"✅ Dates chronologically ordered ({chronological_score}/15)")
                else:
                    feedback_parts.append(f"⚠️ {order_feedback} ({chronological_score}/15)")
            else:
                feedback_parts.append(f"⚠️ Found only {len(dates_info)} dates in table ({chronological_score}/15)")
        else:
            feedback_parts.append("❌ Cannot check chronology without table (0/15)")
        
        score += chronological_score

        # ============================================================
        # CRITERION 5: Pattern Analysis Section (15 points)
        # ============================================================
        pattern_score = 0
        
        # Check for "pattern" or "analysis" heading (4 points)
        if "pattern" in full_text_lower or "analysis" in full_text_lower:
            pattern_score += 4
        
        # Check for total incidents count (4 points)
        # Look for "9" in context of total/incidents
        if re.search(r'\b9\b', full_text) or "nine" in full_text_lower:
            pattern_score += 4
        
        # Check for timespan mention (4 points)
        if "74" in full_text or "74 days" in full_text_lower:
            pattern_score += 4
        
        # Check for frequency/average calculation (3 points)
        if "frequency" in full_text_lower or "every 8" in full_text_lower or "8 days" in full_text_lower or "average" in full_text_lower:
            pattern_score += 3
        
        score += pattern_score
        if pattern_score >= 10:
            feedback_parts.append(f"✅ Pattern analysis complete ({pattern_score}/15)")
        else:
            feedback_parts.append(f"⚠️ Pattern analysis incomplete ({pattern_score}/15 points)")

        # ============================================================
        # CRITERION 6: Professional Formatting (5 points)
        # ============================================================
        formatting_score = 0
        
        # Check for any bold headers (3 points)
        has_bold_header = False
        for keyword in ["SUMMARY", "INCIDENT", "TIMELINE", "PATTERN", "ANALYSIS", "REPORT"]:
            if check_text_formatting(doc, keyword, bold=True):
                has_bold_header = True
                break
        
        if has_bold_header:
            formatting_score += 3
        
        # Bonus for having table (2 points)
        if num_tables > 0:
            formatting_score += 2
        
        score += formatting_score

        # ============================================================
        # FINAL EVALUATION
        # ============================================================
        
        # Normalize score to 0-1 range
        normalized_score = score / 100.0
        
        # Pass if score >= 70
        passed = score >= 70

        # Compile feedback
        feedback = " | ".join(feedback_parts)
        feedback += f" | TOTAL: {score}/100 points"

        return {
            "passed": passed,
            "score": normalized_score,
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
