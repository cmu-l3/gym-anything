"""
verifier.py — Programmatic verifier for threat_intel_enrichment_pipeline task.

Scoring breakdown (100 pts total, pass threshold: 65):
  1. Lookup CSV file exists with correct fields          (15 pts)
  2. Lookup definition exists                             (15 pts)
  3. Automatic lookup configured                          (15 pts)
  4. Dashboard exists with correct name                   (10 pts)
  5. Dashboard has >= 3 panels                            (15 pts)
  6. Dashboard references enriched fields                 (10 pts)
  7. Alert exists with correct name                       (10 pts)
  8. Alert is scheduled with correct cron                 (10 pts)
"""

import json
import os
import re
import tempfile


def verify_threat_intel_enrichment_pipeline(traj, env_info, task_info):
    """Main verification function."""
    result = {
        "passed": False,
        "score": 0,
        "feedback": "",
        "subscores": {},
    }

    # ── Retrieve exported result from VM ─────────────────────────────────
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        result["feedback"] = "No copy_from_env function available"
        return result

    metadata = task_info.get("metadata", {})

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env("/tmp/tiep_task_result.json", tmp_path)
        with open(tmp_path) as f:
            data = json.load(f)
    except Exception as e:
        result["feedback"] = f"Failed to read task result: {e}"
        return result
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    feedback_parts = []
    score = 0
    subscores = {}

    def normalize(name):
        return name.lower().replace(" ", "_").replace("-", "_")

    # ── Criterion 1: Lookup CSV file (15 pts) ────────────────────────────
    lookup_file = data.get("lookup_file", {})
    c1_score = 0
    if lookup_file.get("exists"):
        has_src = lookup_file.get("has_src_ip", False)
        has_tl = lookup_file.get("has_threat_level", False)
        has_ac = lookup_file.get("has_attempt_count", False)
        rows = lookup_file.get("row_count", 0)

        if has_src and has_tl and rows > 0:
            c1_score = 15
            feedback_parts.append(f"Lookup CSV: OK ({rows} rows, all required fields)")
        elif has_src and rows > 0:
            c1_score = 8
            feedback_parts.append(f"Lookup CSV: partial (has src_ip + {rows} rows, missing some fields)")
        else:
            c1_score = 3
            feedback_parts.append(f"Lookup CSV: exists but missing key fields (header: {lookup_file.get('header', 'unknown')})")
    else:
        feedback_parts.append("Lookup CSV: NOT FOUND")
    subscores["lookup_file_exists"] = lookup_file.get("exists", False)
    score += c1_score

    # ── Criterion 2: Lookup definition (15 pts) ─────────────────────────
    lookup_def = data.get("lookup_definition", {})
    c2_score = 0
    if lookup_def.get("exists"):
        fname = lookup_def.get("filename", "").lower()
        if "threat_intel" in fname:
            c2_score = 15
            feedback_parts.append(f"Lookup definition: OK (name={lookup_def.get('name')}, file={fname})")
        else:
            c2_score = 8
            feedback_parts.append(f"Lookup definition: exists but points to wrong file ({fname})")
    else:
        feedback_parts.append("Lookup definition: NOT FOUND")
    subscores["lookup_definition_exists"] = lookup_def.get("exists", False)
    score += c2_score

    # ── Criterion 3: Automatic lookup (15 pts) ──────────────────────────
    auto_lookup = data.get("automatic_lookup", {})
    c3_score = 0
    if auto_lookup.get("exists"):
        c3_score = 15
        feedback_parts.append(f"Automatic lookup: OK (name={auto_lookup.get('name')})")
        # Check for btool evidence as bonus confirmation
        if auto_lookup.get("btool_evidence"):
            feedback_parts.append(f"  btool confirms: {auto_lookup.get('btool_evidence')}")
    else:
        feedback_parts.append("Automatic lookup: NOT FOUND")
    subscores["automatic_lookup_exists"] = auto_lookup.get("exists", False)
    score += c3_score

    # ── Criterion 4: Dashboard exists with correct name (10 pts) ────────
    dashboard = data.get("dashboard", {})
    c4_score = 0
    if dashboard.get("exists"):
        name = normalize(dashboard.get("name", ""))
        if name == "threat_intelligence_monitor":
            c4_score = 10
            feedback_parts.append(f"Dashboard: OK (exact name match)")
        else:
            c4_score = 5
            feedback_parts.append(f"Dashboard: found but wrong name ({dashboard.get('name')})")
    else:
        feedback_parts.append("Dashboard: NOT FOUND")
    subscores["dashboard_exists"] = dashboard.get("exists", False)
    score += c4_score

    # ── Criterion 5: Dashboard has >= 3 panels (15 pts) ─────────────────
    c5_score = 0
    panel_count = dashboard.get("panel_count", 0)
    if panel_count >= 3:
        c5_score = 15
        feedback_parts.append(f"Dashboard panels: OK ({panel_count} panels)")
    elif panel_count >= 2:
        c5_score = 8
        feedback_parts.append(f"Dashboard panels: partial ({panel_count}/3 panels)")
    elif panel_count >= 1:
        c5_score = 4
        feedback_parts.append(f"Dashboard panels: minimal ({panel_count}/3 panels)")
    else:
        feedback_parts.append(f"Dashboard panels: NONE ({panel_count} panels)")
    subscores["dashboard_min_panels"] = panel_count >= 3
    score += c5_score

    # ── Criterion 6: Dashboard references enriched fields (10 pts) ──────
    c6_score = 0
    has_tl = dashboard.get("has_threat_level_ref", False)
    has_tc = dashboard.get("has_timechart", False)
    has_st = dashboard.get("has_stats", False)
    if has_tl and (has_tc or has_st):
        c6_score = 10
        feedback_parts.append("Dashboard enrichment refs: OK (threat_level + timechart/stats)")
    elif has_tl:
        c6_score = 5
        feedback_parts.append("Dashboard enrichment refs: partial (threat_level found but missing timechart/stats)")
    elif has_tc or has_st:
        c6_score = 3
        feedback_parts.append("Dashboard enrichment refs: partial (timechart/stats found but no threat_level)")
    else:
        feedback_parts.append("Dashboard enrichment refs: NONE")
    subscores["dashboard_uses_enriched_fields"] = has_tl
    score += c6_score

    # ── Criterion 7: Alert exists with correct name (10 pts) ────────────
    alert = data.get("alert", {})
    c7_score = 0
    if alert.get("exists"):
        name = normalize(alert.get("name", ""))
        if name == "critical_threat_activity":
            c7_score = 10
            feedback_parts.append("Alert: OK (exact name match)")
        else:
            c7_score = 5
            feedback_parts.append(f"Alert: found but wrong name ({alert.get('name')})")
    else:
        feedback_parts.append("Alert: NOT FOUND")
    subscores["alert_exists"] = alert.get("exists", False)
    score += c7_score

    # ── Criterion 8: Alert is scheduled with correct cron (10 pts) ──────
    c8_score = 0
    if alert.get("is_scheduled"):
        cron = alert.get("cron_schedule", "")
        if "*/15" in cron:
            c8_score = 10
            feedback_parts.append(f"Alert schedule: OK (cron={cron})")
        else:
            c8_score = 5
            feedback_parts.append(f"Alert schedule: scheduled but wrong cron ({cron})")
    elif alert.get("exists"):
        feedback_parts.append("Alert schedule: exists but NOT scheduled")
    else:
        feedback_parts.append("Alert schedule: N/A (alert missing)")
    subscores["alert_scheduled_correctly"] = alert.get("is_scheduled", False) and "*/15" in alert.get("cron_schedule", "")
    score += c8_score

    # ── Final scoring ───────────────────────────────────────────────────
    # Must have at least lookup file + dashboard + alert for pass
    has_core_artifacts = (
        lookup_file.get("exists", False)
        and dashboard.get("exists", False)
        and alert.get("exists", False)
    )
    passed = score >= 65 and has_core_artifacts

    result["passed"] = passed
    result["score"] = score
    result["feedback"] = " | ".join(feedback_parts)
    result["subscores"] = subscores

    return result
