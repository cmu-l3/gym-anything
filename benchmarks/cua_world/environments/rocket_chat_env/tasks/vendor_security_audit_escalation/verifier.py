#!/usr/bin/env python3
"""Verifier for vendor_security_audit_escalation task.

Scoring breakdown (100 points, pass >= 70):
  C1  (8pts): Pentest alert message starred in #security-alerts
  C2 (10pts): Private channel sec-remediation-2026-03-06 exists
  C3 (10pts): Channel topic contains Critical + at least 2 CVE numbers + deadline date
  C4 (15pts): Required members invited (ciso, security.analyst, vendor.liaison,
              compliance.officer, devops.lead) - 3pts each
  C5 (12pts): Vulnerability triage matrix message with all 3 CVEs and CVSS scores
  C6  (7pts): Triage matrix message pinned
  C7 (10pts): Thread reply on pentest alert in #security-alerts mentioning remediation channel
  C8 (10pts): DM to compliance.officer about PCI-DSS/compliance/notification
  C9  (8pts): DM to vendor.liaison about vendor contact/patch/PayStream/IdentityBridge
  C10(10pts): Status update in remediation channel about containment/vendor contacts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/vendor_security_audit_escalation_result.json"


def verify_vendor_security_audit_escalation(traj, env_info, task_info):
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

    rem = result.get("remediation_channel", {})

    # --- Do-nothing gate ---
    if not rem.get("exists", False):
        messages = rem.get("messages", [])
        comp_dm_msgs = result.get("compliance_officer_dm", {}).get("messages", [])
        vend_dm_msgs = result.get("vendor_liaison_dm", {}).get("messages", [])
        thread_msgs = result.get("security_alerts", {}).get("thread_replies", [])
        starred = result.get("security_alerts", {}).get("pentest_starred", False)
        if (
            len(messages) == 0
            and len(comp_dm_msgs) == 0
            and len(vend_dm_msgs) == 0
            and len(thread_msgs) == 0
            and not starred
        ):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No remediation channel created and no actions taken. Agent likely did nothing.",
            }

    # --- C1 (8pts): Pentest alert message starred ---
    pentest_starred = result.get("security_alerts", {}).get("pentest_starred", False)
    c1 = 0
    if pentest_starred:
        c1 = 8
    score += c1
    feedback.append(f"C1: +{c1} Pentest alert starred ({pentest_starred})")

    # --- C2 (10pts): Private channel exists ---
    c2 = 0
    if rem.get("exists"):
        if rem.get("type") == "private":
            c2 = 10
            feedback.append("C2: +10 Private remediation channel exists")
        else:
            c2 = 5
            feedback.append("C2: +5 Remediation channel exists but is public (expected private)")
    else:
        feedback.append("C2: +0 Remediation channel sec-remediation-2026-03-06 not found")
    score += c2

    # --- C3 (10pts): Channel topic ---
    topic = (rem.get("topic") or "").lower()
    c3 = 0
    if "critical" in topic:
        c3 += 3
    # Check for at least 2 CVE numbers
    cve_ids = ["cve-2026-0142", "cve-2026-0198", "cve-2026-0215"]
    cves_found = sum(1 for cve in cve_ids if cve in topic)
    if cves_found >= 2:
        c3 += 4
    elif cves_found == 1:
        c3 += 2
    if "2026-03-13" in topic:
        c3 += 3
    score += c3
    feedback.append(f"C3: +{c3} Topic check (found: {rem.get('topic', 'none')[:120]})")

    # --- C4 (15pts): Members invited - 3pts each ---
    members = [m.lower() for m in rem.get("members", [])]
    c4 = 0
    required_members = ["ciso", "security.analyst", "vendor.liaison", "compliance.officer", "devops.lead"]
    found_members = []
    for req in required_members:
        if req in members:
            c4 += 3
            found_members.append(req)
    score += c4
    feedback.append(f"C4: +{c4} Members ({len(found_members)}/5: {found_members})")

    # --- C5 (12pts): Vulnerability triage matrix with all 3 CVEs and CVSS scores ---
    messages = rem.get("messages", [])
    c5 = 0
    best_triage_score = 0
    triage_msg_text = ""
    for msg in messages:
        text = (msg.get("msg") or "").lower()
        cve_count = 0
        cvss_count = 0
        if "cve-2026-0142" in text:
            cve_count += 1
        if "cve-2026-0198" in text:
            cve_count += 1
        if "cve-2026-0215" in text:
            cve_count += 1
        if "9.8" in text:
            cvss_count += 1
        if "9.1" in text:
            cvss_count += 1
        if "8.6" in text:
            cvss_count += 1
        # Score: 2pts per CVE found, 2pts per CVSS found
        msg_score = min(cve_count * 2, 6) + min(cvss_count * 2, 6)
        if msg_score > best_triage_score:
            best_triage_score = msg_score
            triage_msg_text = text
    c5 = best_triage_score
    score += c5
    feedback.append(f"C5: +{c5} Vulnerability triage matrix message")

    # --- C6 (7pts): Triage matrix message pinned ---
    pinned = rem.get("pinned_messages", [])
    c6 = 0
    if len(pinned) > 0:
        # Check if any pinned message contains CVE references (confirming it's the triage matrix)
        for p in pinned:
            p_text = (p.get("msg") or "").lower()
            if "cve-2026" in p_text:
                c6 = 7
                break
        if c6 == 0:
            # A message is pinned but may not be the triage matrix
            c6 = 4
    else:
        # Fallback: check pinned flag on messages
        any_pinned = any(m.get("pinned") for m in messages)
        if any_pinned:
            c6 = 4
    score += c6
    feedback.append(f"C6: +{c6} Pinned triage matrix ({len(pinned)} pinned messages found)")

    # --- C7 (10pts): Thread reply on pentest alert ---
    thread_replies = result.get("security_alerts", {}).get("thread_replies", [])
    c7 = 0
    if len(thread_replies) > 0:
        c7 = 6
        for reply in thread_replies:
            text = (reply.get("msg") or "").lower()
            if any(kw in text for kw in ["remediation", "channel", "sec-remediation", "mobilized", "team"]):
                c7 = 10
                break
    score += c7
    feedback.append(f"C7: +{c7} Thread reply on pentest alert ({len(thread_replies)} replies)")

    # --- C8 (10pts): DM to compliance.officer about PCI-DSS ---
    comp_dm_messages = result.get("compliance_officer_dm", {}).get("messages", [])
    c8 = 0
    if len(comp_dm_messages) > 0:
        c8 = 5
        for msg in comp_dm_messages:
            text = (msg.get("msg") or "").lower()
            if any(kw in text for kw in ["pci-dss", "pci dss", "compliance", "notification", "reporting"]):
                c8 = 10
                break
    score += c8
    feedback.append(f"C8: +{c8} DM to compliance.officer ({len(comp_dm_messages)} messages)")

    # --- C9 (8pts): DM to vendor.liaison about vendor contact ---
    vend_dm_messages = result.get("vendor_liaison_dm", {}).get("messages", [])
    c9 = 0
    if len(vend_dm_messages) > 0:
        c9 = 4
        for msg in vend_dm_messages:
            text = (msg.get("msg") or "").lower()
            if any(kw in text for kw in ["paystream", "identitybridge", "patch", "vendor", "contact", "urgent"]):
                c9 = 8
                break
    score += c9
    feedback.append(f"C9: +{c9} DM to vendor.liaison ({len(vend_dm_messages)} messages)")

    # --- C10 (10pts): Status update in remediation channel ---
    c10 = 0
    for msg in messages:
        text = (msg.get("msg") or "").lower()
        has_containment = any(kw in text for kw in ["containment", "contain", "mitigat"])
        has_vendor = any(kw in text for kw in ["vendor", "contact", "establish"])
        has_update = any(kw in text for kw in ["update", "status", "confirm"])
        # Must mention containment or vendor contacts and be an update-like message
        if (has_containment or has_vendor) and has_update:
            # Make sure it's not the same as the triage matrix
            is_triage = "cve-2026-0142" in text and "cve-2026-0198" in text and "cve-2026-0215" in text
            if not is_triage:
                c10 = 10
                break
    score += c10
    feedback.append(f"C10: +{c10} Status update in remediation channel")

    passed = score >= 70
    summary = f"Score: {score}/100 (pass >= 70)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
