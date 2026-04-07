#!/usr/bin/env python3
"""
Verifier for Multi-Band Aperture Photometry and Color-Magnitude Diagram task.

Scoring (100 points total):
  Criterion 1:  V-band measurements with sufficient stars    (10 pts)
  Criterion 2:  B-band measurements with sufficient stars    (10 pts)
  Criterion 3:  Calibrated photometry CSV with columns       (10 pts)
  Criterion 4:  B-V color values in reasonable range         (8 pts)
  Criterion 5:  Zero-point values computed and reasonable    (8 pts)
  Criterion 6:  CMD plot created                             (7 pts)
  Criterion 7:  Brightest star V magnitude reasonable        (10 pts)
  Criterion 8:  Summary report with required numeric values  (7 pts)
  Criterion 9:  VLM process verification                    (15 pts)
  Criterion 10: VLM content quality                         (10 pts)
  Criterion 11: Cross-validation                             (5 pts)

Pass threshold: 60 points AND at least one measurement file found.

This task is designed as a long-horizon pipeline that requires:
- Multi-band aperture photometry with consistent settings
- Cross-matching stars between bands
- Photometric zero-point calibration against a published catalog
- Color-magnitude diagram construction
- Brightest star magnitude measurement (V ≈ 15.68 from catalog)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# ----------------------------------------------------------------
# VLM Prompts
# ----------------------------------------------------------------
VLM_PROCESS_PROMPT = """You are evaluating an AI agent's performance on a multi-band \
astronomical photometry task in AstroImageJ.

The agent was asked to:
1. Open V-band and B-band FITS images of the Messier 12 globular cluster
2. Perform aperture photometry on 20+ stars in BOTH images
3. Write a Python script to cross-match, calibrate, and compute colors
4. Create a color-magnitude diagram (CMD) scatter plot
5. Write a summary report

Examine these trajectory screenshots and assess workflow progression:
- Did the agent open FITS images in AstroImageJ?
- Did the agent interact with photometry tools (aperture placement, measurements)?
- Did the agent work with BOTH V-band AND B-band images (two separate images)?
- Did the agent open a terminal and write/run a Python script?
- Did the agent create or view a scatter plot (the CMD)?
- Did the agent write a text report?

Rate from 0-100:
  0-15: Agent barely started or got stuck on menus
 15-30: Agent opened one image but did not complete photometry
 30-45: Agent did photometry on one band only
 45-60: Agent did photometry on both bands
 60-75: Agent did photometry on both bands and started analysis
 75-90: Agent completed analysis and created CMD
 90-100: Agent completed full pipeline including report

Respond with ONLY a JSON object: {"score": <0-100>, "reasoning": "<brief explanation>"}"""

VLM_CONTENT_PROMPT = """Examine this final screenshot from an astronomical photometry task.

The agent should have produced:
- Measurement tables from aperture photometry
- A color-magnitude diagram (CMD) — a scatter plot with B-V color on x-axis \
and V magnitude on y-axis (inverted, brighter at top)
- A calibrated photometry CSV file
- A summary report

Assess what is visible:
- Is there evidence of completed photometry (measurement tables, results windows)?
- Is there a scatter plot that could be a CMD?
- Are there any error dialogs, crashes, or unrelated windows?
- Does the work look like genuine astronomical analysis?

Rate content quality from 0-100:
  0-25: Errors, crashes, or no relevant work visible
 25-50: Some astronomical work but no CMD or calibrated results
 50-75: Measurement tables or partial analysis visible
 75-100: CMD plot or calibrated results clearly visible

Respond with ONLY a JSON object: \
{"score": <0-100>, "has_cmd": <true/false>, "reasoning": "<brief explanation>"}"""


def verify_multiband_cmd_photometry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []
    details = {}

    # ------------------------------------------------------------------
    # Load result JSON from VM
    # ------------------------------------------------------------------
    result = None
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # ------------------------------------------------------------------
    # Load ground truth
    # ------------------------------------------------------------------
    gt = result.get('ground_truth', {})
    if not gt:
        try:
            temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            copy_from_env("/tmp/cmd_ground_truth.json", temp_gt.name)
            with open(temp_gt.name, 'r') as f:
                gt = json.load(f)
        except Exception:
            pass
        finally:
            if os.path.exists(temp_gt.name):
                os.unlink(temp_gt.name)

    metadata = task_info.get('metadata', {})
    min_stars = metadata.get('minimum_stars_measured', 20)

    # ==================================================================
    # Criterion 1: V-band measurements (10 pts)
    # ==================================================================
    try:
        v_found = result.get('v_band_measurement_found', False)
        v_stars = result.get('v_band_num_stars', 0)
        if v_found and v_stars >= min_stars:
            score += 10
            feedback.append(f"V-band: {v_stars} stars measured")
        elif v_found and v_stars >= 10:
            score += 7
            feedback.append(f"V-band: {v_stars} stars (below {min_stars} target)")
        elif v_found and v_stars >= 1:
            score += 3
            feedback.append(f"V-band: only {v_stars} stars")
        elif v_found:
            score += 1
            feedback.append("V-band measurement file found but empty")
        else:
            feedback.append("V-band measurement file not found")
        details['v_band_stars'] = v_stars
    except Exception as e:
        feedback.append(f"V-band check error: {e}")

    # ==================================================================
    # Criterion 2: B-band measurements (10 pts)
    # ==================================================================
    try:
        b_found = result.get('b_band_measurement_found', False)
        b_stars = result.get('b_band_num_stars', 0)
        if b_found and b_stars >= min_stars:
            score += 10
            feedback.append(f"B-band: {b_stars} stars measured")
        elif b_found and b_stars >= 10:
            score += 7
            feedback.append(f"B-band: {b_stars} stars (below {min_stars} target)")
        elif b_found and b_stars >= 1:
            score += 3
            feedback.append(f"B-band: only {b_stars} stars")
        elif b_found:
            score += 1
            feedback.append("B-band measurement file found but empty")
        else:
            feedback.append("B-band measurement file not found")
        details['b_band_stars'] = b_stars
    except Exception as e:
        feedback.append(f"B-band check error: {e}")

    # ==================================================================
    # Criterion 3: Calibrated photometry CSV (10 pts)
    # ==================================================================
    try:
        cal_found = result.get('calibrated_csv_found', False)
        cal_stars = result.get('calibrated_num_stars', 0)
        cal_cols = result.get('calibrated_columns', [])

        if cal_found and cal_stars >= 10:
            col_str = ','.join(c.lower() for c in cal_cols)
            has_v = any(k in col_str for k in ['v_inst', 'v_cal', 'v_mag', 'vmag'])
            has_b = any(k in col_str for k in ['b_inst', 'b_cal', 'b_mag', 'bmag'])
            has_bv = any(k in col_str for k in ['bv', 'b-v', 'b_v', 'color'])
            has_coords = any(k in col_str for k in ['x_pixel', 'x_pix', 'xpix'])
            col_score = sum([has_v, has_b, has_bv, has_coords])

            if col_score >= 3:
                score += 10
                feedback.append(
                    f"Calibrated CSV: {cal_stars} stars, "
                    f"{col_score}/4 required column groups")
            elif col_score >= 2:
                score += 7
                feedback.append(
                    f"Calibrated CSV: {cal_stars} stars, "
                    f"missing some columns")
            else:
                score += 3
                feedback.append(
                    f"Calibrated CSV exists but columns unclear: "
                    f"{cal_cols[:6]}")
        elif cal_found:
            score += 2
            feedback.append(f"Calibrated CSV found but only {cal_stars} stars")
        else:
            feedback.append("Calibrated photometry CSV not found")
        details['calibrated_stars'] = cal_stars
    except Exception as e:
        feedback.append(f"Calibrated CSV check error: {e}")

    # ==================================================================
    # Criterion 4: B-V color values reasonable (8 pts)
    # ==================================================================
    try:
        bv_values = result.get('bv_values', [])
        if bv_values and len(bv_values) >= 5:
            bv_min = min(bv_values)
            bv_max = max(bv_values)
            bv_range = bv_max - bv_min

            # For a globular cluster, B-V typically spans ~0.0 to ~1.5
            reasonable_range = (-1.0 <= bv_min <= 1.0) and (0.3 <= bv_max <= 3.0)
            good_spread = bv_range >= 0.3

            if reasonable_range and good_spread:
                score += 8
                feedback.append(
                    f"B-V range [{bv_min:.2f}, {bv_max:.2f}] — "
                    f"reasonable for globular cluster")
            elif reasonable_range:
                score += 5
                feedback.append(
                    f"B-V range [{bv_min:.2f}, {bv_max:.2f}] — narrow spread")
            else:
                score += 2
                feedback.append(
                    f"B-V range [{bv_min:.2f}, {bv_max:.2f}] — "
                    f"outside expected range")
            details['bv_range'] = [bv_min, bv_max]
        elif bv_values:
            score += 2
            feedback.append(f"Only {len(bv_values)} B-V values — insufficient")
        else:
            feedback.append("No B-V color values found")
    except Exception as e:
        feedback.append(f"B-V check error: {e}")

    # ==================================================================
    # Criterion 5: Zero-point values (8 pts)
    # ==================================================================
    try:
        zp_v_found = result.get('zp_v_found', False)
        zp_b_found = result.get('zp_b_found', False)
        zp_v = result.get('zp_v_value')
        zp_b = result.get('zp_b_value')

        zp_score = 0

        if zp_v_found and zp_v is not None:
            # Reasonable range for instrumental-to-standard zero-point
            if -35 < zp_v < 5:
                zp_score += 4
                feedback.append(f"ZP_V = {zp_v:.2f}")
            else:
                zp_score += 2
                feedback.append(f"ZP_V = {zp_v:.2f} (unusual value)")
        else:
            feedback.append("V-band zero-point not found in report")

        if zp_b_found and zp_b is not None:
            if -35 < zp_b < 5:
                zp_score += 4
                feedback.append(f"ZP_B = {zp_b:.2f}")
            else:
                zp_score += 2
                feedback.append(f"ZP_B = {zp_b:.2f} (unusual value)")
        else:
            feedback.append("B-band zero-point not found in report")

        score += zp_score
        details['zp_v'] = zp_v
        details['zp_b'] = zp_b
    except Exception as e:
        feedback.append(f"Zero-point check error: {e}")

    # ==================================================================
    # Criterion 6: CMD plot (7 pts)
    # ==================================================================
    try:
        cmd_found = result.get('cmd_plot_found', False)
        cmd_size = result.get('cmd_plot_size_bytes', 0)

        if cmd_found and cmd_size > 10000:
            score += 7
            feedback.append(f"CMD plot created ({cmd_size // 1024} KB)")
        elif cmd_found and cmd_size > 1000:
            score += 4
            feedback.append(f"CMD plot exists but small ({cmd_size} bytes)")
        elif cmd_found:
            score += 2
            feedback.append("CMD plot file exists but may be empty/corrupt")
        else:
            feedback.append("CMD plot not found")
    except Exception as e:
        feedback.append(f"CMD plot check error: {e}")

    # ==================================================================
    # Criterion 7: Brightest star calibrated V magnitude (10 pts)
    # ==================================================================
    expected_bright_v = metadata.get('expected_brightest_v', 15.68)
    bright_v_tol = metadata.get('expected_brightest_v_tolerance', 1.5)
    try:
        v_cal_values = result.get('v_cal_values', [])
        if v_cal_values and len(v_cal_values) >= 5:
            brightest_v = min(v_cal_values)
            diff = abs(brightest_v - expected_bright_v)
            if diff <= bright_v_tol:
                score += 10
                feedback.append(
                    f"Brightest V_cal = {brightest_v:.2f} "
                    f"(expected ~{expected_bright_v:.1f}, diff={diff:.2f})")
            elif diff <= bright_v_tol * 2:
                score += 5
                feedback.append(
                    f"Brightest V_cal = {brightest_v:.2f} "
                    f"(approximate, diff={diff:.2f})")
            elif 5 < brightest_v < 30:
                score += 2
                feedback.append(
                    f"Brightest V_cal = {brightest_v:.2f} "
                    f"(plausible magnitude)")
            else:
                feedback.append(
                    f"Brightest V_cal = {brightest_v:.2f} "
                    f"(unreasonable)")
            details['brightest_v_cal'] = brightest_v
        elif v_cal_values:
            score += 2
            feedback.append(
                f"Only {len(v_cal_values)} V_cal values — insufficient")
        else:
            feedback.append("No calibrated V magnitudes found")
    except Exception as e:
        feedback.append(f"Brightest V check error: {e}")

    # ==================================================================
    # Criterion 8: Summary report with numeric values (7 pts)
    # ==================================================================
    try:
        rpt_found = result.get('report_found', False)
        if rpt_found:
            mentions_zp = result.get('report_mentions_zp', False)
            mentions_bv = result.get('report_mentions_bv', False)
            mentions_bright = result.get('report_mentions_brightest', False)

            rpt_score = 1  # base for having the report
            if mentions_zp:
                rpt_score += 2
            if mentions_bv:
                rpt_score += 2
            if mentions_bright:
                rpt_score += 2
            score += rpt_score

            parts = []
            if mentions_zp:
                parts.append("ZP values")
            if mentions_bv:
                parts.append("B-V range")
            if mentions_bright:
                parts.append("brightest star")
            feedback.append(
                f"Report found, contains: "
                f"{', '.join(parts) if parts else 'minimal content'}")
        else:
            feedback.append("Summary report not found")
    except Exception as e:
        feedback.append(f"Report check error: {e}")

    # ==================================================================
    # VLM Checks (30 pts total)
    # ==================================================================
    vlm_process_score = 0
    vlm_content_score = 0
    vlm_cmd_detected = False

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')

    # Criterion 8: VLM process verification (15 pts)
    if query_vlm and sample_frames:
        try:
            sampled = sample_frames(traj, num_samples=8)
            if sampled:
                vlm_response = query_vlm(
                    images=sampled,
                    prompt=VLM_PROCESS_PROMPT,
                )
                if vlm_response:
                    try:
                        import re
                        resp_text = (vlm_response if isinstance(vlm_response, str)
                                     else str(vlm_response))
                        json_match = re.search(r'\{[^}]+\}', resp_text)
                        if json_match:
                            vlm_result = json.loads(json_match.group())
                            vlm_score_raw = vlm_result.get('score', 0)
                            vlm_process_score = int(
                                15 * min(vlm_score_raw, 100) / 100)
                            feedback.append(
                                f"VLM process: {vlm_score_raw}/100")
                    except (json.JSONDecodeError, ValueError):
                        feedback.append(
                            "VLM process: could not parse response")
        except Exception as e:
            logger.warning(f"VLM process check failed: {e}")

    # Criterion 9: VLM content quality (10 pts)
    if query_vlm and get_final:
        try:
            final = get_final(traj)
            if final:
                vlm_response = query_vlm(
                    images=[final],
                    prompt=VLM_CONTENT_PROMPT,
                )
                if vlm_response:
                    try:
                        import re
                        resp_text = (vlm_response if isinstance(vlm_response, str)
                                     else str(vlm_response))
                        json_match = re.search(r'\{[^}]+\}', resp_text)
                        if json_match:
                            vlm_result = json.loads(json_match.group())
                            vlm_score_raw = vlm_result.get('score', 0)
                            vlm_content_score = int(
                                10 * min(vlm_score_raw, 100) / 100)
                            vlm_cmd_detected = vlm_result.get(
                                'has_cmd', False)
                            feedback.append(
                                f"VLM content: {vlm_score_raw}/100")
                    except (json.JSONDecodeError, ValueError):
                        feedback.append(
                            "VLM content: could not parse response")
        except Exception as e:
            logger.warning(f"VLM content check failed: {e}")

    score += vlm_process_score
    score += vlm_content_score

    # Criterion 10: Cross-validation (5 pts)
    try:
        programmatic_has_cmd = (
            result.get('cmd_plot_found', False)
            and result.get('calibrated_csv_found', False))
        if programmatic_has_cmd and vlm_cmd_detected:
            score += 5
            feedback.append(
                "Cross-validation: programmatic + VLM agree on CMD")
        elif programmatic_has_cmd or vlm_cmd_detected:
            score += 2
            feedback.append("Cross-validation: partial agreement")
        else:
            feedback.append(
                "Cross-validation: neither confirmed CMD completion")
    except Exception as e:
        feedback.append(f"Cross-validation error: {e}")

    # ==================================================================
    # Pass criteria
    # ==================================================================
    any_measurement = (result.get('v_band_measurement_found', False)
                       or result.get('b_band_measurement_found', False))
    passed = score >= 60 and any_measurement

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": details,
    }
