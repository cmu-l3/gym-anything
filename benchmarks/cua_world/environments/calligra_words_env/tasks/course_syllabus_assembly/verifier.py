#!/usr/bin/env python3
"""Verifier for the course_syllabus_assembly task."""

import logging
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_tables,
)

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_course_syllabus_assembly(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/cs3301_syllabus.odt")

    # Anti-gaming timestamp check
    try:
        temp_time = tempfile.NamedTemporaryFile(delete=False)
        temp_time.close()
        copy_from_env("/tmp/task_start_time.txt", temp_time.name)
        with open(temp_time.name, 'r') as f:
            start_time = int(f.read().strip())
        os.unlink(temp_time.name)
    except Exception as e:
        logger.warning(f"Could not read start time: {e}")
        start_time = 0

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        # Check text preservation to avoid deletion gaming
        full_text = get_document_text_odt(content_tree)
        content_keywords = metadata.get("content_keywords", [])
        keyword_hits = sum(1 for kw in content_keywords if kw.lower() in full_text.lower())
        if keyword_hits >= 7:
            score += 10
            feedback_parts.append(f"Content preservation: {keyword_hits}/{len(content_keywords)} OK")
        else:
            feedback_parts.append(f"Content missing: only {keyword_hits}/{len(content_keywords)} found")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
            
        # ── 1. Title formatting (10 pts) ──
        expected_title = metadata.get("expected_title", "CS 3301: Data Structures and Algorithms")
        title_pattern = re.escape(expected_title)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 14.0)

        if title_bold and title_sized:
            score += 10
            feedback_parts.append("Title: bold and >=14pt OK")
        else:
            missing = []
            if not title_bold: missing.append("bold")
            if not title_sized: missing.append(">=14pt")
            feedback_parts.append(f"Title missing: {', '.join(missing)}")

        # ── 2. H1 section headings (15 pts) ──
        expected_h1 = metadata.get("expected_h1_sections", [])
        h1_matched, h1_total, h1_details = check_heading_styles_odt(
            content_tree, styles_tree, expected_h1, 1,
        )
        if h1_matched >= 5:
            score += 15
            feedback_parts.append(f"Heading 1: {h1_matched}/{h1_total} OK")
        else:
            score += (h1_matched * 2)
            feedback_parts.append(f"Heading 1: only {h1_matched}/{h1_total} (need 5)")

        # ── 3. H2 subsection headings (8 pts) ──
        expected_h2 = metadata.get("expected_h2_subsections", [])
        h2_matched, h2_total, h2_details = check_heading_styles_odt(
            content_tree, styles_tree, expected_h2, 2,
        )
        if h2_matched >= 3:
            score += 8
            feedback_parts.append(f"Heading 2: {h2_matched}/{h2_total} OK")
        else:
            score += (h2_matched * 2)
            feedback_parts.append(f"Heading 2: only {h2_matched}/{h2_total} (need 3)")

        # ── 4. Table creation (course info, schedule, grading) ──
        tables = get_odt_tables(content_tree)
        num_tables = len(tables)
        max_rows = max([len(t.get("rows", [])) for t in tables]) if tables else 0
        
        # We need 3 tables total.
        # Course info (12 pts)
        if num_tables >= 1:
            score += 12
            feedback_parts.append(f"Table 1 (Course Info): Created")
        else:
            feedback_parts.append("Tables: No tables found")
            
        # Schedule table (15 pts)
        if num_tables >= 2 and max_rows >= 12:
            score += 15
            feedback_parts.append(f"Table 2 (Schedule): Created with {max_rows} rows")
        elif num_tables >= 2:
            score += 7
            feedback_parts.append(f"Table 2 (Schedule): Created but only {max_rows} rows")
            
        # Grading table (10 pts)
        if num_tables >= 3:
            score += 10
            feedback_parts.append(f"Table 3 (Grading): Created")
            
        # ── 5. Body alignment (5 pts) ──
        body_samples = metadata.get("body_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(
                content_tree, styles_tree, re.escape(sample), "justify",
            )
            if matched > 0:
                justified_count += 1

        if body_samples and justified_count >= 2:
            score += 5
            feedback_parts.append(f"Body justified: {justified_count}/{len(body_samples)} OK")
        else:
            feedback_parts.append(f"Body justified: only {justified_count}/{len(body_samples)}")

        # ── 6. Body font size (5 pts) ──
        font_size_ok = 0
        for sample in body_samples:
            sized = check_text_font_size_odt(
                content_tree, styles_tree, re.escape(sample), 11.0,
            )
            if sized:
                font_size_ok += 1

        if body_samples and font_size_ok >= 2:
            score += 5
            feedback_parts.append(f"Body font size: {font_size_ok}/{len(body_samples)} >= 11pt OK")
        else:
            feedback_parts.append(f"Body font size: only {font_size_ok}/{len(body_samples)}")

        # ── 7. VLM verification (10 pts) ──
        query_vlm = env_info.get("query_vlm")
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are evaluating an agent's formatting of a course syllabus document in Calligra Words.
            The agent was instructed to apply heading styles to sections, convert text to tables, and format the text.
            
            Review the screenshots across the trajectory and the final document state.
            Are there clear visible tables in the document? Is there a heading hierarchy?
            Does the document look like a structured syllabus rather than just a block of text?
            
            Respond ONLY with a valid JSON object matching this schema:
            {
                "formatted_well": true
            }
            """
            
            try:
                vlm_res = query_vlm(images=images, prompt=prompt)
                if vlm_res.get("success") and vlm_res.get("parsed", {}).get("formatted_well", False):
                    score += 10
                    feedback_parts.append("VLM visual verification: passed")
                else:
                    feedback_parts.append("VLM visual verification: failed or no clear formatting")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback_parts.append("VLM visual verification: exception")

        passed = score >= 60
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    except Exception as e:
        logger.exception("Error during verification")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {e}"
        }
    finally:
        cleanup_verification_temp(temp_dir)