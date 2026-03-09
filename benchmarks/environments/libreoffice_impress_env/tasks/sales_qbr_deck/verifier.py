#!/usr/bin/env python3
"""
Verifier for sales_qbr_deck task.

A Sales Manager must build a complete Q3 2023 Quarterly Business Review presentation
from a 2-slide draft and real US Census Bureau retail sales data.

Scoring (100 pts total, pass >= 65):
  GATE:  ODP file exists and is openable              (fail immediately if missing)
  25 pts: Slide count >= 7
  20 pts: Title slide identifies Q3 2023 + QBR/Quarterly Business Review
  30 pts: Charts present >= 2 (embedded OLE chart objects)
  15 pts: Speaker notes with content on >= 3 slides
  10 pts: PDF export exists at expected path
"""

import os
import re
import sys
import zipfile
import tempfile
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _parse_odp_metrics(odp_path: str) -> dict:
    """Parse ODP file and return key metrics using zipfile."""
    metrics = {
        "slide_count": 0,
        "chart_count": 0,
        "notes_with_content": 0,
        "first_slide_text": "",
        "all_text": "",
        "error": None,
    }
    try:
        with zipfile.ZipFile(odp_path, 'r') as z:
            names = z.namelist()

            # Read content.xml for slide/notes/text analysis
            if 'content.xml' not in names:
                metrics["error"] = "content.xml not found in ODP archive"
                return metrics

            content_raw = z.read('content.xml').decode('utf-8', errors='replace')

            # Count slides
            slides = re.split(r'(?=<draw:page\b)', content_raw)
            slide_xmls = [s for s in slides if s.strip().startswith('<draw:page')]
            metrics["slide_count"] = len(slide_xmls)

            # First slide text (for title check)
            if slide_xmls:
                metrics["first_slide_text"] = re.sub(r'<[^>]+>', ' ', slide_xmls[0]).lower()

            # All text across all slides
            metrics["all_text"] = re.sub(r'<[^>]+>', ' ', content_raw).lower()

            # Count slides with substantive speaker notes
            notes_count = 0
            for slide_xml in slide_xmls:
                notes_match = re.search(
                    r'<presentation:notes\b[^>]*>(.*?)</presentation:notes>',
                    slide_xml, re.DOTALL
                )
                if notes_match:
                    notes_text = re.sub(r'<[^>]+>', ' ', notes_match.group(1))
                    # Must have more than a trivial amount of text
                    if len(notes_text.strip()) > 25:
                        notes_count += 1
            metrics["notes_with_content"] = notes_count

            # Count embedded chart objects
            # In ODP, each embedded chart has its own Object N/ directory
            # with a content.xml that contains <chart:chart ...>
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

    except zipfile.BadZipFile as e:
        metrics["error"] = f"Invalid ZIP/ODP file: {e}"
    except Exception as e:
        metrics["error"] = f"Error parsing ODP: {e}"

    return metrics


def verify_sales_qbr_deck(traj, env_info, task_info):
    """
    Verify the Q3 2023 Sales QBR deck task.

    Checks:
    1. GATE: ODP file exists
    2. Slide count >= 7
    3. Title slide mentions Q3 2023 and Quarterly Business Review / QBR
    4. At least 2 embedded charts
    5. Speaker notes on >= 3 slides
    6. PDF export exists
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    odp_container_path = metadata.get('odp_path', '/home/ga/Documents/Presentations/qbr_q3_2023.odp')
    pdf_container_path = metadata.get('pdf_path', '/home/ga/Documents/Presentations/qbr_q3_2023.pdf')

    temp_dir = tempfile.mkdtemp(prefix='verify_qbr_')
    try:
        odp_local = os.path.join(temp_dir, 'result.odp')

        # GATE: Copy ODP file
        try:
            copy_from_env(odp_container_path, odp_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"GATE FAIL: Could not copy ODP file — {e}",
            }

        if not os.path.exists(odp_local) or os.path.getsize(odp_local) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "GATE FAIL: ODP file is missing or empty",
            }

        metrics = _parse_odp_metrics(odp_local)
        if metrics.get("error"):
            return {
                "passed": False,
                "score": 0,
                "feedback": f"GATE FAIL: Could not parse ODP — {metrics['error']}",
            }

        slide_count = metrics["slide_count"]

        # SLIDE GATE: presentation must have at least 5 slides to score any other criteria.
        # This prevents gaming by adding charts/notes to the 2-slide starting draft.
        # (Do-nothing = 2 slides → immediate score=0; starting file has no charts/notes anyway)
        if slide_count < 5:
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    f"GATE FAIL: Presentation too short — only {slide_count} slide(s). "
                    "At least 5 slides are needed to qualify for scoring. "
                    "Build the complete QBR deck (7+ slides required for full credit)."
                ),
                "debug": {"slide_count": slide_count},
            }

        score = 0
        feedback_parts = []
        debug = {}

        # Criterion 1: Slide count >= 7 (25 pts)
        debug["slide_count"] = slide_count
        if slide_count >= 7:
            score += 25
            feedback_parts.append(f"PASS slide_count={slide_count} (need 7+)")
        else:
            feedback_parts.append(f"FAIL slide_count={slide_count} (need 7+)")

        # Criterion 2: Title mentions Q3 2023 and QBR/Quarterly Business Review (20 pts)
        first_text = metrics["first_slide_text"]
        has_q3 = bool(re.search(r'q3\s*2023|third\s*quarter\s*2023|q3[-/]2023', first_text))
        has_qbr = bool(re.search(r'quarterly\s*business\s*review|qbr', first_text))
        debug["has_q3_in_title"] = has_q3
        debug["has_qbr_in_title"] = has_qbr
        if has_q3 and has_qbr:
            score += 20
            feedback_parts.append("PASS title identifies Q3 2023 QBR")
        elif has_q3 or has_qbr:
            score += 10
            feedback_parts.append(f"PARTIAL title partial (q3={has_q3}, qbr={has_qbr})")
        else:
            feedback_parts.append("FAIL title missing Q3 2023 and QBR identifiers")

        # Criterion 3: At least 2 charts (30 pts)
        chart_count = metrics["chart_count"]
        debug["chart_count"] = chart_count
        if chart_count >= 2:
            score += 30
            feedback_parts.append(f"PASS chart_count={chart_count} (need 2+)")
        elif chart_count == 1:
            score += 15
            feedback_parts.append(f"PARTIAL only 1 chart found (need 2+)")
        else:
            feedback_parts.append("FAIL no charts found")

        # Criterion 4: Speaker notes on >= 3 slides (15 pts)
        notes_count = metrics["notes_with_content"]
        debug["notes_slides"] = notes_count
        if notes_count >= 3:
            score += 15
            feedback_parts.append(f"PASS notes_slides={notes_count} (need 3+)")
        elif notes_count >= 1:
            score += 7
            feedback_parts.append(f"PARTIAL notes on {notes_count} slide(s) (need 3+)")
        else:
            feedback_parts.append("FAIL no speaker notes found")

        # Criterion 5: PDF export (10 pts)
        pdf_local = os.path.join(temp_dir, 'result.pdf')
        try:
            copy_from_env(pdf_container_path, pdf_local)
            if os.path.exists(pdf_local) and os.path.getsize(pdf_local) > 1000:
                score += 10
                feedback_parts.append("PASS PDF export exists")
            else:
                feedback_parts.append("FAIL PDF missing or too small")
        except Exception:
            feedback_parts.append("FAIL PDF not found at expected path")

        passed = score >= 65
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "debug": debug,
        }

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
