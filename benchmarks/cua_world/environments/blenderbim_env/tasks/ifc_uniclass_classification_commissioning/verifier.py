"""
Verifier for ifc_uniclass_classification_commissioning task.

Scoring (100 points total):
  file_new        (10 pts) : Output IFC exists and is newer than task start
  system_correct  (15 pts) : IfcClassification with "Uniclass" in name found
  walls_classified (25 pts): Partial: walls_code_correct / expected_walls * 25, capped at 25
  windows_classified (20 pts): Partial: windows_code_correct / expected_windows * 20, capped at 20
  doors_classified (15 pts): Partial: doors_code_correct / expected_doors * 15, capped at 15
  slabs_classified (15 pts): Partial: slabs_code_correct / expected_slabs * 15, capped at 15

Pass threshold: 65
Anti-pattern safety: max without correct codes = 10+15 = 25 (file+system). Agent must
classify elements correctly to reach 65.
"""
import json
import os
import tempfile


def verify_uniclass_classification(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env("/tmp/uniclass_classification_result.json", tmp_path)
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

    # ── Gate: output file must exist and be new ────────────────────────────
    file_exists = result.get("file_exists", False)
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output IFC /home/ga/BIMProjects/fzk_classified.ifc was not created."
        }

    file_mtime = float(result.get("file_mtime", 0))
    task_start = float(result.get("task_start", 0))
    file_is_new = file_mtime > task_start

    if not file_is_new:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output IFC file was not modified during the task (stale file)."
        }

    score += 10
    feedback.append("PASS (+10): Output IFC file created and is new.")

    # ── Criterion 1: Uniclass 2015 classification system ──────────────────
    uniclass_found = result.get("uniclass_system_found", False)
    cls_systems = result.get("classification_systems", [])
    if uniclass_found:
        score += 15
        feedback.append("PASS (+15): Uniclass 2015 classification system found in IFC.")
    else:
        names = [s.get("name", "") for s in cls_systems]
        feedback.append(f"FAIL (+0): No Uniclass classification system found. Systems present: {names}")

    # ── Criterion 2: Walls classified with correct code ───────────────────
    EXPECTED_WALLS = 13
    walls_correct = result.get("walls_code_correct", 0)
    walls_classified = result.get("walls_classified", 0)
    wall_pts = min(25, round((walls_correct / EXPECTED_WALLS) * 25)) if EXPECTED_WALLS > 0 else 0
    score += wall_pts
    if wall_pts > 0:
        feedback.append(f"PASS (+{wall_pts}): {walls_correct}/{EXPECTED_WALLS} walls correctly classified Ss_25_16_94.")
    else:
        feedback.append(f"FAIL (+0): Walls with correct Ss_25_16_94 code: {walls_correct}/{EXPECTED_WALLS} (classified: {walls_classified}).")

    # ── Criterion 3: Windows classified with correct code ─────────────────
    EXPECTED_WINDOWS = 11
    windows_correct = result.get("windows_code_correct", 0)
    windows_classified = result.get("windows_classified", 0)
    window_pts = min(20, round((windows_correct / EXPECTED_WINDOWS) * 20)) if EXPECTED_WINDOWS > 0 else 0
    score += window_pts
    if window_pts > 0:
        feedback.append(f"PASS (+{window_pts}): {windows_correct}/{EXPECTED_WINDOWS} windows correctly classified Ss_25_96_57.")
    else:
        feedback.append(f"FAIL (+0): Windows with correct Ss_25_96_57 code: {windows_correct}/{EXPECTED_WINDOWS}.")

    # ── Criterion 4: Doors classified with correct code ───────────────────
    EXPECTED_DOORS = 5
    doors_correct = result.get("doors_code_correct", 0)
    doors_classified = result.get("doors_classified", 0)
    door_pts = min(15, round((doors_correct / EXPECTED_DOORS) * 15)) if EXPECTED_DOORS > 0 else 0
    score += door_pts
    if door_pts > 0:
        feedback.append(f"PASS (+{door_pts}): {doors_correct}/{EXPECTED_DOORS} doors correctly classified Ss_25_32_33.")
    else:
        feedback.append(f"FAIL (+0): Doors with correct Ss_25_32_33 code: {doors_correct}/{EXPECTED_DOORS}.")

    # ── Criterion 5: Slabs classified with correct code ───────────────────
    EXPECTED_SLABS = 4
    slabs_correct = result.get("slabs_code_correct", 0)
    slabs_classified = result.get("slabs_classified", 0)
    slab_pts = min(15, round((slabs_correct / EXPECTED_SLABS) * 15)) if EXPECTED_SLABS > 0 else 0
    score += slab_pts
    if slab_pts > 0:
        feedback.append(f"PASS (+{slab_pts}): {slabs_correct}/{EXPECTED_SLABS} slabs correctly classified Ss_25_56_95.")
    else:
        feedback.append(f"FAIL (+0): Slabs with correct Ss_25_56_95 code: {slabs_correct}/{EXPECTED_SLABS}.")

    PASS_THRESHOLD = 65
    passed = score >= PASS_THRESHOLD
    feedback.append(f"\nTotal score: {score}/100 (threshold: {PASS_THRESHOLD})")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
