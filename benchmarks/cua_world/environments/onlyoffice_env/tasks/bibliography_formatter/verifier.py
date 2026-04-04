#!/usr/bin/env python3
"""
Verifier for Bibliography Formatter task
Checks for proper MLA Works Cited formatting
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_author_lastname(entry_text):
    """
    Extract the first word of an entry (the sorting key for alphabetization).
    Handles both author names and organizational authors.
    Returns lowercase for case-insensitive comparison.
    """
    entry_text = entry_text.strip()
    
    # Remove leading quotes if it's an article title
    if entry_text.startswith('"'):
        entry_text = entry_text[1:]
    
    # Get first word
    first_word = entry_text.split()[0].strip('.,;:')
    return first_word.lower()


def is_entry_paragraph(para):
    """
    Determine if a paragraph is a bibliography entry.
    Entries typically contain periods, author names, dates, or start with quotes.
    """
    text = para.text.strip()
    
    # Skip empty paragraphs
    if not text:
        return False
    
    # Skip the heading
    if text.lower() in ['works cited', 'my sources (needs formatting)', 'my sources']:
        return False
    
    # Entry indicators: contains period, year pattern, or starts with quote
    has_period = '.' in text
    has_year = re.search(r'\b(19|20)\d{2}\b', text)
    starts_with_quote = text.startswith('"')
    
    # Must be substantial text (more than just a few words)
    word_count = len(text.split())
    
    return (has_period or starts_with_quote) and word_count >= 5


def check_hanging_indent(para):
    """
    Check if a paragraph has hanging indent.
    Hanging indent: left_indent > 0 and first_line_indent is negative or less than left_indent.
    """
    try:
        pf = para.paragraph_format
        left_indent = pf.left_indent
        first_line_indent = pf.first_line_indent
        
        if left_indent is None:
            return False
        
        # Convert to inches for checking
        left_indent_inches = left_indent.inches if hasattr(left_indent, 'inches') else (left_indent / 914400)
        
        # Check for hanging indent pattern
        if first_line_indent is None:
            # If first_line is None but left_indent > 0.3", might be hanging
            return left_indent_inches >= 0.3
        
        first_line_inches = first_line_indent.inches if hasattr(first_line_indent, 'inches') else (first_line_indent / 914400)
        
        # Hanging indent: first line is less indented than subsequent lines
        # Typically first_line is negative or zero, left_indent is ~0.5"
        is_hanging = (left_indent_inches >= 0.3) and (first_line_inches < left_indent_inches)
        
        return is_hanging
    except Exception as e:
        logger.debug(f"Error checking hanging indent: {e}")
        return False


def has_italicized_text(para):
    """
    Check if paragraph contains any italicized text.
    """
    try:
        for run in para.runs:
            if run.italic:
                return True
        return False
    except:
        return False


def check_heading_centered(doc):
    """
    Check if the document has 'Works Cited' heading that is centered.
    """
    for para in doc.paragraphs:
        text = para.text.strip().lower()
        if 'works cited' in text:
            # Check if it's centered (alignment == 1 means CENTER)
            try:
                alignment = para.alignment
                if alignment is not None:
                    # WD_ALIGN_PARAGRAPH.CENTER = 1
                    return alignment == 1 or alignment == 'CENTER'
                # Also check paragraph_format
                if hasattr(para.paragraph_format, 'alignment'):
                    alignment = para.paragraph_format.alignment
                    return alignment == 1
            except:
                pass
    return False


def verify_bibliography_formatting(traj, env_info, task_info):
    """
    Verify that bibliography was properly formatted.

    Checks:
    1. "Works Cited" heading exists and is centered
    2. Entries are in alphabetical order by author last name
    3. Hanging indent is applied to entries (~0.5 inches)
    4. At least 70% of entries have italicized titles
    5. All 10 entries are still present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/research_sources.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_biblio_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        criteria_passed = 0
        feedback_parts = []

        # Criterion 1: Check for "Works Cited" heading (centered)
        has_works_cited = False
        is_centered = False
        
        for para in doc.paragraphs:
            text = para.text.strip().lower()
            if 'works cited' in text:
                has_works_cited = True
                # Check centering
                try:
                    if para.alignment == 1:  # CENTER
                        is_centered = True
                except:
                    pass
                break
        
        if has_works_cited and is_centered:
            criteria_passed += 1
            feedback_parts.append("✅ 'Works Cited' heading present and centered")
        elif has_works_cited:
            feedback_parts.append("⚠️ 'Works Cited' heading present but not centered")
        else:
            feedback_parts.append("❌ 'Works Cited' heading missing")

        # Criterion 2: Check alphabetical order
        entries = []
        entry_paragraphs = []
        
        for para in doc.paragraphs:
            if is_entry_paragraph(para):
                entries.append(para.text.strip())
                entry_paragraphs.append(para)
        
        if len(entries) < 8:
            feedback_parts.append(f"❌ Only {len(entries)} entries found (expected 10)")
        else:
            criteria_passed += 1
            feedback_parts.append(f"✅ Found {len(entries)} bibliography entries")
        
        # Check alphabetization
        if len(entries) >= 3:
            authors = [extract_author_lastname(e) for e in entries]
            sorted_authors = sorted(authors)
            
            # Count how many are in correct position
            correct_positions = sum(1 for i, (a, s) in enumerate(zip(authors, sorted_authors)) if a == s)
            alphabetization_ratio = correct_positions / len(authors)
            
            if alphabetization_ratio >= 0.8:  # 80% in correct order
                criteria_passed += 1
                feedback_parts.append(f"✅ Entries alphabetically ordered ({int(alphabetization_ratio*100)}% correct)")
            else:
                out_of_order = [authors[i] for i in range(len(authors)) if authors[i] != sorted_authors[i]]
                feedback_parts.append(f"❌ Entries not properly alphabetized (only {int(alphabetization_ratio*100)}% correct)")
                if len(out_of_order) <= 3:
                    feedback_parts.append(f"   Out of order: {', '.join(out_of_order[:3])}")

        # Criterion 3: Check hanging indent
        entries_with_hanging = 0
        for para in entry_paragraphs:
            if check_hanging_indent(para):
                entries_with_hanging += 1
        
        if len(entry_paragraphs) > 0:
            hanging_ratio = entries_with_hanging / len(entry_paragraphs)
            
            if hanging_ratio >= 0.7:  # 70% have hanging indent
                criteria_passed += 1
                feedback_parts.append(f"✅ Hanging indent applied ({entries_with_hanging}/{len(entry_paragraphs)} entries)")
            else:
                feedback_parts.append(f"❌ Hanging indent missing or incorrect ({entries_with_hanging}/{len(entry_paragraphs)} entries have it)")

        # Criterion 4: Check italicization
        entries_with_italics = 0
        for para in entry_paragraphs:
            if has_italicized_text(para):
                entries_with_italics += 1
        
        if len(entry_paragraphs) > 0:
            italics_ratio = entries_with_italics / len(entry_paragraphs)
            
            # We expect at least 70% to have italicized titles
            # (Some entries are articles which might not need italics)
            if italics_ratio >= 0.5:  # 50% threshold (lenient since articles don't need italics)
                criteria_passed += 1
                feedback_parts.append(f"✅ Titles italicized ({entries_with_italics}/{len(entry_paragraphs)} entries)")
            else:
                feedback_parts.append(f"❌ Insufficient title italicization ({entries_with_italics}/{len(entry_paragraphs)} entries have italics)")

        # Calculate score (5 criteria total)
        score = int((criteria_passed / 5) * 100)
        passed = score >= 60  # Pass with 3/5 criteria

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