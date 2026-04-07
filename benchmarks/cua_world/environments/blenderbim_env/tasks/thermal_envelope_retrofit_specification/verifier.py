#!/usr/bin/env python3
"""
Verifier for thermal_envelope_retrofit_specification task.

This is a stub verifier. The task will primarily be evaluated using
vlm_checklist_verifier. The programmatic verifier provides baseline
structural checks on the exported result JSON.

Scoring rubric (100 points total, pass threshold = 65):
  Section A — Wall Construction (55 pts):
    file_is_new               :  5 pts
    layer_set_exists          : 10 pts  (named "Retrofit External Wall" or similar)
    layer_count               :  5 pts  (exactly 5 layers)
    layer_materials           : 10 pts  (2 pts per matching material keyword)
    layer_thicknesses         : 10 pts  (2 pts per correct thickness within tolerance)
    walls_assigned            : 15 pts  (>= 10 walls; partial at >= 5, >= 1)

  Section B — Glazing Specification (20 pts):
    window_type_exists        :  5 pts  (name contains "TG" or "Triple" or "Glazed")
    thermal_transmittance     :  5 pts  (value in 0.6–1.0 range)
    windows_assigned          : 10 pts  (>= 8 windows; partial at >= 4, >= 1)

  Section C — Thermal Zoning (20 pts):
    zones_exist               :  5 pts  (>= 2 IfcZone entities)
    heated_zone_spaces        : 10 pts  (zone with "Heated" keyword has >= 2 space members)
    semi_heated_zone_spaces   :  5 pts  (zone with "Semi" keyword has >= 1 space member)

  Anti-gaming:
    If total_walls < 10, score capped at 20 (model corrupted).

  Total: 100 pts. Pass threshold: 65.
"""

import json
import os
import tempfile


def verify_thermal_envelope_retrofit(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info."}

    # ── Copy result JSON from VM ──────────────────────────────────────────
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/thermal_envelope_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run."}
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    # ── Critical gate: output file must exist ─────────────────────────────
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: Output IFC file /home/ga/BIMProjects/fzk_thermal_envelope.ifc "
                "was not created. Score: 0/100."
            ),
        }

    # ── Anti-gaming: model must not be corrupted ──────────────────────────
    n_walls = result.get("n_walls", 0)
    if n_walls < 10:
        return {
            "passed": False,
            "score": min(score, 20),
            "feedback": (
                f"FAIL: Base building geometry is missing (only {n_walls} walls found, "
                "expected >= 10). The original model must remain intact. "
                f"Score capped at {min(score, 20)}/100."
            ),
        }

    # ══════════════════════════════════════════════════════════════════════
    # Section A — Wall Construction (55 pts)
    # ══════════════════════════════════════════════════════════════════════

    # A1: File is newly created during this task session (5 pts)
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 5
        feedback_lines.append("PASS: Output IFC file was saved during this task session. (+5)")
    else:
        feedback_lines.append(
            "FAIL: Output file was not modified during the task "
            f"(file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)"
        )

    # A2: Layer set with correct name exists (10 pts)
    target_ls = None
    for ls in result.get("layer_sets", []):
        name = (ls.get("name") or "").lower()
        if "retrofit" in name or ("external" in name and "wall" in name):
            target_ls = ls
            score += 10
            feedback_lines.append(
                f"PASS: Material layer set '{ls.get('name')}' found. (+10)"
            )
            break
    if target_ls is None:
        # Accept any layer set as partial credit
        all_ls = result.get("layer_sets", [])
        if all_ls:
            target_ls = all_ls[0]
            score += 4
            feedback_lines.append(
                f"PARTIAL: Layer set found ('{target_ls.get('name')}') but name does not "
                "match 'Retrofit External Wall'. (+4)"
            )
        else:
            feedback_lines.append("FAIL: No IfcMaterialLayerSet found. (+0)")

    # A3: Layer count is exactly 5 (5 pts)
    if target_ls:
        lc = target_ls.get("layer_count", 0)
        if lc == 5:
            score += 5
            feedback_lines.append(f"PASS: Layer set has exactly 5 layers. (+5)")
        elif lc >= 3:
            score += 2
            feedback_lines.append(f"PARTIAL: Layer set has {lc} layers (expected 5). (+2)")
        else:
            feedback_lines.append(f"FAIL: Layer set has {lc} layers (expected 5). (+0)")

    # A4: Layer materials match expected keywords (10 pts, 2 per match)
    expected_mats = ["render", "insulation", "air", "block", "plaster"]
    if target_ls:
        remaining = list(expected_mats)
        matched = 0
        for layer in target_ls.get("layers", []):
            mat = (layer.get("material") or "").lower()
            for i, kw in enumerate(remaining):
                if kw in mat:
                    matched += 1
                    remaining.pop(i)
                    break
        pts = min(matched * 2, 10)
        score += pts
        feedback_lines.append(f"+{pts}: {matched}/5 layer material names matched.")

    # A5: Layer thicknesses correct within tolerance (10 pts, 2 per match)
    expected_thick = [0.015, 0.120, 0.025, 0.200, 0.013]
    if target_ls:
        remaining = list(expected_thick)
        matched = 0
        for layer in target_ls.get("layers", []):
            t = layer.get("thickness", 0) or 0
            # Handle both meter and millimeter input
            if t > 1.0:
                t = t / 1000.0  # Convert mm to m
            for i, et in enumerate(remaining):
                if abs(t - et) < 0.006:  # 6mm tolerance
                    matched += 1
                    remaining.pop(i)
                    break
        pts = min(matched * 2, 10)
        score += pts
        feedback_lines.append(f"+{pts}: {matched}/5 layer thicknesses correct.")

    # A6: Walls assigned to material layer set (15 pts)
    wls = result.get("walls_with_layerset", 0)
    if wls >= 10:
        score += 15
        feedback_lines.append(f"PASS: Layer set assigned to {wls} walls. (+15)")
    elif wls >= 5:
        score += 8
        feedback_lines.append(f"PARTIAL: Layer set assigned to {wls} walls. (+8)")
    elif wls >= 1:
        score += 3
        feedback_lines.append(f"PARTIAL: Layer set assigned to {wls} wall(s). (+3)")
    else:
        feedback_lines.append("FAIL: No walls assigned to any material layer set. (+0)")

    # ══════════════════════════════════════════════════════════════════════
    # Section B — Glazing Specification (20 pts)
    # ══════════════════════════════════════════════════════════════════════

    # B1: Window type with correct name exists (5 pts)
    target_wt = None
    for wt in result.get("window_types", []):
        name = (wt.get("name") or "").lower()
        if "tg" in name or "triple" in name or "glazed" in name:
            target_wt = wt
            score += 5
            feedback_lines.append(
                f"PASS: IfcWindowType '{wt.get('name')}' found. (+5)"
            )
            break
    if target_wt is None:
        all_wt = result.get("window_types", [])
        if all_wt:
            target_wt = all_wt[0]
            score += 2
            feedback_lines.append(
                f"PARTIAL: IfcWindowType found ('{target_wt.get('name')}') but name "
                "does not match expected keywords. (+2)"
            )
        else:
            feedback_lines.append("FAIL: No IfcWindowType found. (+0)")

    # B2: ThermalTransmittance property (5 pts)
    if target_wt:
        props = target_wt.get("properties", {})
        tt = props.get("ThermalTransmittance")
        if tt is not None:
            try:
                tt_val = float(tt)
                if 0.6 <= tt_val <= 1.0:
                    score += 5
                    feedback_lines.append(
                        f"PASS: ThermalTransmittance = {tt_val}. (+5)"
                    )
                else:
                    score += 2
                    feedback_lines.append(
                        f"PARTIAL: ThermalTransmittance = {tt_val} (expected 0.6-1.0). (+2)"
                    )
            except (ValueError, TypeError):
                feedback_lines.append(
                    f"FAIL: ThermalTransmittance value '{tt}' is not numeric. (+0)"
                )
        else:
            feedback_lines.append(
                "FAIL: No ThermalTransmittance property found on window type. (+0)"
            )

    # B3: Windows assigned to type (10 pts)
    wt_count = result.get("windows_with_type", 0)
    if wt_count >= 8:
        score += 10
        feedback_lines.append(f"PASS: {wt_count} windows assigned to type. (+10)")
    elif wt_count >= 4:
        score += 5
        feedback_lines.append(f"PARTIAL: {wt_count} windows assigned to type. (+5)")
    elif wt_count >= 1:
        score += 2
        feedback_lines.append(f"PARTIAL: {wt_count} window(s) assigned to type. (+2)")
    else:
        feedback_lines.append("FAIL: No windows assigned to any window type. (+0)")

    # ══════════════════════════════════════════════════════════════════════
    # Section C — Thermal Zoning (20 pts)
    # ══════════════════════════════════════════════════════════════════════

    zones = result.get("zones", [])

    # C1: At least 2 zones exist (5 pts)
    if len(zones) >= 2:
        score += 5
        feedback_lines.append(
            f"PASS: {len(zones)} IfcZone entities found. (+5)"
        )
    elif len(zones) == 1:
        score += 2
        feedback_lines.append("PARTIAL: Only 1 IfcZone found (expected 2). (+2)")
    else:
        feedback_lines.append("FAIL: No IfcZone entities found. (+0)")

    # C2: Heated zone with space members (10 pts)
    heated_found = False
    for z in zones:
        name = (z.get("name") or "").lower()
        if "heated" in name and "semi" not in name:
            mc = z.get("member_count", 0)
            heated_found = True
            if mc >= 2:
                score += 10
                feedback_lines.append(
                    f"PASS: 'Heated Envelope' zone has {mc} space members. (+10)"
                )
            elif mc >= 1:
                score += 5
                feedback_lines.append(
                    f"PARTIAL: 'Heated Envelope' zone has {mc} member. (+5)"
                )
            else:
                feedback_lines.append(
                    "FAIL: 'Heated Envelope' zone has no members assigned. (+0)"
                )
            break
    if not heated_found:
        feedback_lines.append("FAIL: No zone with 'Heated' in name found. (+0)")

    # C3: Semi-heated zone with space members (5 pts)
    semi_found = False
    for z in zones:
        name = (z.get("name") or "").lower()
        if "semi" in name:
            mc = z.get("member_count", 0)
            semi_found = True
            if mc >= 1:
                score += 5
                feedback_lines.append(
                    f"PASS: 'Semi-Heated Envelope' zone has {mc} member(s). (+5)"
                )
            else:
                feedback_lines.append(
                    "FAIL: 'Semi-Heated Envelope' zone has no members. (+0)"
                )
            break
    if not semi_found:
        feedback_lines.append("FAIL: No zone with 'Semi' in name found. (+0)")

    # ── Final result ──────────────────────────────────────────────────────
    passed = score >= 65
    feedback_lines.append(
        f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 65)."
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }


<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
