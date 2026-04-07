#!/usr/bin/env python3
"""
Verifier for post_repair_qa_cross_reference_audit task.

This is a stub verifier. Primary evaluation uses vlm_checklist_verifier.
The programmatic scoring below provides a baseline but the VLM checklist
is the authoritative score.

Scoring breakdown (100 pts total):
  - Report created after task start (anti-gaming gate): required
  - Vehicle identified (Ducato / VIN / engine code):  5 pts
  - Engine ECU section present:                       15 pts
  - Body Computer section present:                    12 pts
  - ECU identification (part number, HW/SW):          8 pts
  - DTC section with codes:                           8 pts
  - DTC descriptions from CSV cross-reference:        12 pts
  - Parameter comparison with CSV normal ranges:      12 pts
  - Vehicle spec verification from CSV:                5 pts
  - Parameter table with 4+ parameters:                8 pts
  - QA verdict (PASSED/CONDITIONAL/FAILED):            8 pts
  - Repair assessment (turbo + reflash):               7 pts

Pass threshold: 65 / 100
"""

import json
import os
import tempfile


def verify_post_repair_qa_cross_reference_audit(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    result_path_in_vm = r"C:\Users\Docker\post_repair_qa_cross_reference_audit_result.json"

    # ── Pull result file from VM ─────────────────────────────────────────────
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        env_info["copy_from_env"](result_path_in_vm, local_path)
        with open(local_path, encoding="utf-8-sig") as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export file not found — agent likely did not complete the task. ({e})",
        }

    # ── Anti-gaming gate ─────────────────────────────────────────────────────
    report_mtime = int(result.get("report_file_mtime", 0))
    start_ts = int(result.get("start_timestamp", 0))
    report_exists = result.get("report_exists", False)

    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not created."}

    if start_ts > 0 and report_mtime <= start_ts:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report predates task start — likely pre-existing file.",
        }

    # ── Scoring ──────────────────────────────────────────────────────────────

    # 1. Vehicle identification (5 pts)
    if result.get("vehicle_id_present"):
        score += 5
        feedback_lines.append("+ Vehicle identified (Ducato / VIN / engine code) (+5)")
    else:
        feedback_lines.append("- Vehicle not identified in report (0/5)")

    # 2. Engine ECU section (15 pts)
    if result.get("has_engine_ecu_section"):
        score += 15
        feedback_lines.append("+ Engine ECU section present (+15)")
    else:
        feedback_lines.append("- Engine ECU section missing (0/15)")

    # 3. Body Computer section (12 pts)
    if result.get("has_body_computer_section"):
        score += 12
        feedback_lines.append("+ Body Computer section present (+12)")
    else:
        feedback_lines.append("- Body Computer section missing (0/12)")

    # 4. ECU identification with HW/SW (8 pts)
    ecu_pts = 0
    if result.get("has_ecu_identification"):
        ecu_pts += 4
    if result.get("has_hw_sw_versions"):
        ecu_pts += 4
    score += ecu_pts
    if ecu_pts >= 8:
        feedback_lines.append("+ ECU identification with HW/SW versions (+8)")
    elif ecu_pts > 0:
        feedback_lines.append(f"+ Partial ECU identification (+{ecu_pts}/8)")
    else:
        feedback_lines.append("- No ECU identification data (0/8)")

    # 5. DTC section (8 pts)
    if result.get("has_dtc_section"):
        score += 8
        dtcs = result.get("all_dtcs_found", [])
        feedback_lines.append(
            f"+ DTC section present with {len(dtcs)} code(s): "
            f"{', '.join(dtcs[:6])} (+8)"
        )
    else:
        feedback_lines.append("- No DTC section found (0/8)")

    # 6. DTC descriptions cross-referenced from CSV (12 pts)
    if result.get("has_csv_dtc_descriptions"):
        score += 12
        feedback_lines.append(
            "+ DTC descriptions cross-referenced from dtc_database_full.csv (+12)"
        )
    else:
        feedback_lines.append(
            "- DTCs listed without CSV descriptions — cross-reference missing (0/12)"
        )

    # 7. Parameter comparison with CSV normal ranges (12 pts)
    param_pts = 0
    if result.get("has_csv_parameter_ranges"):
        param_pts += 6
    if result.get("has_normal_range_values"):
        param_pts += 6
    score += param_pts
    if param_pts >= 12:
        feedback_lines.append(
            "+ Parameters compared against CSV normal ranges with specific values (+12)"
        )
    elif param_pts > 0:
        feedback_lines.append(
            f"+ Partial parameter range comparison (+{param_pts}/12)"
        )
    else:
        feedback_lines.append(
            "- No parameter comparison against CSV ranges (0/12)"
        )

    # 8. Vehicle spec verification from CSV (5 pts)
    if result.get("has_csv_vehicle_specs"):
        score += 5
        feedback_lines.append(
            "+ Vehicle specs verified against fiat_vehicle_specs.csv (+5)"
        )
    else:
        feedback_lines.append("- No vehicle spec verification from CSV (0/5)")

    # 9. Parameter table with 4+ parameters (8 pts)
    params = result.get("parameter_names_found", [])
    if result.get("has_parameter_table") and len(params) >= 4:
        score += 8
        feedback_lines.append(
            f"+ Parameter comparison table with {len(params)} parameters (+8)"
        )
    elif len(params) >= 4:
        score += 4
        feedback_lines.append(
            f"+ {len(params)} parameters documented but no clear comparison table (+4/8)"
        )
    elif len(params) >= 1:
        score += 2
        feedback_lines.append(f"+ Some parameters mentioned ({len(params)}) (+2/8)")
    else:
        feedback_lines.append("- No engine parameters documented (0/8)")

    # 10. QA verdict (8 pts)
    if result.get("has_qa_verdict"):
        verdict = result.get("qa_verdict_value", "")
        if verdict:
            score += 8
            feedback_lines.append(f"+ QA verdict present: {verdict} (+8)")
        else:
            score += 4
            feedback_lines.append("+ QA verdict section present but verdict unclear (+4/8)")
    else:
        feedback_lines.append("- No QA verdict (PASSED/CONDITIONAL/FAILED) found (0/8)")

    # 11. Repair assessment (7 pts)
    repair_pts = 0
    if result.get("has_turbo_assessment"):
        repair_pts += 4
    if result.get("has_reflash_assessment"):
        repair_pts += 3
    score += repair_pts
    if repair_pts >= 7:
        feedback_lines.append(
            "+ Repair assessment covers turbo and body computer reflash (+7)"
        )
    elif repair_pts > 0:
        feedback_lines.append(f"+ Partial repair assessment (+{repair_pts}/7)")
    else:
        feedback_lines.append("- No repair verification assessment (0/7)")

    score = min(score, 100)
    passed = score >= 65

    # Summary
    csv_count = int(result.get("csv_cross_reference_count", 0))
    feedback_lines.append(f"\nCSV cross-references detected: {csv_count}/3")
    feedback_lines.append(
        f"Both ECU systems covered: {result.get('both_systems_covered', False)}"
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }
