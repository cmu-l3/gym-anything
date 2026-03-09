#!/usr/bin/env python3
"""Verifier for release_rollback_communication task.

Scoring breakdown (100 points, pass >= 70):
  C1  (8pts): 7.8.5 release message starred
  C2  (8pts): 8.0.2 release message reacted with :warning:
  C3 (10pts): rollback-8-0-2-coordination channel exists
  C4 (10pts): Channel description mentions rollback/payment regression
  C5 (12pts): Required members invited (qa.lead, devops.engineer, product.manager)
  C6 (15pts): Rollback plan message with version numbers and verification steps
  C7  (7pts): Rollback plan pinned
  C8 (10pts): DM to devops.engineer with deployment instructions
  C9 (10pts): Release-updates announcement about rollback
  C10(10pts): Admin status text about rollback
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/release_rollback_communication_result.json"


def verify_release_rollback_communication(traj, env_info, task_info):
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

    rb = result.get("rollback_channel", {})

    # --- Do-nothing gate ---
    if not rb.get("exists") and not result.get("starred_785") and not result.get("reaction_802"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No rollback channel created and no message actions taken. Agent likely did nothing.",
        }

    # --- C1 (8pts): Starred 7.8.5 message ---
    if result.get("starred_785"):
        score += 8
        feedback.append("C1: +8 Release 7.8.5 message starred")
    else:
        feedback.append("C1: +0 Release 7.8.5 message not starred")

    # --- C2 (8pts): Reacted to 8.0.2 with :warning: ---
    c2 = 0
    if result.get("reaction_802"):
        emoji = result.get("reaction_802_emoji", "")
        if "warning" in emoji.lower():
            c2 = 8
        else:
            c2 = 4  # Reacted but wrong emoji
    score += c2
    feedback.append(f"C2: +{c2} Reaction on 8.0.2 (emoji: {result.get('reaction_802_emoji', 'none')})")

    # --- C3 (10pts): Rollback channel exists ---
    if rb.get("exists"):
        score += 10
        feedback.append("C3: +10 Rollback channel exists")
    else:
        feedback.append("C3: +0 Rollback channel not found")

    # --- C4 (10pts): Channel description ---
    desc = (rb.get("description") or "").lower()
    c4 = 0
    if "rollback" in desc or "8.0.2" in desc:
        c4 += 5
    if "payment" in desc or "regression" in desc or "7.8.5" in desc:
        c4 += 5
    score += c4
    feedback.append(f"C4: +{c4} Channel description")

    # --- C5 (12pts): Members invited - 4pts each ---
    members = [m.lower() for m in rb.get("members", [])]
    c5 = 0
    for req in ["qa.lead", "devops.engineer", "product.manager"]:
        if req in members:
            c5 += 4
    score += c5
    feedback.append(f"C5: +{c5} Members invited ({sum(1 for r in ['qa.lead','devops.engineer','product.manager'] if r in members)}/3)")

    # --- C6 (15pts): Rollback plan message ---
    messages = rb.get("messages", [])
    c6 = 0
    for msg in messages:
        text = (msg.get("msg") or "").lower()
        has_802 = "8.0.2" in text
        has_785 = "7.8.5" in text
        has_reason = "payment" in text or "regression" in text
        has_steps = text.count("- ") >= 3 or text.count("1.") >= 1 or text.count("* ") >= 3
        sub = sum([has_802, has_785, has_reason, has_steps])
        if sub >= 4:
            c6 = 15
            break
        elif sub >= 3:
            c6 = max(c6, 10)
        elif sub >= 2:
            c6 = max(c6, 6)
    score += c6
    feedback.append(f"C6: +{c6} Rollback plan message")

    # --- C7 (7pts): Rollback plan pinned ---
    pinned = rb.get("pinned_messages", [])
    c7 = 0
    if len(pinned) > 0:
        c7 = 7
    else:
        if any(m.get("pinned") for m in messages):
            c7 = 7
    score += c7
    feedback.append(f"C7: +{c7} Pinned message ({len(pinned)} pinned)")

    # --- C8 (10pts): DM to devops.engineer ---
    dm_msgs = result.get("devops_dm", [])
    c8 = 0
    if len(dm_msgs) > 0:
        c8 = 5
        for msg in dm_msgs:
            text = (msg.get("msg") or "").lower()
            if any(kw in text for kw in ["rollback", "deploy", "7.8.5", "begin", "start"]):
                c8 = 10
                break
    score += c8
    feedback.append(f"C8: +{c8} DM to devops.engineer ({len(dm_msgs)} messages)")

    # --- C9 (10pts): Release-updates announcement ---
    announcement = (result.get("release_announcement") or "").lower()
    c9 = 0
    if "rollback" in announcement or "8.0.2" in announcement:
        c9 += 5
    if "do not deploy" in announcement or "rollback-" in announcement:
        c9 += 5
    score += c9
    feedback.append(f"C9: +{c9} Release-updates announcement")

    # --- C10 (10pts): Admin status text ---
    status = (result.get("admin_status") or "").lower()
    c10 = 0
    if "rollback" in status:
        c10 += 5
    if "deploy" in status or "do not" in status:
        c10 += 5
    score += c10
    feedback.append(f"C10: +{c10} Admin status text (found: {result.get('admin_status', 'none')[:60]})")

    passed = score >= 70
    summary = f"Score: {score}/100 (pass >= 70)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
