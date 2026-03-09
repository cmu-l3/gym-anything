#!/usr/bin/env python3
"""
Verifier for legal_contract_styles task.

A senior paralegal must fix a commercial lease agreement where all headings
use direct bold formatting instead of proper paragraph styles, and add
required document navigation elements per firm standards.

Scoring (100 points total):
  - Heading 1 style applied to main sections (>= 9 headings):  30 pts
  - Heading 2 style applied to subsections (>= 18 headings):   30 pts
  - Table of Contents inserted (auto-generated):               25 pts
  - Page numbers in footer:                                    15 pts

Pass threshold: 70 points
GATE: If file does not exist, score=0 immediately.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_legal_contract_styles(traj, env_info, task_info):
    """Verify the legal contract formatting has been corrected."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_h1_min = metadata.get('expected_heading1_min', 9)
    expected_h2_min = metadata.get('expected_heading2_min', 18)

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may have failed"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0,
                "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy error: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    # ── GATE: output file must exist ──────────────────────────────────────
    if not result.get('file_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "Output file /home/ga/Documents/commercial_lease_final.odt "
                "not found. Agent did not save the corrected document."
            )
        }

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Criterion 1: Heading 1 applied to main sections (30 pts) ──────────
    h1_count = result.get('heading1_count', 0)
    try:
        if h1_count >= expected_h1_min:
            score += 30
            subscores['heading1_styles'] = True
            feedback_parts.append(
                f"Heading 1 style correctly applied ({h1_count} sections)"
            )
        elif h1_count >= 5:
            partial = 15
            score += partial
            subscores['heading1_styles'] = 'partial'
            feedback_parts.append(
                f"Heading 1 partially applied ({h1_count}/{expected_h1_min} sections) +{partial}pts"
            )
        else:
            subscores['heading1_styles'] = False
            feedback_parts.append(
                f"Heading 1 style not properly applied "
                f"({h1_count} found, {expected_h1_min} required). "
                "Headings may still use direct bold formatting."
            )
    except Exception as e:
        feedback_parts.append(f"Heading 1 check error: {e}")

    # ── Criterion 2: Heading 2 applied to subsections (30 pts) ────────────
    h2_count = result.get('heading2_count', 0)
    try:
        if h2_count >= expected_h2_min:
            score += 30
            subscores['heading2_styles'] = True
            feedback_parts.append(
                f"Heading 2 style correctly applied ({h2_count} subsections)"
            )
        elif h2_count >= 8:
            partial = 15
            score += partial
            subscores['heading2_styles'] = 'partial'
            feedback_parts.append(
                f"Heading 2 partially applied ({h2_count}/{expected_h2_min} subsections) +{partial}pts"
            )
        else:
            subscores['heading2_styles'] = False
            feedback_parts.append(
                f"Heading 2 style not properly applied "
                f"({h2_count} found, {expected_h2_min} required)."
            )
    except Exception as e:
        feedback_parts.append(f"Heading 2 check error: {e}")

    # ── Criterion 3: Table of Contents inserted (25 pts) ──────────────────
    try:
        if result.get('has_toc'):
            score += 25
            subscores['toc_inserted'] = True
            feedback_parts.append(
                "Table of Contents found (auto-generated TOC element present)"
            )
        else:
            subscores['toc_inserted'] = False
            feedback_parts.append(
                "Table of Contents not found. "
                "Per firm standards, an auto-generated TOC is required."
            )
    except Exception as e:
        feedback_parts.append(f"TOC check error: {e}")

    # ── Criterion 4: Page numbers in footer (15 pts) ──────────────────────
    try:
        has_pg = result.get('has_page_numbers') or result.get('has_footer')
        if has_pg:
            score += 15
            subscores['page_numbers'] = True
            feedback_parts.append(
                "Page number field found in footer"
            )
        else:
            subscores['page_numbers'] = False
            feedback_parts.append(
                "Page numbers not found in footer. "
                "Per firm standards, centered page numbers are required in the footer."
            )
    except Exception as e:
        feedback_parts.append(f"Page number check error: {e}")

    # ── Pass determination ─────────────────────────────────────────────────
    # Must score >= 70. An agent completing only prerequisites (correct headings
    # but no TOC or footer) would score at most 60, which does not pass.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria evaluated",
        "subscores": subscores,
        "details": {
            "heading1_count": result.get('heading1_count', 0),
            "heading2_count": result.get('heading2_count', 0),
            "has_toc": result.get('has_toc', False),
            "has_page_numbers": result.get('has_page_numbers', False),
            "file_size_bytes": result.get('file_size', 0),
        }
    }
