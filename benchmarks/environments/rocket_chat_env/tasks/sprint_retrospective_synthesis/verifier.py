#!/usr/bin/env python3
"""Verifier for sprint_retrospective_synthesis task.

Scoring breakdown (100 points, pass >= 70):
  C1  (8pts):  Channel q1-retro-action-items exists (public)
  C2  (8pts):  Topic contains "Q1" and "retro" and "action" (case-insensitive)
  C3  (12pts): Required members invited (eng.director, alpha.lead, beta.lead,
               gamma.lead, product.manager) - partial credit
  C4  (15pts): Synthesized summary with cross-cutting themes (must mention
               code review/reviews + at least one team name or cross-team ref)
  C5  (15pts): Action items message with >= 3 items AND owner assignments
  C6  (7pts):  Action items message is pinned
  C7  (10pts): DM to eng.director about retrospective/cross-team issues
  C8  (8pts):  Confirmation message posted in #retro-team-alpha
  C9  (8pts):  Confirmation message posted in #retro-team-beta
  C10 (9pts):  Confirmation message posted in #retro-team-gamma
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/sprint_retrospective_synthesis_result.json"


def verify_sprint_retrospective_synthesis(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []

    ac = result.get("action_channel", {})

    # --- Do-nothing gate ---
    if not ac.get("exists", False):
        messages = ac.get("messages", [])
        dm_msgs = result.get("eng_director_dm", {}).get("messages", [])
        alpha_msgs = result.get("retro_team_alpha", {}).get("admin_messages", [])
        beta_msgs = result.get("retro_team_beta", {}).get("admin_messages", [])
        gamma_msgs = result.get("retro_team_gamma", {}).get("admin_messages", [])
        total_actions = (
            len(messages) + len(dm_msgs) + len(alpha_msgs)
            + len(beta_msgs) + len(gamma_msgs)
        )
        if total_actions == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No action items channel created and no actions taken. Agent likely did nothing.",
            }

    # --- C1 (8pts): Public channel q1-retro-action-items exists ---
    if ac.get("exists"):
        if ac.get("type") == "public":
            score += 8
            feedback.append("C1: +8 Public action items channel exists")
        else:
            score += 4
            feedback.append("C1: +4 Action items channel exists but is private (expected public)")
    else:
        feedback.append("C1: +0 Channel q1-retro-action-items not found")

    # --- C2 (8pts): Channel topic ---
    topic = (ac.get("topic") or "").lower()
    c2 = 0
    if "q1" in topic:
        c2 += 3
    if "retro" in topic:
        c2 += 2
    if "action" in topic:
        c2 += 3
    score += c2
    feedback.append(f"C2: +{c2} Topic check (found: {ac.get('topic', 'none')[:120]})")

    # --- C3 (12pts): Required members invited - partial credit ---
    members = [m.lower() for m in ac.get("members", [])]
    c3 = 0
    required_members = [
        "eng.director", "alpha.lead", "beta.lead",
        "gamma.lead", "product.manager",
    ]
    found_members = []
    # 12 points across 5 members: first 4 get 2pts each, last gets 4pts
    # Simpler: award 2pts per member found, up to 12 (cap at 12)
    for req in required_members:
        if req in members:
            c3 += 2
            found_members.append(req)
    # Award up to 12 maximum, with bonus for getting all 5
    if len(found_members) == 5:
        c3 = 12
    else:
        c3 = min(c3, 10)  # partial credit capped at 10 if not all found
    score += c3
    feedback.append(f"C3: +{c3} Members ({len(found_members)}/5: {found_members})")

    # --- C4 (15pts): Synthesized summary with cross-cutting themes ---
    messages = ac.get("messages", [])
    c4 = 0
    for msg in messages:
        text = (msg.get("msg") or "").lower()
        # Must mention code review(s)
        has_code_review = (
            "code review" in text or "code reviews" in text
            or "review turnaround" in text or "review sla" in text
        )
        # Must reference cross-team or at least one team name
        has_cross_ref = (
            "cross-team" in text or "cross team" in text
            or "multiple teams" in text or "both team" in text
            or "alpha" in text or "beta" in text or "gamma" in text
        )
        # Check for theme-related language
        has_theme_word = (
            "theme" in text or "pattern" in text or "common" in text
            or "recurring" in text or "shared" in text
            or "across" in text or "both" in text
        )
        if has_code_review and has_cross_ref:
            # Full marks if mentions code review + cross-team reference
            c4 = 15
            break
        elif has_code_review:
            c4 = max(c4, 10)
        elif has_cross_ref and has_theme_word:
            c4 = max(c4, 8)
        elif has_cross_ref or has_theme_word:
            c4 = max(c4, 5)
    score += c4
    feedback.append(f"C4: +{c4} Synthesized summary with cross-cutting themes")

    # --- C5 (15pts): Action items message with >= 3 items AND owner assignments ---
    c5 = 0
    best_action_msg = None
    best_action_score = 0
    for msg in messages:
        text = (msg.get("msg") or "")
        text_lower = text.lower()

        # Count numbered or bulleted items
        # Look for patterns like "1.", "2.", "- ", "* ", "1)", etc.
        numbered = len(re.findall(r'(?:^|\n)\s*\d+[\.\)]\s', text))
        bulleted = len(re.findall(r'(?:^|\n)\s*[-*]\s', text))
        item_count = max(numbered, bulleted)
        # Also try counting by newlines that start with action-like words
        if item_count < 3:
            action_lines = len(re.findall(
                r'(?:^|\n)\s*(?:action|item|task|establish|implement|create|set up|define|reduce|improve)',
                text_lower
            ))
            item_count = max(item_count, action_lines)

        # Check for owner assignments (usernames or @mentions)
        owner_names = [
            "alpha.lead", "beta.lead", "gamma.lead",
            "eng.director", "product.manager", "ux.researcher",
        ]
        owners_found = sum(1 for name in owner_names if name in text_lower)
        has_owners = owners_found >= 1

        msg_score = 0
        if item_count >= 3 and has_owners:
            msg_score = 15
        elif item_count >= 3:
            msg_score = 10
        elif item_count >= 2 and has_owners:
            msg_score = 10
        elif item_count >= 1 and has_owners:
            msg_score = 7
        elif item_count >= 1:
            msg_score = 5

        if msg_score > best_action_score:
            best_action_score = msg_score
            best_action_msg = msg

    c5 = best_action_score
    score += c5
    feedback.append(f"C5: +{c5} Action items message")

    # --- C6 (7pts): Action items message is pinned ---
    pinned = ac.get("pinned_messages", [])
    c6 = 0
    if len(pinned) > 0:
        c6 = 7
    else:
        # Fallback: check if any message has pinned flag
        any_pinned = any(m.get("pinned") for m in messages)
        if any_pinned:
            c6 = 7
    score += c6
    feedback.append(f"C6: +{c6} Pinned messages ({len(pinned)} found)")

    # --- C7 (10pts): DM to eng.director about retrospective/cross-team issues ---
    dm_messages = result.get("eng_director_dm", {}).get("messages", [])
    c7 = 0
    if len(dm_messages) > 0:
        c7 = 5
        for msg in dm_messages:
            text = (msg.get("msg") or "").lower()
            retro_keywords = [
                "retro", "retrospective", "sprint", "q1",
                "cross-team", "cross team", "action item",
                "code review", "theme", "summary", "finding",
            ]
            if any(kw in text for kw in retro_keywords):
                c7 = 10
                break
    score += c7
    feedback.append(f"C7: +{c7} DM to eng.director ({len(dm_messages)} messages)")

    # --- C8 (8pts): Confirmation message in #retro-team-alpha ---
    alpha_admin_msgs = result.get("retro_team_alpha", {}).get("admin_messages", [])
    c8 = 0
    # Filter to only messages posted AFTER setup (exclude seeded messages)
    # Seeded messages are the retro feedback; confirmation should reference
    # action items, captured, or the new channel
    for msg in alpha_admin_msgs:
        text = (msg.get("msg") or "").lower()
        # Confirmation should mention capturing feedback or the action items channel
        confirm_keywords = [
            "captured", "action item", "q1-retro", "cross-team",
            "summary", "synthesized", "consolidated", "compiled",
            "noted", "acknowledged", "recorded", "tracked",
            "feedback", "thank",
        ]
        if any(kw in text for kw in confirm_keywords):
            c8 = 8
            break
    # If no keyword-matched message found, but admin posted something new
    # (beyond the 4 seeded messages), give partial credit
    if c8 == 0 and len(alpha_admin_msgs) > 4:
        c8 = 4
    score += c8
    feedback.append(f"C8: +{c8} Confirmation in #retro-team-alpha ({len(alpha_admin_msgs)} admin msgs)")

    # --- C9 (8pts): Confirmation message in #retro-team-beta ---
    beta_admin_msgs = result.get("retro_team_beta", {}).get("admin_messages", [])
    c9 = 0
    for msg in beta_admin_msgs:
        text = (msg.get("msg") or "").lower()
        confirm_keywords = [
            "captured", "action item", "q1-retro", "cross-team",
            "summary", "synthesized", "consolidated", "compiled",
            "noted", "acknowledged", "recorded", "tracked",
            "feedback", "thank",
        ]
        if any(kw in text for kw in confirm_keywords):
            c9 = 8
            break
    if c9 == 0 and len(beta_admin_msgs) > 5:
        c9 = 4
    score += c9
    feedback.append(f"C9: +{c9} Confirmation in #retro-team-beta ({len(beta_admin_msgs)} admin msgs)")

    # --- C10 (9pts): Confirmation message in #retro-team-gamma ---
    gamma_admin_msgs = result.get("retro_team_gamma", {}).get("admin_messages", [])
    c10 = 0
    for msg in gamma_admin_msgs:
        text = (msg.get("msg") or "").lower()
        confirm_keywords = [
            "captured", "action item", "q1-retro", "cross-team",
            "summary", "synthesized", "consolidated", "compiled",
            "noted", "acknowledged", "recorded", "tracked",
            "feedback", "thank",
        ]
        if any(kw in text for kw in confirm_keywords):
            c10 = 9
            break
    if c10 == 0 and len(gamma_admin_msgs) > 5:
        c10 = 4
    score += c10
    feedback.append(f"C10: +{c10} Confirmation in #retro-team-gamma ({len(gamma_admin_msgs)} admin msgs)")

    passed = score >= 70
    summary = f"Score: {score}/100 (pass >= 70)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
