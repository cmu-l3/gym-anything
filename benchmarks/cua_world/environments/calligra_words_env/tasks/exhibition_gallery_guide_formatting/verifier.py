#!/usr/bin/env python3
"""Verifier for the exhibition_gallery_guide_formatting task."""

import logging
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_italic_odt,
    check_text_font_size_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_odt_tables,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exhibition_gallery_guide_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/gallery_guide_draft.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []

        # ── Criterion 1: Title formatting (10 pts) ──
        title_text = "The Impressionist Revolution: Gallery Guide"
        title_pattern = re.escape(title_text)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 16.0)
        title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, title_pattern, "center")

        if title_bold and title_sized and title_centered > 0:
            score += 10
            feedback_parts.append("Title: properly formatted (10/10)")
        else:
            missing = []
            if not title_bold: missing.append("bold")
            if not title_sized: missing.append(">=16pt")
            if title_centered == 0: missing.append("centered")
            feedback_parts.append(f"Title missing: {', '.join(missing)} (0/10)")

        # ── Criterion 2: Room Headings (15 pts) ──
        room_headings = metadata.get("room_headings", [
            "Room 1: The Origins",
            "Room 2: The First Exhibition",
            "Room 3: Everyday Life",
            "Room 4: The Bridge to Post-Impressionism"
        ])
        h1_matched, h1_total, _ = check_heading_styles_odt(
            content_tree, styles_tree, room_headings, 1
        )
        if h1_matched >= 3:
            score += 15
            feedback_parts.append(f"Room Headings: {h1_matched}/{h1_total} OK (15/15)")
        else:
            partial_h1 = int((h1_matched / len(room_headings)) * 15)
            score += partial_h1
            feedback_parts.append(f"Room Headings: {h1_matched}/{h1_total} ({partial_h1}/15)")

        # ── Criterion 3: Artist Names Bolded (20 pts) ──
        artists = metadata.get("artists", [
            "Édouard Manet", "Claude Monet", "Edgar Degas", 
            "Pierre-Auguste Renoir", "Paul Cézanne"
        ])
        bolded_artists = 0
        for artist in artists:
            if check_text_bold_odt(content_tree, styles_tree, re.escape(artist)):
                bolded_artists += 1
        
        artist_score = bolded_artists * 4
        score += artist_score
        feedback_parts.append(f"Artist Names Bolded: {bolded_artists}/{len(artists)} ({artist_score}/20)")

        # ── Criterion 4: Artwork Titles Italicized (20 pts) ──
        artworks = metadata.get("artworks", [
            "The Luncheon on the Grass", "Impression Sunrise", 
            "The Dancing Class", "Dance at Le Moulin de la Galette", 
            "Mont Sainte-Victoire"
        ])
        italic_artworks = 0
        for artwork in artworks:
            if check_text_italic_odt(content_tree, styles_tree, re.escape(artwork)):
                italic_artworks += 1
        
        artwork_score = italic_artworks * 4
        score += artwork_score
        feedback_parts.append(f"Artwork Titles Italicized: {italic_artworks}/{len(artworks)} ({artwork_score}/20)")

        # ── Criterion 5: Anti-Gaming / No Over-Formatting (15 pts) ──
        anti_gaming_phrases = metadata.get("anti_gaming_phrases", [
            "Manet's large canvas was rejected",
            "depicting the port of Le Havre",
            "focused extensively on the world of ballet",
            "masterfully captured the dappled sunlight",
            "geometric approach to the landscape"
        ])
        
        over_formatted = False
        for phrase in anti_gaming_phrases:
            pattern = re.escape(phrase)
            if check_text_bold_odt(content_tree, styles_tree, pattern) or check_text_italic_odt(content_tree, styles_tree, pattern):
                over_formatted = True
                break
        
        if not over_formatted:
            score += 15
            feedback_parts.append("Anti-gaming: Descriptions are standard text (15/15)")
        else:
            feedback_parts.append("Anti-gaming FAILED: General text was improperly bolded/italicized (0/15)")

        # ── Criterion 6: Inventory Table (20 pts) ──
        tables = get_odt_tables(content_tree)
        table_found = False
        for tbl in tables:
            rows = tbl.get("rows", [])
            if len(rows) >= 5:
                # Check column count
                if all(len(row) >= 3 for row in rows[:3]):
                    text_dump = " ".join([" ".join(cell for cell in r) for r in rows]).lower()
                    if "cézanne" in text_dump and "manet" in text_dump and "1872" in text_dump:
                        table_found = True
                        break
        
        if table_found:
            score += 20
            feedback_parts.append("Inventory Table: Correct structure and content found (20/20)")
        else:
            feedback_parts.append("Inventory Table: Not found or incorrectly structured (0/20)")

        # Final Evaluation
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with exception: {e}"}
    finally:
        cleanup_verification_temp(temp_dir)