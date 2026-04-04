#!/usr/bin/env python3
"""
Verifier for Bibliography Rescue task

Checks that messy citations have been converted to proper APA 7th edition format:
- Alphabetical ordering
- Author name format (LastName, F. M.)
- Italics on journals/books
- Article title capitalization (sentence case)
- Year format with parentheses
- DOI presence for journal articles
- Proper punctuation patterns
- Hanging indents
- No MLA remnants
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


def extract_citations(doc):
    """
    Extract citation paragraphs from document.
    Returns list of (paragraph_object, text) tuples.
    """
    citations = []
    references_found = False
    
    for para in doc.paragraphs:
        text = para.text.strip()
        
        # Skip until we find "References" header
        if not references_found:
            if "references" in text.lower():
                references_found = True
            continue
        
        # Skip empty paragraphs and section markers
        if not text or text == "---" or "MISSING INFORMATION" in text or "TASK:" in text:
            continue
            
        # Skip instruction lines starting with "-" or "•"
        if text.startswith("-") or text.startswith("•") or text.startswith("TASK"):
            continue
        
        # This should be a citation
        if len(text) > 30:  # Citations are substantial
            citations.append((para, text))
    
    return citations


def check_alphabetical_order(citations):
    """
    Check if citations are in alphabetical order by first author's last name.
    Returns (is_sorted, details)
    """
    first_words = []
    
    for para, text in citations:
        # Extract first word (should be author's last name)
        words = text.split()
        if words:
            # Remove any leading/trailing punctuation
            first_word = words[0].strip('.,;:()[]{}')
            first_words.append(first_word)
    
    if len(first_words) < 2:
        return False, "Not enough citations to check order"
    
    # Check if sorted (case-insensitive)
    sorted_words = sorted(first_words, key=str.lower)
    is_sorted = [w.lower() for w in first_words] == [w.lower() for w in sorted_words]
    
    return is_sorted, f"Order: {' -> '.join(first_words[:4])}..."


def check_author_format(citations):
    """
    Check if author names follow APA format: LastName, F. M.
    Returns (count_correct, total, details)
    """
    # Pattern for APA author format: LastName, F. or LastName, F. M.
    # Should have comma after last name, then initials with periods
    author_pattern = re.compile(r'\b[A-Z][a-z]+,\s+[A-Z]\.\s*(?:[A-Z]\.\s*)?')
    
    correct_count = 0
    
    for para, text in citations:
        # Check first 50 characters for author format
        beginning = text[:100]
        if author_pattern.search(beginning):
            correct_count += 1
    
    return correct_count, len(citations)


def check_italics_present(doc, citations):
    """
    Check if book/journal titles are italicized.
    Returns count of citations with italics.
    """
    italic_count = 0
    
    for para, text in citations:
        # Check if this paragraph has any italic runs
        has_italic = False
        for run in para.runs:
            if run.italic or (run.font.italic is True):
                # Check if italic text is substantial (not just a single letter)
                if len(run.text.strip()) > 3:
                    has_italic = True
                    break
        
        if has_italic:
            italic_count += 1
    
    return italic_count


def check_title_capitalization(citations):
    """
    Check that article titles don't have excessive Title Case.
    Title Case articles are a common error (should be sentence case).
    Returns (violations_found, details)
    """
    # Look for patterns that suggest Title Case in article titles
    # E.g., "The Role Of" instead of "The role of"
    title_case_pattern = re.compile(r'\bThe [A-Z][a-z]+ Of [A-Z]')
    
    violations = 0
    
    for para, text in citations:
        if title_case_pattern.search(text):
            violations += 1
    
    # Fewer violations is better (ideally 0)
    return violations


def check_year_format(citations):
    """
    Check if years are in parentheses: (YYYY) or (YYYY, Month)
    Returns count of citations with correct year format.
    """
    year_pattern = re.compile(r'\(\d{4}(?:,\s+\w+(?:\s+\d{1,2})?)?\)')
    
    correct_count = 0
    
    for para, text in citations:
        if year_pattern.search(text):
            correct_count += 1
    
    return correct_count


def check_doi_presence(citations):
    """
    Check if DOIs are present for journal articles.
    Returns count of citations with DOI URLs.
    """
    doi_pattern = re.compile(r'https?://doi\.org/')
    
    doi_count = 0
    
    for para, text in citations:
        if doi_pattern.search(text):
            doi_count += 1
    
    return doi_count


def check_punctuation_patterns(citations):
    """
    Check for proper APA punctuation patterns.
    After year should be "). " or "). *" (for italic title)
    Returns count of citations with correct pattern.
    """
    # Pattern: year closing paren followed by period and space/content
    punctuation_pattern = re.compile(r'\(\d{4}[^)]*\)\.\s+\w')
    
    correct_count = 0
    
    for para, text in citations:
        if punctuation_pattern.search(text):
            correct_count += 1
    
    return correct_count


def check_hanging_indent(citations):
    """
    Check if citations have hanging indent (first line < left indent).
    Returns count of citations with hanging indent.
    """
    hanging_count = 0
    
    for para, text in citations:
        # Check paragraph format
        fmt = para.paragraph_format
        
        # Hanging indent means: first_line_indent < left_indent
        # In python-docx, these might be None, so handle carefully
        try:
            left = fmt.left_indent if fmt.left_indent is not None else 0
            first = fmt.first_line_indent if fmt.first_line_indent is not None else 0
            
            # Convert to inches for comparison (they're in EMUs)
            # Hanging indent: first line is less indented than subsequent lines
            # Typically: first=0, left=0.5" (457200 EMUs)
            if left > first and left > 100000:  # Some reasonable indent
                hanging_count += 1
        except Exception as e:
            logger.debug(f"Error checking indent: {e}")
            continue
    
    return hanging_count


def check_no_mla_remnants(citations):
    """
    Check that old MLA-style markers are removed.
    Returns count of violations (should be 0).
    """
    mla_patterns = [
        re.compile(r'\bPrint\.\s*$'),
        re.compile(r'\bWeb\.\s*$'),
        re.compile(r'\bAccessed from\b'),
        re.compile(r'\bRetrieved from\b'),
    ]
    
    violations = 0
    
    for para, text in citations:
        for pattern in mla_patterns:
            if pattern.search(text):
                violations += 1
                break  # Count each citation only once
    
    return violations


def verify_bibliography_rescue(traj, env_info, task_info):
    """
    Verify that bibliography has been properly converted to APA 7th edition format.

    10 Criteria (need 8+ to pass):
    1. Correct citation count (exactly 8)
    2. Alphabetical ordering by first author
    3. Author name format (at least 6/8 in correct format)
    4. Italics present (at least 4/8 citations)
    5. Title capitalization (no Title Case violations)
    6. Year format (at least 6/8 correct)
    7. DOI presence (at least 2 citations)
    8. Punctuation patterns (at least 6/8 correct)
    9. Hanging indents (at least 6/8 correct)
    10. No MLA remnants (0 violations)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/thesis_references.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_bib_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        # Extract citations from document
        citations = extract_citations(doc)
        
        if len(citations) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No citations found in document. Ensure 'References' section exists."
            }

        criteria_passed = 0
        feedback_parts = []

        # Criterion 1: Citation count (should be exactly 8)
        if len(citations) == 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Citation count: 8")
        else:
            feedback_parts.append(f"❌ Citation count: {len(citations)} (expected 8)")

        # Criterion 2: Alphabetical ordering
        is_sorted, order_details = check_alphabetical_order(citations)
        if is_sorted:
            criteria_passed += 1
            feedback_parts.append("✅ Alphabetically ordered")
        else:
            feedback_parts.append(f"❌ Not alphabetically ordered ({order_details})")

        # Criterion 3: Author name format (at least 6/8)
        author_correct, author_total = check_author_format(citations)
        if author_correct >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Author format: {author_correct}/{author_total}")
        else:
            feedback_parts.append(f"❌ Author format: only {author_correct}/{author_total} correct")

        # Criterion 4: Italics present (at least 4/8)
        italic_count = check_italics_present(doc, citations)
        if italic_count >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Italics applied: {italic_count}/{len(citations)}")
        else:
            feedback_parts.append(f"❌ Italics missing: only {italic_count}/{len(citations)}")

        # Criterion 5: Title capitalization (no Title Case violations)
        title_case_violations = check_title_capitalization(citations)
        if title_case_violations == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Article titles in sentence case")
        else:
            feedback_parts.append(f"❌ Title Case violations: {title_case_violations}")

        # Criterion 6: Year format (at least 6/8)
        year_correct = check_year_format(citations)
        if year_correct >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Year format: {year_correct}/{len(citations)}")
        else:
            feedback_parts.append(f"❌ Year format: only {year_correct}/{len(citations)}")

        # Criterion 7: DOI presence (at least 2)
        doi_count = check_doi_presence(citations)
        if doi_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ DOIs present: {doi_count}")
        else:
            feedback_parts.append(f"❌ DOIs missing: only {doi_count} (expected 2+)")

        # Criterion 8: Punctuation patterns (at least 6/8)
        punct_correct = check_punctuation_patterns(citations)
        if punct_correct >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Punctuation: {punct_correct}/{len(citations)}")
        else:
            feedback_parts.append(f"❌ Punctuation: only {punct_correct}/{len(citations)}")

        # Criterion 9: Hanging indents (at least 6/8)
        hanging_count = check_hanging_indent(citations)
        if hanging_count >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Hanging indents: {hanging_count}/{len(citations)}")
        else:
            feedback_parts.append(f"❌ Hanging indents: only {hanging_count}/{len(citations)}")

        # Criterion 10: No MLA remnants
        mla_violations = check_no_mla_remnants(citations)
        if mla_violations == 0:
            criteria_passed += 1
            feedback_parts.append("✅ No MLA remnants")
        else:
            feedback_parts.append(f"❌ MLA remnants found: {mla_violations}")

        # Calculate score and pass/fail
        score = int((criteria_passed / 10) * 100)
        passed = criteria_passed >= 8  # Need 8/10 to pass (80%)

        feedback = " | ".join(feedback_parts)

        logger.info(f"Bibliography verification: {criteria_passed}/10 criteria passed")

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
