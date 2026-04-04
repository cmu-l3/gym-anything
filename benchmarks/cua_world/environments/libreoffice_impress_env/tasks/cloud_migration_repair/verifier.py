#!/usr/bin/env python3
"""
Verifier for cloud_migration_repair task.

A Computer Systems Analyst must repair a 9-slide cloud migration deck before
it goes to the CTO. Errors introduced: typo "Infrastrucutre" in slide 3 title,
Security Overview slide (slide 6) is empty, no speaker notes anywhere, no transitions.

Scoring (100 pts total, pass >= 65):
  GATE:  ODP file exists and is openable              (fail immediately if missing)
  25 pts: Typo "Infrastrucutre" no longer present in any slide
  25 pts: Security Overview slide has >= 3 substantive bullet points
  30 pts: Speaker notes present on >= 5 slides
  20 pts: Slide transitions present on >= 7 slides
"""

import os
import re
import zipfile
import tempfile
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _parse_odp_metrics(odp_path: str) -> dict:
    metrics = {
        "slide_count": 0,
        "has_typo": False,
        "security_slide_bullets": 0,
        "notes_with_content": 0,
        "slides_with_transitions": 0,
        "all_text": "",
        "slide_texts": [],
        "error": None,
    }
    try:
        with zipfile.ZipFile(odp_path, 'r') as z:
            if 'content.xml' not in z.namelist():
                metrics["error"] = "content.xml not in archive"
                return metrics

            content_raw = z.read('content.xml').decode('utf-8', errors='replace')
            slides = re.split(r'(?=<draw:page\b)', content_raw)
            slide_xmls = [s for s in slides if s.strip().startswith('<draw:page')]
            metrics["slide_count"] = len(slide_xmls)

            all_text = re.sub(r'<[^>]+>', ' ', content_raw)
            metrics["all_text"] = all_text
            metrics["has_typo"] = 'infrastrucutre' in all_text.lower()

            slide_texts = []
            for slide_xml in slide_xmls:
                clean = re.sub(r'<[^>]+>', ' ', slide_xml)
                slide_texts.append(clean)
            metrics["slide_texts"] = slide_texts

            # Find Security Overview slide (slide index 5, 0-based)
            # We search by title content rather than fixed index in case agent rearranges slides
            security_bullets = 0
            for slide_text in slide_texts:
                if 'security overview' in slide_text.lower():
                    # Count non-title, non-empty lines as bullets
                    lines = [ln.strip() for ln in slide_text.splitlines() if ln.strip()]
                    # First non-empty line is the title; count meaningful content lines after it
                    content_lines = [ln for ln in lines[1:] if len(ln) > 10]
                    security_bullets = max(security_bullets, len(content_lines))
            metrics["security_slide_bullets"] = security_bullets

            # Count slides with notes
            notes_count = 0
            for slide_xml in slide_xmls:
                notes_match = re.search(
                    r'<presentation:notes\b[^>]*>(.*?)</presentation:notes>',
                    slide_xml, re.DOTALL
                )
                if notes_match:
                    notes_text = re.sub(r'<[^>]+>', ' ', notes_match.group(1))
                    if len(notes_text.strip()) > 20:
                        notes_count += 1
            metrics["notes_with_content"] = notes_count

            # Count slides with transitions
            # LibreOffice stores transitions via presentation:transition-style on draw:page
            # or via <presentation:transition> child elements
            transition_count = 0
            for slide_xml in slide_xmls:
                has_transition = bool(
                    re.search(r'presentation:transition-style\s*=', slide_xml) or
                    re.search(r'<presentation:transition\b', slide_xml)
                )
                if has_transition:
                    transition_count += 1
            metrics["slides_with_transitions"] = transition_count

    except zipfile.BadZipFile as e:
        metrics["error"] = f"Bad ZIP: {e}"
    except Exception as e:
        metrics["error"] = f"Parse error: {e}"

    return metrics


def verify_cloud_migration_repair(traj, env_info, task_info):
    """
    Verify the cloud migration deck repair task.

    Checks:
    1. GATE: ODP file exists
    2. Typo 'Infrastrucutre' no longer present
    3. Security Overview slide has >= 3 substantive lines of content
    4. Speaker notes on >= 5 slides
    5. Slide transitions on >= 7 slides
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    odp_path = metadata.get('odp_path', '/home/ga/Documents/Presentations/cloud_migration_deck.odp')

    temp_dir = tempfile.mkdtemp(prefix='verify_cloud_')
    try:
        odp_local = os.path.join(temp_dir, 'result.odp')

        try:
            copy_from_env(odp_path, odp_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"GATE FAIL: Could not copy ODP — {e}",
            }

        if not os.path.exists(odp_local) or os.path.getsize(odp_local) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "GATE FAIL: ODP file missing or empty",
            }

        metrics = _parse_odp_metrics(odp_local)
        if metrics.get("error"):
            return {
                "passed": False,
                "score": 0,
                "feedback": f"GATE FAIL: Could not parse ODP — {metrics['error']}",
            }

        score = 0
        feedback_parts = []
        debug = {}

        # Criterion 1: Typo fixed — "Infrastrucutre" absent (25 pts)
        has_typo = metrics["has_typo"]
        debug["has_typo"] = has_typo
        if not has_typo:
            score += 25
            feedback_parts.append("PASS typo 'Infrastrucutre' corrected")
        else:
            feedback_parts.append("FAIL typo 'Infrastrucutre' still present")

        # Criterion 2: Security Overview slide has >= 3 content lines (25 pts)
        sec_bullets = metrics["security_slide_bullets"]
        debug["security_slide_bullets"] = sec_bullets
        if sec_bullets >= 3:
            score += 25
            feedback_parts.append(f"PASS Security slide has {sec_bullets} content lines")
        elif sec_bullets >= 1:
            score += 12
            feedback_parts.append(f"PARTIAL Security slide has {sec_bullets} line(s) (need 3+)")
        else:
            feedback_parts.append("FAIL Security Overview slide still empty")

        # Criterion 3: Notes on >= 5 slides (30 pts)
        notes_count = metrics["notes_with_content"]
        debug["notes_slides"] = notes_count
        if notes_count >= 5:
            score += 30
            feedback_parts.append(f"PASS notes on {notes_count} slides (need 5+)")
        elif notes_count >= 3:
            score += 15
            feedback_parts.append(f"PARTIAL notes on {notes_count} slides (need 5+)")
        elif notes_count >= 1:
            score += 7
            feedback_parts.append(f"PARTIAL notes on only {notes_count} slide(s)")
        else:
            feedback_parts.append("FAIL no speaker notes found")

        # Criterion 4: Transitions on >= 7 slides (20 pts)
        trans_count = metrics["slides_with_transitions"]
        debug["transition_slides"] = trans_count
        if trans_count >= 7:
            score += 20
            feedback_parts.append(f"PASS transitions on {trans_count} slides (need 7+)")
        elif trans_count >= 4:
            score += 10
            feedback_parts.append(f"PARTIAL transitions on {trans_count} slides (need 7+)")
        elif trans_count >= 1:
            score += 5
            feedback_parts.append(f"PARTIAL transitions on only {trans_count} slide(s)")
        else:
            feedback_parts.append("FAIL no slide transitions found")

        passed = score >= 65
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "debug": debug,
        }

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
