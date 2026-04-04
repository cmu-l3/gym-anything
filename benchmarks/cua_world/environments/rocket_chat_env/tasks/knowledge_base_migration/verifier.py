#!/usr/bin/env python3
"""Verifier for knowledge_base_migration task.

Scoring breakdown (100 points, pass >= 70):
  C1  (9pts): All 3 KB channels created (kb-architecture, kb-api-docs, kb-decisions)
  C2  (9pts): KB channel topics set appropriately
  C3 (15pts): Microservices/ADR content migrated to kb-decisions
  C4 (15pts): API endpoint docs migrated to kb-api-docs
  C5 (15pts): Event-driven architecture content migrated to kb-architecture
  C6  (9pts): At least one pinned message in each KB channel
  C7 (10pts): All 3 team members invited to all KB channels
  C8  (9pts): Index message posted in engineering-chat
  C9  (9pts): DM to tech.architect about reviewing content
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/knowledge_base_migration_result.json"

TEAM_MEMBERS = {"junior.dev", "senior.dev", "tech.architect"}


def verify_knowledge_base_migration(traj, env_info, task_info):
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

    arch = result.get("kb_architecture", {})
    api = result.get("kb_api_docs", {})
    dec = result.get("kb_decisions", {})

    # --- Do-nothing gate ---
    if not arch.get("exists") and not api.get("exists") and not dec.get("exists"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No KB channels created. Agent likely did nothing.",
        }

    # --- C1 (9pts): All 3 KB channels exist ---
    c1 = 0
    for ch in [arch, api, dec]:
        if ch.get("exists"):
            c1 += 3
    score += c1
    feedback.append(f"C1: +{c1} KB channels created ({c1 // 3}/3)")

    # --- C2 (9pts): Topics set ---
    c2 = 0
    arch_topic = (arch.get("topic") or "").lower()
    api_topic = (api.get("topic") or "").lower()
    dec_topic = (dec.get("topic") or "").lower()
    if "architecture" in arch_topic or "system" in arch_topic or "diagram" in arch_topic:
        c2 += 3
    if "api" in api_topic or "endpoint" in api_topic or "documentation" in api_topic:
        c2 += 3
    if "decision" in dec_topic or "adr" in dec_topic or "record" in dec_topic:
        c2 += 3
    score += c2
    feedback.append(f"C2: +{c2} KB channel topics")

    # --- C3 (15pts): ADR/microservices content in kb-decisions ---
    c3 = 0
    for msg in dec.get("messages", []):
        text = (msg.get("msg") or "").lower()
        has_microservices = "microservice" in text or "monolith" in text
        has_decision = "decision" in text or "adr" in text or "accepted" in text
        has_versioning = "versioning" in text or "deprecation" in text
        if has_microservices and has_decision:
            c3 = max(c3, 10)
        if has_versioning:
            c3 = min(c3 + 5, 15)
        if has_microservices or has_decision or has_versioning:
            c3 = max(c3, 5)
    score += c3
    feedback.append(f"C3: +{c3} ADR content in kb-decisions")

    # --- C4 (15pts): API docs content in kb-api-docs ---
    c4 = 0
    for msg in api.get("messages", []):
        text = (msg.get("msg") or "").lower()
        has_endpoints = "endpoint" in text or "/users" in text or "/orders" in text or "/auth" in text
        has_api = "api" in text or "rest" in text
        has_methods = "get" in text or "post" in text or "put" in text
        sub = sum([has_endpoints, has_api, has_methods])
        if sub >= 3:
            c4 = 15
            break
        elif sub >= 2:
            c4 = max(c4, 10)
        elif sub >= 1:
            c4 = max(c4, 5)
    score += c4
    feedback.append(f"C4: +{c4} API docs in kb-api-docs")

    # --- C5 (15pts): Event-driven architecture in kb-architecture ---
    c5 = 0
    for msg in arch.get("messages", []):
        text = (msg.get("msg") or "").lower()
        has_event = "event" in text or "kafka" in text or "event-driven" in text
        has_arch = "architecture" in text or "pattern" in text or "cqrs" in text or "saga" in text
        has_details = "broker" in text or "schema" in text or "sourcing" in text
        sub = sum([has_event, has_arch, has_details])
        if sub >= 3:
            c5 = 15
            break
        elif sub >= 2:
            c5 = max(c5, 10)
        elif sub >= 1:
            c5 = max(c5, 5)
    score += c5
    feedback.append(f"C5: +{c5} Architecture content in kb-architecture")

    # --- C6 (9pts): Pinned messages in each KB channel ---
    c6 = 0
    for ch_data, name in [(arch, "arch"), (api, "api"), (dec, "dec")]:
        pinned = ch_data.get("pinned_messages", [])
        has_pinned = len(pinned) > 0 or any(m.get("pinned") for m in ch_data.get("messages", []))
        if has_pinned:
            c6 += 3
    score += c6
    feedback.append(f"C6: +{c6} Pinned messages ({c6 // 3}/3 channels)")

    # --- C7 (10pts): Team members invited to all KB channels ---
    c7 = 0
    total_invites = 0
    for ch_data in [arch, api, dec]:
        members = set(m.lower() for m in ch_data.get("members", []))
        found = TEAM_MEMBERS & members
        total_invites += len(found)
    # 9 total possible invites (3 members x 3 channels)
    if total_invites >= 9:
        c7 = 10
    elif total_invites >= 6:
        c7 = 7
    elif total_invites >= 3:
        c7 = 4
    elif total_invites > 0:
        c7 = 2
    score += c7
    feedback.append(f"C7: +{c7} Team member invites ({total_invites}/9)")

    # --- C8 (9pts): Index message in engineering-chat ---
    c8 = 0
    for msg in result.get("engineering_chat_messages", []):
        text = (msg.get("msg") or "").lower()
        mentions_arch = "kb-architecture" in text or "architecture" in text
        mentions_api = "kb-api" in text or "api-docs" in text
        mentions_dec = "kb-decisions" in text or "decisions" in text
        count = sum([mentions_arch, mentions_api, mentions_dec])
        if count >= 3:
            c8 = 9
            break
        elif count >= 2:
            c8 = max(c8, 6)
        elif count >= 1:
            c8 = max(c8, 3)
    score += c8
    feedback.append(f"C8: +{c8} Index message in engineering-chat")

    # --- C9 (9pts): DM to tech.architect ---
    dm_msgs = result.get("architect_dm", [])
    c9 = 0
    if len(dm_msgs) > 0:
        c9 = 4
        for msg in dm_msgs:
            text = (msg.get("msg") or "").lower()
            if any(kw in text for kw in ["review", "accuracy", "check", "migrated", "knowledge base", "kb"]):
                c9 = 9
                break
    score += c9
    feedback.append(f"C9: +{c9} DM to tech.architect ({len(dm_msgs)} messages)")

    passed = score >= 70
    summary = f"Score: {score}/100 (pass >= 70)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
