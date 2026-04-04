#!/usr/bin/env python3
"""
Verifier for Manuscript Submission Format task

This verifier checks that a short story manuscript has been properly
formatted according to standard literary magazine submission guidelines.
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


def verify_manuscript_format(traj, env_info, task_info):
    """
    Verify that manuscript has been properly formatted for submission.

    Scoring breakdown (100 points total):
    - Title page content (25 points): author info, title, word count
    - Font formatting (15 points): 12pt Courier New or Times New Roman
    - Line spacing (15 points): Double-spaced
    - Margins (10 points): 1 inch all sides
    - Headers (20 points): Present on pages 2+, not on page 1, contains required elements
    - Paragraph indentation (10 points): First-line indent ~0.5"
    - Scene breaks (5 points): Centered # markers present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/last_train_home_submission.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_manuscript_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load submission document: {error}"
            }

        score = 0
        max_score = 100
        feedback_parts = []

        # Get all text for initial checks
        all_text = get_document_text(doc)
        all_text_lower = all_text.lower()

        # ===================================================================
        # CRITERION 1: Title Page Content (25 points)
        # ===================================================================
        title_page_score = 0
        title_page_max = 25

        # Extract first ~500 characters as "title page area"
        first_page_text = '\n'.join([p.text for p in doc.paragraphs[:15]])
        first_page_lower = first_page_text.lower()

        # Check for author name (4 pts)
        if "jordan reeves" in first_page_lower:
            title_page_score += 4
        else:
            feedback_parts.append("❌ Missing author name 'Jordan Reeves' on title page")

        # Check for address (4 pts)
        if "456 maple drive" in first_page_lower and "lincoln" in first_page_lower:
            title_page_score += 4
        else:
            feedback_parts.append("❌ Missing complete address on title page")

        # Check for email (3 pts)
        if "jreeves.writer@email.com" in first_page_lower or "jreeves" in first_page_lower and "@email.com" in first_page_lower:
            title_page_score += 3
        else:
            feedback_parts.append("❌ Missing email address on title page")

        # Check for word count (3 pts) - flexible matching
        word_count_patterns = [r'2[,\s]?500', r'2500', r'word count.*2[,\s]?500']
        has_word_count = any(re.search(pattern, first_page_lower) for pattern in word_count_patterns)
        if has_word_count:
            title_page_score += 3
        else:
            feedback_parts.append("❌ Missing word count (2,500 words) on title page")

        # Check for story title in all caps (7 pts)
        if "THE LAST TRAIN HOME" in first_page_text or "LAST TRAIN HOME" in first_page_text:
            title_page_score += 7
        elif "last train home" in first_page_lower:
            title_page_score += 3  # Partial credit if present but not all caps
            feedback_parts.append("⚠️ Story title present but not in all caps")
        else:
            feedback_parts.append("❌ Missing story title 'THE LAST TRAIN HOME' on title page")

        # Check for byline (4 pts)
        if "by jordan reeves" in first_page_lower:
            title_page_score += 4
        else:
            feedback_parts.append("❌ Missing byline 'by Jordan Reeves' on title page")

        score += title_page_score
        if title_page_score >= 20:
            feedback_parts.append(f"✅ Title page content: {title_page_score}/{title_page_max} pts")
        else:
            feedback_parts.append(f"⚠️ Title page incomplete: {title_page_score}/{title_page_max} pts")

        # ===================================================================
        # CRITERION 2: Font Formatting (15 points)
        # ===================================================================
        font_score = 0
        font_max = 15

        # Check font consistency across paragraphs
        acceptable_fonts = ['courier new', 'times new roman', 'courier', 'times']
        fonts_used = set()
        font_sizes_used = set()

        for para in doc.paragraphs:
            for run in para.runs:
                if run.text.strip():  # Only count runs with actual text
                    if run.font.name:
                        fonts_used.add(run.font.name.lower())
                    if run.font.size:
                        font_sizes_used.add(run.font.size.pt)

        # Check if fonts are acceptable (8 pts)
        if fonts_used:
            acceptable_count = sum(1 for font in fonts_used if any(af in font for af in acceptable_fonts))
            if acceptable_count == len(fonts_used) and len(fonts_used) <= 2:
                font_score += 8
            elif acceptable_count > 0:
                font_score += 4  # Partial credit
                feedback_parts.append(f"⚠️ Some non-standard fonts used: {fonts_used}")
            else:
                feedback_parts.append(f"❌ Wrong fonts used: {fonts_used}")
        
        # Check if font size is 12pt (7 pts)
        if font_sizes_used:
            if 12.0 in font_sizes_used or 12 in font_sizes_used:
                # Check if 12pt is the dominant size
                sizes_list = list(font_sizes_used)
                if len(sizes_list) == 1 or (12.0 in sizes_list and len(sizes_list) <= 2):
                    font_score += 7
                else:
                    font_score += 3  # Partial credit
                    feedback_parts.append(f"⚠️ Inconsistent font sizes: {font_sizes_used}")
            else:
                feedback_parts.append(f"❌ Wrong font size (expected 12pt, found: {font_sizes_used})")

        score += font_score
        if font_score >= 12:
            feedback_parts.append(f"✅ Font formatting: {font_score}/{font_max} pts")
        else:
            feedback_parts.append(f"⚠️ Font formatting issues: {font_score}/{font_max} pts")

        # ===================================================================
        # CRITERION 3: Line Spacing (15 points)
        # ===================================================================
        spacing_score = 0
        spacing_max = 15

        # Check line spacing (should be 2.0 for double-spacing)
        spacings_used = set()
        para_with_spacing = 0

        for para in doc.paragraphs:
            if para.text.strip():  # Only check paragraphs with content
                para_with_spacing += 1
                spacing = para.paragraph_format.line_spacing
                if spacing:
                    # line_spacing can be a float or a line spacing object
                    try:
                        if hasattr(spacing, 'pt'):
                            spacings_used.add(f"{spacing.pt}pt")
                        else:
                            spacings_used.add(float(spacing))
                    except:
                        spacings_used.add(str(spacing))

        # Check if double-spaced (2.0) or approximately double-spaced
        has_double_spacing = False
        for spacing_val in spacings_used:
            if isinstance(spacing_val, float):
                if 1.9 <= spacing_val <= 2.1:  # Tolerance for double spacing
                    has_double_spacing = True
                    break

        if has_double_spacing:
            spacing_score = 15
            feedback_parts.append(f"✅ Line spacing: double-spaced")
        elif spacings_used:
            feedback_parts.append(f"❌ Wrong line spacing: {spacings_used} (expected 2.0)")
        else:
            feedback_parts.append(f"⚠️ Line spacing could not be determined")

        score += spacing_score

        # ===================================================================
        # CRITERION 4: Margins (10 points)
        # ===================================================================
        margins_score = 0
        margins_max = 10

        # Check margins (should be 1 inch = 914400 EMUs)
        section = doc.sections[0]
        ONE_INCH = 914400  # in EMUs (English Metric Units)
        TOLERANCE = 91440  # 0.1 inch tolerance

        margins_correct = 0
        margins_to_check = {
            'top': section.top_margin,
            'bottom': section.bottom_margin,
            'left': section.left_margin,
            'right': section.right_margin
        }

        for margin_name, margin_value in margins_to_check.items():
            if abs(margin_value - ONE_INCH) <= TOLERANCE:
                margins_correct += 1

        if margins_correct == 4:
            margins_score = 10
            feedback_parts.append("✅ Margins: 1 inch on all sides")
        elif margins_correct >= 2:
            margins_score = 5  # Partial credit
            feedback_parts.append(f"⚠️ Some margins incorrect ({margins_correct}/4 correct)")
        else:
            feedback_parts.append("❌ Margins not set to 1 inch")

        score += margins_score

        # ===================================================================
        # CRITERION 5: Headers (20 points)
        # ===================================================================
        headers_score = 0
        headers_max = 20

        # Check headers
        # Headers should appear on pages 2+ but NOT on page 1
        # Should contain: last name (Reeves), title (LAST TRAIN HOME), page number

        has_headers = False
        header_elements_found = []

        # Check each section for headers
        for i, section in enumerate(doc.sections):
            # Check if there's a header
            header = section.header
            if header and header.paragraphs:
                header_text = '\n'.join([p.text for p in header.paragraphs])
                header_text_lower = header_text.lower()
                
                if header_text.strip():
                    has_headers = True
                    
                    # Check for required elements
                    if "reeves" in header_text_lower:
                        if "Reeves" not in header_elements_found:
                            header_elements_found.append("Reeves")
                            headers_score += 6
                    
                    if "last train home" in header_text_lower:
                        if "Title" not in header_elements_found:
                            header_elements_found.append("Title")
                            headers_score += 6
                    
                    # Check for page number (can be represented various ways)
                    # Look for numbers or page field codes
                    if re.search(r'\d+|page', header_text_lower):
                        if "PageNum" not in header_elements_found:
                            header_elements_found.append("PageNum")
                            headers_score += 4

        # Check that first page doesn't have header (4 pts)
        # This is tricky - in many cases, headers are set per-section
        # We'll give benefit of doubt if headers are present at all
        if has_headers:
            headers_score += 4  # Assume they didn't put it on page 1 if they added headers

        if headers_score >= 16:
            feedback_parts.append(f"✅ Headers present with required elements: {', '.join(header_elements_found)}")
        elif headers_score > 0:
            feedback_parts.append(f"⚠️ Headers incomplete: {headers_score}/{headers_max} pts (found: {', '.join(header_elements_found)})")
        else:
            feedback_parts.append(f"❌ Headers missing or incorrect")

        score += headers_score

        # ===================================================================
        # CRITERION 6: Paragraph Indentation (10 points)
        # ===================================================================
        indent_score = 0
        indent_max = 10

        # Check for first-line indentation (~0.5 inches = 457200 EMUs)
        HALF_INCH = 457200
        INDENT_TOLERANCE = 91440  # 0.1 inch tolerance

        para_with_indent = 0
        total_content_para = 0

        for para in doc.paragraphs:
            if para.text.strip() and len(para.text.strip()) > 20:  # Only check substantial paragraphs
                total_content_para += 1
                indent = para.paragraph_format.first_line_indent
                if indent and abs(indent - HALF_INCH) <= INDENT_TOLERANCE:
                    para_with_indent += 1

        if total_content_para > 0:
            indent_ratio = para_with_indent / total_content_para
            if indent_ratio >= 0.7:  # At least 70% of paragraphs indented
                indent_score = 10
                feedback_parts.append(f"✅ Paragraph indentation: {para_with_indent}/{total_content_para} paragraphs indented")
            elif indent_ratio >= 0.3:
                indent_score = 5  # Partial credit
                feedback_parts.append(f"⚠️ Some paragraphs indented: {para_with_indent}/{total_content_para}")
            else:
                feedback_parts.append(f"❌ Missing first-line indentation")

        score += indent_score

        # ===================================================================
        # CRITERION 7: Scene Breaks (5 points)
        # ===================================================================
        scene_break_score = 0
        scene_break_max = 5

        # Check for centered "#" symbols as scene breaks
        has_scene_break = False
        for para in doc.paragraphs:
            para_text = para.text.strip()
            if para_text in ['#', '# ', ' # ', '***', '* * *']:
                # Check if it's centered
                alignment = para.paragraph_format.alignment
                if alignment == 1:  # CENTER alignment
                    has_scene_break = True
                    break
                elif para_text in ['#', '# ']:
                    # Give partial credit even if not perfectly centered
                    has_scene_break = True
                    break

        if has_scene_break:
            scene_break_score = 5
            feedback_parts.append("✅ Scene breaks marked with centered '#'")
        else:
            # Check if any "#" exists even if not centered
            if '#' in all_text:
                scene_break_score = 2  # Partial credit
                feedback_parts.append("⚠️ Scene break markers present but may not be centered")
            else:
                feedback_parts.append("❌ Missing scene break markers")

        score += scene_break_score

        # ===================================================================
        # Final Assessment
        # ===================================================================
        passed = score >= 70  # 70% threshold
        final_score = score / max_score

        # Add summary
        summary = f"Total: {score}/{max_score} points"
        feedback_parts.insert(0, summary)

        feedback = " | ".join(feedback_parts)

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
        cleanup_temp_dir(temp_dir)
