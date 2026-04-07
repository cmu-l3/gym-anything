"""
Verifier stub for supernova_photometric_classification.

Full programmatic scoring is optional — the VLM checklist verifier
will be used as the primary evaluation method.  This stub performs
basic file-existence and structural checks only.
"""

import json
import base64
import tempfile


def verify_supernova_photometric_classification(traj, env_info, task_info):
    """Verify supernova photometric classification task."""

    score = 0
    feedback = []

    # ── Load exported results ────────────────────────────────────────
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {
            "passed": False,
            "decided": True,
            "score": 0,
            "feedback": "copy_from_env not available in env_info",
        }
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", mode="w") as tmp:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "decided": True,
            "score": 0,
            "feedback": f"Could not load /tmp/task_result.json: {e}",
        }

    task_start = result.get("task_start", 0)
    fits_files = result.get("fits_files", [])

    # Helper: count new FITS in a given subdir
    def count_new_fits(subdir, min_size=2048):
        return sum(
            1
            for f in fits_files
            if f.get("subdir", "") == subdir
            and f.get("mtime", 0) > task_start
            and f.get("size", 0) > min_size
        )

    # ── Phase 1: Reference imaging (15 pts) ──────────────────────────
    ref_count = count_new_fits("reference")
    if ref_count >= 3:
        score += 10
        feedback.append(f"Phase1-Ref: {ref_count}/3 Luminance frames OK")
    elif ref_count >= 1:
        score += 5
        feedback.append(f"Phase1-Ref: {ref_count}/3 Luminance frames (partial)")
    else:
        feedback.append(f"Phase1-Ref: 0/3 Luminance frames")

    chart = result.get("finding_chart", {})
    if chart.get("exists") and chart.get("size", 0) > 10000 and chart.get("mtime", 0) > task_start:
        score += 5
        feedback.append("Phase1-Chart: finding_chart.png OK")
    else:
        feedback.append("Phase1-Chart: finding_chart.png missing or invalid")

    # ── Phase 2: Candidate multi-band photometry (30 pts) ────────────
    for band, subdir in [("B", "candidate/B"), ("V", "candidate/V"), ("R", "candidate/R")]:
        n = count_new_fits(subdir)
        if n >= 5:
            score += 10
            feedback.append(f"Phase2-{band}: {n}/5 frames OK")
        elif n >= 3:
            score += 5
            feedback.append(f"Phase2-{band}: {n}/5 frames (partial)")
        else:
            feedback.append(f"Phase2-{band}: {n}/5 frames")

    # ── Phase 3: Standard star calibration (15 pts) ──────────────────
    for band, subdir in [("B", "standard/B"), ("V", "standard/V"), ("R", "standard/R")]:
        n = count_new_fits(subdir)
        if n >= 3:
            score += 5
            feedback.append(f"Phase3-Std-{band}: {n}/3 frames OK")
        elif n >= 1:
            score += 2
            feedback.append(f"Phase3-Std-{band}: {n}/3 frames (partial)")
        else:
            feedback.append(f"Phase3-Std-{band}: 0/3 frames")

    # ── Phase 4: Reduction script + classification JSON (25 pts) ─────
    script_info = result.get("reduction_script", {})
    if script_info.get("exists"):
        score += 5
        feedback.append("Phase4-Script: reduce_photometry.py exists")

        # Check script content for key components
        try:
            script_text = base64.b64decode(script_info.get("content_b64", "")).decode("utf-8")
            if "astropy" in script_text:
                score += 3
                feedback.append("Phase4-Script: uses astropy")
            else:
                feedback.append("Phase4-Script: astropy import not found")
            if "log10" in script_text:
                score += 2
                feedback.append("Phase4-Script: has log10 computation")
            else:
                feedback.append("Phase4-Script: log10 not found")
        except Exception:
            feedback.append("Phase4-Script: could not decode content")
    else:
        feedback.append("Phase4-Script: reduce_photometry.py missing")

    class_info = result.get("classification_json", {})
    if class_info.get("exists"):
        score += 5
        feedback.append("Phase4-JSON: classification.json exists")
        try:
            cdata = class_info.get("content", {})
            if isinstance(cdata, str):
                cdata = json.loads(cdata)
            required_keys = [
                "candidate_B_mag", "candidate_V_mag", "candidate_R_mag",
                "B_minus_V", "V_minus_R", "sn_type_estimate",
            ]
            present = [k for k in required_keys if k in cdata]
            if len(present) == len(required_keys):
                score += 10
                feedback.append(f"Phase4-JSON: all {len(required_keys)} keys present")
            else:
                partial = 5 * len(present) // len(required_keys)
                score += partial
                feedback.append(
                    f"Phase4-JSON: {len(present)}/{len(required_keys)} keys "
                    f"({', '.join(present)})"
                )
        except Exception as e:
            feedback.append(f"Phase4-JSON: parse error — {e}")
    else:
        feedback.append("Phase4-JSON: classification.json missing")

    # ── Phase 5: ATel draft (15 pts) ─────────────────────────────────
    atel_info = result.get("atel_draft", {})
    if atel_info.get("exists") and atel_info.get("mtime", 0) > task_start:
        score += 5
        feedback.append("Phase5-ATel: atel_draft.txt exists")

        try:
            atel_text = base64.b64decode(atel_info.get("content_b64", "")).decode("utf-8")
            atel_lower = atel_text.lower()

            checks = [
                ("at2026xy" in atel_lower, "designation AT2026xy"),
                ("ngc 4526" in atel_lower or "ngc4526" in atel_lower, "host galaxy NGC 4526"),
                (any(w in atel_lower for w in ["12h", "12 h", "188.", "189.", "12.5"]), "RA reference"),
                (any(w in atel_lower for w in ["mag", "magnitude", "b-v", "color"]), "photometric data"),
                (any(w in atel_lower for w in ["ia", "ii-p", "ib/c", "ib", "type"]), "SN classification"),
            ]
            for passed, desc in checks:
                if passed:
                    score += 2
                    feedback.append(f"Phase5-ATel: contains {desc}")
                else:
                    feedback.append(f"Phase5-ATel: missing {desc}")
        except Exception:
            feedback.append("Phase5-ATel: could not decode content")
    else:
        feedback.append("Phase5-ATel: atel_draft.txt missing or stale")

    # ── Final verdict ────────────────────────────────────────────────
    passed = score >= 60

    return {
        "passed": passed,
        "decided": True,
        "score": score,
        "feedback": f"Total: {score}/100\n" + "\n".join(feedback),
    }
