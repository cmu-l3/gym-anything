#!/usr/bin/env python3
"""Verifier for multi_team_project_kickoff task.

Scoring breakdown (100 points, pass >= 70):
  C1  (10pts): Main channel phoenix-migration exists as private
  C2  (8pts): Main channel topic and description set correctly
  C3  (10pts): Sub-channels phoenix-frontend, phoenix-backend, phoenix-devops exist
  C4  (15pts): Main channel has all 6 team members
  C5  (12pts): Sub-channels have correct role-based members
  C6  (12pts): Project charter in main channel with required content
  C7  (7pts): Charter message pinned
  C8  (12pts): Sprint planning messages in all 3 sub-channels
  C9  (7pts): Each sprint message has team-specific tasks
  C10 (7pts): DM to pm.coordinator about project tracking
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/multi_team_project_kickoff_result.json"

ALL_MEMBERS = {"fe.lead", "be.lead", "qa.tester", "ux.designer", "pm.coordinator", "devops.lead"}
FE_MEMBERS = {"fe.lead", "ux.designer", "qa.tester"}
BE_MEMBERS = {"be.lead", "qa.tester"}
DEVOPS_MEMBERS = {"devops.lead", "be.lead"}


def verify_multi_team_project_kickoff(traj, env_info, task_info):
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

    main = result.get("main_channel", {})
    fe = result.get("frontend_channel", {})
    be = result.get("backend_channel", {})
    devops = result.get("devops_channel", {})

    # --- Do-nothing gate ---
    if not main.get("exists") and not fe.get("exists") and not be.get("exists") and not devops.get("exists"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No project channels created. Agent likely did nothing.",
        }

    # --- C1 (10pts): Main channel exists as private ---
    if main.get("exists"):
        if main.get("type") == "private":
            score += 10
            feedback.append("C1: +10 Main channel exists as private")
        else:
            score += 5
            feedback.append("C1: +5 Main channel exists but is public (expected private)")
    else:
        feedback.append("C1: +0 Main channel phoenix-migration not found")

    # --- C2 (8pts): Topic and description ---
    c2 = 0
    topic = (main.get("topic") or "").lower()
    desc = (main.get("description") or "").lower()
    if "cloud" in topic or "migration" in topic or "phoenix" in topic:
        c2 += 2
    if "q1" in topic or "q2" in topic or "2026" in topic:
        c2 += 2
    if "migration" in desc or "phoenix" in desc or "coordination" in desc:
        c2 += 2
    if "cloud" in desc or "project" in desc:
        c2 += 2
    score += c2
    feedback.append(f"C2: +{c2} Topic/description")

    # --- C3 (10pts): Sub-channels exist ---
    c3 = 0
    for ch_name, ch_data in [("frontend", fe), ("backend", be), ("devops", devops)]:
        if ch_data.get("exists"):
            c3 += 3
    if c3 == 9:
        c3 = 10  # Bonus for all 3
    score += c3
    feedback.append(f"C3: +{c3} Sub-channels exist ({sum(1 for c in [fe,be,devops] if c.get('exists'))}/3)")

    # --- C4 (15pts): Main channel members ---
    main_members = set(m.lower() for m in main.get("members", []))
    main_found = ALL_MEMBERS & main_members
    c4 = int(len(main_found) / len(ALL_MEMBERS) * 15) if ALL_MEMBERS else 0
    score += c4
    feedback.append(f"C4: +{c4} Main channel members ({len(main_found)}/{len(ALL_MEMBERS)})")

    # --- C5 (12pts): Sub-channel role-based members - 4pts each ---
    c5 = 0
    for expected, actual_data, name in [(FE_MEMBERS, fe, "frontend"), (BE_MEMBERS, be, "backend"), (DEVOPS_MEMBERS, devops, "devops")]:
        actual = set(m.lower() for m in actual_data.get("members", []))
        found = expected & actual
        if found == expected:
            c5 += 4
        elif len(found) > 0:
            c5 += 2
    score += c5
    feedback.append(f"C5: +{c5} Sub-channel members")

    # --- C6 (12pts): Project charter message ---
    main_msgs = main.get("messages", [])
    c6 = 0
    for msg in main_msgs:
        text = (msg.get("msg") or "").lower()
        has_name = "phoenix" in text
        has_timeline = "q1" in text or "q2" in text or "2026" in text
        has_objective = "migrat" in text or "cloud" in text or "infrastructure" in text
        has_team = sum(1 for m in ALL_MEMBERS if m in text) >= 3
        sub = sum([has_name, has_timeline, has_objective, has_team])
        if sub >= 4:
            c6 = 12
            break
        elif sub >= 3:
            c6 = max(c6, 9)
        elif sub >= 2:
            c6 = max(c6, 6)
    score += c6
    feedback.append(f"C6: +{c6} Project charter message")

    # --- C7 (7pts): Charter pinned ---
    pinned = main.get("pinned_messages", [])
    c7 = 0
    if len(pinned) > 0:
        c7 = 7
    else:
        if any(m.get("pinned") for m in main_msgs):
            c7 = 7
    score += c7
    feedback.append(f"C7: +{c7} Charter pinned")

    # --- C8 (12pts): Sprint planning messages in sub-channels ---
    c8 = 0
    for ch_data, name in [(fe, "frontend"), (be, "backend"), (devops, "devops")]:
        msgs = ch_data.get("messages", [])
        for msg in msgs:
            text = (msg.get("msg") or "").lower()
            if "sprint" in text or "planning" in text or "task" in text:
                c8 += 4
                break
    score += c8
    feedback.append(f"C8: +{c8} Sprint planning messages ({c8 // 4}/3 channels)")

    # --- C9 (7pts): Team-specific content in sprint messages ---
    c9 = 0
    # Frontend: UI, component, responsive
    for msg in fe.get("messages", []):
        text = (msg.get("msg") or "").lower()
        if any(kw in text for kw in ["ui", "component", "responsive", "frontend", "css"]):
            c9 += 2
            break
    # Backend: API, database, schema
    for msg in be.get("messages", []):
        text = (msg.get("msg") or "").lower()
        if any(kw in text for kw in ["api", "database", "schema", "backend", "endpoint"]):
            c9 += 2
            break
    # DevOps: CI/CD, pipeline, monitoring
    for msg in devops.get("messages", []):
        text = (msg.get("msg") or "").lower()
        if any(kw in text for kw in ["ci/cd", "pipeline", "monitoring", "deploy", "infrastructure"]):
            c9 += 3
            break
    score += c9
    feedback.append(f"C9: +{c9} Team-specific sprint content")

    # --- C10 (7pts): DM to pm.coordinator ---
    pm_dm = result.get("pm_dm", [])
    c10 = 0
    if len(pm_dm) > 0:
        c10 = 3
        for msg in pm_dm:
            text = (msg.get("msg") or "").lower()
            if any(kw in text for kw in ["project", "tracking", "board", "phoenix", "migration"]):
                c10 = 7
                break
    score += c10
    feedback.append(f"C10: +{c10} DM to pm.coordinator ({len(pm_dm)} messages)")

    passed = score >= 70
    summary = f"Score: {score}/100 (pass >= 70)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
