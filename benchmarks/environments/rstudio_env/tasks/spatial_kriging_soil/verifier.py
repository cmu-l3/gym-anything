"""
Verifier for spatial_kriging_soil task.

Scoring (100 points total):
  Variogram model CSV     — 25 pts
  Kriging predictions CSV — 30 pts
  Moran's I test CSV      — 15 pts
  2-panel spatial map PNG — 30 pts
  VLM visual check        — up to 10 bonus pts (capped at 100)

Pass threshold: 60 / 100
"""

import json
import os
import tempfile


def verify_spatial_kriging_soil(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    get_final_screenshot = env_info.get("get_final_screenshot")

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # ── load result JSON ──────────────────────────────────────────────────────
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/spatial_kriging_soil_result.json", tmp.name)
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}

    score = 0
    parts = []

    # ── 1. Variogram model CSV (25 pts) ───────────────────────────────────────
    vario = result.get("variogram_csv", {})
    vario_pts = result.get("variogram_points_csv", {})
    v_score = 0

    if vario.get("exists") and vario.get("is_new"):
        v_score += 10
        parts.append("Variogram model CSV exists and is new (+10)")
    elif vario.get("exists"):
        parts.append("Variogram model CSV predates task start (0)")
    else:
        parts.append("Variogram model CSV missing (0)")

    if vario.get("has_required_columns"):
        v_score += 10
        parts.append("Variogram CSV has nugget/sill/range columns (+10)")

    if vario.get("parameters_valid"):
        v_score += 5
        parts.append("Variogram parameters in plausible range (+5)")
    else:
        parts.append("Variogram parameters out of expected range or unverifiable")

    # Bonus for variogram points CSV
    if vario_pts.get("exists") and vario_pts.get("is_new"):
        row_count = vario_pts.get("row_count", 0)
        if row_count >= 5:
            v_score = min(25, v_score + 2)
            parts.append(f"Variogram points CSV with {row_count} bins (+2 bonus)")

    score += v_score

    # ── 2. Kriging predictions CSV (30 pts) ───────────────────────────────────
    pred = result.get("predictions_csv", {})
    p_score = 0

    if pred.get("exists") and pred.get("is_new"):
        p_score += 12
        parts.append("Kriging predictions CSV exists and is new (+12)")
    elif pred.get("exists"):
        parts.append("Kriging predictions CSV predates task start (0)")
    else:
        parts.append("Kriging predictions CSV missing (0)")

    if pred.get("has_required_columns"):
        p_score += 10
        parts.append("Predictions CSV has x, y, pred columns (+10)")

    pred_rows = pred.get("row_count", 0)
    # meuse.grid has 3103 cells; 40m grid should produce hundreds of predictions
    if pred_rows >= 200:
        p_score += 8
        parts.append(f"Predictions CSV has {pred_rows} rows (full grid) (+8)")
    elif pred_rows >= 50:
        p_score += 4
        parts.append(f"Predictions CSV has {pred_rows} rows (partial grid) (+4)")
    else:
        parts.append(f"Predictions CSV has only {pred_rows} rows")

    if pred.get("values_in_valid_range"):
        parts.append("Prediction values in valid range (log or original scale)")

    score += p_score

    # ── 3. Moran's I test CSV (15 pts) ────────────────────────────────────────
    moran = result.get("moran_csv", {})
    m_score = 0

    if moran.get("exists") and moran.get("is_new"):
        m_score += 8
        parts.append("Moran test CSV exists and is new (+8)")
    elif moran.get("exists"):
        parts.append("Moran test CSV predates task start (0)")
    else:
        parts.append("Moran test CSV missing (0)")

    if moran.get("has_required_columns"):
        m_score += 7
        parts.append("Moran CSV has statistic and p-value columns (+7)")

    score += m_score

    # ── 4. 2-panel spatial map PNG (30 pts) ───────────────────────────────────
    mapf = result.get("map_png", {})
    map_score = 0

    if mapf.get("exists") and mapf.get("is_new"):
        map_score += 10
        parts.append("Kriging map PNG exists and is new (+10)")
    elif mapf.get("exists"):
        parts.append("Kriging map PNG predates task start (0)")
    else:
        parts.append("Kriging map PNG missing (0)")

    if mapf.get("is_valid_png"):
        map_score += 5
        parts.append("Kriging map has valid PNG header (+5)")

    map_size = mapf.get("size_bytes", 0)
    if map_size >= 150_000:
        map_score += 15
        parts.append(f"Map size {map_size:,} bytes ≥ 150KB (2-panel with spatial data) (+15)")
    elif map_size >= 80_000:
        map_score += 10
        parts.append(f"Map size {map_size:,} bytes ≥ 80KB (+10)")
    elif map_size >= 30_000:
        map_score += 5
        parts.append(f"Map size {map_size:,} bytes ≥ 30KB (+5)")
    else:
        parts.append(f"Map too small ({map_size:,} bytes)")

    score += map_score

    # ── 5. Script evidence ────────────────────────────────────────────────────
    script = result.get("script", {})
    if script.get("has_variogram") and script.get("has_krige"):
        parts.append("Script has variogram() and krige() calls")
    if script.get("has_moran"):
        parts.append("Script has Moran's I test call")

    # ── 6. VLM visual check (up to 10 bonus pts) ─────────────────────────────
    if query_vlm and get_final_screenshot:
        try:
            screenshot = get_final_screenshot()
            if screenshot:
                vlm_response = query_vlm(
                    image=screenshot,
                    prompt=(
                        "This is a screenshot from an RStudio session where the user performed "
                        "spatial kriging geostatistics on soil zinc concentration data from the "
                        "Meuse river flood plain. "
                        "Do you see evidence of: (1) a variogram plot or fitted model output, "
                        "(2) ordinary kriging results or prediction map, "
                        "(3) Moran's I autocorrelation test output, or "
                        "(4) a spatial map with bubble plot or color-coded predictions? "
                        "Rate the evidence on a scale of 0-10 where 10 means clear evidence of "
                        "all four completed deliverables. Respond with just a number 0-10."
                    ),
                )
                try:
                    vlm_score = int(str(vlm_response).strip().split()[0])
                    bonus = min(10, max(0, vlm_score))
                    score = min(100, score + bonus)
                    parts.append(f"VLM visual check: {vlm_score}/10 (+{bonus} bonus)")
                except (ValueError, IndexError):
                    parts.append("VLM response could not be parsed")
        except Exception as e:
            parts.append(f"VLM check skipped: {e}")

    score = min(100, max(0, score))

    # ── Score cap gates (Lesson 25): all deliverables required to pass ──────────
    # Without gate: Predictions(30) + Map(30) = 60 → passes without variogram or Moran
    PASS_THRESHOLD = 60
    vario = result.get("variogram_csv", {})
    vario_present = vario.get("exists") and vario.get("is_new")
    if not vario_present and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        parts.append(f"Score capped at {PASS_THRESHOLD - 1}: zinc_variogram.csv is a required deliverable")

    pred = result.get("predictions_csv", {})
    pred_present = pred.get("exists") and pred.get("is_new")
    if not pred_present and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        parts.append(f"Score capped at {PASS_THRESHOLD - 1}: zinc_kriging_predictions.csv is a required deliverable")

    moran = result.get("moran_csv", {})
    moran_present = moran.get("exists") and moran.get("is_new")
    if not moran_present and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        parts.append(f"Score capped at {PASS_THRESHOLD - 1}: zinc_moran_test.csv is a required deliverable")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts) or "No criteria met",
    }
