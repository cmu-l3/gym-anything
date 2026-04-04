#!/usr/bin/env python3
"""Verifier for airfoil_polar_comparison task.

Scoring (100 points):
- NACA 0015 polar file exists with valid data: 25 points
- NACA 2412 polar file exists with valid data: 25 points
- NACA 4412 polar file exists with valid data: 25 points
- At least 2 polars have sufficient data points (>=10): 15 points
- At least 2 polars cover negative AoA range: 10 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_airfoil_polar_comparison(traj, env_info, task_info):
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

        # Check baseline: verify new work was done
        initial_count = result.get('initial_polar_count', 0)
        current_count = result.get('current_polar_count', 0)
        if current_count <= initial_count:
            # No new polar files created at expected location;
            # still check individual files in case of alternate naming
            feedback_parts.append("No new polar files detected at expected paths")

        polars_with_data = 0
        polars_with_neg_aoa = 0

        # Criterion 1: NACA 0015 polar (25 pts)
        try:
            p0015 = result.get('polar_naca0015', {})
            if p0015.get('exists') and p0015.get('has_data'):
                score += 25
                subscores['polar_naca0015'] = True
                feedback_parts.append(f"NACA 0015 polar: {p0015.get('data_points', 0)} data points")
                if p0015.get('data_points', 0) >= 10:
                    polars_with_data += 1
                if p0015.get('has_negative_aoa'):
                    polars_with_neg_aoa += 1
            elif p0015.get('exists'):
                score += 10
                feedback_parts.append("NACA 0015 polar file exists but lacks valid data")
            else:
                feedback_parts.append("NACA 0015 polar file not found")
        except Exception as e:
            feedback_parts.append(f"NACA 0015 check error: {e}")

        # Criterion 2: NACA 2412 polar (25 pts)
        try:
            p2412 = result.get('polar_naca2412', {})
            if p2412.get('exists') and p2412.get('has_data'):
                score += 25
                subscores['polar_naca2412'] = True
                feedback_parts.append(f"NACA 2412 polar: {p2412.get('data_points', 0)} data points")
                if p2412.get('data_points', 0) >= 10:
                    polars_with_data += 1
                if p2412.get('has_negative_aoa'):
                    polars_with_neg_aoa += 1
            elif p2412.get('exists'):
                score += 10
                feedback_parts.append("NACA 2412 polar file exists but lacks valid data")
            else:
                feedback_parts.append("NACA 2412 polar file not found")
        except Exception as e:
            feedback_parts.append(f"NACA 2412 check error: {e}")

        # Criterion 3: NACA 4412 polar (25 pts)
        try:
            p4412 = result.get('polar_naca4412', {})
            if p4412.get('exists') and p4412.get('has_data'):
                score += 25
                subscores['polar_naca4412'] = True
                feedback_parts.append(f"NACA 4412 polar: {p4412.get('data_points', 0)} data points")
                if p4412.get('data_points', 0) >= 10:
                    polars_with_data += 1
                if p4412.get('has_negative_aoa'):
                    polars_with_neg_aoa += 1
            elif p4412.get('exists'):
                score += 10
                feedback_parts.append("NACA 4412 polar file exists but lacks valid data")
            else:
                feedback_parts.append("NACA 4412 polar file not found")
        except Exception as e:
            feedback_parts.append(f"NACA 4412 check error: {e}")

        # Criterion 4: Sufficient data points across polars (15 pts)
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
            feedback_parts.append(f"Data point check error: {e}")

        # Criterion 5: AoA range coverage (10 pts)
        try:
            if polars_with_neg_aoa >= 2:
                score += 10
                subscores['aoa_range'] = True
                feedback_parts.append(f"{polars_with_neg_aoa}/3 polars cover negative AoA")
            elif polars_with_neg_aoa >= 1:
                score += 5
                feedback_parts.append(f"Only {polars_with_neg_aoa}/3 polars cover negative AoA")
        except Exception as e:
            feedback_parts.append(f"AoA range check error: {e}")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
