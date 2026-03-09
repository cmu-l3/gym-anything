#!/usr/bin/env python3
"""
Verifier for audit_report_fix task.

A senior editor must fix four classes of formatting errors in a government
facility condition assessment report (building_audit_draft.odt) and save
the corrected version as building_audit_final.odt.

The four bugs in the draft:
  1. All 10 subsection headings are at outline-level=3 (should be level=2)
  2. Table of Contents is a manually-typed text block (not text:table-of-content)
  3. 3 paragraphs have red text (fo:color="#ff0000") — must be black
  4. No footer / no page numbers

Scoring (100 points):
  - File exists with substantial content (≥ 5KB):        gate (score=0 if fails)
  - Heading 2 count ≥ 10 (all wrong H3s fixed to H2):   20 pts
  - Heading 3 count = 0 (no H3s remain):                 15 pts
  - Auto-generated TOC inserted:                         20 pts
  - No red text (red_text_count == 0):                   20 pts
  - Footer with page numbers present:                    25 pts

Pass threshold: 70 points

Partial calibration:
  - Headings fixed only (H2+H3): 35 pts (fails)
  - Headings + TOC: 55 pts (fails)
  - Headings + TOC + footer: 80 pts (passes)
  - Headings + TOC + red fixed: 75 pts (passes)
  - Headings + red + footer: 80 pts (passes)
  - Only TOC + footer (headings not fixed): 45 pts (fails)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_audit_report_fix(traj, env_info, task_info):
    """Verify the audit report was properly corrected."""
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
                "Output file /home/ga/Documents/building_audit_final.odt "
                "not found or too small. "
                f"Size: {result.get('file_size', 0)} bytes."
            )
        }

    score = 0
    feedback_parts = []
    subscores = {}

    expected_h2_min = metadata.get('expected_h2_min', 10)
    expected_h3_max = metadata.get('expected_h3_max', 0)

    # ── Criterion 1: Heading 2 count (20 pts) ────────────────────────────
    h2 = result.get('heading2_count', 0)
    try:
        if h2 >= expected_h2_min:
            score += 20
            subscores['heading2_fixed'] = True
            feedback_parts.append(f"Heading 2 count: {h2} (expected ≥{expected_h2_min}) (+20)")
        elif h2 >= 5:
            score += 10
            subscores['heading2_fixed'] = 'partial'
            feedback_parts.append(
                f"Heading 2 count: {h2}/{expected_h2_min} — partially fixed (+10)")
        else:
            subscores['heading2_fixed'] = False
            feedback_parts.append(
                f"Heading 2 count: {h2} — most subsection headings still wrong")
    except Exception as e:
        feedback_parts.append(f"H2 check error: {e}")

    # ── Criterion 2: Heading 3 count = 0 (15 pts) ────────────────────────
    h3 = result.get('heading3_count', 0)
    try:
        if h3 <= expected_h3_max:
            score += 15
            subscores['heading3_cleared'] = True
            feedback_parts.append(f"Heading 3 cleared: {h3} remaining (+15)")
        elif h3 <= 3:
            score += 7
            subscores['heading3_cleared'] = 'partial'
            feedback_parts.append(
                f"Heading 3 partially cleared: {h3} still at wrong level (+7)")
        else:
            subscores['heading3_cleared'] = False
            feedback_parts.append(
                f"Heading 3 not fixed: {h3} headings still at wrong level (need {expected_h3_max})")
    except Exception as e:
        feedback_parts.append(f"H3 check error: {e}")

    # ── Criterion 3: Auto-generated TOC (20 pts) ─────────────────────────
    try:
        if result.get('has_toc'):
            score += 20
            subscores['toc'] = True
            feedback_parts.append("Auto-generated TOC present (+20)")
        else:
            subscores['toc'] = False
            feedback_parts.append(
                "TOC not found or still a manual text table of contents "
                "(needs text:table-of-content element)")
    except Exception as e:
        feedback_parts.append(f"TOC check error: {e}")

    # ── Criterion 4: Red text removed (20 pts) ───────────────────────────
    red_count = result.get('red_text_count', 0)
    try:
        if red_count == 0:
            score += 20
            subscores['red_text_removed'] = True
            feedback_parts.append("Red text removed — all body text is black (+20)")
        else:
            subscores['red_text_removed'] = False
            feedback_parts.append(
                f"Red text still present ({red_count} occurrence(s) of fo:color=#ff0000). "
                "All body text must be black per office formatting policy.")
    except Exception as e:
        feedback_parts.append(f"Red text check error: {e}")

    # ── Criterion 5: Footer with page numbers (25 pts) ───────────────────
    try:
        has_pg = result.get('has_page_numbers') or result.get('has_footer')
        if has_pg:
            score += 25
            subscores['footer_page_numbers'] = True
            feedback_parts.append("Footer / page numbers present (+25)")
        else:
            subscores['footer_page_numbers'] = False
            feedback_parts.append("No footer or page numbers found")
    except Exception as e:
        feedback_parts.append(f"Footer check error: {e}")

    # ── Pass determination ────────────────────────────────────────────────
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria evaluated",
        "subscores": subscores,
        "details": {
            "heading2_count": result.get('heading2_count', 0),
            "heading3_count": result.get('heading3_count', 0),
            "has_toc": result.get('has_toc', False),
            "red_text_count": result.get('red_text_count', 0),
            "has_footer": result.get('has_footer', False),
            "has_page_numbers": result.get('has_page_numbers', False),
            "file_size_bytes": result.get('file_size', 0),
        }
    }
