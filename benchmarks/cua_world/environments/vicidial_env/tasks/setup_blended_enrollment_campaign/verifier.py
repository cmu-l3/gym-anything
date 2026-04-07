#!/usr/bin/env python3
"""
Verifier stub for setup_blended_enrollment_campaign@1 task.

This is a minimal programmatic verifier. The primary verification method
for this task is the VLM checklist verifier (vlm_checklist_verifier).

The programmatic verifier checks basic object existence from the exported
task_result.json but does NOT perform exhaustive field-level validation.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_setup_blended_enrollment_campaign(traj, env_info, task_info):
    """
    Stub verifier: checks whether the major objects were created.
    Returns partial scores based on object existence.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load task_result.json: {e}",
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Campaign exists
    campaign = result.get("campaign")
    if campaign and campaign.get("campaign_id") == "PSHLTH26":
        score += 10
        feedback.append("Campaign PSHLTH26 exists")
    else:
        feedback.append("Campaign PSHLTH26 NOT found")

    # 2. List exists with leads
    lst = result.get("list")
    lead_count = result.get("lead_count", 0)
    if lst and lst.get("list_id") == "8800":
        score += 5
        feedback.append("List 8800 exists")
        if lead_count >= 40:
            score += 10
            feedback.append(f"Leads imported: {lead_count}")
        else:
            feedback.append(f"Lead count low: {lead_count}")
    else:
        feedback.append("List 8800 NOT found")

    # 3. Script exists
    script = result.get("script")
    if script and script.get("script_id") == "PS_ENROLL":
        score += 10
        feedback.append("Script PS_ENROLL exists")
    else:
        feedback.append("Script PS_ENROLL NOT found")

    # 4. Statuses
    statuses = result.get("statuses", [])
    found_codes = {s["status"] for s in statuses}
    expected_codes = {"ENROLD", "DECLIN", "CALLBK", "NOELIG", "HANGUP"}
    matched = found_codes & expected_codes
    score += len(matched) * 3
    if matched == expected_codes:
        feedback.append("All 5 statuses created")
    else:
        missing = expected_codes - matched
        feedback.append(f"Statuses missing: {missing}")

    # 5. Call Time
    ct = result.get("call_time")
    if ct and ct.get("call_time_id") == "PS_HOURS":
        score += 10
        feedback.append("Call Time PS_HOURS exists")
    else:
        feedback.append("Call Time PS_HOURS NOT found")

    # 6. Voicemail
    vm = result.get("voicemail")
    if vm and vm.get("voicemail_id") == "8800":
        score += 5
        feedback.append("Voicemail 8800 exists")
    else:
        feedback.append("Voicemail 8800 NOT found")

    # 7. Inbound Group
    ig = result.get("inbound_group")
    if ig and ig.get("group_id") == "PS_INBOUND":
        score += 10
        feedback.append("Inbound Group PS_INBOUND exists")
    else:
        feedback.append("Inbound Group PS_INBOUND NOT found")

    # 8. Blended mode
    if campaign:
        if campaign.get("allow_closers") == "Y":
            score += 5
            feedback.append("Allow Closers enabled")
        if campaign.get("closer_campaigns") and "PS_INBOUND" in campaign.get("closer_campaigns", ""):
            score += 5
            feedback.append("PS_INBOUND in Closer Campaigns")

    # 9. Lead Recycling
    recycles = result.get("lead_recycles", [])
    recycle_statuses = {r["status"] for r in recycles}
    if "NA" in recycle_statuses:
        score += 5
        feedback.append("Lead recycle NA configured")
    if "B" in recycle_statuses:
        score += 5
        feedback.append("Lead recycle B configured")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
