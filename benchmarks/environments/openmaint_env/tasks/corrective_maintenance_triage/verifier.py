#!/usr/bin/env python3
"""Verifier for corrective_maintenance_triage task.

Scoring breakdown (100 points total):
  C1 (25 pts): Critical tickets (GAS_LEAK, EMERGENCY_LIGHT, HVAC_OVERHEAT) have
               priority set to critical/urgent/emergency.
  C2 (20 pts): Misclassified tickets have corrected categories.
  C3 (20 pts): Duplicate ticket (PAINT_PEEL_DUP) is closed/resolved.
  C4 (20 pts): All non-duplicate tickets have an assignee.
  C5 (15 pts): Contamination ticket (PAINT_PEEL_LEGIT) is still active and NOT closed.

Pass threshold: score >= 60
Do-nothing check: if no ticket states changed from seeded values, score = 0.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

CRITICAL_TAGS = ["GAS_LEAK", "EMERGENCY_LIGHT", "HVAC_OVERHEAT"]
CRITICAL_KEYWORDS = ["critical", "urgent", "emergency", "high", "1", "highest"]
CLOSED_KEYWORDS = ["closed", "resolved", "duplicate", "cancelled", "canceled", "done",
                    "completed", "rejected", "close"]
ACTIVE_NON_CLOSED = True


def _is_critical(priority_str):
    if not priority_str:
        return False
    p = priority_str.lower().strip()
    return any(kw in p for kw in CRITICAL_KEYWORDS)


def _is_closed(state):
    status = (state.get("status", "") or "").lower()
    flow = (state.get("flow_status", "") or "").lower()
    is_active = state.get("is_active", True)
    if any(kw in status for kw in CLOSED_KEYWORDS):
        return True
    if any(kw in flow for kw in CLOSED_KEYWORDS):
        return True
    if is_active is False:
        return True
    if state.get("deleted_or_missing"):
        return True
    return False


def _has_assignee(state):
    assignee = state.get("assignee", "")
    return bool(assignee and str(assignee).strip() and str(assignee).strip() != "None")


def _category_corrected(tag, state):
    cat = (state.get("category", "") or "").lower()
    if tag == "GAS_LEAK":
        return any(kw in cat for kw in ["mechanical", "hvac", "gas", "mech"])
    elif tag == "WINDOW_LATCH":
        return any(kw in cat for kw in ["structural", "building", "envelope", "architectural", "carpentry"])
    elif tag == "HVAC_OVERHEAT":
        return any(kw in cat for kw in ["mechanical", "hvac", "cooling", "mech"])
    return True


def verify_corrective_maintenance_triage(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    score = 0
    feedback_parts = []
    subscores = {}

    # Retrieve result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/cmt_result.json", local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}",
            "subscores": {},
        }

    if result.get("error"):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export error: {result['error']}",
            "subscores": {},
        }

    ticket_states = result.get("ticket_states", {})
    tickets_spec = result.get("tickets_spec", {})

    if not ticket_states:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No ticket state data found — setup may have failed.",
            "subscores": {},
        }

    # --- Do-nothing check ---
    # If no priorities changed and no tickets closed and no assignees added, score = 0
    any_priority_changed = False
    any_closed = False
    any_assigned = False
    for tag, state in ticket_states.items():
        spec = tickets_spec.get(tag, {})
        if state.get("error") or state.get("deleted_or_missing"):
            continue
        current_priority = (state.get("priority", "") or "").lower()
        seeded_priority = (spec.get("expected_priority", "") or "").lower()
        if current_priority and current_priority != seeded_priority:
            any_priority_changed = True
        if _is_closed(state):
            any_closed = True
        if _has_assignee(state):
            any_assigned = True

    if not any_priority_changed and not any_closed and not any_assigned:
        return {
            "passed": False,
            "score": 0,
            "feedback": "DO-NOTHING: No ticket modifications detected. All tickets unchanged from seeded state.",
            "subscores": {"c1_priority": 0, "c2_category": 0, "c3_duplicate": 0,
                          "c4_assignment": 0, "c5_contamination": 0},
        }

    # --- C1 (25 pts): Critical tickets have correct priority ---
    c1_correct = 0
    c1_total = len(CRITICAL_TAGS)
    for tag in CRITICAL_TAGS:
        state = ticket_states.get(tag, {})
        if state.get("error") or state.get("deleted_or_missing"):
            continue
        if _is_critical(state.get("priority", "")):
            c1_correct += 1

    c1 = round((c1_correct / max(c1_total, 1)) * 25, 2)
    subscores["c1_priority"] = c1
    score += c1
    feedback_parts.append(f"C1 Critical priorities: {c1_correct}/{c1_total} correct ({c1:.1f}/25)")

    # --- C2 (20 pts): Category corrections ---
    c2_tags = ["GAS_LEAK", "WINDOW_LATCH", "HVAC_OVERHEAT"]
    c2_correct = 0
    for tag in c2_tags:
        state = ticket_states.get(tag, {})
        if state.get("error") or state.get("deleted_or_missing"):
            continue
        if _category_corrected(tag, state):
            c2_correct += 1

    c2 = round((c2_correct / max(len(c2_tags), 1)) * 20, 2)
    subscores["c2_category"] = c2
    score += c2
    feedback_parts.append(f"C2 Category corrections: {c2_correct}/{len(c2_tags)} ({c2:.1f}/20)")

    # --- C3 (20 pts): Duplicate ticket closed ---
    dup_state = ticket_states.get("PAINT_PEEL_DUP", {})
    if _is_closed(dup_state):
        c3 = 20
        feedback_parts.append("C3 Duplicate closed (20/20)")
    elif dup_state.get("error") or dup_state.get("deleted_or_missing"):
        c3 = 15  # deleted is acceptable
        feedback_parts.append("C3 Duplicate removed/deleted — partial credit (15/20)")
    else:
        c3 = 0
        feedback_parts.append("C3 Duplicate NOT closed (0/20)")
    subscores["c3_duplicate"] = c3
    score += c3

    # --- C4 (20 pts): Non-duplicate tickets have assignees ---
    non_dup_tags = ["GAS_LEAK", "WINDOW_LATCH", "EMERGENCY_LIGHT",
                    "HVAC_OVERHEAT", "PAINT_PEEL_LEGIT"]
    c4_assigned = 0
    for tag in non_dup_tags:
        state = ticket_states.get(tag, {})
        if state.get("error") or state.get("deleted_or_missing"):
            continue
        if _has_assignee(state):
            c4_assigned += 1

    c4 = round((c4_assigned / max(len(non_dup_tags), 1)) * 20, 2)
    subscores["c4_assignment"] = c4
    score += c4
    feedback_parts.append(f"C4 Assignments: {c4_assigned}/{len(non_dup_tags)} assigned ({c4:.1f}/20)")

    # --- C5 (15 pts): Contamination ticket preserved ---
    contam_state = ticket_states.get("PAINT_PEEL_LEGIT", {})
    if contam_state.get("deleted_or_missing") or _is_closed(contam_state):
        c5 = 0
        feedback_parts.append("C5 CONTAMINATION: Legitimate ticket wrongly closed/deleted (0/15)")
        score = min(score, 50)  # cap total score
    else:
        c5 = 15
        feedback_parts.append("C5 Contamination ticket preserved (15/15)")
    subscores["c5_contamination"] = c5
    score += c5

    score = min(round(score, 2), 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
