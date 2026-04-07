#!/usr/bin/env python3
"""Verifier for the technical_manual_structuring task."""

import logging
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    detect_toc_odt,
    get_document_text_odt,
    get_odt_page_layout,
    get_odt_paragraphs,
    get_odt_styles,
    get_odt_tables,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_technical_manual_structuring(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/netwatch_manual.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        criteria_passed = 0
        total_criteria = 10
        feedback_parts = []

        # ── Criterion 1: H1 sections created (at least 6 of 8) ──
        expected_h1 = metadata.get("expected_h1_sections", [])
        h1_matched, h1_total, h1_details = check_heading_styles_odt(
            content_tree, styles_tree, expected_h1, 1,
        )
        if h1_matched >= 6:
            criteria_passed += 1
            feedback_parts.append(f"Heading 1: {h1_matched}/{h1_total} OK")
        else:
            feedback_parts.append(f"Heading 1: only {h1_matched}/{h1_total} (need 6)")

        # ── Criterion 2: H2 subsections created (at least 6 of 10) ──
        expected_h2 = metadata.get("expected_h2_subsections", [])
        h2_matched, h2_total, h2_details = check_heading_styles_odt(
            content_tree, styles_tree, expected_h2, 2,
        )
        if h2_matched >= 6:
            criteria_passed += 1
            feedback_parts.append(f"Heading 2: {h2_matched}/{h2_total} OK")
        else:
            feedback_parts.append(f"Heading 2: only {h2_matched}/{h2_total} (need 6)")

        # ── Criterion 3: Tables exist (at least 2) with expected keywords ──
        tables = get_odt_tables(content_tree)
        table_keywords = metadata.get("expected_tables_keywords", [])
        table_text = ""
        for tbl in tables:
            for row in tbl.get("rows", []):
                table_text += " ".join(row).lower() + " "

        keyword_hits = sum(1 for kw in table_keywords if kw.lower() in table_text)
        if len(tables) >= 2 and keyword_hits >= 3:
            criteria_passed += 1
            feedback_parts.append(
                f"Tables: {len(tables)} found, {keyword_hits}/{len(table_keywords)} keywords matched"
            )
        elif len(tables) >= 2:
            criteria_passed += 1
            feedback_parts.append(
                f"Tables: {len(tables)} found (keywords: {keyword_hits}/{len(table_keywords)})"
            )
        else:
            feedback_parts.append(
                f"Tables: only {len(tables)} found (need 2), "
                f"keywords: {keyword_hits}/{len(table_keywords)}"
            )

        # ── Criterion 4: Monospace/code formatting for commands ──
        expected_commands = metadata.get("expected_monospace_commands", [])
        paragraphs = get_odt_paragraphs(content_tree)
        styles = get_odt_styles(content_tree, styles_tree)

        monospace_fonts = {
            'courier', 'courier new', 'monospace', 'consolas',
            'liberation mono', 'dejavu sans mono', 'noto mono',
            'freemono', 'nimbus mono', 'nimbus mono l',
        }

        # Determine the most common body font to detect "different" fonts
        body_fonts = {}
        for para in paragraphs:
            if para['outline_level'] is None and len(para['text']) > 50:
                style_info = styles.get(para['style_name'], {})
                font = style_info.get('font_name', '')
                parent = style_info.get('parent', '')
                if not font and parent:
                    font = styles.get(parent, {}).get('font_name', '')
                if font:
                    body_fonts[font.lower()] = body_fonts.get(font.lower(), 0) + 1

        dominant_body_font = ''
        if body_fonts:
            dominant_body_font = max(body_fonts, key=body_fonts.get)

        monospace_count = 0
        for cmd in expected_commands:
            for para in paragraphs:
                if cmd.lower() in para['text'].lower():
                    # Check paragraph-level font
                    style_info = styles.get(para['style_name'], {})
                    font = style_info.get('font_name', '')
                    parent = style_info.get('parent', '')
                    if not font and parent:
                        font = styles.get(parent, {}).get('font_name', '')

                    if font and font.lower() in monospace_fonts:
                        monospace_count += 1
                        break

                    # Check inline spans for monospace font
                    elem = para.get('element')
                    if elem is not None:
                        ns_text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
                        for span in elem.iter(f'{{{ns_text}}}span'):
                            span_style_name = span.get(f'{{{ns_text}}}style-name', '')
                            span_style = styles.get(span_style_name, {})
                            span_font = span_style.get('font_name', '')
                            span_parent = span_style.get('parent', '')
                            if not span_font and span_parent:
                                span_font = styles.get(span_parent, {}).get('font_name', '')
                            if span_font and span_font.lower() in monospace_fonts:
                                monospace_count += 1
                                break
                        else:
                            # Also accept if the font is simply different from body text
                            if (font and dominant_body_font
                                    and font.lower() != dominant_body_font):
                                monospace_count += 1
                            continue
                        break  # span matched, move to next command
                    else:
                        if (font and dominant_body_font
                                and font.lower() != dominant_body_font):
                            monospace_count += 1
                    break

        if monospace_count >= 2:
            criteria_passed += 1
            feedback_parts.append(
                f"Monospace commands: {monospace_count}/{len(expected_commands)} OK"
            )
        else:
            feedback_parts.append(
                f"Monospace commands: only {monospace_count}/{len(expected_commands)} (need 2)"
            )

        # ── Criterion 5: Table of Contents present ──
        toc_present = detect_toc_odt(content_tree)
        if toc_present:
            criteria_passed += 1
            feedback_parts.append("Table of Contents: present")
        else:
            feedback_parts.append("Table of Contents: not found")

        # ── Criterion 6: Title formatted (bold, >=14pt) ──
        title_text = metadata.get("title_text", "NetWatch Pro v3.2")
        title_pattern = re.escape(title_text)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 14.0)

        if title_bold and title_sized:
            criteria_passed += 1
            feedback_parts.append("Title: bold and >=14pt OK")
        else:
            missing = []
            if not title_bold:
                missing.append("bold")
            if not title_sized:
                missing.append(">=14pt")
            feedback_parts.append(f"Title missing: {', '.join(missing)}")

        # ── Criterion 7: Body text justified (at least 2 of 3 samples) ──
        body_samples = metadata.get("body_alignment_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(
                content_tree, styles_tree, re.escape(sample), "justify",
            )
            if matched > 0:
                justified_count += 1

        if body_samples and justified_count >= 2:
            criteria_passed += 1
            feedback_parts.append(
                f"Body justified: {justified_count}/{len(body_samples)} OK"
            )
        else:
            feedback_parts.append(
                f"Body justified: only {justified_count}/{len(body_samples)} (need 2)"
            )

        # ── Criterion 8: Content preservation (at least 6 of 8 keywords) ──
        full_text = get_document_text_odt(content_tree).lower()
        content_keywords = metadata.get("content_keywords", [])
        preserved = sum(1 for kw in content_keywords if kw.lower() in full_text)

        if content_keywords and preserved >= 6:
            criteria_passed += 1
            feedback_parts.append(
                f"Content preserved: {preserved}/{len(content_keywords)} OK"
            )
        else:
            feedback_parts.append(
                f"Content preserved: only {preserved}/{len(content_keywords)} (need 6)"
            )

        # ── Criterion 9: Page layout set (margins defined) ──
        page_layout = get_odt_page_layout(styles_tree)
        margins_defined = False
        if page_layout:
            for layout_name, layout_props in page_layout.items():
                margin_values = [
                    layout_props.get('margin_top', ''),
                    layout_props.get('margin_bottom', ''),
                    layout_props.get('margin_left', ''),
                    layout_props.get('margin_right', ''),
                ]
                if any(v for v in margin_values):
                    margins_defined = True
                    break

        if margins_defined:
            criteria_passed += 1
            feedback_parts.append("Page layout: margins defined OK")
        else:
            feedback_parts.append("Page layout: no margins defined")

        # ── Criterion 10: VLM visual verification ──
        vlm_result = vlm_verify_screenshot(env_info, """
Analyze this Calligra Words screenshot of a technical manual and answer in JSON:
{
  "title_formatted": true/false,
  "headings_styled": true/false,
  "tables_visible": true/false,
  "professional_layout": true/false
}
- title_formatted: Is there a large, bold title visible?
- headings_styled: Are section headings visually distinct from body text (larger, bold)?
- tables_visible: Are any formatted tables visible in the document?
- professional_layout: Does the document look like a professionally structured technical manual?
Judge only what is visible on screen.
""")
        if vlm_result is not None:
            vlm_pass_count = sum(1 for k in (
                "title_formatted", "headings_styled", "tables_visible",
                "professional_layout",
            ) if vlm_result.get(k))
            if vlm_pass_count >= 3:
                criteria_passed += 1
                feedback_parts.append(
                    f"VLM: {vlm_pass_count}/4 visual checks passed"
                )
            else:
                feedback_parts.append(
                    f"VLM: only {vlm_pass_count}/4 visual checks passed"
                )
        else:
            total_criteria -= 1
            feedback_parts.append("VLM: unavailable, reducing total criteria")

        # ── Scoring ──
        score = int((criteria_passed / total_criteria) * 100) if total_criteria > 0 else 0
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
        }
    except Exception as exc:
        logger.error("Verification failed", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {exc}"}
    finally:
        cleanup_verification_temp(temp_dir)
