"""
Verifier for acoustic_performance_pset_authoring task.

Scoring (100 points total, threshold 65):
  file_new         (10 pts) : Output IFC exists and is newer than task start
  ext_wall_pset    (25 pts) : Partial: ew_acoustic_rating_correct / n_ew_walls * 25
  int_wall_pset    (30 pts) : Partial over 3 sub-criteria (STC×10, IIC×10, Flanking×10),
                              scored as iw_with_custom_pset / n_iw_walls * 30 as gate,
                              then sub-scored: stc_correct + iic_correct + flanking_correct
  zones            (20 pts) : zone_a_found(10) + zone_b_found(10)
  zone_members     (15 pts) : bonus - zones have correct space members assigned

Do-nothing → score 0. Max partial without correct codes = 10 (file only).
"""
import json
import os
import tempfile


def verify_acoustic_pset_authoring(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env("/tmp/acoustic_pset_result.json", tmp_path)
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
            "feedback": "FAIL: Output IFC /home/ga/BIMProjects/fzk_acoustic.ifc was not created."
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

    # ── Criterion 1: External wall acoustic rating ─────────────────────────
    n_ew = result.get("n_ew_walls", 0)
    ew_correct = result.get("ew_acoustic_rating_correct", 0)
    ew_with_rating = result.get("ew_walls_with_acoustic_rating", 0)
    if n_ew > 0:
        # Partial credit based on correct ratings
        ew_pts = min(25, round((ew_correct / n_ew) * 25))
        score += ew_pts
        if ew_pts >= 20:
            feedback.append(f"PASS (+{ew_pts}): {ew_correct}/{n_ew} external walls have correct AcousticRating 'Rw 52 dB' in Pset_WallCommon.")
        elif ew_pts > 0:
            feedback.append(f"PARTIAL (+{ew_pts}): {ew_correct}/{n_ew} external walls have correct AcousticRating ({ew_with_rating} have any rating).")
        else:
            feedback.append(f"FAIL (+0): No external walls have correct AcousticRating. ({ew_with_rating} have some rating property, {n_ew} EW walls total).")
    else:
        feedback.append("FAIL (+0): No EW-prefixed external walls found in output model.")

    # ── Criterion 2: Internal wall custom Pset_AcousticPerformance ────────
    n_iw = result.get("n_iw_walls", 0)
    iw_with_pset = result.get("iw_walls_with_custom_pset", 0)
    iw_stc = result.get("iw_stc_correct", 0)
    iw_iic = result.get("iw_iic_correct", 0)
    iw_flanking = result.get("iw_flanking_correct", 0)
    if n_iw > 0:
        # Gate: how many IW walls have the custom pset
        coverage_frac = iw_with_pset / n_iw if n_iw > 0 else 0
        # Sub-scores for property correctness (average fraction across walls)
        stc_pts = min(10, round((iw_stc / n_iw) * 10))
        iic_pts = min(10, round((iw_iic / n_iw) * 10))
        flank_pts = min(10, round((iw_flanking / n_iw) * 10))
        iw_total = stc_pts + iic_pts + flank_pts
        # If pset exists but properties wrong, give partial for pset existence
        if iw_with_pset > 0 and iw_total == 0:
            iw_total = min(8, round(coverage_frac * 8))
        score += iw_total
        if iw_total >= 25:
            feedback.append(f"PASS (+{iw_total}): Internal walls have Pset_AcousticPerformance with correct values (STC×{stc_pts}/10, IIC×{iic_pts}/10, Flanking×{flank_pts}/10).")
        elif iw_total > 0:
            feedback.append(f"PARTIAL (+{iw_total}): Internal wall pset partially correct ({iw_with_pset}/{n_iw} have pset; STC={iw_stc}, IIC={iw_iic}, Flanking={iw_flanking}).")
        else:
            feedback.append(f"FAIL (+0): Internal walls missing Pset_AcousticPerformance ({iw_with_pset}/{n_iw} have it).")
    else:
        feedback.append("FAIL (+0): No IW-prefixed internal walls found in output model.")

    # ── Criterion 3: Acoustic zones ───────────────────────────────────────
    zones = result.get("zones", [])
    zone_names = [z.get("name", "").lower() for z in zones]

    zone_a_found = any("zone a" in n or ("living" in n and "acoustic" in n) for n in zone_names)
    zone_b_found = any("zone b" in n or ("sleeping" in n and "acoustic" in n) for n in zone_names)

    zone_pts = 0
    if zone_a_found:
        zone_pts += 10
        feedback.append("PASS (+10): Acoustic Zone A (Living) found.")
    else:
        feedback.append("FAIL (+0): Acoustic Zone A (Living) not found.")

    if zone_b_found:
        zone_pts += 10
        feedback.append("PASS (+10): Acoustic Zone B (Sleeping) found.")
    else:
        feedback.append("FAIL (+0): Acoustic Zone B (Sleeping) not found.")

    score += zone_pts

    # ── Bonus: zone members assigned ─────────────────────────────────────
    member_bonus = 0
    for z in zones:
        zname = z.get("name", "").lower()
        members = z.get("members", [])
        space_members = [m for m in members if m.get("class", "").startswith("IfcSpace")]
        if space_members:
            if ("zone a" in zname or "living" in zname) and len(space_members) >= 1:
                member_bonus = min(15, member_bonus + 8)
            elif ("zone b" in zname or "sleeping" in zname) and len(space_members) >= 1:
                member_bonus = min(15, member_bonus + 7)
    score += member_bonus
    if member_bonus > 0:
        feedback.append(f"BONUS (+{member_bonus}): Spaces assigned to acoustic zones.")

    score = min(100, score)
    PASS_THRESHOLD = 65
    passed = score >= PASS_THRESHOLD
    feedback.append(f"\nTotal score: {score}/100 (threshold: {PASS_THRESHOLD})")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
