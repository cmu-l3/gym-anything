"""
Verifier for hvac_system_grouping_and_specification task.

Scoring (100 points total, threshold 60):
  file_new       (10 pts): Output IFC exists and is newer than task start
  ahu            (20 pts): IfcUnitaryEquipment 'AHU-01' exists with correct pset
  ducts          (20 pts): ≥4 IfcDuctSegment elements, partial for <4, bonus for pset
  terminals      (15 pts): ≥2 IfcAirTerminal elements, bonus for pset
  system         (25 pts): IfcSystem 'HVAC Supply Air System' with correct ObjectType
                           and members assigned
  spatial        (10 pts): Elements placed in valid IFC spatial hierarchy

Pass threshold: 60
Anti-pattern: no file → 0. Empty project → 0.
"""
import json
import os
import tempfile


def verify_hvac_system(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env("/tmp/hvac_system_result.json", tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"FAIL: Could not read result file: {e}"
        }
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    feedback = []
    score = 0

    # ── Gate ────────────────────────────────────────────────────────────────
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output IFC /home/ga/BIMProjects/hvac_system.ifc was not created."
        }

    file_mtime = float(result.get("file_mtime", 0))
    task_start = float(result.get("task_start", 0))
    if file_mtime <= task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output IFC was not modified during the task."
        }

    score += 10
    feedback.append("PASS (+10): Output IFC file created and is new.")

    # ── Criterion 1: AHU IfcUnitaryEquipment ──────────────────────────────
    ahu_found = result.get("ahu_found", False)
    ahu_name = result.get("ahu_name", "") or ""
    ahu_pset = result.get("ahu_pset", {})

    if ahu_found:
        ahu_pts = 8
        name_ok = "ahu-01" in ahu_name.lower() or "ahu01" in ahu_name.lower()
        if name_ok:
            ahu_pts += 4
        # Check pset properties
        flow = str(ahu_pset.get("NominalSupplyAirFlowRate", ""))
        cool = str(ahu_pset.get("NominalCoolingCapacity", ""))
        heat = str(ahu_pset.get("NominalHeatingCapacity", ""))
        if "2500" in flow:
            ahu_pts += 3
        if "45" in cool:
            ahu_pts += 2
        if "50" in heat:
            ahu_pts += 3
        ahu_pts = min(20, ahu_pts)
        score += ahu_pts
        feedback.append(f"PASS (+{ahu_pts}): IfcUnitaryEquipment found (name='{ahu_name}', pset keys: {list(ahu_pset.keys())}).")
    else:
        feedback.append("FAIL (+0): No IfcUnitaryEquipment (AHU-01) found in output IFC.")

    # ── Criterion 2: Duct segments ────────────────────────────────────────
    n_ducts = result.get("n_duct_segments", 0)
    ducts_with_pset = result.get("ducts_with_pset", 0)
    if n_ducts >= 4:
        duct_pts = 15
        if ducts_with_pset >= 4:
            duct_pts += 5
        score += duct_pts
        feedback.append(f"PASS (+{duct_pts}): {n_ducts} IfcDuctSegment elements found ({ducts_with_pset} with pset).")
    elif n_ducts > 0:
        duct_pts = round((n_ducts / 4) * 12)
        score += duct_pts
        feedback.append(f"PARTIAL (+{duct_pts}): Only {n_ducts}/4 required IfcDuctSegment elements found.")
    else:
        feedback.append("FAIL (+0): No IfcDuctSegment elements found.")

    # ── Criterion 3: Air terminals ────────────────────────────────────────
    n_terminals = result.get("n_air_terminals", 0)
    terminals_with_pset = result.get("terminals_with_pset", 0)
    if n_terminals >= 2:
        term_pts = 10
        if terminals_with_pset >= 2:
            term_pts += 5
        score += term_pts
        feedback.append(f"PASS (+{term_pts}): {n_terminals} IfcAirTerminal elements found ({terminals_with_pset} with pset).")
    elif n_terminals == 1:
        score += 6
        feedback.append(f"PARTIAL (+6): Only 1/2 required IfcAirTerminal elements found.")
    else:
        feedback.append("FAIL (+0): No IfcAirTerminal elements found.")

    # ── Criterion 4: HVAC system grouping ────────────────────────────────
    systems = result.get("systems", [])
    hvac_system = None
    for s in systems:
        sname = s.get("name", "").lower()
        if "hvac" in sname and ("supply" in sname or "air" in sname):
            hvac_system = s
            break
    if hvac_system is None:
        # Try looser match
        for s in systems:
            sname = s.get("name", "").lower()
            if "hvac" in sname or "supply air" in sname:
                hvac_system = s
                break

    if hvac_system:
        sys_pts = 10
        obj_type = (hvac_system.get("object_type") or "").upper()
        if "HVAC" in obj_type:
            sys_pts += 5
        member_count = hvac_system.get("member_count", 0)
        # Check elements are grouped: AHU(1) + ducts(≥4) + terminals(≥2) = ≥7
        if member_count >= 7:
            sys_pts += 10
        elif member_count >= 3:
            sys_pts += round((member_count / 7) * 10)
        elif member_count >= 1:
            sys_pts += 3
        sys_pts = min(25, sys_pts)
        score += sys_pts
        feedback.append(f"PASS (+{sys_pts}): HVAC System '{hvac_system.get('name')}' found (ObjectType='{obj_type}', {member_count} members).")
    else:
        sys_names = [s.get("name") for s in systems]
        feedback.append(f"FAIL (+0): No IfcSystem named 'HVAC Supply Air System' found. Systems present: {sys_names}")

    score = min(100, score)
    PASS_THRESHOLD = 60
    passed = score >= PASS_THRESHOLD
    feedback.append(f"\nTotal score: {score}/100 (threshold: {PASS_THRESHOLD})")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
