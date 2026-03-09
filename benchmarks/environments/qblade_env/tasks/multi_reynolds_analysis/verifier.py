#!/usr/bin/env python3
"""Verifier for multi_reynolds_analysis task.

Scoring (100 points):
- Re=200k polar file exists with valid data: 25 points
- Re=500k polar file exists with valid data: 25 points
- Re=1M polar file exists with valid data: 25 points
- At least 2 polars have sufficient data (>=10 points): 15 points
- At least 2 polars cover negative AoA range: 10 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def _check_polar(result, key, label):
    """Check a single polar file and return (points, data_ok, neg_aoa_ok, feedback)."""
    try:
        polar = result.get(key, {})
        if polar.get('exists') and polar.get('has_data'):
            dp = polar.get('data_points', 0)
            neg = polar.get('has_negative_aoa', False)
            return 25, dp >= 10, neg, f"{label}: {dp} data points"
        elif polar.get('exists'):
            return 10, False, False, f"{label}: file exists but lacks valid data"
        else:
            return 0, False, False, f"{label}: file not found"
    except Exception as e:
        return 0, False, False, f"{label} check error: {e}"


def verify_multi_reynolds_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        subscores = {}
        polars_with_data = 0
        polars_with_neg_aoa = 0

        # Criterion 1: Re=200k polar (25 pts)
        pts, data_ok, neg_ok, fb = _check_polar(result, 'polar_re200k', 'Re=200k')
        score += pts
        feedback_parts.append(fb)
        if pts == 25:
            subscores['polar_re200k'] = True
        if data_ok:
            polars_with_data += 1
        if neg_ok:
            polars_with_neg_aoa += 1

        # Criterion 2: Re=500k polar (25 pts)
        pts, data_ok, neg_ok, fb = _check_polar(result, 'polar_re500k', 'Re=500k')
        score += pts
        feedback_parts.append(fb)
        if pts == 25:
            subscores['polar_re500k'] = True
        if data_ok:
            polars_with_data += 1
        if neg_ok:
            polars_with_neg_aoa += 1

        # Criterion 3: Re=1M polar (25 pts)
        pts, data_ok, neg_ok, fb = _check_polar(result, 'polar_re1m', 'Re=1M')
        score += pts
        feedback_parts.append(fb)
        if pts == 25:
            subscores['polar_re1m'] = True
        if data_ok:
            polars_with_data += 1
        if neg_ok:
            polars_with_neg_aoa += 1

        # Criterion 4: Data density across polars (15 pts)
        try:
            if polars_with_data >= 3:
                score += 15
                subscores['sufficient_data'] = True
                feedback_parts.append("All 3 polars have >= 10 data points")
            elif polars_with_data >= 2:
                score += 10
                feedback_parts.append(f"{polars_with_data}/3 polars have >= 10 data points")
            elif polars_with_data >= 1:
                score += 5
                feedback_parts.append(f"Only {polars_with_data}/3 polars have >= 10 data points")
        except Exception as e:
            feedback_parts.append(f"Data density check error: {e}")

        # Criterion 5: AoA range coverage (10 pts)
        try:
            if polars_with_neg_aoa >= 2:
                score += 10
                subscores['aoa_coverage'] = True
                feedback_parts.append(f"{polars_with_neg_aoa}/3 polars cover negative AoA")
            elif polars_with_neg_aoa >= 1:
                score += 5
                feedback_parts.append(f"Only {polars_with_neg_aoa}/3 polars cover negative AoA")
        except Exception as e:
            feedback_parts.append(f"AoA check error: {e}")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
