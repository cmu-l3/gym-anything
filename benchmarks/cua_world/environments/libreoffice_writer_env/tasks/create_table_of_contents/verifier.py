#!/usr/bin/env python3
"""Verifier for create_table_of_contents task."""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_heading_styles,
    detect_toc_present,
    count_headings_by_level,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_table_of_contents(traj, env_info, task_info):
    """
    Verify that:
    1. Chapter titles have Heading 1 style (4 chapters)
    2. Section headers have Heading 2 style (8 sections)
    3. Table of Contents is present
    4. Original text content is preserved
    5. TOC placed near beginning of document (within first 10 paragraphs)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/origin_of_species_excerpt.docx"
    success, doc, error, temp_dir = copy_and_parse_document(
        container_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        metadata = task_info.get('metadata', {})
        chapter_titles = metadata.get('chapter_titles', [])
        section_headers = metadata.get('section_headers', [])

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []

        # Criterion 1: Chapter titles have Heading 1 style
        chapter_headings = {title: 'Heading 1' for title in chapter_titles}
        h1_matched, h1_total, h1_feedback = check_heading_styles(doc, chapter_headings)

        if h1_matched >= 3:  # At least 3 of 4 chapters
            criteria_passed += 1
            feedback_parts.append(f"Chapter headings: {h1_matched}/{h1_total} correct")
        else:
            feedback_parts.append(
                f"Chapter headings: only {h1_matched}/{h1_total} have Heading 1 style"
            )

        # Criterion 2: Section headers have Heading 2 style
        section_heading_map = {header: 'Heading 2' for header in section_headers}
        h2_matched, h2_total, h2_feedback = check_heading_styles(doc, section_heading_map)

        if h2_matched >= 6:  # At least 6 of 8 sections
            criteria_passed += 1
            feedback_parts.append(f"Section headings: {h2_matched}/{h2_total} correct")
        else:
            feedback_parts.append(
                f"Section headings: only {h2_matched}/{h2_total} have Heading 2 style"
            )

        # Criterion 3: Table of Contents present
        toc_present = detect_toc_present(doc)
        if toc_present:
            criteria_passed += 1
            feedback_parts.append("Table of Contents detected")
        else:
            feedback_parts.append("Table of Contents NOT detected")

        # Criterion 4: Original text content preserved
        full_text = get_document_text(doc).lower()
        key_phrases = [
            "cultivated plants and animals",
            "individual differences",
            "struggle for existence",
            "natural selection",
        ]
        preserved = sum(1 for phrase in key_phrases if phrase in full_text)
        if preserved >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Content preserved: {preserved}/{len(key_phrases)} key phrases")
        else:
            feedback_parts.append(f"Content may be corrupted: only {preserved}/{len(key_phrases)} key phrases found")

        # Criterion 5: TOC is placed near the beginning of the document
        toc_near_start = False
        for idx, para in enumerate(doc.paragraphs[:15]):
            text_lower = para.text.strip().lower()
            # Check for TOC heading or TOC-style paragraphs near the start
            if text_lower in ('table of contents', 'contents'):
                toc_near_start = True
                break
            # Check for TOC style name
            if para.style and 'toc' in para.style.name.lower():
                toc_near_start = True
                break
            # Check XML for TOC field near start
            xml_str = para._element.xml
            if 'TOC' in xml_str and ('w:fldChar' in xml_str or 'w:instrText' in xml_str):
                toc_near_start = True
                break
        if toc_near_start:
            criteria_passed += 1
            feedback_parts.append("TOC placed near beginning of document")
        else:
            feedback_parts.append("TOC not found near beginning of document")

        # Criterion 6: VLM cross-validation (visual check of final screenshot)
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this LibreOffice Writer screenshot. Answer in JSON:
{
    "has_toc": true/false,
    "has_styled_headings": true/false,
    "document_has_structure": true/false
}
Does the document show:
1. A visible Table of Contents section (list of chapter names with page numbers)?
2. Styled headings (larger/bold text for chapter or section titles)?
3. Overall document structure (not just plain unstyled text)?
""")
        if vlm_result is not None:
            has_toc = vlm_result.get("has_toc", False)
            has_headings = vlm_result.get("has_styled_headings", False)
            has_structure = vlm_result.get("document_has_structure", False)
            if has_toc or (has_headings and has_structure):
                criteria_passed += 1
                feedback_parts.append("VLM: document structure confirmed visually")
            else:
                feedback_parts.append("VLM: document structure not confirmed visually")
        else:
            # VLM unavailable — don't penalize, adjust total
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
