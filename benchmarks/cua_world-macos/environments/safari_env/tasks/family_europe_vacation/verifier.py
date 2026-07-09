#!/usr/bin/env python3
"""Verifier for family_europe_vacation task.

Scoring (100 points total), pass threshold = 70:

  C1 (20 pts): Fresh Apple Notes note exists (created/modified after task start)
               — 10 pts note_found, +10 pts note_is_fresh
  C2 (15 pts): A flight/travel comparison site was visited
  C3 (15 pts): An accommodation site was visited
  C4 (15 pts): Note has substantial length (≥2000 chars = 15 pts; ≥500 = 8 pts)
  C5 (20 pts): Note contains domain keywords (≥5 of 9 = 20 pts; ≥2 = 10 pts)
  C6 (15 pts): Activity/tourism site visited AND note has ≥5 domain keywords

Gates:
  - No note AND no sites visited → score 0
  - Note present but neither flight nor accommodation site visited → cap at 15
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_family_europe_vacation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env("/tmp/family_europe_vacation_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 5, "feedback": f"Result parse error: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    score = 0
    feedback_parts = []

    visited_flight = bool(result.get("visited_flight_site"))
    visited_accommodation = bool(result.get("visited_accommodation_site"))
    visited_activity = bool(result.get("visited_activity_site"))
    note_found = bool(result.get("note_found"))
    note_fresh = bool(result.get("note_is_fresh"))
    note_length = int(result.get("note_length", 0))
    note_kw_count = int(result.get("note_keyword_count", 0))

    # ── Gate: did nothing ────────────────────────────────────────────────────
    if not note_found and not visited_flight and not visited_accommodation:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No Apple Notes note created and no relevant sites visited — agent did nothing",
        }

    # ── C1: Note found and fresh (20 pts) ────────────────────────────────────
    if note_found:
        score += 10
        feedback_parts.append("Apple Notes note found (+10)")
        if note_fresh:
            score += 10
            feedback_parts.append("Note was created/modified after task start (+10)")
        else:
            feedback_parts.append("Note is stale (pre-dates task start) (+0)")
    else:
        feedback_parts.append("No Apple Notes note found (+0)")

    # ── Gate: note with no research ──────────────────────────────────────────
    if note_found and note_fresh and not visited_flight and not visited_accommodation:
        score = min(score, 15)
        feedback_parts.append("Score capped: note present but no flight or accommodation site visited")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ── C2: Flight/travel site visited (15 pts) ──────────────────────────────
    if visited_flight:
        score += 15
        feedback_parts.append("Flight/travel comparison site visited (+15)")
    else:
        feedback_parts.append("No flight/travel site visited (+0)")

    # ── C3: Accommodation site visited (15 pts) ──────────────────────────────
    if visited_accommodation:
        score += 15
        feedback_parts.append("Accommodation site visited (+15)")
    else:
        feedback_parts.append("No accommodation site visited (+0)")

    # ── C4: Note length (15 pts) ─────────────────────────────────────────────
    if note_length >= 2000:
        score += 15
        feedback_parts.append(f"Note is comprehensive ({note_length} chars) (+15)")
    elif note_length >= 500:
        score += 8
        feedback_parts.append(f"Note has content but is brief ({note_length} chars, target ≥2000) (+8)")
    else:
        feedback_parts.append(f"Note is too short or empty ({note_length} chars) (+0)")

    # ── C5: Domain keywords present (20 pts) ─────────────────────────────────
    if note_kw_count >= 5:
        score += 20
        feedback_parts.append(f"Note contains {note_kw_count}+ domain keywords (+20)")
    elif note_kw_count >= 2:
        score += 10
        feedback_parts.append(f"Note contains {note_kw_count} domain keywords (target ≥5) (+10)")
    else:
        feedback_parts.append(f"Note contains only {note_kw_count} domain keywords (+0)")

    # ── C6: Activity site + keywords (15 pts) ────────────────────────────────
    activity_keywords_ok = note_kw_count >= 5
    if visited_activity and activity_keywords_ok:
        score += 15
        feedback_parts.append("Activity/tourism site visited and note has 5+ keywords (+15)")
    elif visited_activity or activity_keywords_ok:
        score += 7
        detail = "activity site visited" if visited_activity else "note has 5+ keywords"
        feedback_parts.append(f"Partial C6: {detail} (+7)")
    else:
        feedback_parts.append("No activity site visited and keyword count below 5 (+0)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "debug": {
            "note_found": note_found,
            "note_fresh": note_fresh,
            "note_length": note_length,
            "note_kw_count": note_kw_count,
            "visited_flight": visited_flight,
            "visited_accommodation": visited_accommodation,
            "visited_activity": visited_activity,
        },
    }
