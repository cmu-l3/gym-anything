"""
Verifier for cobie_asset_handover_enrichment task.

Scoring (100 points total, threshold 65):
  file_new         (10 pts): Output IFC exists and is newer than task start
  window_mfr       (25 pts): Partial - windows with correct Pset_ManufacturerTypeInformation
                             sub-scored: manufacturer_name(10) + model(8) + gtin(7)
  door_mfr         (20 pts): Partial - doors with correct Pset_ManufacturerTypeInformation
                             sub-scored: manufacturer_name(8) + model(7) + gtin(5)
  window_common    (20 pts): Partial - windows with correct Pset_WindowCommon
                             sub-scored: thermal_transmittance(8) + glazing_fraction(7) + is_external(5)
  glazing_group    (15 pts): IfcGroup 'Glazing Package' with all 11 windows assigned
                             group_found(8) + windows_in_group_partial(7)
  bonus_coverage   (10 pts): All expected windows/doors covered (not just some)

Pass threshold: 65
Anti-pattern: window_mfr(25)+door_mfr(20)+window_common(20) = 65 exact minimum path.
Do-nothing → 0.
"""
import json
import os
import tempfile


def verify_cobie_handover(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env("/tmp/cobie_handover_result.json", tmp_path)
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
            "feedback": "FAIL: Output IFC /home/ga/BIMProjects/fzk_cobie.ifc was not created."
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

    n_windows = result.get("n_windows", 11)
    n_doors = result.get("n_doors", 5)
    if n_windows == 0:
        n_windows = 11  # expected fallback
    if n_doors == 0:
        n_doors = 5

    # ── Criterion 1: Window manufacturer data ─────────────────────────────
    windows_with_mfr = result.get("windows_with_mfr_pset", 0)
    mfr_correct = result.get("window_mfr_name_correct", 0)
    model_correct = result.get("window_model_correct", 0)
    gtin_correct = result.get("window_gtin_correct", 0)

    # Score based on correct values (not just pset presence)
    mfr_pts = min(10, round((mfr_correct / n_windows) * 10))
    model_pts = min(8, round((model_correct / n_windows) * 8))
    gtin_pts = min(7, round((gtin_correct / n_windows) * 7))
    # If pset present but all values wrong, give tiny partial for effort
    if windows_with_mfr > 0 and (mfr_pts + model_pts + gtin_pts) == 0:
        pset_presence_pts = min(5, round((windows_with_mfr / n_windows) * 5))
        score += pset_presence_pts
        feedback.append(f"PARTIAL (+{pset_presence_pts}): {windows_with_mfr}/{n_windows} windows have Pset_ManufacturerTypeInformation but values are incorrect.")
    else:
        win_mfr_total = mfr_pts + model_pts + gtin_pts
        score += win_mfr_total
        if win_mfr_total >= 20:
            feedback.append(f"PASS (+{win_mfr_total}): Window manufacturer data correct (manufacturer={mfr_correct}, model={model_correct}, GTIN={gtin_correct}/{n_windows} windows).")
        elif win_mfr_total > 0:
            feedback.append(f"PARTIAL (+{win_mfr_total}): Window manufacturer partially correct (manufacturer={mfr_correct}, model={model_correct}, GTIN={gtin_correct}).")
        else:
            feedback.append(f"FAIL (+0): No correct window manufacturer data found ({windows_with_mfr} have pset).")

    # ── Criterion 2: Door manufacturer data ───────────────────────────────
    doors_with_mfr = result.get("doors_with_mfr_pset", 0)
    door_mfr_correct = result.get("door_mfr_name_correct", 0)
    door_model_correct = result.get("door_model_correct", 0)
    door_gtin_correct = result.get("door_gtin_correct", 0)

    door_mfr_pts = min(8, round((door_mfr_correct / n_doors) * 8))
    door_model_pts = min(7, round((door_model_correct / n_doors) * 7))
    door_gtin_pts = min(5, round((door_gtin_correct / n_doors) * 5))
    if doors_with_mfr > 0 and (door_mfr_pts + door_model_pts + door_gtin_pts) == 0:
        pset_presence_pts = min(4, round((doors_with_mfr / n_doors) * 4))
        score += pset_presence_pts
        feedback.append(f"PARTIAL (+{pset_presence_pts}): {doors_with_mfr}/{n_doors} doors have Pset_ManufacturerTypeInformation but values are incorrect.")
    else:
        door_mfr_total = door_mfr_pts + door_model_pts + door_gtin_pts
        score += door_mfr_total
        if door_mfr_total >= 16:
            feedback.append(f"PASS (+{door_mfr_total}): Door manufacturer data correct (manufacturer={door_mfr_correct}, model={door_model_correct}, GTIN={door_gtin_correct}/{n_doors} doors).")
        elif door_mfr_total > 0:
            feedback.append(f"PARTIAL (+{door_mfr_total}): Door manufacturer partially correct.")
        else:
            feedback.append(f"FAIL (+0): No correct door manufacturer data found ({doors_with_mfr} have pset).")

    # ── Criterion 3: Window common properties ─────────────────────────────
    windows_with_common = result.get("windows_with_window_common", 0)
    thermal_correct = result.get("window_thermal_correct", 0)
    glazing_correct = result.get("window_glazing_correct", 0)
    external_correct = result.get("window_external_correct", 0)

    thermal_pts = min(8, round((thermal_correct / n_windows) * 8))
    glazing_pts = min(7, round((glazing_correct / n_windows) * 7))
    external_pts = min(5, round((external_correct / n_windows) * 5))
    if windows_with_common > 0 and (thermal_pts + glazing_pts + external_pts) == 0:
        pset_presence_pts = min(5, round((windows_with_common / n_windows) * 5))
        score += pset_presence_pts
        feedback.append(f"PARTIAL (+{pset_presence_pts}): {windows_with_common}/{n_windows} windows have Pset_WindowCommon but values are incorrect.")
    else:
        window_common_total = thermal_pts + glazing_pts + external_pts
        score += window_common_total
        if window_common_total >= 16:
            feedback.append(f"PASS (+{window_common_total}): Pset_WindowCommon correct (thermal={thermal_correct}, glazing={glazing_correct}, external={external_correct}/{n_windows}).")
        elif window_common_total > 0:
            feedback.append(f"PARTIAL (+{window_common_total}): Pset_WindowCommon partially correct.")
        else:
            feedback.append(f"FAIL (+0): No correct Pset_WindowCommon data found ({windows_with_common} have pset).")

    # ── Criterion 4: Glazing Package group ───────────────────────────────
    glazing_group_found = result.get("glazing_group_found", False)
    glazing_window_count = result.get("glazing_group_window_count", 0)
    if glazing_group_found:
        group_pts = 8
        # Partial for windows assigned
        if glazing_window_count >= n_windows:
            group_pts += 7
        elif glazing_window_count >= round(n_windows * 0.5):
            group_pts += round((glazing_window_count / n_windows) * 7)
        score += group_pts
        feedback.append(f"PASS (+{group_pts}): 'Glazing Package' IfcGroup found with {glazing_window_count}/{n_windows} windows assigned.")
    else:
        feedback.append("FAIL (+0): No IfcGroup named 'Glazing Package' found.")

    score = min(100, score)
    PASS_THRESHOLD = 65
    passed = score >= PASS_THRESHOLD
    feedback.append(f"\nTotal score: {score}/100 (threshold: {PASS_THRESHOLD})")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
