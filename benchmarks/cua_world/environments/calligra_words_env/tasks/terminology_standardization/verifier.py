#!/usr/bin/env python3
"""Verifier for the terminology_standardization task."""

import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_document_text_odt
)

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Process verification using framework-captured trajectory frames
TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent standardizing terminology in a document.

The agent needs to:
1. Open the terminology glossary text file on the Desktop to read the standard terms.
2. Use Find and Replace in Calligra Words to standardize terms.
3. Apply Heading styles to the document.

Assess:
1. GLOSSARY_READ: Did the agent open and view the terminology glossary file at any point?
2. FIND_AND_REPLACE: Is there evidence of the agent using the Find/Replace dialog, or actively editing terminology?
3. FORMATTING: Does the document appear visually structured with larger, bold headings by the end?

Respond in JSON format:
{
    "glossary_read": true/false,
    "find_and_replace_used": true/false,
    "formatting_applied": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


def verify_terminology_standardization(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/clinical_study_report.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        full_text = get_document_text_odt(content_tree)

        # ── 1. Drug Name (15 pts) ──
        drug_variants = ["nexapril XR", "Nexapril Extended Release", "NXP-XR", "nexapril-xr"]
        drug_correct = "Nexapril-XR"
        
        absent_count = sum(1 for v in drug_variants if v not in full_text)
        present_count = full_text.count(drug_correct)
        
        if absent_count == len(drug_variants) and present_count >= 3:
            score += 15
            feedback_parts.append("Drug name standardized")
        else:
            still_present = [v for v in drug_variants if v in full_text]
            feedback_parts.append(f"Drug name: {absent_count}/4 removed, {present_count} correct. Leftovers: {still_present}")

        # ── 2. Condition (15 pts) ──
        cond_variants = ["Type II Diabetes", "type-2 diabetes", "Type 2 Diabetes Mellitus", "T2D"]
        cond_correct = "type 2 diabetes mellitus"
        
        absent_count = sum(1 for v in cond_variants if v not in full_text)
        present_count = full_text.count(cond_correct)
        
        if absent_count == len(cond_variants) and present_count >= 3:
            score += 15
            feedback_parts.append("Condition standardized")
        else:
            still_present = [v for v in cond_variants if v in full_text]
            feedback_parts.append(f"Condition: {absent_count}/4 removed, {present_count} correct. Leftovers: {still_present}")

        # ── 3. Endpoint (15 pts) ──
        end_variants = ["hemoglobin A1c", "glycated hemoglobin", "A1C", "Hba1c"]
        end_correct = "HbA1c"
        
        absent_count = sum(1 for v in end_variants if v not in full_text)
        present_count = full_text.count(end_correct)
        
        if absent_count == len(end_variants) and present_count >= 2:
            score += 15
            feedback_parts.append("Endpoint standardized")
        else:
            still_present = [v for v in end_variants if v in full_text]
            feedback_parts.append(f"Endpoint: {absent_count}/4 removed, {present_count} correct. Leftovers: {still_present}")

        # ── 4. Comparator (10 pts) ──
        comp_variants = ["Metformin hydrochloride", "metformin HCl", "Metformin HCL"]
        comp_correct = "metformin hydrochloride"
        
        absent_count = sum(1 for v in comp_variants if v not in full_text)
        present_count = full_text.count(comp_correct)
        
        if absent_count == len(comp_variants) and present_count >= 2:
            score += 10
            feedback_parts.append("Comparator standardized")
        else:
            still_present = [v for v in comp_variants if v in full_text]
            feedback_parts.append(f"Comparator: {absent_count}/3 removed, {present_count} correct. Leftovers: {still_present}")

        # ── 5. Sponsor (10 pts) ──
        spon_variants = ["AcmePharma", "ACME Pharmaceuticals", "Acme Pharma Inc."]
        spon_correct = "Acme Pharmaceuticals, Inc."
        
        absent_count = sum(1 for v in spon_variants if v not in full_text)
        present_count = full_text.count(spon_correct)
        
        if absent_count == len(spon_variants) and present_count >= 2:
            score += 10
            feedback_parts.append("Sponsor standardized")
        else:
            still_present = [v for v in spon_variants if v in full_text]
            feedback_parts.append(f"Sponsor: {absent_count}/3 removed, {present_count} correct. Leftovers: {still_present}")

        # ── 6. H1 Sections (10 pts) ──
        expected_h1 = metadata.get("expected_h1_sections", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h1, 1)
        if h1_matched >= 6:
            score += 10
            feedback_parts.append(f"H1 headings: {h1_matched}/{h1_total} OK")
        else:
            feedback_parts.append(f"H1 headings: {h1_matched}/{h1_total} (need 6)")

        # ── 7. H2 Subsections (10 pts) ──
        expected_h2 = metadata.get("expected_h2_subsections", [])
        h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h2, 2)
        if h2_matched >= 5:
            score += 10
            feedback_parts.append(f"H2 headings: {h2_matched}/{h2_total} OK")
        else:
            feedback_parts.append(f"H2 headings: {h2_matched}/{h2_total} (need 5)")

        # ── 8. Content Preservation (10 pts) ──
        keywords = metadata.get("content_keywords", [])
        full_text_lower = full_text.lower()
        keyword_hits = sum(1 for kw in keywords if kw.lower() in full_text_lower)
        if keyword_hits >= 7:
            score += 10
            feedback_parts.append(f"Content preserved: {keyword_hits}/{len(keywords)}")
        else:
            feedback_parts.append(f"Content preservation failed: {keyword_hits}/{len(keywords)}")

        # ── 9. VLM Trajectory Verification (5 pts) ──
        vlm_score = 0
        query_vlm = env_info.get("query_vlm")
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            if frames and final:
                all_frames = frames + [final]
                parsed = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=all_frames)
                if parsed:
                    if parsed.get("glossary_read") and parsed.get("find_and_replace_used"):
                        vlm_score = 5
                        feedback_parts.append("VLM: Process verified")
                    else:
                        feedback_parts.append("VLM: Workflow missing key steps (glossary or find/replace)")
                else:
                    feedback_parts.append("VLM: Query failed")
            else:
                feedback_parts.append("VLM: No frames available")
        
        score += vlm_score

        # Check total points. To pass, they need 65.
        passed = score >= 65
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        cleanup_verification_temp(temp_dir)