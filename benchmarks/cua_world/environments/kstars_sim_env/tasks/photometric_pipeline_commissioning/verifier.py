"""
Verifier stub for photometric_pipeline_commissioning.

Performs basic structural and plausibility checks. The VLM checklist
verifier will be used as the primary evaluation method.
"""

import json
import base64
import tempfile


def verify_photometric_pipeline_commissioning(traj, env_info, task_info):
    """Verify photometric pipeline commissioning task."""

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
    dir_counts = result.get("dir_counts", {})

    # ── Phase 1: Focus frames (8 pts) ───────────────────────────────
    focus_count = dir_counts.get("focus_test", 0)
    if focus_count >= 5:
        score += 8
        feedback.append(f"Focus: {focus_count}/5 frames OK")
    elif focus_count >= 3:
        score += 4
        feedback.append(f"Focus: {focus_count}/5 frames (partial)")
    else:
        feedback.append(f"Focus: {focus_count}/5 frames")

    # ── Focus script exists (3 pts) ──────────────────────────────────
    if result.get("focus_script", {}).get("exists"):
        score += 3
        feedback.append("Focus script: exists")
    else:
        feedback.append("Focus script: missing")

    # ── Focuser at a tested position (4 pts) ─────────────────────────
    tested_positions = [25000, 28000, 31000, 34000, 37000]
    try:
        focus_pos = int(result.get("focuser_position", 0))
        if focus_pos in tested_positions:
            score += 4
            feedback.append(f"Focuser: at tested position {focus_pos}")
        elif 24000 <= focus_pos <= 38000:
            score += 2
            feedback.append(f"Focuser: at plausible position {focus_pos}")
        else:
            feedback.append(f"Focuser: at unexpected position {focus_pos}")
    except (ValueError, TypeError):
        feedback.append("Focuser: position unknown")

    # ── Phase 2: Calibration frames ──────────────────────────────────
    # Bias (8 pts)
    bias_count = dir_counts.get("bias", 0)
    if bias_count >= 10:
        score += 8
        feedback.append(f"Bias: {bias_count}/10 frames OK")
    elif bias_count >= 5:
        score += 4
        feedback.append(f"Bias: {bias_count}/10 frames (partial)")
    else:
        feedback.append(f"Bias: {bias_count}/10 frames")

    # Flats (8 pts)
    flat_count = dir_counts.get("flats_V", 0)
    if flat_count >= 10:
        score += 8
        feedback.append(f"Flats: {flat_count}/10 frames OK")
    elif flat_count >= 5:
        score += 4
        feedback.append(f"Flats: {flat_count}/10 frames (partial)")
    else:
        feedback.append(f"Flats: {flat_count}/10 frames")

    # SA 98 V (5 pts)
    sa98v = dir_counts.get("sa98_V", 0)
    if sa98v >= 5:
        score += 5
        feedback.append(f"SA98 V: {sa98v}/5 frames OK")
    else:
        feedback.append(f"SA98 V: {sa98v}/5 frames")

    # SA 98 B (5 pts)
    sa98b = dir_counts.get("sa98_B", 0)
    if sa98b >= 5:
        score += 5
        feedback.append(f"SA98 B: {sa98b}/5 frames OK")
    else:
        feedback.append(f"SA98 B: {sa98b}/5 frames")

    # M67 V (5 pts)
    m67v = dir_counts.get("m67_V", 0)
    if m67v >= 5:
        score += 5
        feedback.append(f"M67 V: {m67v}/5 frames OK")
    else:
        feedback.append(f"M67 V: {m67v}/5 frames")

    # M67 B (5 pts)
    m67b = dir_counts.get("m67_B", 0)
    if m67b >= 5:
        score += 5
        feedback.append(f"M67 B: {m67b}/5 frames OK")
    else:
        feedback.append(f"M67 B: {m67b}/5 frames")

    # ── Pipeline script exists (4 pts) ───────────────────────────────
    if result.get("pipeline_script", {}).get("exists"):
        score += 4
        feedback.append("Pipeline script: exists")
    else:
        feedback.append("Pipeline script: missing")

    # ── Output JSON validation (40 pts) ──────────────────────────────
    output_info = result.get("output_json", {})
    if output_info.get("exists") and output_info.get("content") is not None:
        try:
            out = output_info["content"]
            if isinstance(out, str):
                out = json.loads(out)

            required_keys = [
                "best_focus_position", "best_fwhm",
                "readnoise_adu", "master_flat_mean",
                "zp_V", "zp_V_std", "zp_B", "zp_B_std",
                "m67_V_cal", "m67_B_cal", "m67_BV_color",
                "n_frames_total",
            ]

            # All keys present (10 pts)
            missing = [k for k in required_keys if k not in out]
            if not missing:
                score += 10
                feedback.append("JSON: all 12 keys present")
            else:
                partial = int(10 * (len(required_keys) - len(missing)) / len(required_keys))
                score += partial
                feedback.append(f"JSON: missing {missing}")

            # Zero-points plausible (8 pts)
            zp_v = out.get("zp_V", 0)
            zp_b = out.get("zp_B", 0)
            if isinstance(zp_v, (int, float)) and isinstance(zp_b, (int, float)):
                if 15 < zp_v < 30 and 15 < zp_b < 30:
                    score += 8
                    feedback.append(f"JSON: ZP plausible (V={zp_v:.2f}, B={zp_b:.2f})")
                else:
                    feedback.append(f"JSON: ZP implausible (V={zp_v}, B={zp_b})")
            else:
                feedback.append("JSON: ZP not numeric")

            # Scatter plausible (4 pts)
            zp_v_std = out.get("zp_V_std", 999)
            zp_b_std = out.get("zp_B_std", 999)
            if isinstance(zp_v_std, (int, float)) and isinstance(zp_b_std, (int, float)):
                if zp_v_std < 1.0 and zp_b_std < 1.0:
                    score += 4
                    feedback.append(f"JSON: scatter OK (V_std={zp_v_std:.3f}, B_std={zp_b_std:.3f})")
                else:
                    feedback.append(f"JSON: scatter too high (V_std={zp_v_std}, B_std={zp_b_std})")

            # Color plausible (4 pts)
            color = out.get("m67_BV_color", 999)
            if isinstance(color, (int, float)) and abs(color) < 5:
                score += 4
                feedback.append(f"JSON: color plausible (B-V={color:.2f})")
            else:
                feedback.append(f"JSON: color implausible ({color})")

            # Frame count (4 pts)
            n_frames = out.get("n_frames_total", 0)
            if n_frames == 45:
                score += 4
                feedback.append("JSON: frame count correct (45)")
            else:
                feedback.append(f"JSON: frame count {n_frames} (expected 45)")

            # Internal consistency (5 pts)
            try:
                m67_v = out.get("m67_V_cal", 0)
                m67_b = out.get("m67_B_cal", 0)
                computed_color = m67_b - m67_v
                if abs(computed_color - color) < 0.01:
                    score += 3
                    feedback.append("JSON: color internally consistent")
                else:
                    feedback.append(f"JSON: color inconsistent ({computed_color:.3f} vs {color:.3f})")

                best_fp = out.get("best_focus_position", 0)
                if best_fp in tested_positions:
                    score += 2
                    feedback.append(f"JSON: focus position in tested set ({best_fp})")
                else:
                    feedback.append(f"JSON: focus position {best_fp} not in tested set")
            except (TypeError, ValueError):
                feedback.append("JSON: consistency check failed")

            # FWHM plausible (5 pts)
            fwhm = out.get("best_fwhm", 0)
            if isinstance(fwhm, (int, float)) and 0 < fwhm < 50:
                score += 5
                feedback.append(f"JSON: FWHM plausible ({fwhm:.2f} px)")
            else:
                feedback.append(f"JSON: FWHM implausible ({fwhm})")

        except Exception as e:
            feedback.append(f"JSON: parse error — {e}")
    else:
        feedback.append("JSON: photometric_pipeline.json missing")

    # ── Final verdict ────────────────────────────────────────────────
    passed = score >= 60

    return {
        "passed": passed,
        "decided": True,
        "score": score,
        "feedback": f"Total: {score}/100\n" + "\n".join(feedback),
    }
