#!/usr/bin/env python3
"""
Verifier for esg_sustainability_report task.

A Sustainability Specialist must expand a 4-slide ESG draft into a complete
10-slide ESG report with charts, notes, transitions, and PDF export.
Data source: Apple Inc. Environmental Progress Report 2023 (real published values).

Scoring (100 pts total, pass >= 65):
  GATE:  ODP file exists and is openable              (fail immediately if missing)
  25 pts: Slide count >= 10
  30 pts: Charts present >= 3 (embedded OLE chart objects)
  20 pts: Speaker notes with content on >= 6 slides
  15 pts: Slide transitions on >= 8 slides
  10 pts: PDF export exists at expected path
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
        "chart_count": 0,
        "notes_with_content": 0,
        "slides_with_transitions": 0,
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

            # Chart count — check Object N/content.xml files
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

            # Transitions
            trans_count = 0
            for slide_xml in slide_xmls:
                has_trans = bool(
                    re.search(r'presentation:transition-style\s*=', slide_xml) or
                    re.search(r'<presentation:transition\b', slide_xml)
                )
                if has_trans:
                    trans_count += 1
            metrics["slides_with_transitions"] = trans_count

    except zipfile.BadZipFile as e:
        metrics["error"] = f"Bad ZIP: {e}"
    except Exception as e:
        metrics["error"] = f"Parse error: {e}"

    return metrics


def verify_esg_sustainability_report(traj, env_info, task_info):
    """
    Verify ESG sustainability report task.

    Checks:
    1. GATE: ODP file exists
    2. Slide count >= 10
    3. Charts >= 3
    4. Notes on >= 6 slides
    5. Transitions on >= 8 slides
    6. PDF export exists
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    odp_path = metadata.get('odp_path', '/home/ga/Documents/Presentations/esg_report_2022.odp')
    pdf_path = metadata.get('pdf_path', '/home/ga/Documents/Presentations/esg_report_2022.pdf')

    temp_dir = tempfile.mkdtemp(prefix='verify_esg_')
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

        # SLIDE GATE: must have at least 6 slides to score any other criteria.
        # Prevents gaming the charts/notes/transitions criteria with only the 4-slide starting draft.
        if slide_count < 6:
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    f"GATE FAIL: Only {slide_count} slide(s) — minimum 6 required to qualify "
                    "for scoring. Build the complete ESG report (10+ slides required for full credit)."
                ),
                "debug": {"slide_count": slide_count},
            }

        score = 0
        feedback_parts = []
        debug = {}

        # Criterion 1: Slide count >= 10 (25 pts)
        debug["slide_count"] = slide_count
        if slide_count >= 10:
            score += 25
            feedback_parts.append(f"PASS slide_count={slide_count} (need 10+)")
        elif slide_count >= 7:
            score += 12
            feedback_parts.append(f"PARTIAL slide_count={slide_count} (need 10+)")
        else:
            feedback_parts.append(f"FAIL slide_count={slide_count} (need 10+)")

        # Criterion 2: Charts >= 3 (30 pts)
        chart_count = metrics["chart_count"]
        debug["chart_count"] = chart_count
        if chart_count >= 3:
            score += 30
            feedback_parts.append(f"PASS chart_count={chart_count} (need 3+)")
        elif chart_count == 2:
            score += 20
            feedback_parts.append(f"PARTIAL chart_count={chart_count} (need 3+)")
        elif chart_count == 1:
            score += 10
            feedback_parts.append(f"PARTIAL only 1 chart (need 3+)")
        else:
            feedback_parts.append("FAIL no charts found")

        # Criterion 3: Notes on >= 6 slides (20 pts)
        notes_count = metrics["notes_with_content"]
        debug["notes_slides"] = notes_count
        if notes_count >= 6:
            score += 20
            feedback_parts.append(f"PASS notes on {notes_count} slides (need 6+)")
        elif notes_count >= 3:
            score += 10
            feedback_parts.append(f"PARTIAL notes on {notes_count} slides (need 6+)")
        elif notes_count >= 1:
            score += 5
            feedback_parts.append(f"PARTIAL notes on {notes_count} slide(s) (need 6+)")
        else:
            feedback_parts.append("FAIL no speaker notes found")

        # Criterion 4: Transitions on >= 8 slides (15 pts)
        trans_count = metrics["slides_with_transitions"]
        debug["transition_slides"] = trans_count
        if trans_count >= 8:
            score += 15
            feedback_parts.append(f"PASS transitions on {trans_count} slides (need 8+)")
        elif trans_count >= 5:
            score += 8
            feedback_parts.append(f"PARTIAL transitions on {trans_count} slides (need 8+)")
        elif trans_count >= 1:
            score += 4
            feedback_parts.append(f"PARTIAL transitions on {trans_count} slide(s)")
        else:
            feedback_parts.append("FAIL no transitions found")

        # Criterion 5: PDF export (10 pts)
        pdf_local = os.path.join(temp_dir, 'result.pdf')
        try:
            copy_from_env(pdf_path, pdf_local)
            if os.path.exists(pdf_local) and os.path.getsize(pdf_local) > 1000:
                score += 10
                feedback_parts.append("PASS PDF export found")
            else:
                feedback_parts.append("FAIL PDF missing or too small")
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
