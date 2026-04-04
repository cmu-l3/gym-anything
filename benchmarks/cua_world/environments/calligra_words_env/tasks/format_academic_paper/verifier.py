#!/usr/bin/env python3
"""Verifier for format_academic_paper."""

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../utils"))
from calligra_verification_utils import (  # type: ignore
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_italic_odt,
    cleanup_verification_temp,
    copy_and_parse_odt,
)


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/format_academic_paper_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def verify_format_academic_paper(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {exc}"}

    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output document not found."}
    if not result.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Document was not saved during the task session."}

    temp_dir = None
    try:
        temp_dir, content_tree, styles_tree = copy_and_parse_odt(
            copy_from_env, "/home/ga/Documents/origin_of_species.odt"
        )
        if content_tree is None:
            return {"passed": False, "score": 0, "feedback": "Failed to parse output ODT document."}

        metadata = task_info.get("metadata", {})
        sections = metadata.get(
            "section_headings",
            [
                "Variation Under Domestication",
                "Variation Under Nature",
                "Struggle for Existence",
                "Natural Selection",
            ],
        )
        subsections = metadata.get(
            "subsection_headings",
            [
                "Causes of Variability",
                "Effects of Habit and Use",
                "Geometrical Ratio of Increase",
                "Complex Relations of All Animals",
            ],
        )

        score = 0
        feedback = []

        title_centered, _ = check_paragraph_alignment_odt(
            content_tree, styles_tree, r"On the Origin of Species", "center"
        )
        title_bold = check_text_bold_odt(content_tree, styles_tree, r"On the Origin of Species")
        if title_centered and title_bold:
            score += 20
            feedback.append("Title is centered and bold.")
        else:
            feedback.append("Title formatting is incomplete.")

        author_centered, _ = check_paragraph_alignment_odt(
            content_tree, styles_tree, r"Charles Darwin", "center"
        )
        author_italic = check_text_italic_odt(content_tree, styles_tree, r"Charles Darwin")
        if author_centered and author_italic:
            score += 15
            feedback.append("Author line is centered and italic.")
        else:
            feedback.append("Author line formatting is incomplete.")

        section_matches, section_total, _ = check_heading_styles_odt(
            content_tree, styles_tree, sections, 1
        )
        if section_matches == section_total:
            score += 20
            feedback.append("All section headings use Heading 1.")
        elif section_matches:
            partial = int(20 * section_matches / section_total)
            score += partial
            feedback.append(f"{section_matches}/{section_total} section headings use Heading 1.")
        else:
            feedback.append("Section headings do not use Heading 1.")

        subsection_matches, subsection_total, _ = check_heading_styles_odt(
            content_tree, styles_tree, subsections, 2
        )
        if subsection_matches == subsection_total:
            score += 20
            feedback.append("All subsection headings use Heading 2.")
        elif subsection_matches:
            partial = int(20 * subsection_matches / subsection_total)
            score += partial
            feedback.append(
                f"{subsection_matches}/{subsection_total} subsection headings use Heading 2."
            )
        else:
            feedback.append("Subsection headings do not use Heading 2.")

        body_checks = [
            r"Domesticated animals and cultivated plants display",
            r"Natural populations vary from place to place",
            r"Because more individuals are born than can survive",
            r"If profitable variations occur",
        ]
        justified = 0
        for pattern in body_checks:
            matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, pattern, "justify")
            if matched:
                justified += 1
        if justified >= 3:
            score += 25
            feedback.append(f"Body paragraphs are justified ({justified}/{len(body_checks)} checks).")
        elif justified:
            partial = int(25 * justified / len(body_checks))
            score += partial
            feedback.append(
                f"Body paragraph justification partial ({justified}/{len(body_checks)} checks)."
            )
        else:
            feedback.append("Body paragraphs are not justified.")

        passed = score >= 70
        return {"passed": passed, "score": score, "feedback": " ".join(feedback)}
    finally:
        cleanup_verification_temp(temp_dir)
