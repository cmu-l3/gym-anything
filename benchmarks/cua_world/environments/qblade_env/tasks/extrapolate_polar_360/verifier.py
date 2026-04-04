#!/usr/bin/env python3
"""Verifier for extrapolate_polar_360 task.

Scoring (100 points):
- Extrapolated polar file exists: 20 points
- File has multi-column aerodynamic data: 15 points
- File has >= 30 data points (real extrapolation, not stub): 15 points
- File contains AoA values beyond +-90 deg (evidence of 360 extrapolation): 25 points
- File references NACA 6412 or has correct airfoil context: 10 points
- Base XFoil polar range is present (data in -10 to 25 deg range): 15 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_extrapolate_polar_360(traj, env_info, task_info):
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

        # Criterion 1: File exists (20 pts)
        try:
            if not result.get('file_exists'):
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "Extrapolated polar file not found at expected path"
                }
            score += 20
            subscores['file_exists'] = True
            feedback_parts.append("Polar file exists")
        except Exception as e:
            feedback_parts.append(f"File check error: {e}")

        # Criterion 2: Has multi-column data (15 pts)
        try:
            if result.get('has_data'):
                score += 15
                subscores['has_data'] = True
                feedback_parts.append(f"Has aerodynamic data ({result.get('data_points', 0)} rows)")
            else:
                feedback_parts.append("File lacks valid multi-column aerodynamic data")
        except Exception as e:
            feedback_parts.append(f"Data check error: {e}")

        # Criterion 3: Sufficient data points (15 pts)
        try:
            data_points = result.get('data_points', 0)
            if data_points >= 30:
                score += 15
                subscores['sufficient_points'] = True
                feedback_parts.append(f"Sufficient data density: {data_points} points")
            elif data_points >= 15:
                score += 8
                feedback_parts.append(f"Moderate data density: {data_points} points")
            elif data_points >= 5:
                score += 3
                feedback_parts.append(f"Low data density: {data_points} points")
        except Exception as e:
            feedback_parts.append(f"Point count error: {e}")

        # Criterion 4: Evidence of 360-degree extrapolation (25 pts)
        # This is the KEY criterion - the file must contain AoA beyond +-90 degrees
        try:
            has_extreme = result.get('has_extreme_aoa', False)
            min_aoa = float(result.get('min_aoa', 0))
            max_aoa = float(result.get('max_aoa', 0))

            if has_extreme and (max_aoa > 90 or min_aoa < -90):
                score += 25
                subscores['360_extrapolation'] = True
                feedback_parts.append(f"360° extrapolation confirmed: AoA range [{min_aoa:.0f}°, {max_aoa:.0f}°]")
            elif has_extreme:
                score += 15
                feedback_parts.append(f"Some extreme AoA values found: [{min_aoa:.0f}°, {max_aoa:.0f}°]")
            elif max_aoa > 30 or min_aoa < -15:
                score += 8
                feedback_parts.append(f"Extended AoA range but not full 360°: [{min_aoa:.0f}°, {max_aoa:.0f}°]")
            else:
                feedback_parts.append(f"No evidence of 360° extrapolation: AoA range [{min_aoa:.0f}°, {max_aoa:.0f}°]")
        except Exception as e:
            feedback_parts.append(f"Extrapolation check error: {e}")

        # Criterion 5: Airfoil reference (10 pts)
        try:
            if result.get('has_6412_ref'):
                score += 10
                subscores['airfoil_ref'] = True
                feedback_parts.append("NACA 6412 reference found in file")
        except Exception as e:
            feedback_parts.append(f"Reference check error: {e}")

        # Criterion 6: Base XFoil range present (15 pts)
        try:
            has_neg = result.get('has_negative_aoa', False)
            min_aoa = float(result.get('min_aoa', 0))
            max_aoa = float(result.get('max_aoa', 0))

            # Base XFoil should cover roughly -10 to 25 range
            if has_neg and min_aoa <= -5 and max_aoa >= 20:
                score += 15
                subscores['base_polar'] = True
                feedback_parts.append("Base XFoil polar range present")
            elif has_neg and max_aoa >= 15:
                score += 8
                feedback_parts.append("Partial base polar range detected")
            elif has_neg:
                score += 4
                feedback_parts.append("Negative AoA present but limited range")
        except Exception as e:
            feedback_parts.append(f"Base polar check error: {e}")

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
