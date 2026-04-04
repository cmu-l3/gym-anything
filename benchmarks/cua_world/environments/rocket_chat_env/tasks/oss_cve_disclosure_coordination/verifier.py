#!/usr/bin/env python3
"""Verifier for oss_cve_disclosure_coordination task.

Occupation: Information Security Analyst
Industry: Open Source / Technology

Scenario: Security Lead at an open source foundation must manage coordinated
disclosure of a critical heap overflow (CVSS 9.8) in a widely-used library.
Must coordinate private patch review, notify downstream consumers under embargo,
set disclosure timeline, and communicate with the security researcher.

Scoring (100 points, pass >= 60):
  C1 (15pts): Private coordination channel created for the disclosure process
  C2 (15pts): All three maintainer parties engaged (core.maintainer, release.manager,
               lib.author invited to channel OR DM'd)
  C3 (15pts): Downstream consumers under embargo notified — at least 2 of 3
               (enterprise.consumer, cloud.vendor, distro.maintainer) DM'd or in channel
  C4 (10pts): Security researcher (security.researcher) contacted with
               acknowledgment/timeline
  C5 (15pts): Disclosure timeline specified in coordination content
               (date, deadline, or embargo window mentioned)
  C6 (10pts): Thread replies on triage channel messages showing active coordination
  C7 (10pts): Patch review process coordinated (keywords: patch, review, branch,
               merge, staging, testing, verify, fix)
  C8 (10pts): Advisory/CVE documentation referenced (cve, advisory, mitre, github
               advisory, cvss, security advisory, credit)
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/oss_cve_disclosure_coordination_result.json"

MAINTAINERS = ["core.maintainer", "release.manager", "lib.author"]
DOWNSTREAM = ["enterprise.consumer", "cloud.vendor", "distro.maintainer"]


def _collect_all_admin_text(result):
    texts = []
    cc = result.get("coord_channel", {})
    for m in cc.get("messages", []):
        if m.get("u") != "system":
            texts.append((m.get("msg") or "").lower())
    for m in result.get("triage_admin_messages", []):
        texts.append((m.get("msg") or "").lower())
    dms = result.get("direct_messages", {})
    for msgs in dms.values():
        for m in msgs:
            texts.append((m.get("msg") or "").lower())
    threads = result.get("triage_threads", {})
    for thread_msgs in threads.values():
        for m in thread_msgs:
            if m.get("u") == "admin":
                texts.append((m.get("msg") or "").lower())
    return texts


def verify_oss_cve_disclosure_coordination(traj, env_info, task_info):
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

    cc = result.get("coord_channel", {})
    cc_messages = cc.get("messages", [])
    cc_members = [m.lower() for m in cc.get("members", [])]
    triage_threads = result.get("triage_threads", {})
    dms = result.get("direct_messages", {})
    triage_admin = result.get("triage_admin_messages", [])

    all_texts = _collect_all_admin_text(result)
    combined = " ".join(all_texts)

    # Do-nothing gate
    cc_msg_count = len([m for m in cc_messages if m.get("u") != "system"])
    thread_count = sum(len(v) for v in triage_threads.values())
    dm_count = sum(len(v) for v in dms.values())

    if cc_msg_count == 0 and thread_count == 0 and dm_count == 0 and len(triage_admin) == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No coordination channel activity, no thread replies, no DMs. Agent likely did nothing.",
        }

    # --- C1 (15pts): Private coordination channel created ---
    c1 = 0
    if cc.get("found"):
        c1 = 15
        feedback.append(f"C1: +15 Disclosure coordination channel created: '{cc.get('name', 'unknown')}'")
    elif len(triage_admin) >= 2:
        c1 = 6
        feedback.append(f"C1: +6 No new channel but {len(triage_admin)} admin msgs in triage channel")
    else:
        feedback.append("C1: +0 No private coordination channel found")
    score += c1

    # --- C2 (15pts): Maintainers engaged ---
    c2 = 0
    maintainers_in_channel = [m for m in MAINTAINERS if m in cc_members]
    maintainers_dmd = []
    for m in MAINTAINERS:
        dm_key = m.replace(".", "_")
        if len(dms.get(dm_key, [])) > 0:
            maintainers_dmd.append(m)
    maintainers_mentioned = [m for m in MAINTAINERS if m in combined]
    all_engaged = set(maintainers_in_channel + maintainers_dmd + maintainers_mentioned)
    if len(all_engaged) >= 3:
        c2 = 15
    elif len(all_engaged) == 2:
        c2 = 10
    elif len(all_engaged) == 1:
        c2 = 5
    feedback.append(
        f"C2: +{c2} Maintainers engaged: channel={maintainers_in_channel}, "
        f"DM'd={maintainers_dmd}, mentioned={maintainers_mentioned}"
    )
    score += c2

    # --- C3 (15pts): Downstream consumers notified under embargo ---
    c3 = 0
    downstream_notified = []
    for d in DOWNSTREAM:
        dm_key = d.replace(".", "_").replace("-", "_")
        # Try variations of the key
        for key_try in [d.replace(".", "_"), d.replace(".", "_").replace("-", "_"),
                        "enterprise_consumer", "cloud_vendor", "distro_maintainer"]:
            if key_try in dms and len(dms[key_try]) > 0:
                downstream_notified.append(d)
                break
    # Also check if they are in coord channel members
    downstream_in_channel = [d for d in DOWNSTREAM if d in cc_members]
    all_downstream = set(downstream_notified + downstream_in_channel)
    if len(all_downstream) >= 3:
        c3 = 15
    elif len(all_downstream) == 2:
        c3 = 10
    elif len(all_downstream) == 1:
        c3 = 5
    feedback.append(
        f"C3: +{c3} Downstream consumers engaged: DM={downstream_notified}, "
        f"in_channel={downstream_in_channel}"
    )
    score += c3

    # --- C4 (10pts): Researcher contacted ---
    c4 = 0
    researcher_dm_count = len(dms.get("researcher", []))
    researcher_mentioned = "security.researcher" in combined or "acuteangle" in combined
    if researcher_dm_count > 0:
        c4 = 10
    elif researcher_mentioned:
        c4 = 4
    feedback.append(f"C4: +{c4} Researcher contacted (DMs: {researcher_dm_count}, mentioned: {researcher_mentioned})")
    score += c4

    # --- C5 (15pts): Disclosure timeline specified ---
    c5 = 0
    timeline_kw = [
        "embargo", "disclosure date", "2026-03", "march", "deadline",
        "7 day", "seven day", "72h", "72 hour", "coordinated release",
        "synchronized", "simultaneous", "publish", "go public", "timeline", "schedule"
    ]
    timeline_hits = [kw for kw in timeline_kw if kw in combined]
    if len(timeline_hits) >= 4:
        c5 = 15
    elif len(timeline_hits) >= 2:
        c5 = 10
    elif len(timeline_hits) >= 1:
        c5 = 5
    feedback.append(f"C5: +{c5} Disclosure timeline keywords ({len(timeline_hits)}): {timeline_hits[:4]}")
    score += c5

    # --- C6 (10pts): Thread replies on triage messages ---
    c6 = 0
    threads_replied = sum(1 for v in triage_threads.values() if len(v) > 0)
    if threads_replied >= 2:
        c6 = 10
    elif threads_replied == 1:
        c6 = 5
    thread_counts = {k: len(v) for k, v in triage_threads.items()}
    feedback.append(f"C6: +{c6} Thread replies on triage messages ({threads_replied}/2): {thread_counts}")
    score += c6

    # --- C7 (10pts): Patch review process coordinated ---
    c7 = 0
    patch_kw = ["patch", "review", "branch", "merge", "staging", "testing",
                "test", "verify", "fix", "hotfix", "security fix", "backport"]
    patch_hits = [kw for kw in patch_kw if kw in combined]
    if len(patch_hits) >= 4:
        c7 = 10
    elif len(patch_hits) >= 2:
        c7 = 6
    elif len(patch_hits) >= 1:
        c7 = 3
    feedback.append(f"C7: +{c7} Patch review coordination ({len(patch_hits)} keywords: {patch_hits[:4]})")
    score += c7

    # --- C8 (10pts): Advisory/CVE documentation ---
    c8 = 0
    advisory_kw = ["cve", "advisory", "mitre", "cvss", "security advisory",
                   "github advisory", "nvd", "credit", "acknowledge", "disclosure policy"]
    advisory_hits = [kw for kw in advisory_kw if kw in combined]
    if len(advisory_hits) >= 3:
        c8 = 10
    elif len(advisory_hits) >= 2:
        c8 = 6
    elif len(advisory_hits) >= 1:
        c8 = 3
    feedback.append(f"C8: +{c8} Advisory/CVE documentation ({len(advisory_hits)} keywords: {advisory_hits[:4]})")
    score += c8

    passed = score >= 60
    summary = f"Score: {score}/100 (pass >= 60)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
