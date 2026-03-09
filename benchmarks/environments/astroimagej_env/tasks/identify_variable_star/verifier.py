#!/usr/bin/env python3
"""
Verifier for Identify Variable Star task.

Uses REAL WASP-12b transit data (186 r-band frames from University of Louisville).
The agent must discover that WASP-12 is the variable star through multi-aperture
differential photometry — the transit depth is only ~1.4%.

Scoring (100 points total):
  Criterion 1: Measurement table exists with multi-star photometry data (25 pts)
  Criterion 2: Variable star correctly identified as WASP-12 / T1 (25 pts)
  Criterion 3: Transit depth approximately correct (~1.4%) (20 pts)
  Criterion 4: Transit timing identified (frame numbers or JD) (15 pts)
  Criterion 5: Report file created with required content (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)


def verify_identify_variable_star(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_depth_pct = metadata.get('expected_transit_depth_percent', 1.4)
    depth_tolerance_pct = metadata.get('expected_transit_depth_tolerance_percent', 0.5)
    min_comparison = metadata.get('minimum_comparison_stars', 2)
    num_images = metadata.get('num_images', 186)

    score = 0
    feedback = []
    details = {}

    # ================================================================
    # Load result file from container
    # ================================================================
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # ================================================================
    # Criterion 1: Measurement table with multi-star data (25 pts)
    #
    # For 186 real FITS frames, we expect ~100+ data rows if the agent
    # ran photometry on a significant portion of the sequence, and
    # at least 3 stars (target + 2 comparison).
    # ================================================================
    try:
        meas_found = result.get('measurement_file_found', False)
        num_rows = result.get('num_data_rows', 0)
        num_stars = result.get('num_stars_measured', 0)
        num_comp = result.get('num_comparison_stars', 0)
        has_time = result.get('has_time_column', False)
        has_flux = result.get('has_flux_column', False)

        if meas_found and num_rows >= 100 and num_stars >= 3:
            score += 25
            feedback.append(f"Measurements: {num_rows} rows, {num_stars} stars ({num_comp} comparison)")
        elif meas_found and num_rows >= 50 and num_stars >= 2:
            score += 18
            feedback.append(f"Partial measurements: {num_rows} rows, {num_stars} stars")
        elif meas_found and num_rows >= 20:
            score += 12
            feedback.append(f"Sparse measurements: {num_rows} rows")
        elif meas_found and num_rows >= 1:
            score += 5
            feedback.append(f"Minimal measurements: {num_rows} rows")
        else:
            feedback.append("No measurement file found")

        details['num_data_rows'] = num_rows
        details['num_stars_measured'] = num_stars
        details['num_comparison_stars'] = num_comp

    except Exception as e:
        feedback.append(f"Measurement check error: {e}")

    # ================================================================
    # Criterion 2: Variable star correctly identified (25 pts)
    #
    # The agent should identify WASP-12 as the variable star. Accept:
    # - Name match: "WASP-12" mentioned as the variable
    # - Aperture label: "T1" (target aperture in AstroImageJ)
    # - Star #1 / "target star" / "star 1"
    # - Pixel coordinates near the WASP-12 position
    # ================================================================
    try:
        var_identified = result.get('variable_star_identified', False)
        var_label = result.get('variable_star_label', '')
        name_match = result.get('variable_star_name_match', False)
        report_content = result.get('report_content', '')

        if name_match:
            # Best case: explicitly names WASP-12
            score += 25
            feedback.append(f"Variable star correctly identified as WASP-12")
        elif var_identified and var_label:
            # Good: identified by T1 or target aperture
            score += 22
            feedback.append(f"Variable star identified as '{var_label}'")
        elif var_identified:
            score += 18
            feedback.append("Variable star identified (label unclear)")
        else:
            # Check report text for any indirect evidence
            report_lower = report_content.lower() if report_content else ''
            if any(kw in report_lower for kw in ['wasp', 't1', 'target', 'variable', 'transit']):
                score += 10
                feedback.append("Variable star possibly identified (keyword in report)")
            else:
                feedback.append("Variable star not identified")

        details['variable_star_identified'] = var_identified
        details['variable_star_label'] = var_label
        details['name_match'] = name_match

    except Exception as e:
        feedback.append(f"Variable star identification error: {e}")

    # ================================================================
    # Criterion 3: Transit depth approximately correct (20 pts)
    #
    # Expected: ~1.4% (WASP-12b transit depth in r-band)
    # Accept range: 0.9% to 1.9% for full credit (tolerance 0.5%)
    # Wider range: 0.5% to 3.0% for partial credit
    # Also accept magnitude equivalent (~0.015 mag) or fraction (~0.014)
    # ================================================================
    try:
        depth_str = result.get('reported_depth_percent', '')
        depth_correct = False

        if depth_str:
            try:
                depth_val = float(depth_str)

                # depth_val is already in percent (export script normalizes)
                error_pct = abs(depth_val - expected_depth_pct)

                if error_pct <= depth_tolerance_pct:
                    score += 20
                    feedback.append(f"Transit depth correct: {depth_val:.2f}% (expected ~{expected_depth_pct}%)")
                    depth_correct = True
                elif error_pct <= depth_tolerance_pct * 2:
                    score += 12
                    feedback.append(f"Transit depth approximate: {depth_val:.2f}% (expected ~{expected_depth_pct}%)")
                    depth_correct = True
                elif error_pct <= depth_tolerance_pct * 3:
                    score += 6
                    feedback.append(f"Transit depth rough: {depth_val:.2f}%")
                else:
                    score += 3
                    feedback.append(f"Transit depth reported but inaccurate: {depth_val:.2f}%")

            except (ValueError, TypeError):
                # Try to find depth info in report text
                report_content = result.get('report_content', '')
                if report_content and any(kw in report_content.lower() for kw in ['depth', 'dip', 'decrease', 'dimming']):
                    score += 3
                    feedback.append("Depth mentioned in report but not parseable")
                else:
                    feedback.append("Transit depth could not be parsed")
        else:
            feedback.append("Transit depth not reported")

        details['depth_correct'] = depth_correct

    except Exception as e:
        feedback.append(f"Depth check error: {e}")

    # ================================================================
    # Criterion 4: Transit timing identified (15 pts)
    #
    # The agent should report frame numbers or JD values around the
    # transit minimum. For WASP-12b real data, the transit occurs
    # in the middle portion of the observation sequence.
    # ================================================================
    try:
        timing_frames = result.get('reported_timing_frames', [])
        timing_jd_str = result.get('reported_timing_jd', '')
        timing_found = False

        if timing_frames and len(timing_frames) > 0:
            # Agent reported frame numbers
            # Any reasonable frame numbers within the 186-frame sequence
            valid_frames = [f for f in timing_frames if 1 <= f <= num_images]
            if valid_frames:
                score += 15
                feedback.append(f"Transit timing reported: frames {valid_frames}")
                timing_found = True
            else:
                score += 5
                feedback.append(f"Timing frames reported but outside valid range: {timing_frames}")

        elif timing_jd_str:
            try:
                timing_jd = float(timing_jd_str)
                # Any reasonable JD (Julian Date around 2450000-2470000 range)
                if 2450000 < timing_jd < 2470000:
                    score += 15
                    feedback.append(f"Transit timing reported: JD {timing_jd:.4f}")
                    timing_found = True
                else:
                    score += 5
                    feedback.append(f"JD reported but unusual: {timing_jd}")
            except (ValueError, TypeError):
                feedback.append("Timing JD could not be parsed")
        else:
            # Check report text for any timing mention
            report_content = result.get('report_content', '')
            if report_content:
                report_lower = report_content.lower()
                if any(kw in report_lower for kw in ['frame', 'minimum', 'jd', 'bjd', 'mid-transit']):
                    score += 5
                    feedback.append("Timing possibly mentioned in report text")
                else:
                    feedback.append("Transit timing not reported")
            else:
                feedback.append("Transit timing not reported")

        details['timing_found'] = timing_found

    except Exception as e:
        feedback.append(f"Timing check error: {e}")

    # ================================================================
    # Criterion 5: Report file with required content (15 pts)
    #
    # Report should contain:
    # - Which star is variable (identification)
    # - Depth of brightness dip
    # - Timing of minimum brightness
    # ================================================================
    try:
        report_found = result.get('report_file_found', False)
        report_content = result.get('report_content', '')

        if report_found and report_content:
            report_len = len(report_content)
            content_lower = report_content.lower()

            # Count how many required elements are present
            elements = 0
            if any(kw in content_lower for kw in ['wasp', 't1', 'variable', 'target']):
                elements += 1  # star identification
            if any(kw in content_lower for kw in ['depth', 'dip', 'decrease', 'dimming', '%', 'percent']):
                elements += 1  # depth
            if any(kw in content_lower for kw in ['frame', 'time', 'jd', 'minimum', 'mid']):
                elements += 1  # timing

            if report_len > 100 and elements >= 3:
                score += 15
                feedback.append(f"Complete report ({report_len} chars, all 3 elements)")
            elif report_len > 50 and elements >= 2:
                score += 10
                feedback.append(f"Good report ({report_len} chars, {elements}/3 elements)")
            elif report_len > 20 and elements >= 1:
                score += 6
                feedback.append(f"Partial report ({report_len} chars, {elements}/3 elements)")
            elif report_found:
                score += 3
                feedback.append(f"Report exists but minimal ({report_len} chars)")
        elif report_found:
            score += 2
            feedback.append("Report file exists but empty")
        else:
            feedback.append("No report file found")

    except Exception as e:
        feedback.append(f"Report check error: {e}")

    # ================================================================
    # Pass criteria
    # ================================================================
    passed = score >= 60

    if passed and score >= 85:
        feedback.append("Excellent variable star identification")
    elif passed:
        feedback.append("Variable star identification successful")
    else:
        feedback.append(f"FAIL: Score {score}/100 below threshold (60)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": details,
    }
