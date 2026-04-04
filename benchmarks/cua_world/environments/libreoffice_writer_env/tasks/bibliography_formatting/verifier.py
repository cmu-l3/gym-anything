#!/usr/bin/env python3
"""Verifier for bibliography_formatting task."""

import sys
import os
import re
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_paragraph_alignment,
    check_hanging_indent,
    has_italicized_text,
    extract_citation_paragraphs,
    check_alphabetical_order,
    check_apa_citation_format,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bibliography_formatting(traj, env_info, task_info):
    """
    Verify that bibliography has been properly converted to APA 7th edition format.

    Checks:
    1. "References" heading exists and is centered
    2. Citations follow APA 7th edition format (author format, year in parens)
    3. Entries are alphabetically ordered by first author
    4. Hanging indent applied to entries
    5. Italicized text present in entries (journal/book titles)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/raw_citations.docx"
    success, doc, error, temp_dir = copy_and_parse_document(
        container_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        metadata = task_info.get('metadata', {})
        expected_count = metadata.get('citation_count', 10)
        expected_sorted = metadata.get('expected_first_authors_sorted', [])

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []

        # Criterion 1: "References" heading exists and is centered
        references_found = False
        references_centered = False
        for para in doc.paragraphs:
            text = para.text.strip().lower()
            if text == 'references':
                references_found = True
                if para.alignment is not None:
                    from docx.enum.text import WD_ALIGN_PARAGRAPH
                    references_centered = (para.alignment == WD_ALIGN_PARAGRAPH.CENTER)
                break

        if references_found and references_centered:
            criteria_passed += 1
            feedback_parts.append("'References' heading: present and centered")
        elif references_found:
            # Give partial credit - heading exists but not centered
            feedback_parts.append("'References' heading: present but not centered")
        else:
            feedback_parts.append("'References' heading: NOT found")

        # Criterion 2: Citations follow APA format (author format, year in parens)
        citations = extract_citation_paragraphs(doc, start_after="References")
        if not citations:
            # Try all substantial paragraphs if no References heading found
            citations = [p for p in doc.paragraphs if len(p.text.strip()) > 30]

        apa_valid_count = 0
        for para in citations:
            is_valid, _ = check_apa_citation_format(para.text.strip())
            if is_valid:
                apa_valid_count += 1

        if len(citations) > 0 and apa_valid_count >= len(citations) * 0.6:
            criteria_passed += 1
            feedback_parts.append(f"APA format valid: {apa_valid_count}/{len(citations)}")
        else:
            feedback_parts.append(
                f"APA format issues: only {apa_valid_count}/{len(citations)} follow APA style"
            )

        # Criterion 3: Alphabetical ordering
        is_sorted, first_words = check_alphabetical_order(doc, start_after="References")
        if is_sorted:
            criteria_passed += 1
            feedback_parts.append("Alphabetically ordered")
        else:
            # Also check without the "References" heading in case it wasn't added
            is_sorted_alt, _ = check_alphabetical_order(doc, start_after="")
            if is_sorted_alt:
                criteria_passed += 1
                feedback_parts.append("Alphabetically ordered (no heading detected)")
            else:
                order_str = " -> ".join(first_words[:5]) if first_words else "unknown"
                feedback_parts.append(f"NOT alphabetically ordered: {order_str}")

        # Criterion 4: Hanging indent applied
        hanging_count = 0
        for para in citations:
            if check_hanging_indent(para):
                hanging_count += 1

        if len(citations) > 0 and hanging_count >= len(citations) * 0.6:
            criteria_passed += 1
            feedback_parts.append(f"Hanging indent: {hanging_count}/{len(citations)}")
        else:
            feedback_parts.append(
                f"Hanging indent: only {hanging_count}/{len(citations)} entries"
            )

        # Criterion 5: Italics present in entries (journal/book titles)
        italic_count = 0
        for para in citations:
            if has_italicized_text(para):
                italic_count += 1

        if len(citations) > 0 and italic_count >= len(citations) * 0.5:
            criteria_passed += 1
            feedback_parts.append(f"Italics applied: {italic_count}/{len(citations)}")
        else:
            feedback_parts.append(
                f"Italics missing: only {italic_count}/{len(citations)} entries"
            )

        # Criterion 6: VLM cross-validation (visual check of final screenshot)
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this LibreOffice Writer screenshot. Answer in JSON:
{
    "has_references_heading": true/false,
    "entries_appear_formatted": true/false,
    "has_hanging_indent": true/false
}
Does the document show:
1. A centered "References" heading at the top?
2. Citation entries that appear consistently formatted (not messy/mixed styles)?
3. Entries with hanging indent (first line flush left, subsequent lines indented)?
""")
        if vlm_result is not None:
            has_heading = vlm_result.get("has_references_heading", False)
            entries_formatted = vlm_result.get("entries_appear_formatted", False)
            if has_heading and entries_formatted:
                criteria_passed += 1
                feedback_parts.append("VLM: bibliography formatting confirmed visually")
            else:
                feedback_parts.append("VLM: bibliography formatting not confirmed visually")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM: unavailable (skipped)")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80

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
