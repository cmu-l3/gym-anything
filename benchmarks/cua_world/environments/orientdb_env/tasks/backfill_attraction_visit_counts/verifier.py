#!/usr/bin/env python3
"""Verifier for backfill_attraction_visit_counts."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/backfill_attraction_visit_counts_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _has_notunique_audit_batch_index(indexes):
    for idx in indexes or []:
        itype = (idx.get("type") or "").upper()
        if itype not in ("NOTUNIQUE", "NOTUNIQUE_HASH_INDEX"):
            continue
        if idx.get("name") == "AttractionVisitAudit.AuditBatch":
            return True
        fields = idx.get("fields") or []
        if len(fields) == 1 and fields[0] == "AuditBatch":
            return True
    return False


def verify_backfill_attraction_visit_counts(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_counts = metadata.get("expected_visit_counts", {})
    zero_visit = set(metadata.get("zero_visit_attractions", []))
    expected_audit_count = metadata.get("expected_audit_count", 5)
    audit_batch = metadata.get("audit_batch", "visit_backfill_2026q1")

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"could not load result: {exc}"}

    visit_counts = result.get("visit_counts", {})
    audit_rows = result.get("audit_rows", {})

    # Wrong-target rejection: any zero-visit attraction with VisitCount > 0
    overcounted = [
        name for name in zero_visit
        if visit_counts.get(name) is not None and int(visit_counts.get(name) or 0) > 0
    ]
    if overcounted:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Attractions incorrectly given VisitCount > 0: {overcounted}",
        }

    score = 0
    feedback = []

    # Criterion 1: VisitCount property exists on Attractions (15 pts)
    if result.get("visit_count_property_exists"):
        score += 15
        feedback.append("VisitCount property exists on Attractions class")
    else:
        feedback.append("VisitCount property missing from Attractions class")

    # Criterion 2: AttractionVisitAudit schema + NOTUNIQUE index on AuditBatch (15 pts)
    req_props = {"AttractionName", "NewVisitCount", "AuditBatch"}
    props = set(result.get("attraction_visit_audit_properties", []))
    mandatory = result.get("attraction_visit_audit_mandatory", {})
    audit_schema_ok = (
        result.get("attraction_visit_audit_exists")
        and req_props.issubset(props)
        and all(mandatory.get(p, False) for p in req_props)
    )
    if audit_schema_ok:
        score += 10
        feedback.append("AttractionVisitAudit schema is correct")
    else:
        feedback.append(f"AttractionVisitAudit schema incomplete; found={sorted(props)}")

    if _has_notunique_audit_batch_index(result.get("attraction_visit_audit_indexes", [])):
        score += 5
        feedback.append("AttractionVisitAudit.AuditBatch NOTUNIQUE index present")
    else:
        feedback.append("AttractionVisitAudit.AuditBatch NOTUNIQUE index missing")

    # Criterion 3: High-traffic attraction VisitCounts (Acropolis=2, Neuschwanstein=2) (25 pts)
    acropolis_ok = int(visit_counts.get("Acropolis of Athens") or 0) == 2
    neuschwanstein_ok = int(visit_counts.get("Neuschwanstein Castle") or 0) == 2
    if acropolis_ok and neuschwanstein_ok:
        score += 25
        feedback.append("Acropolis of Athens=2 and Neuschwanstein Castle=2 correct")
    elif acropolis_ok or neuschwanstein_ok:
        score += 12
        feedback.append(
            f"Partial: Acropolis={visit_counts.get('Acropolis of Athens')}, "
            f"Neuschwanstein={visit_counts.get('Neuschwanstein Castle')}"
        )
    else:
        feedback.append(
            f"High-traffic counts wrong: Acropolis={visit_counts.get('Acropolis of Athens')}, "
            f"Neuschwanstein={visit_counts.get('Neuschwanstein Castle')}"
        )

    # Criterion 4: Single-visit attraction VisitCounts (25 pts — 8-9 each)
    single_visit_ok = 0
    single_targets = ["Sagrada Familia", "Edinburgh Castle", "Brandenburg Gate"]
    for name in single_targets:
        if int(visit_counts.get(name) or 0) == 1:
            single_visit_ok += 1
    single_pts = int(25 * single_visit_ok / len(single_targets))
    score += single_pts
    if single_visit_ok == 3:
        feedback.append("All 3 single-visit attractions correct (Sagrada Familia=1, Edinburgh=1, Brandenburg=1)")
    else:
        wrong = {n: visit_counts.get(n) for n in single_targets if int(visit_counts.get(n) or 0) != 1}
        feedback.append(f"Single-visit count issues: {wrong}")

    # Criterion 5: Audit row count = expected_audit_count with correct AuditBatch (10 pts)
    audit_count = result.get("audit_row_count", 0)
    batch_correct = all(
        v.get("AuditBatch") == audit_batch for v in audit_rows.values()
    ) if audit_rows else False
    if audit_count == expected_audit_count and batch_correct:
        score += 10
        feedback.append(f"Audit row count={audit_count} with correct AuditBatch")
    elif audit_count == expected_audit_count:
        score += 5
        feedback.append(f"Audit row count correct ({audit_count}) but AuditBatch mismatch")
    else:
        feedback.append(f"Audit row count: expected {expected_audit_count}, got {audit_count}")

    # Criterion 6: Baseline delta proves new work (10 pts)
    baseline_audit = int(result.get("baseline_audit_row_count", 0) or 0)
    if result.get("visit_count_property_exists") and audit_count > baseline_audit:
        score += 10
        feedback.append("VisitCount property and audit rows both increased from baseline")
    else:
        feedback.append("Baseline delta check failed — property or audit rows unchanged")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
