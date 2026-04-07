#!/usr/bin/env python3
"""Verifier for the board_minutes_sanitization task."""

import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_paragraphs,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Approximate character count of the original unsanitized document.
# The setup script generates ~3 800 characters of visible text; we use a
# conservative baseline so minor edits don't cause a false negative.
ORIGINAL_CHAR_COUNT_BASELINE = 3400


def verify_board_minutes_sanitization(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/board_minutes_q4.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []

        full_text = get_document_text_odt(content_tree)
        full_text_lower = full_text.lower()

        # ── Criterion 1: Attorney-client privilege removed ──
        priv_phrases = [
            "60% probability of adverse outcome",
            "settling for $4.2 million",
        ]
        priv_absent = all(phrase.lower() not in full_text_lower for phrase in priv_phrases)
        if priv_absent:
            criteria_passed += 1
            feedback_parts.append("Attorney-client privilege: removed OK")
        else:
            still_present = [p for p in priv_phrases if p.lower() in full_text_lower]
            feedback_parts.append(
                f"Attorney-client privilege: still contains {still_present}"
            )

        # ── Criterion 2: Acquisition target redacted ──
        acq_phrases = [
            "CloudNest Systems",
            "$78 million acquisition",
        ]
        acq_absent = all(phrase.lower() not in full_text_lower for phrase in acq_phrases)
        if acq_absent:
            criteria_passed += 1
            feedback_parts.append("Acquisition target: redacted OK")
        else:
            still_present = [p for p in acq_phrases if p.lower() in full_text_lower]
            feedback_parts.append(
                f"Acquisition target: still contains {still_present}"
            )

        # ── Criterion 3: Executive compensation redacted ──
        comp_phrases = [
            "$875,000",
            "$1.2 million",
            "50,000 shares",
        ]
        comp_absent = all(phrase.lower() not in full_text_lower for phrase in comp_phrases)
        if comp_absent:
            criteria_passed += 1
            feedback_parts.append("Executive compensation: redacted OK")
        else:
            still_present = [p for p in comp_phrases if p.lower() in full_text_lower]
            feedback_parts.append(
                f"Executive compensation: still contains {still_present}"
            )

        # ── Criterion 4: Non-public projections removed ──
        proj_phrases = [
            "preliminary q4 revenue of $412 million",
            "$412 million",
        ]
        # Pass if the long phrase is absent; the short "$412 million" is checked
        # only as a secondary signal (it might appear in a redaction note).
        proj_absent = proj_phrases[0].lower() not in full_text_lower
        if proj_absent:
            criteria_passed += 1
            feedback_parts.append("Non-public projections: removed OK")
        else:
            feedback_parts.append(
                "Non-public projections: still contains preliminary revenue figure"
            )

        # ── Criterion 5: Code names replaced ──
        falcon_absent = "project falcon" not in full_text_lower
        analytics_present = "advanced analytics platform" in full_text_lower
        if falcon_absent and analytics_present:
            criteria_passed += 1
            feedback_parts.append("Code names: replaced OK")
        else:
            issues = []
            if not falcon_absent:
                issues.append("'Project Falcon' still present")
            if not analytics_present:
                issues.append("'Advanced Analytics Platform' missing")
            feedback_parts.append(f"Code names: {'; '.join(issues)}")

        # ── Criterion 6: Legitimate content preserved ──
        legitimate_phrases = metadata.get("legitimate_phrases_must_be_present", [
            "Board of Directors",
            "Meridian Technologies",
            "quarterly dividend of $0.35 per share",
            "2026 capital expenditure budget",
            "Chief Technology Officer",
            "Ernst & Young",
            "Annual Meeting of Shareholders",
            "cybersecurity improvements",
        ])
        legit_count = sum(
            1 for phrase in legitimate_phrases if phrase.lower() in full_text_lower
        )
        if legit_count >= 6:
            criteria_passed += 1
            feedback_parts.append(
                f"Legitimate content preserved: {legit_count}/{len(legitimate_phrases)} OK"
            )
        else:
            missing = [p for p in legitimate_phrases if p.lower() not in full_text_lower]
            feedback_parts.append(
                f"Legitimate content preserved: only {legit_count}/{len(legitimate_phrases)} "
                f"(need 6). Missing: {missing}"
            )

        # ── Criterion 7: Document structure preserved ──
        section_headings = metadata.get("section_headings", [
            "Call to Order",
            "Approval of Previous Minutes",
            "Financial Report",
            "Strategic Initiatives",
            "Legal and Compliance Update",
            "Human Resources and Compensation",
            "New Business",
            "Adjournment",
        ])
        paragraphs = get_odt_paragraphs(content_tree)
        headings_found = 0
        for heading in section_headings:
            for para in paragraphs:
                if heading.lower() in para['text'].lower().strip():
                    headings_found += 1
                    break

        if headings_found >= 6:
            criteria_passed += 1
            feedback_parts.append(
                f"Document structure preserved: {headings_found}/{len(section_headings)} headings OK"
            )
        else:
            feedback_parts.append(
                f"Document structure preserved: only {headings_found}/{len(section_headings)} "
                f"headings (need 6)"
            )

        # ── Criterion 8: Content volume gate ──
        current_length = len(full_text)
        min_length = int(ORIGINAL_CHAR_COUNT_BASELINE * 0.60)
        if current_length >= min_length:
            criteria_passed += 1
            pct = int((current_length / ORIGINAL_CHAR_COUNT_BASELINE) * 100)
            feedback_parts.append(
                f"Content volume: {current_length} chars (~{pct}% of baseline) OK"
            )
        else:
            pct = int((current_length / ORIGINAL_CHAR_COUNT_BASELINE) * 100)
            feedback_parts.append(
                f"Content volume: {current_length} chars (~{pct}% of baseline), "
                f"below 60% threshold — document may be over-redacted"
            )

        # ── Scoring ──
        score = int((criteria_passed / total_criteria) * 100) if total_criteria > 0 else 0
        passed = score >= 75

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
