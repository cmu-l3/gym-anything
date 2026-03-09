#!/usr/bin/env python3
"""
Verifier for iq_validation_protocol task.

A Senior Validation Engineer must create a complete pharmaceutical
Installation Qualification (IQ) Protocol for a Waters ACQUITY UPLC H-Class
system using instrument data from a JSON reference file.

Scoring (100 points):
  - File exists with substantial content (≥ 5KB):        gate (score=0 if fails)
  - Table of Contents present:                           20 pts
  - ≥ 5 Heading 1 (main IQ sections):                   20 pts
  - ≥ 6 Heading 2 (subsections):                        15 pts
  - ≥ 3 Tables (test execution tables, specs, etc.):    20 pts
  - Footer with page numbers:                           15 pts
  - Document length ≥ 25 paragraphs:                    5 pts
  - Instrument name / IQ terms mentioned:               5 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_iq_validation_protocol(traj, env_info, task_info):
    """Verify the IQ validation protocol document was properly created."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy/parse error: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    # ── GATE: output file must exist and be substantial ───────────────────
    if not result.get('file_exists') or result.get('file_size', 0) < 5000:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "Output file /home/ga/Documents/VAL-IQ-UPLC-2024-004.odt "
                "not found or too small. "
                f"Size: {result.get('file_size', 0)} bytes."
            )
        }

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Criterion 1: Table of Contents (20 pts) ───────────────────────────
    try:
        if result.get('has_toc'):
            score += 20
            subscores['toc'] = True
            feedback_parts.append("Table of Contents present (+20)")
        else:
            subscores['toc'] = False
            feedback_parts.append("Table of Contents missing")
    except Exception as e:
        feedback_parts.append(f"TOC check error: {e}")

    # ── Criterion 2: Heading 1 sections (20 pts) ─────────────────────────
    h1 = result.get('heading1_count', 0)
    h1_min = metadata.get('required_h1_min', 5)
    try:
        if h1 >= h1_min:
            score += 20
            subscores['heading1'] = True
            feedback_parts.append(f"Heading 1 sections: {h1} (+20)")
        elif h1 >= 3:
            score += 10
            subscores['heading1'] = 'partial'
            feedback_parts.append(f"Heading 1 sections: {h1}/{h1_min} (partial +10)")
        else:
            subscores['heading1'] = False
            feedback_parts.append(
                f"Insufficient Heading 1 sections: {h1} (need {h1_min})")
    except Exception as e:
        feedback_parts.append(f"H1 check error: {e}")

    # ── Criterion 3: Heading 2 subsections (15 pts) ───────────────────────
    h2 = result.get('heading2_count', 0)
    h2_min = metadata.get('required_h2_min', 6)
    try:
        if h2 >= h2_min:
            score += 15
            subscores['heading2'] = True
            feedback_parts.append(f"Heading 2 subsections: {h2} (+15)")
        elif h2 >= 3:
            score += 7
            subscores['heading2'] = 'partial'
            feedback_parts.append(f"Heading 2 subsections: {h2}/{h2_min} (partial +7)")
        else:
            subscores['heading2'] = False
            feedback_parts.append(
                f"Insufficient Heading 2 subsections: {h2} (need {h2_min})")
    except Exception as e:
        feedback_parts.append(f"H2 check error: {e}")

    # ── Criterion 4: Tables (20 pts) ─────────────────────────────────────
    tables = result.get('table_count', 0)
    tables_min = metadata.get('required_tables_min', 3)
    try:
        if tables >= tables_min:
            score += 20
            subscores['tables'] = True
            feedback_parts.append(f"Tables present: {tables} (+20)")
        elif tables >= 1:
            score += 7
            subscores['tables'] = 'partial'
            feedback_parts.append(f"Only {tables} table(s) found (need {tables_min}) (+7)")
        else:
            subscores['tables'] = False
            feedback_parts.append(
                "No tables found. IQ protocol requires test execution tables.")
    except Exception as e:
        feedback_parts.append(f"Table check error: {e}")

    # ── Criterion 5: Footer with page numbers (15 pts) ────────────────────
    try:
        has_pg = result.get('has_page_numbers') or result.get('has_footer')
        if has_pg:
            score += 15
            subscores['footer_page_numbers'] = True
            feedback_parts.append("Footer / page numbers present (+15)")
        else:
            subscores['footer_page_numbers'] = False
            feedback_parts.append("No footer or page numbers found")
    except Exception as e:
        feedback_parts.append(f"Footer check error: {e}")

    # ── Criterion 6: Document length (5 pts) ─────────────────────────────
    para_count = result.get('paragraph_count', 0)
    para_min = metadata.get('required_paragraph_min', 25)
    try:
        if para_count >= para_min:
            score += 5
            subscores['document_length'] = True
            feedback_parts.append(f"Document length: {para_count} paragraphs (+5)")
        else:
            subscores['document_length'] = False
            feedback_parts.append(
                f"Document short: {para_count}/{para_min} paragraphs (need {para_min})")
    except Exception as e:
        feedback_parts.append(f"Length check error: {e}")

    # ── Criterion 7: Instrument/IQ content (5 pts) ───────────────────────
    try:
        if result.get('mentions_instrument') and result.get('mentions_iq_terms'):
            score += 5
            subscores['content_relevance'] = True
            feedback_parts.append("Instrument name and IQ terminology present (+5)")
        else:
            subscores['content_relevance'] = False
            feedback_parts.append(
                "Instrument name or IQ terms (installation qualification, acceptance criteria, etc.) missing")
    except Exception as e:
        feedback_parts.append(f"Content check error: {e}")

    # ── Pass determination ────────────────────────────────────────────────
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria evaluated",
        "subscores": subscores,
        "details": {
            "heading1_count": result.get('heading1_count', 0),
            "heading2_count": result.get('heading2_count', 0),
            "table_count": result.get('table_count', 0),
            "paragraph_count": result.get('paragraph_count', 0),
            "has_toc": result.get('has_toc', False),
            "has_footer": result.get('has_footer', False),
            "file_size_bytes": result.get('file_size', 0),
        }
    }
