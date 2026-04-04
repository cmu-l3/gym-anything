"""
Verifier for cox_survival_cancer task.

Scoring (100 points total):
  Cox results CSV      — 30 pts
  PH assumption CSV    — 20 pts
  KM curves PNG        — 25 pts
  Forest plot PNG      — 25 pts
  VLM visual check     — up to 10 bonus pts (capped at 100)

Pass threshold: 60 / 100
"""

import json
import os
import tempfile


def verify_cox_survival_cancer(traj, env_info, task_info):
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
            copy_from_env("/tmp/cox_survival_cancer_result.json", tmp.name)
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

    # ── 1. Cox results CSV (30 pts) ───────────────────────────────────────────
    cox = result.get("cox_csv", {})
    cox_pts = 0

    if cox.get("exists") and cox.get("is_new"):
        cox_pts += 10
        parts.append("Cox CSV exists and is new (+10)")
    elif cox.get("exists"):
        parts.append("Cox CSV exists but predates task start (0)")
    else:
        parts.append("Cox CSV missing (0)")

    if cox.get("has_hr_column"):
        cox_pts += 5
        parts.append("Cox CSV has HR column (+5)")

    if cox.get("has_pvalue_column"):
        cox_pts += 5
        parts.append("Cox CSV has p-value column (+5)")

    # HR for horTh should be < 1 (protective) — accept "true" or "unknown"
    horthy = cox.get("horthy_hr_valid", "false")
    if horthy == "true":
        cox_pts += 10
        parts.append("horTh HR in plausible protective range 0.3–1.2 (+10)")
    elif horthy == "unknown":
        # Can't determine — partial credit
        cox_pts += 5
        parts.append("horTh HR check inconclusive, partial credit (+5)")
    else:
        parts.append("horTh HR outside expected range or missing (0)")

    score += cox_pts

    # ── 2. PH test CSV (20 pts) ───────────────────────────────────────────────
    ph = result.get("ph_test_csv", {})
    ph_pts = 0

    if ph.get("exists") and ph.get("is_new"):
        ph_pts += 10
        parts.append("PH test CSV exists and is new (+10)")
    elif ph.get("exists"):
        parts.append("PH test CSV predates task start (0)")
    else:
        parts.append("PH test CSV missing (0)")

    if ph.get("has_chisq_column"):
        ph_pts += 10
        parts.append("PH test CSV has chi-sq statistic column (+10)")

    # Expect at least 8 rows (7 covariates + 1 global)
    row_count = ph.get("row_count", 0)
    if row_count >= 8:
        parts.append(f"PH test CSV has {row_count} rows (expected ≥8)")
    elif row_count >= 2:
        parts.append(f"PH test CSV has only {row_count} rows (expected ≥8)")

    score += ph_pts

    # ── 3. KM curves PNG (25 pts) ─────────────────────────────────────────────
    km = result.get("km_png", {})
    km_pts = 0

    if km.get("exists") and km.get("is_new"):
        km_pts += 10
        parts.append("KM PNG exists and is new (+10)")
    elif km.get("exists"):
        parts.append("KM PNG predates task start (0)")
    else:
        parts.append("KM PNG missing (0)")

    if km.get("is_valid_png"):
        km_pts += 5
        parts.append("KM PNG has valid PNG header (+5)")

    km_size = km.get("size_bytes", 0)
    if km_size >= 80_000:
        km_pts += 10
        parts.append(f"KM PNG size {km_size:,} bytes ≥ 80KB (risk table likely included) (+10)")
    elif km_size >= 30_000:
        km_pts += 5
        parts.append(f"KM PNG size {km_size:,} bytes ≥ 30KB (+5)")
    else:
        parts.append(f"KM PNG too small ({km_size:,} bytes), risk table may be missing")

    score += km_pts

    # ── 4. Forest plot PNG (25 pts) ───────────────────────────────────────────
    forest = result.get("forest_png", {})
    forest_pts = 0

    if forest.get("exists") and forest.get("is_new"):
        forest_pts += 10
        parts.append("Forest plot PNG exists and is new (+10)")
    elif forest.get("exists"):
        parts.append("Forest plot PNG predates task start (0)")
    else:
        parts.append("Forest plot PNG missing (0)")

    if forest.get("is_valid_png"):
        forest_pts += 5
        parts.append("Forest plot has valid PNG header (+5)")

    forest_size = forest.get("size_bytes", 0)
    if forest_size >= 30_000:
        forest_pts += 10
        parts.append(f"Forest plot size {forest_size:,} bytes ≥ 30KB (+10)")
    elif forest_size >= 10_000:
        forest_pts += 5
        parts.append(f"Forest plot size {forest_size:,} bytes ≥ 10KB (+5)")
    else:
        parts.append(f"Forest plot too small ({forest_size:,} bytes)")

    score += forest_pts

    # ── 5. Script evidence (bonus sanity check, not scored separately) ────────
    script = result.get("script", {})
    if script.get("has_coxph") and script.get("has_cox_zph"):
        parts.append("Script contains coxph() and cox.zph() calls")

    # ── 6. VLM visual check (up to 10 bonus pts) ─────────────────────────────
    if query_vlm and get_final_screenshot:
        try:
            screenshot = get_final_screenshot()
            if screenshot:
                vlm_response = query_vlm(
                    image=screenshot,
                    prompt=(
                        "This is a screenshot from an RStudio session where the user completed "
                        "a Cox proportional hazards survival analysis on breast cancer data. "
                        "Look at the RStudio console or any visible output. "
                        "Do you see evidence of: (1) a fitted Cox model output with hazard ratios, "
                        "(2) cox.zph() proportional hazards test results, "
                        "(3) Kaplan-Meier curves from survminer, or "
                        "(4) a forest plot? "
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

    # ── Score cap gates (Lesson 25): all 4 deliverables are required to pass ──
    # Without gates: Cox(30) + KM(25) + Forest(25) = 80 → passes without PH test
    PASS_THRESHOLD = 60
    ph = result.get("ph_test_csv", {})
    ph_present = ph.get("exists") and ph.get("is_new")
    if not ph_present and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        parts.append(f"Score capped at {PASS_THRESHOLD - 1}: gbsg_ph_test.csv is a required deliverable")

    km = result.get("km_png", {})
    km_present = km.get("exists") and km.get("is_new")
    if not km_present and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        parts.append(f"Score capped at {PASS_THRESHOLD - 1}: gbsg_km_curves.png is a required deliverable")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts) or "No criteria met",
    }
