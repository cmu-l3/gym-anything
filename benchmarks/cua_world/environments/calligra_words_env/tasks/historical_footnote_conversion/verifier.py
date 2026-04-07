#!/usr/bin/env python3
"""Verifier for historical_footnote_conversion task."""

import json
import logging
import os
import shutil
import tempfile
import zipfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_text_skip_notes(elem):
    """Extract text from an element, but entirely skip <text:note> elements."""
    text = []
    # ODF namespace for text
    note_tag = '{urn:oasis:names:tc:opendocument:xmlns:text:1.0}note'
    if elem.tag == note_tag:
        return ""
    if elem.text:
        text.append(elem.text)
    for child in elem:
        text.append(extract_text_skip_notes(child))
        if child.tail:
            text.append(child.tail)
    return "".join(text)

def get_all_footnote_texts(content_tree):
    """Extract all text from footnote bodies."""
    notes = content_tree.findall(
        './/text:note[@text:note-class="footnote"]',
        namespaces={'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'}
    )
    texts = []
    for note in notes:
        body = note.find(
            'text:note-body',
            namespaces={'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'}
        )
        if body is not None:
            # recursively grab all text inside the note body
            def extract(e):
                res = []
                if e.text: res.append(e.text)
                for c in e:
                    res.append(extract(c))
                    if c.tail: res.append(c.tail)
                return "".join(res)
            texts.append(extract(body))
    return texts

def verify_historical_footnote_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/triangle_fire_essay.odt")

    # Self-contained parsing avoiding reliance on host's external odfpy availability
    temp_dir = tempfile.mkdtemp(prefix="calligra_verify_")
    local_path = os.path.join(temp_dir, "document.odt")
    content_tree = None

    try:
        copy_from_env(document_path, local_path)
        if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
            with zipfile.ZipFile(local_path, 'r') as zf:
                content_xml = zf.read('content.xml')
                content_tree = ET.fromstring(content_xml)
    except Exception as e:
        logger.error(f"Failed to copy or parse ODT document: {e}")
    finally:
        if os.path.exists(local_path):
            os.remove(local_path)
        os.rmdir(temp_dir)

    if content_tree is None:
        return {"passed": False, "score": 0, "feedback": "Failed to parse ODT document"}

    try:
        score = 0
        feedback_parts = []
        
        # 1. Footnote count (20 pts)
        footnote_texts = get_all_footnote_texts(content_tree)
        num_footnotes = len(footnote_texts)
        if num_footnotes >= 6:
            score += 20
            feedback_parts.append(f"Footnotes created: {num_footnotes}/8")
        else:
            feedback_parts.append(f"Footnotes created: only {num_footnotes}/8 (need >=6)")

        # 2-6. Footnote content checks (total 32 pts)
        ft_lower = [ft.lower() for ft in footnote_texts]
        
        if any("von drehle" in t or "triangle: the fire that changed america" in t for t in ft_lower):
            score += 8
            feedback_parts.append("Von Drehle footnote found")
        else:
            feedback_parts.append("Von Drehle footnote missing")

        if any("stein" in t and "triangle fire" in t for t in ft_lower):
            score += 7
            feedback_parts.append("Stein footnote found")
        else:
            feedback_parts.append("Stein footnote missing")

        if any("new york times" in t or "141 men and girls" in t for t in ft_lower):
            score += 7
            feedback_parts.append("NYT footnote found")
        else:
            feedback_parts.append("NYT footnote missing")

        if any("mcevoy" in t or "common-sense causality" in t for t in ft_lower):
            score += 5
            feedback_parts.append("McEvoy footnote found")
        else:
            feedback_parts.append("McEvoy footnote missing")

        if any("greenwald" in t or "protocols of peace" in t for t in ft_lower):
            score += 5
            feedback_parts.append("Greenwald footnote found")
        else:
            feedback_parts.append("Greenwald footnote missing")

        # Get body text EXCLUDING footnotes to check markers, references section, and keywords
        body_text = extract_text_skip_notes(content_tree)
        body_text_lower = body_text.lower()

        # 7. Inline markers removed (15 pts)
        markers = metadata.get("markers", ["[1]", "[2]", "[3]", "[4]", "[5]", "[6]", "[7]", "[8]"])
        markers_removed = sum(1 for m in markers if m not in body_text)
        if markers_removed >= 6:
            score += 15
            feedback_parts.append(f"Markers removed: {markers_removed}/8")
        else:
            feedback_parts.append(f"Markers removed: only {markers_removed}/8 (need >=6)")

        # 8. References section removed (8 pts)
        ref_heading_gone = "references" not in body_text_lower.split()
        ref_text_gone = "von drehle" not in body_text_lower and "mcevoy" not in body_text_lower
        if ref_heading_gone and ref_text_gone:
            score += 8
            feedback_parts.append("References section removed")
        else:
            feedback_parts.append("References section still in body")

        # 9. Content preservation (15 pts)
        keywords = metadata.get("content_keywords", [
            "Triangle Shirtwaist Company",
            "Asch Building",
            "Frances Perkins",
            "International Ladies' Garment Workers' Union",
            "Sullivan-Hoey Fire Prevention Law",
            "Factory Investigating Commission",
            "Washington Place",
            "New Deal"
        ])
        keywords_present = sum(1 for kw in keywords if kw.lower() in body_text_lower)
        if keywords_present >= 6:
            score += 15
            feedback_parts.append(f"Content preserved: {keywords_present}/8")
        else:
            feedback_parts.append(f"Content preserved: only {keywords_present}/8 (need >=6)")

        # 10. VLM visual verification (10 pts)
        vlm_score = 0
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)
        except Exception as e:
            logger.warning(f"Error extracting frames: {e}")
            frames = []

        if frames:
            query_vlm = env_info.get("query_vlm")
            if query_vlm:
                prompt = (
                    "Look at this word processor document. Are there proper superscript footnote "
                    "numbers (like ¹, ², etc.) attached to words in the body text? Note: They "
                    "should look like small numbers raised above the text line. If you only see "
                    "regular bracketed numbers like [1], that is not a proper footnote. "
                    "Respond with JSON: {\"has_superscript_footnotes\": true/false}"
                )
                try:
                    result = query_vlm(prompt=prompt, images=frames)
                    if result and result.get("success"):
                        parsed = result.get("parsed", {})
                        if parsed.get("has_superscript_footnotes", False):
                            vlm_score = 10
                            feedback_parts.append("VLM confirms superscript footnotes")
                        else:
                            feedback_parts.append("VLM did not detect superscript footnotes")
                    else:
                        feedback_parts.append("VLM query failed")
                except Exception as e:
                    feedback_parts.append(f"VLM error: {e}")
            else:
                feedback_parts.append("VLM unavailable")
        else:
            feedback_parts.append("No screenshots for VLM")
            
        score += vlm_score

        passed = score >= 65

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with exception: {e}"
        }