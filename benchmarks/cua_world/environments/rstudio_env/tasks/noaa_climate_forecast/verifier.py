"""
Verifier for noaa_climate_forecast task.

Scoring (100 points total):
  STL decomposition CSV   — 25 pts
  ARIMA forecast CSV      — 25 pts
  Changepoints CSV        — 20 pts
  3-panel plot PNG        — 30 pts
  VLM visual check        — up to 10 bonus pts (capped at 100)

Pass threshold: 60 / 100
"""

import json
import os
import tempfile


def verify_noaa_climate_forecast(traj, env_info, task_info):
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
            copy_from_env("/tmp/noaa_climate_forecast_result.json", tmp.name)
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

    # ── 1. STL decomposition CSV (25 pts) ─────────────────────────────────────
    stl = result.get("stl_csv", {})
    stl_pts = 0

    if stl.get("exists") and stl.get("is_new"):
        stl_pts += 10
        parts.append("STL CSV exists and is new (+10)")
    elif stl.get("exists"):
        parts.append("STL CSV predates task start (0)")
    else:
        parts.append("STL CSV missing (0)")

    if stl.get("has_trend_column"):
        stl_pts += 10
        parts.append("STL CSV has trend column (+10)")

    # Expect ~144 rows (1880-2023)
    row_count = stl.get("row_count", 0)
    if row_count >= 100:
        stl_pts += 5
        parts.append(f"STL CSV has {row_count} rows covering full record (+5)")
    elif row_count >= 50:
        stl_pts += 2
        parts.append(f"STL CSV has {row_count} rows (partial, expected ~144)")

    if stl.get("trend_is_positive"):
        parts.append("STL trend component shows correct warming direction")
    else:
        parts.append("STL trend direction check inconclusive")

    score += stl_pts

    # ── 2. ARIMA forecast CSV (25 pts) ────────────────────────────────────────
    fcst = result.get("forecast_csv", {})
    fcst_pts = 0

    if fcst.get("exists") and fcst.get("is_new"):
        fcst_pts += 10
        parts.append("Forecast CSV exists and is new (+10)")
    elif fcst.get("exists"):
        parts.append("Forecast CSV predates task start (0)")
    else:
        parts.append("Forecast CSV missing (0)")

    if fcst.get("has_required_columns"):
        fcst_pts += 10
        parts.append("Forecast CSV has forecast + CI columns (+10)")

    # Expect 10 rows (2024-2033)
    fcst_rows = fcst.get("row_count", 0)
    if fcst_rows >= 10:
        fcst_pts += 5
        parts.append(f"Forecast CSV has {fcst_rows} rows (10-year horizon) (+5)")
    elif fcst_rows >= 5:
        fcst_pts += 2
        parts.append(f"Forecast CSV has {fcst_rows} rows (expected 10)")

    if fcst.get("forecast_values_valid"):
        parts.append("Forecast values in plausible range")

    score += fcst_pts

    # ── 3. Changepoints CSV (20 pts) ──────────────────────────────────────────
    bp = result.get("breakpoints_csv", {})
    bp_pts = 0

    if bp.get("exists") and bp.get("is_new"):
        bp_pts += 10
        parts.append("Breakpoints CSV exists and is new (+10)")
    elif bp.get("exists"):
        parts.append("Breakpoints CSV predates task start (0)")
    else:
        parts.append("Breakpoints CSV missing (0)")

    if bp.get("has_required_columns"):
        bp_pts += 10
        parts.append("Breakpoints CSV has breakpoint_year and segment means (+10)")

    bp_rows = bp.get("row_count", 0)
    if bp_rows >= 2:
        parts.append(f"Breakpoints CSV has {bp_rows} rows (at least 1 breakpoint)")
    elif bp_rows == 1:
        parts.append("Breakpoints CSV has only header row — no breakpoints detected")

    score += bp_pts

    # ── 4. 3-panel plot PNG (30 pts) ──────────────────────────────────────────
    plot = result.get("plot_png", {})
    plot_pts = 0

    if plot.get("exists") and plot.get("is_new"):
        plot_pts += 10
        parts.append("Plot PNG exists and is new (+10)")
    elif plot.get("exists"):
        parts.append("Plot PNG predates task start (0)")
    else:
        parts.append("Plot PNG missing (0)")

    if plot.get("is_valid_png"):
        plot_pts += 5
        parts.append("Plot PNG has valid PNG header (+5)")

    plot_size = plot.get("size_bytes", 0)
    if plot_size >= 100_000:
        plot_pts += 15
        parts.append(f"Plot size {plot_size:,} bytes ≥ 100KB (3-panel likely) (+15)")
    elif plot_size >= 50_000:
        plot_pts += 10
        parts.append(f"Plot size {plot_size:,} bytes ≥ 50KB (+10)")
    elif plot_size >= 20_000:
        plot_pts += 5
        parts.append(f"Plot size {plot_size:,} bytes ≥ 20KB (+5)")
    else:
        parts.append(f"Plot too small ({plot_size:,} bytes)")

    score += plot_pts

    # ── 5. Script evidence ────────────────────────────────────────────────────
    script = result.get("script", {})
    if script.get("has_stl") and script.get("has_auto_arima") and script.get("has_changepoint"):
        parts.append("Script contains stl(), auto.arima(), and changepoint calls")
    elif script.get("has_stl") or script.get("has_auto_arima"):
        parts.append("Script has some required function calls")

    # ── 6. VLM visual check (up to 10 bonus pts) ─────────────────────────────
    if query_vlm and get_final_screenshot:
        try:
            screenshot = get_final_screenshot()
            if screenshot:
                vlm_response = query_vlm(
                    image=screenshot,
                    prompt=(
                        "This is a screenshot from an RStudio session where the user completed "
                        "a climate time series analysis on NASA GISTEMP global temperature anomaly data. "
                        "Do you see evidence of: (1) STL decomposition output, "
                        "(2) ARIMA forecast with confidence intervals, "
                        "(3) changepoint detection results, or "
                        "(4) a multi-panel climate plot? "
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
    # Without gate: STL(25) + Forecast(25) + Plot(30) = 80 → passes without breakpoints
    PASS_THRESHOLD = 60
    bp = result.get("breakpoints_csv", {})
    bp_present = bp.get("exists") and bp.get("is_new")
    if not bp_present and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        parts.append(f"Score capped at {PASS_THRESHOLD - 1}: climate_breakpoints.csv is a required deliverable")

    fcst = result.get("forecast_csv", {})
    fcst_present = fcst.get("exists") and fcst.get("is_new")
    if not fcst_present and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        parts.append(f"Score capped at {PASS_THRESHOLD - 1}: climate_forecast.csv is a required deliverable")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts) or "No criteria met",
    }
