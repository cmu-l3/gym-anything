#!/usr/bin/env python3
"""
Verifier for Segment + Scheduled Report task.

Occupation: Search Marketing Strategist
Task: Create a mobile organic search visitor segment and a linked weekly email report.

Scoring (100 points):
- New segment created during task window:  20 pts  (gate: if 0, score=0)
- Segment definition has device condition:  15 pts
- Segment definition has search condition:  15 pts
- Report period is weekly:                 20 pts
- Report email is analytics@marketingteam.test: 20 pts
- Report is linked to the new segment:     10 pts

Pass threshold: >= 70 points AND segment was created (anti-gaming gate).
"""

import json
import logging
import os
import tempfile
from typing import Any, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_EMAIL = "analytics@marketingteam.test"
EXPECTED_PERIOD = "week"


def _has_device_condition(definition: str) -> bool:
    """Check if segment definition includes a device-type filter."""
    d = definition.lower()
    return any(kw in d for kw in [
        "devicetype", "device_type", "device type",
        "smartphone", "tablet", "mobile", "mobiledevice",
    ])


def _has_search_condition(definition: str) -> bool:
    """Check if segment definition includes an organic search filter."""
    d = definition.lower()
    return any(kw in d for kw in [
        "referrertype", "referrer_type", "channelgrouping", "channel_grouping",
        "organic", "search", "referrerkeyword", "referrer_keyword",
        "serachengine", "searchengine",
    ])


def verify_segment_scheduled_report(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify segment + scheduled report pipeline was configured correctly."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # ── Retrieve result JSON ──────────────────────────────────────────────
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env("/tmp/segment_scheduled_report_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving result: {e}"}

    score = 0
    feedback = []
    subscores: Dict[str, bool] = {
        "segment_created": False,
        "segment_has_device_condition": False,
        "segment_has_search_condition": False,
        "report_weekly": False,
        "report_email_correct": False,
        "report_linked_to_segment": False,
    }

    seg = result.get("segment", {})
    rep = result.get("report", {})
    initial_seg_ids = result.get("initial_segment_ids", "")
    initial_rep_ids = result.get("initial_report_ids", "")

    seg_found = seg.get("found") is True or str(seg.get("found", "")).lower() == "true"
    rep_found = rep.get("found") is True or str(rep.get("found", "")).lower() == "true"
    seg_id = str(seg.get("idsegment", "")).strip()
    definition = seg.get("definition", "") or ""

    logger.info("Segment found=%s id=%s definition=%r", seg_found, seg_id, definition[:120])
    logger.info("Report found=%s period=%s idsegment=%s email_in_params=%s",
                rep_found, rep.get("period"), rep.get("idsegment"), rep.get("email_in_params"))

    # ── GATE: new segment must have been created ──────────────────────────
    seg_is_new = seg_found and (
        not initial_seg_ids or f",{seg_id}," not in f",{initial_seg_ids},"
    )
    if not seg_is_new:
        msg = "No new segment detected — task not completed" if not seg_found else \
              "Segment pre-existed before task (anti-gaming check failed)"
        return {
            "passed": False, "score": 0,
            "feedback": msg,
            "subscores": subscores,
        }

    # ── Criterion 1: segment created (20 pts) ────────────────────────────
    score += 20
    subscores["segment_created"] = True
    feedback.append(f"New segment created (id={seg_id}, name='{seg.get('name', '')}') [+20]")

    # ── Criterion 2: device condition (15 pts) ───────────────────────────
    if _has_device_condition(definition):
        score += 15
        subscores["segment_has_device_condition"] = True
        feedback.append("Segment definition includes mobile/device-type condition [+15]")
    else:
        feedback.append(
            f"Segment definition missing mobile/device-type condition "
            f"(definition: {definition[:100]!r}) [-15]"
        )

    # ── Criterion 3: search/organic condition (15 pts) ───────────────────
    if _has_search_condition(definition):
        score += 15
        subscores["segment_has_search_condition"] = True
        feedback.append("Segment definition includes organic/search referral condition [+15]")
    else:
        feedback.append(
            f"Segment definition missing organic/search condition "
            f"(definition: {definition[:100]!r}) [-15]"
        )

    # ── Criterion 4: report is weekly (20 pts) ───────────────────────────
    rep_is_new = rep_found and (
        not initial_rep_ids or
        f",{str(rep.get('idreport', '')).strip()}," not in f",{initial_rep_ids},"
    )
    if rep_is_new and rep.get("period", "").lower() == EXPECTED_PERIOD:
        score += 20
        subscores["report_weekly"] = True
        feedback.append("Email report scheduled with weekly period [+20]")
    elif rep_found:
        feedback.append(
            f"Report found but period is '{rep.get('period')}' (expected 'week') [-20]"
        )
    else:
        feedback.append("No new email report found [-20]")

    # ── Criterion 5: email recipient (20 pts) ────────────────────────────
    email_correct = (
        rep_found
        and (
            str(rep.get("email_in_params", "")).lower() == "true"
            or TARGET_EMAIL.lower() in (rep.get("parameters", "") or "").lower()
        )
    )
    if email_correct:
        score += 20
        subscores["report_email_correct"] = True
        feedback.append(f"Report email recipient {TARGET_EMAIL} found [+20]")
    else:
        feedback.append(f"Report email recipient {TARGET_EMAIL} NOT found in report parameters [-20]")

    # ── Criterion 6: report linked to the segment (10 pts) ───────────────
    rep_seg_id = str(rep.get("idsegment", "")).strip()
    if rep_found and rep_seg_id and rep_seg_id == seg_id:
        score += 10
        subscores["report_linked_to_segment"] = True
        feedback.append(f"Report linked to segment (idsegment={seg_id}) [+10]")
    elif rep_found:
        feedback.append(
            f"Report not linked to new segment "
            f"(report.idsegment={rep_seg_id!r}, segment.id={seg_id!r}) [-10]"
        )
    else:
        feedback.append("No report found — cannot check segment link [-10]")

    passed = score >= 70 and subscores["segment_created"]
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "segment": seg,
            "report": {k: v for k, v in rep.items() if k != "parameters"},
        },
    }
