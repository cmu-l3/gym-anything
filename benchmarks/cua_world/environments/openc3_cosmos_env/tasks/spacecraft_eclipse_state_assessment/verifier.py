#!/usr/bin/env python3
"""
Verifier for spacecraft_eclipse_state_assessment task.

A mission operations analyst must write a Python script in COSMOS Script Runner
to sample the INST ADCS position vector, compute the radial distance (rho),
evaluate the cylindrical shadow model to determine if the satellite is in
sunlight or eclipse, and write a structured JSON report.

Scoring breakdown (100 pts total, pass threshold = 60):
  15pts  File exists, is new (created during session), and export metadata readable
  15pts  JSON Schema compliant (has all keys, samples array has >= 5 entries)
  20pts  Data Realism Check: ALL samples have a position vector magnitude between
         6000 and 9000 km (verifying real LEO telemetry, preventing trivial [0,0,0])
  25pts  Mathematical Accuracy: ALL samples have correctly calculated 'rho'
         (sqrt(y^2 + z^2)) within a +/- 0.1 tolerance.
  25pts  Logical Accuracy: ALL samples have 'state' correctly mapped to 'IN_ECLIPSE'
         or 'IN_SUNLIGHT' based on (x < 0 and rho < 6371.0).
 ---
 100pts total

Do-nothing invariant: passed=False (score <= 15)
"""

import json
import math
import os
import tempfile


def verify_spacecraft_eclipse_state_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/eclipse_assessment_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/eclipse_report.json')
    earth_radius = float(meta.get('earth_radius_km', 6371.0))

    score = 0
    feedback = []

    # ── Step 1: Read export metadata & File Checks ──────────────────────────
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        feedback.append(f'Export metadata not found: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)

    if not file_exists:
        feedback.append('Report not found on Desktop')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}

    if not file_is_new:
        feedback.append('Report predates task start (no content credit)')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}

    score += 15
    feedback.append('File exists and was created this session (+15)')

    # ── Step 2: Parse and Schema Validation ──────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f'Report is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f'Could not copy report: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    required_keys = {'analyst', 'target', 'samples_collected', 'shadow_model', 'samples', 'current_mode'}
    missing_keys = required_keys - set(report.keys())
    if missing_keys:
        feedback.append(f'Missing required top-level keys: {sorted(missing_keys)}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    samples = report.get('samples', [])
    if not isinstance(samples, list) or len(samples) < 5:
        feedback.append(f'Report has {len(samples) if isinstance(samples, list) else "invalid"} samples, need >= 5')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 15
    feedback.append('JSON Schema valid with >= 5 samples (+15)')

    # ── Step 3: Analytical Checks across Samples ─────────────────────────────
    realism_pass = True
    math_pass = True
    logic_pass = True

    for i, sample in enumerate(samples[:5]):  # check first 5
        try:
            x = float(sample.get('posx'))
            y = float(sample.get('posy'))
            z = float(sample.get('posz'))
            reported_rho = float(sample.get('rho'))
            reported_state = str(sample.get('state'))
        except (TypeError, ValueError) as e:
            feedback.append(f'Sample {i} has missing/invalid data types')
            realism_pass = math_pass = logic_pass = False
            break

        # 1. Realism Check (Magnitude between 6000 and 9000 km)
        magnitude = math.sqrt(x**2 + y**2 + z**2)
        if not (6000.0 <= magnitude <= 9000.0):
            feedback.append(f'Sample {i} failed realism check: mag {magnitude:.1f} not in [6000, 9000]')
            realism_pass = False

        # 2. Math Check (rho = sqrt(y^2 + z^2))
        expected_rho = math.sqrt(y**2 + z**2)
        if abs(reported_rho - expected_rho) > 0.1:
            feedback.append(f'Sample {i} failed math check: rho was {reported_rho:.3f}, expected {expected_rho:.3f}')
            math_pass = False

        # 3. Logic Check (Cylindrical Shadow Model)
        expected_state = "IN_ECLIPSE" if (x < 0 and expected_rho < earth_radius) else "IN_SUNLIGHT"
        if reported_state != expected_state:
            feedback.append(f'Sample {i} failed logic check: state was {reported_state}, expected {expected_state}')
            logic_pass = False

    if realism_pass:
        score += 20
        feedback.append('Data Realism passed (+20)')
    if math_pass:
        score += 25
        feedback.append('Mathematical Accuracy passed (+25)')
    if logic_pass:
        score += 25
        feedback.append('Logical Accuracy passed (+25)')

    passed = (score >= 60) and realism_pass

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }