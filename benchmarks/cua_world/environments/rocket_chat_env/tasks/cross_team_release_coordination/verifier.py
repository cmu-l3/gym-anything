#!/usr/bin/env python3
"""Verifier for cross_team_release_coordination task.

Scoring breakdown (100 points, pass >= 70):
  C1  (8pts):  Public channel release-v3-coordination exists
  C2  (7pts):  Topic contains v3.0 and deployment window date/time
  C3  (12pts): Required members invited (2pts each x 6)
  C4  (12pts): Deployment runbook with ordered sequence and rollback triggers
  C5  (5pts):  Runbook message pinned
  C6  (10pts): Go/no-go tracker with team statuses (GO + CONDITIONAL)
  C7  (8pts):  Message in #team-frontend about cross-browser tests
  C8  (10pts): Rollback procedure summary with team-specific procedures
  C9  (10pts): DM to vp.engineering with readiness summary
  C10 (9pts):  Release notice in #release-announcements about v3.0
  C11 (9pts):  At least 3 distinct messages in coordination channel
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/cross_team_release_coordination_result.json"


def verify_cross_team_release_coordination(traj, env_info, task_info):
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

    coord = result.get("coordination_channel", {})

    # --- Do-nothing gate ---
    if not coord.get("exists", False):
        messages = coord.get("messages", [])
        dm_msgs = result.get("vp_engineering_dm", {}).get("messages", [])
        frontend_msgs = result.get("team_frontend", {}).get("admin_messages", [])
        announce_msgs = result.get("release_announcements", {}).get("admin_messages", [])
        if len(messages) == 0 and len(dm_msgs) == 0 and len(frontend_msgs) == 0 and len(announce_msgs) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No coordination channel created and no actions taken. Agent likely did nothing.",
            }

    # --- C1 (8pts): Public channel exists ---
    if coord.get("exists"):
        if coord.get("type") == "public":
            score += 8
            feedback.append("C1: +8 Public coordination channel exists")
        else:
            score += 4
            feedback.append("C1: +4 Coordination channel exists but is private (expected public)")
    else:
        feedback.append("C1: +0 Coordination channel release-v3-coordination not found")

    # --- C2 (7pts): Channel topic ---
    topic = (coord.get("topic") or "").lower()
    c2 = 0
    if "v3.0" in topic or "v3" in topic:
        c2 += 3
    if "2026-03-07" in topic or "02:00" in topic:
        c2 += 2
    if any(kw in topic for kw in ["deploy", "release", "maintenance", "window", "coordinat"]):
        c2 += 2
    c2 = min(c2, 7)
    score += c2
    feedback.append(f"C2: +{c2} Topic check (found: {coord.get('topic', 'none')[:120]})")

    # --- C3 (12pts): Members invited - 2pts each ---
    members = [m.lower() for m in coord.get("members", [])]
    c3 = 0
    required_members = ["vp.engineering", "frontend.lead", "backend.lead", "payments.lead", "infra.lead", "qa.lead"]
    found_members = []
    for req in required_members:
        if req in members:
            c3 += 2
            found_members.append(req)
    score += c3
    feedback.append(f"C3: +{c3} Members ({len(found_members)}/6: {found_members})")

    # --- C4 (12pts): Deployment runbook with ordered sequence and rollback triggers ---
    messages = coord.get("messages", [])
    c4 = 0
    for msg in messages:
        text = (msg.get("msg") or "").lower()
        # Check for ordered deployment sequence
        has_infra = any(kw in text for kw in ["infrastructure", "infra"])
        has_backend = "backend" in text
        has_payments = "payment" in text
        has_frontend = "frontend" in text
        # Check for rollback triggers
        has_rollback_trigger = any(kw in text for kw in ["error rate", "latency", "rollback trigger", "failure rate"])
        has_sequence = any(kw in text for kw in ["runbook", "deployment sequence", "deploy", "order"])

        seq_count = sum([has_infra, has_backend, has_payments, has_frontend])
        msg_score = 0
        if seq_count >= 3 and has_sequence:
            msg_score += 6
        elif seq_count >= 2:
            msg_score += 3
        if has_rollback_trigger:
            msg_score += 6
        elif any(kw in text for kw in ["rollback", "2%", "500ms", "0.1%"]):
            msg_score += 3

        c4 = max(c4, min(msg_score, 12))
    score += c4
    feedback.append(f"C4: +{c4} Deployment runbook message")

    # --- C5 (5pts): Runbook pinned ---
    pinned = coord.get("pinned_messages", [])
    c5 = 0
    if len(pinned) > 0:
        c5 = 5
    else:
        any_pinned = any(m.get("pinned") for m in messages)
        if any_pinned:
            c5 = 5
    score += c5
    feedback.append(f"C5: +{c5} Pinned messages ({len(pinned)} found)")

    # --- C6 (10pts): Go/no-go tracker with team statuses ---
    c6 = 0
    for msg in messages:
        text = (msg.get("msg") or "").lower()
        has_go = "go" in text
        has_conditional = "conditional" in text
        has_teams = sum([
            "backend" in text,
            "payment" in text,
            "infra" in text or "infrastructure" in text,
            "frontend" in text,
        ])
        msg_score = 0
        if has_go and has_conditional and has_teams >= 2:
            msg_score = 10
        elif has_go and has_teams >= 2:
            msg_score = 6
        elif has_teams >= 1 and (has_go or has_conditional):
            msg_score = 3
        c6 = max(c6, msg_score)
    score += c6
    feedback.append(f"C6: +{c6} Go/no-go tracker message")

    # --- C7 (8pts): Message in #team-frontend about cross-browser tests ---
    frontend_msgs = result.get("team_frontend", {}).get("admin_messages", [])
    c7 = 0
    # Filter out setup messages (checklist seeds) - only look for admin messages
    # that are about cross-browser / deployment window
    for msg in frontend_msgs:
        text = (msg.get("msg") or "").lower()
        # Skip the seeded checklist message
        if "pre-release checklist" in text and "asset bundle" in text:
            continue
        has_browser = any(kw in text for kw in ["cross-browser", "browser", "regression"])
        has_deploy = any(kw in text for kw in ["deployment", "deploy", "window", "v3.0", "v3"])
        if has_browser and has_deploy:
            c7 = 8
            break
        elif has_browser or has_deploy:
            c7 = max(c7, 4)
    score += c7
    feedback.append(f"C7: +{c7} Message in #team-frontend ({len(frontend_msgs)} admin messages)")

    # --- C8 (10pts): Rollback procedure summary with team-specific procedures ---
    c8 = 0
    rollback_keywords = [
        "blue-green",
        "feature flag",
        "kill switch",
        "kubectl rollout",
        "dns switch",
        "dns failover",
        "cdn cache",
        "rollback",
    ]
    for msg in messages:
        text = (msg.get("msg") or "").lower()
        if "rollback" not in text:
            continue
        found_procedures = sum(1 for kw in rollback_keywords[:7] if kw in text)
        if found_procedures >= 3:
            c8 = max(c8, 10)
        elif found_procedures >= 2:
            c8 = max(c8, 7)
        elif found_procedures >= 1:
            c8 = max(c8, 4)
    score += c8
    feedback.append(f"C8: +{c8} Rollback procedure summary")

    # --- C9 (10pts): DM to vp.engineering with readiness summary ---
    dm_messages = result.get("vp_engineering_dm", {}).get("messages", [])
    c9 = 0
    if len(dm_messages) > 0:
        c9 = 4
        for msg in dm_messages:
            text = (msg.get("msg") or "").lower()
            has_go_count = any(kw in text for kw in ["3 teams", "three teams", "3/4", "3 go", "three go"])
            has_conditional = "conditional" in text
            has_readiness = any(kw in text for kw in ["readiness", "ready", "summary", "status", "v3", "release"])
            if has_go_count and has_conditional:
                c9 = 10
                break
            elif has_go_count or has_conditional:
                c9 = max(c9, 7)
            elif has_readiness:
                c9 = max(c9, 5)
    score += c9
    feedback.append(f"C9: +{c9} DM to vp.engineering ({len(dm_messages)} messages)")

    # --- C10 (9pts): Release notice in #release-announcements ---
    announce_msgs = result.get("release_announcements", {}).get("admin_messages", [])
    c10 = 0
    for msg in announce_msgs:
        text = (msg.get("msg") or "").lower()
        # Skip seeded past release notices
        if "v2.8" in text or "v2.9" in text:
            continue
        has_v3 = "v3.0" in text or "v3" in text
        has_deploy = any(kw in text for kw in ["deploy", "release", "maintenance", "window"])
        has_standby = any(kw in text for kw in ["standby", "stand-by", "available", "ready", "on call"])
        if has_v3 and has_deploy:
            c10 = 6
            if has_standby:
                c10 = 9
            break
        elif has_v3:
            c10 = max(c10, 3)
    score += c10
    feedback.append(f"C10: +{c10} Release notice in #release-announcements")

    # --- C11 (9pts): At least 3 distinct messages in coordination channel ---
    # Count non-system messages posted by admin
    admin_messages = [m for m in messages if m.get("u") == "admin" and m.get("msg", "").strip()]
    c11 = 0
    if len(admin_messages) >= 3:
        c11 = 9
    elif len(admin_messages) == 2:
        c11 = 5
    elif len(admin_messages) == 1:
        c11 = 2
    score += c11
    feedback.append(f"C11: +{c11} Distinct messages in coordination channel ({len(admin_messages)} admin messages)")

    passed = score >= 70
    summary = f"Score: {score}/100 (pass >= 70)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
