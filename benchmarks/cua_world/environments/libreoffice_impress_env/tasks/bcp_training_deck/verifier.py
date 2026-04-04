#!/usr/bin/env python3
"""
Verifier for bcp_training_deck task.

A Business Continuity Planner must complete a 6-slide BCP training draft into
a 12-slide training deck with a flowchart, RTO/RPO chart, notes, and PDF.

Scoring (100 pts total, pass >= 65):
  GATE:  ODP file exists and is openable              (fail immediately if missing)
  25 pts: Slide count >= 12
  30 pts: At least one slide has >= 8 shapes (flowchart requirement)
  20 pts: At least 1 embedded chart (RTO/RPO or similar)
  15 pts: Speaker notes on >= 8 slides
  10 pts: PDF export exists
"""

import os
import re
import zipfile
import tempfile
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Shape tags that count toward flowchart detection
SHAPE_TAGS = [
    'draw:custom-shape',
    'draw:connector',
    'draw:rect',
    'draw:ellipse',
    'draw:polygon',
    'draw:path',
    'draw:line',
]


def _count_shapes_in_slide(slide_xml: str) -> int:
    """Count all shape elements in a slide's XML."""
    total = 0
    for tag in SHAPE_TAGS:
        total += len(re.findall(rf'<{re.escape(tag)}\b', slide_xml))
    return total


def _parse_odp_metrics(odp_path: str) -> dict:
    metrics = {
        "slide_count": 0,
        "chart_count": 0,
        "max_shapes_on_single_slide": 0,
        "notes_with_content": 0,
        "error": None,
    }
    try:
        with zipfile.ZipFile(odp_path, 'r') as z:
            names = z.namelist()
            if 'content.xml' not in names:
                metrics["error"] = "content.xml missing"
                return metrics

            content_raw = z.read('content.xml').decode('utf-8', errors='replace')
            slides = re.split(r'(?=<draw:page\b)', content_raw)
            slide_xmls = [s for s in slides if s.strip().startswith('<draw:page')]
            metrics["slide_count"] = len(slide_xmls)

            # Max shapes on any single slide
            max_shapes = 0
            for slide_xml in slide_xmls:
                # Exclude the notes section from shape count
                # Notes are inside <presentation:notes>...</presentation:notes>
                slide_no_notes = re.sub(
                    r'<presentation:notes\b.*?</presentation:notes>',
                    '', slide_xml, flags=re.DOTALL
                )
                shapes = _count_shapes_in_slide(slide_no_notes)
                if shapes > max_shapes:
                    max_shapes = shapes
            metrics["max_shapes_on_single_slide"] = max_shapes

            # Chart count
            chart_count = 0
            for name in names:
                if re.match(r'^Object \d+/content\.xml$', name):
                    try:
                        obj_content = z.read(name).decode('utf-8', errors='replace')
                        if 'chart:chart' in obj_content:
                            chart_count += 1
                    except Exception:
                        pass
            metrics["chart_count"] = chart_count

            # Notes with content
            notes_count = 0
            for slide_xml in slide_xmls:
                notes_match = re.search(
                    r'<presentation:notes\b[^>]*>(.*?)</presentation:notes>',
                    slide_xml, re.DOTALL
                )
                if notes_match:
                    notes_text = re.sub(r'<[^>]+>', ' ', notes_match.group(1))
                    if len(notes_text.strip()) > 25:
                        notes_count += 1
            metrics["notes_with_content"] = notes_count

    except zipfile.BadZipFile as e:
        metrics["error"] = f"Bad ZIP: {e}"
    except Exception as e:
        metrics["error"] = f"Parse error: {e}"

    return metrics


def verify_bcp_training_deck(traj, env_info, task_info):
    """
    Verify the BCP training deck task.

    Checks:
    1. GATE: ODP file exists
    2. Slide count >= 12
    3. Max shapes on any single slide >= 8 (flowchart)
    4. At least 1 chart
    5. Notes on >= 8 slides
    6. PDF export exists
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    odp_path = metadata.get('odp_path', '/home/ga/Documents/Presentations/bcp_training.odp')
    pdf_path = metadata.get('pdf_path', '/home/ga/Documents/Presentations/bcp_training.pdf')
    min_flowchart_shapes = metadata.get('min_shapes_on_flowchart_slide', 8)

    temp_dir = tempfile.mkdtemp(prefix='verify_bcp_')
    try:
        odp_local = os.path.join(temp_dir, 'result.odp')

        try:
            copy_from_env(odp_path, odp_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"GATE FAIL: Cannot copy ODP — {e}",
            }

        if not os.path.exists(odp_local) or os.path.getsize(odp_local) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "GATE FAIL: ODP missing or empty",
            }

        metrics = _parse_odp_metrics(odp_local)
        if metrics.get("error"):
            return {
                "passed": False,
                "score": 0,
                "feedback": f"GATE FAIL: {metrics['error']}",
            }

        slide_count = metrics["slide_count"]

        # SLIDE GATE: must have at least 8 slides to score any other criteria.
        # Prevents gaming the flowchart/chart/notes criteria with only the 6-slide starting draft.
        if slide_count < 8:
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    f"GATE FAIL: Only {slide_count} slide(s) — minimum 8 required to qualify "
                    "for scoring. Build the complete BCP training deck (12+ slides required for full credit)."
                ),
                "debug": {"slide_count": slide_count},
            }

        score = 0
        feedback_parts = []
        debug = {}

        # Criterion 1: Slide count >= 12 (25 pts)
        debug["slide_count"] = slide_count
        if slide_count >= 12:
            score += 25
            feedback_parts.append(f"PASS slide_count={slide_count} (need 12+)")
        elif slide_count >= 9:
            score += 12
            feedback_parts.append(f"PARTIAL slide_count={slide_count} (need 12+)")
        else:
            feedback_parts.append(f"FAIL slide_count={slide_count} (need 12+)")

        # Criterion 2: Flowchart — one slide has >= 8 shapes (30 pts)
        max_shapes = metrics["max_shapes_on_single_slide"]
        debug["max_shapes_single_slide"] = max_shapes
        if max_shapes >= min_flowchart_shapes:
            score += 30
            feedback_parts.append(f"PASS flowchart slide has {max_shapes} shapes (need 8+)")
        elif max_shapes >= 5:
            score += 15
            feedback_parts.append(f"PARTIAL best slide has {max_shapes} shapes (need 8+)")
        elif max_shapes >= 3:
            score += 7
            feedback_parts.append(f"PARTIAL best slide has only {max_shapes} shapes")
        else:
            feedback_parts.append(f"FAIL no flowchart found (max shapes on any slide: {max_shapes})")

        # Criterion 3: At least 1 chart (20 pts)
        chart_count = metrics["chart_count"]
        debug["chart_count"] = chart_count
        if chart_count >= 1:
            score += 20
            feedback_parts.append(f"PASS chart_count={chart_count}")
        else:
            feedback_parts.append("FAIL no charts found (expected RTO/RPO or recovery tier chart)")

        # Criterion 4: Notes on >= 8 slides (15 pts)
        notes_count = metrics["notes_with_content"]
        debug["notes_slides"] = notes_count
        if notes_count >= 8:
            score += 15
            feedback_parts.append(f"PASS notes on {notes_count} slides (need 8+)")
        elif notes_count >= 5:
            score += 8
            feedback_parts.append(f"PARTIAL notes on {notes_count} slides (need 8+)")
        elif notes_count >= 2:
            score += 4
            feedback_parts.append(f"PARTIAL notes on {notes_count} slide(s) (need 8+)")
        else:
            feedback_parts.append("FAIL no speaker notes found")

        # Criterion 5: PDF export (10 pts)
        pdf_local = os.path.join(temp_dir, 'result.pdf')
        try:
            copy_from_env(pdf_path, pdf_local)
            if os.path.exists(pdf_local) and os.path.getsize(pdf_local) > 1000:
                score += 10
                feedback_parts.append("PASS PDF export found")
            else:
                feedback_parts.append("FAIL PDF too small or empty")
        except Exception:
            feedback_parts.append("FAIL PDF not found")

        passed = score >= 65
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "debug": debug,
        }

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
