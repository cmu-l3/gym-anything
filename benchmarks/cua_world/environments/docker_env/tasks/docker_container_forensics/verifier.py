#!/usr/bin/env python3
"""
Verifier for docker_container_forensics task.

Scoring (100 points):
  - acme-webapp-fixed running without SYS_ADMIN/NET_ADMIN/SYS_PTRACE caps: 25 pts
  - acme-gateway-fixed running without hardcoded production secrets: 25 pts
  - acme-monitor-fixed running without /etc bind mount from host: 25 pts
  - All 3 original containers stopped: 10 pts
  - Incident report exists, covers all 3 containers: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_docker_container_forensics(traj, env_info, task_info):
    """Verify container forensics and remediation results."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/docker_forensics_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Criterion 1: acme-webapp-fixed (25 pts) ────────────────────────────────
    webapp_running = result.get("webapp_fixed_running", 0)
    webapp_no_caps = result.get("webapp_no_dangerous_caps", 0)

    if webapp_running and webapp_no_caps:
        score += 25
        subscores["acme_webapp_fixed"] = True
        feedback_parts.append("acme-webapp-fixed: running without dangerous caps (+25)")
    elif webapp_running and not webapp_no_caps:
        score += 5
        subscores["acme_webapp_fixed"] = "partial"
        feedback_parts.append(
            "acme-webapp-fixed: running but still has dangerous capabilities SYS_ADMIN/NET_ADMIN/SYS_PTRACE (5/25)"
        )
    elif not webapp_running:
        subscores["acme_webapp_fixed"] = False
        feedback_parts.append("acme-webapp-fixed: container not running (0/25)")

    # ── Criterion 2: acme-gateway-fixed (25 pts) ──────────────────────────────
    gateway_running = result.get("gateway_fixed_running", 0)
    gateway_no_secrets = result.get("gateway_no_hardcoded_secrets", 0)

    if gateway_running and gateway_no_secrets:
        score += 25
        subscores["acme_gateway_fixed"] = True
        feedback_parts.append("acme-gateway-fixed: running without hardcoded production secrets (+25)")
    elif gateway_running and not gateway_no_secrets:
        score += 5
        subscores["acme_gateway_fixed"] = "partial"
        feedback_parts.append(
            "acme-gateway-fixed: running but hardcoded secret values still present in environment (5/25)"
        )
    elif not gateway_running:
        subscores["acme_gateway_fixed"] = False
        feedback_parts.append("acme-gateway-fixed: container not running (0/25)")

    # ── Criterion 3: acme-monitor-fixed (25 pts) ──────────────────────────────
    monitor_running = result.get("monitor_fixed_running", 0)
    monitor_no_etc = result.get("monitor_no_etc_mount", 0)

    if monitor_running and monitor_no_etc:
        score += 25
        subscores["acme_monitor_fixed"] = True
        feedback_parts.append("acme-monitor-fixed: running without /etc host bind mount (+25)")
    elif monitor_running and not monitor_no_etc:
        score += 5
        subscores["acme_monitor_fixed"] = "partial"
        feedback_parts.append(
            "acme-monitor-fixed: running but /etc is still bind-mounted from host (5/25)"
        )
    elif not monitor_running:
        subscores["acme_monitor_fixed"] = False
        feedback_parts.append("acme-monitor-fixed: container not running (0/25)")

    # ── Criterion 4: Originals stopped (10 pts) ───────────────────────────────
    all_originals_stopped = result.get("all_originals_stopped", 0)
    webapp_stopped = result.get("webapp_orig_stopped", 0)
    gateway_stopped = result.get("gateway_orig_stopped", 0)
    monitor_stopped = result.get("monitor_orig_stopped", 0)

    originals_stopped_count = webapp_stopped + gateway_stopped + monitor_stopped

    if all_originals_stopped:
        score += 10
        subscores["originals_stopped"] = True
        feedback_parts.append("All 3 original containers stopped (+10)")
    elif originals_stopped_count > 0:
        partial = int(originals_stopped_count * 3.3)  # ~3 pts per stopped container
        score += partial
        subscores["originals_stopped"] = "partial"
        feedback_parts.append(
            f"{originals_stopped_count}/3 original containers stopped (+{partial})"
        )
    else:
        subscores["originals_stopped"] = False
        feedback_parts.append("Original containers still running (0/10)")

    # ── Criterion 5: Incident report (15 pts) ─────────────────────────────────
    report_exists = result.get("report_exists", 0)
    report_after_start = result.get("report_after_start", 0)
    report_covers_all = result.get("report_covers_all", 0)
    report_word_count = result.get("report_word_count", 0)
    report_mentions_webapp = result.get("report_mentions_webapp", 0)
    report_mentions_gateway = result.get("report_mentions_gateway", 0)
    report_mentions_monitor = result.get("report_mentions_monitor", 0)
    containers_mentioned = report_mentions_webapp + report_mentions_gateway + report_mentions_monitor

    if report_exists and report_after_start and report_covers_all and report_word_count >= 50:
        score += 15
        subscores["incident_report"] = True
        feedback_parts.append("Incident report covers all 3 containers (+15)")
    elif report_exists and report_after_start and containers_mentioned >= 2:
        score += 8
        subscores["incident_report"] = "partial"
        feedback_parts.append(
            f"Incident report mentions {containers_mentioned}/3 containers (8/15)"
        )
    elif report_exists and report_after_start:
        score += 4
        subscores["incident_report"] = "partial"
        feedback_parts.append("Incident report exists but lacks coverage of all 3 containers (4/15)")
    elif report_exists and not report_after_start:
        subscores["incident_report"] = False
        feedback_parts.append("Incident report exists but was not written during this task (0/15)")
    else:
        subscores["incident_report"] = False
        feedback_parts.append("~/Desktop/incident_report.txt not found (0/15)")

    # ── GATE: at least one fixed container must be correctly remediated ────────
    fixed_correct = (
        (webapp_running and webapp_no_caps)
        + (gateway_running and gateway_no_secrets)
        + (monitor_running and monitor_no_etc)
    )
    if fixed_correct == 0 and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(
            f"Score capped at {PASS_THRESHOLD - 1}: no container was correctly remediated"
        )

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "details": {
            "webapp_fixed_running": webapp_running,
            "webapp_no_dangerous_caps": webapp_no_caps,
            "gateway_fixed_running": gateway_running,
            "gateway_no_hardcoded_secrets": gateway_no_secrets,
            "monitor_fixed_running": monitor_running,
            "monitor_no_etc_mount": monitor_no_etc,
            "all_originals_stopped": all_originals_stopped,
            "report_exists": report_exists,
            "report_covers_all": report_covers_all,
        },
    }
