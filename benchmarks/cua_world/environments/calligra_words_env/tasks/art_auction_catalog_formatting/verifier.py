#!/usr/bin/env python3
"""Verifier for the art_auction_catalog_formatting task."""

import logging
import os
import re
import sys
import json
import tempfile

# Prepend the path where calligra_verification_utils is located
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from calligra_verification_utils import (
        check_heading_styles_odt,
        check_paragraph_alignment_odt,
        check_text_bold_odt,
        check_text_italic_odt,
        check_text_font_size_odt,
        copy_and_parse_document,
    )
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_art_auction_catalog_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/auction_inventory.odt")

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        # ── 1. Anti-Gaming Gate (10 pts) ──
        anti_gaming_passed = True
        
        # Check if plain body text ("Oil on canvas") was improperly bolded/italicized
        if check_text_bold_odt(content_tree, styles_tree, "Oil on canvas") or \
           check_text_italic_odt(content_tree, styles_tree, "Oil on canvas"):
            anti_gaming_passed = False
            feedback_parts.append("Anti-Gaming FAIL: Non-target text ('Oil on canvas') was improperly bolded/italicized.")
            
        # Check if normal paragraph was erroneously right-aligned
        align_end, _ = check_paragraph_alignment_odt(content_tree, styles_tree, "The following conditions of sale", "end")
        align_right, _ = check_paragraph_alignment_odt(content_tree, styles_tree, "The following conditions of sale", "right")
        if (align_end + align_right) > 0:
            anti_gaming_passed = False
            feedback_parts.append("Anti-Gaming FAIL: Standard body paragraph was right-aligned.")

        if anti_gaming_passed:
            score += 10
            feedback_parts.append("Anti-Gaming: Passed")

        # ── 2. Title Formatting (10 pts) ──
        title_text = "Impressionist & Modern Art Evening Sale"
        title_bold = check_text_bold_odt(content_tree, styles_tree, re.escape(title_text))
        title_sized = check_text_font_size_odt(content_tree, styles_tree, re.escape(title_text), 18.0)
        
        align_end, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(title_text), "center")
        title_centered = align_end > 0

        if title_bold and title_sized and title_centered:
            score += 10
            feedback_parts.append("Title Formatting: Perfect")
        elif title_bold or title_centered:
            score += 5
            feedback_parts.append("Title Formatting: Partial")
        else:
            feedback_parts.append("Title Formatting: Failed")

        # ── 3. H1 Sections (10 pts) ──
        h1_sections = ["Conditions of Sale", "Auction Information"]
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, h1_sections, 1)
        if h1_matched == 2:
            score += 10
            feedback_parts.append("H1 Sections: 2/2 OK")
        elif h1_matched == 1:
            score += 5
            feedback_parts.append("H1 Sections: 1/2 OK")
        else:
            feedback_parts.append("H1 Sections: 0/2 OK")

        # ── 4. H2 Lot Numbers (20 pts) ──
        lots = [f"LOT {i}" for i in range(1, 16)]
        h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, lots, 2)
        if h2_matched >= 12:
            score += 20
            feedback_parts.append(f"H2 Lots: {h2_matched}/15 OK")
        elif h2_matched >= 5:
            score += 10
            feedback_parts.append(f"H2 Lots: {h2_matched}/15 OK (Partial)")
        else:
            feedback_parts.append(f"H2 Lots: {h2_matched}/15 (Failed)")

        # ── 5. Bold Artist Names (15 pts) ──
        expected_artists = metadata.get("expected_artists", [])
        bold_artist_count = sum(1 for a in expected_artists if check_text_bold_odt(content_tree, styles_tree, re.escape(a)))
        if bold_artist_count >= 12:
            score += 15
            feedback_parts.append(f"Bold Artists: {bold_artist_count}/15 OK")
        elif bold_artist_count >= 5:
            score += 7
            feedback_parts.append(f"Bold Artists: {bold_artist_count}/15 OK (Partial)")
        else:
            feedback_parts.append(f"Bold Artists: {bold_artist_count}/15 (Failed)")

        # ── 6. Italic Art Titles (15 pts) ──
        expected_titles = metadata.get("expected_titles", [])
        italic_title_count = sum(1 for t in expected_titles if check_text_italic_odt(content_tree, styles_tree, re.escape(t)))
        if italic_title_count >= 12:
            score += 15
            feedback_parts.append(f"Italic Titles: {italic_title_count}/15 OK")
        elif italic_title_count >= 5:
            score += 7
            feedback_parts.append(f"Italic Titles: {italic_title_count}/15 OK (Partial)")
        else:
            feedback_parts.append(f"Italic Titles: {italic_title_count}/15 (Failed)")

        # ── 7. Right-Aligned Estimates (15 pts) ──
        align_end, _ = check_paragraph_alignment_odt(content_tree, styles_tree, "Estimate: ", "end")
        align_right, _ = check_paragraph_alignment_odt(content_tree, styles_tree, "Estimate: ", "right")
        aligned_estimates = align_end + align_right
        
        if aligned_estimates >= 12:
            score += 15
            feedback_parts.append(f"Right-Aligned Estimates: {aligned_estimates}/15 OK")
        elif aligned_estimates >= 5:
            score += 7
            feedback_parts.append(f"Right-Aligned Estimates: {aligned_estimates}/15 OK (Partial)")
        else:
            feedback_parts.append(f"Right-Aligned Estimates: {aligned_estimates}/15 (Failed)")

        # ── 8. Inline Bold Prefixes (5 pts) ──
        prefixes = ["Provenance:", "Exhibited:", "Literature:"]
        prefixes_bolded = sum(1 for p in prefixes if check_text_bold_odt(content_tree, styles_tree, re.escape(p)))
        if prefixes_bolded == 3:
            score += 5
            feedback_parts.append("Inline Prefixes: 3/3 OK")
        elif prefixes_bolded > 0:
            score += 2
            feedback_parts.append(f"Inline Prefixes: {prefixes_bolded}/3 OK")
        else:
            feedback_parts.append("Inline Prefixes: 0/3 (Failed)")

        # Final Evaluation
        passed = score >= 75 and anti_gaming_passed
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}