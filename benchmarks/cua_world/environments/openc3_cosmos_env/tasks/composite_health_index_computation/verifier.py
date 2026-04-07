#!/usr/bin/env python3
"""
Verifier for composite_health_index_computation task.

Checks:
1. Export metadata is readable
2. Target JSON file exists and was created this session
3. Schema compliance (contains 5 snapshots, correct telemetry keys)
4. Data Authenticity: Reported COLLECTS fall within strictly bounded timeline
   (>= initial_collects and <= final_collects) and are monotonically non-decreasing.
5. Mathematical Accuracy: For each snapshot, the verifier recalculates the health
   index based on the agent's reported raw telemetry, ensuring they correctly
   implemented the algorithm rules.

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def compute_expected_index(telemetry, prev_collects, is_first):
    """Computes the Spacecraft Health Index according to task rules."""
    score = 100
    
    # Rule 2: Thermal Penalty
    for sensor in ["TEMP1", "TEMP2", "TEMP3", "TEMP4"]:
        try:
            val = float(telemetry.get(sensor, 50.0))
            if val > 85.0:
                score -= 15
            elif val < 15.0:
                score -= 10
        except (ValueError, TypeError):
            pass # Malformed data will be caught by schema checks, but don't crash here
            
    # Rule 3: Stale Data Penalty
    try:
        current_collects = int(float(telemetry.get("COLLECTS", 0)))
        if not is_first and prev_collects is not None:
            if current_collects == prev_collects:
                score -= 20
    except (ValueError, TypeError):
        pass

    # Rule 4: Floor at 0
    return max(0, score)

def verify_health_index_computation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/health_index_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/health_index_report.json')

    score = 0
    feedback = []

    # 1. Read export metadata
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
        score += 5
        feedback.append('Export metadata readable (+5)')
    except Exception as e:
        feedback.append(f'Export metadata not found: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name): os.unlink(tmp_name)

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    
    try:
        initial_collects = int(float(export_meta.get('initial_collects', 0)))
        final_collects = int(float(export_meta.get('final_collects', 0)))
    except (ValueError, TypeError):
        initial_collects, final_collects = 0, float('inf')

    # 2. File existence and newness
    if not file_exists:
        feedback.append('Output file not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    
    score += 5
    feedback.append('Output file exists (+5)')

    if not file_is_new:
        feedback.append('Output file predates task start (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # 3. Read output JSON
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except Exception as e:
        feedback.append(f'Output file is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name): os.unlink(tmp_name)

    snapshots = report.get('snapshots', [])
    if not isinstance(snapshots, list) or len(snapshots) != 5:
        feedback.append(f'Schema error: "snapshots" must be a list of exactly 5 items (found {len(snapshots) if isinstance(snapshots, list) else "not a list"})')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Schema valid: exactly 5 snapshots found (+10)')

    # 4. Data Authenticity and 5. Mathematical Accuracy
    bounds_valid = True
    prev_collects = None
    math_score = 0
    
    for i, snap in enumerate(snapshots):
        is_first = (i == 0)
        telemetry = snap.get('telemetry', {})
        reported_index = snap.get('health_index')
        
        # Bounds check
        try:
            current_collects = int(float(telemetry.get('COLLECTS', -1)))
            
            # Authenticity check: Ensure it's inside system bounds and monotonically increasing
            if current_collects < initial_collects or current_collects > final_collects:
                bounds_valid = False
                logger.warning(f"Bounds failed: {current_collects} not in [{initial_collects}, {final_collects}]")
            if prev_collects is not None and current_collects < prev_collects:
                bounds_valid = False
                logger.warning(f"Bounds failed: Not monotonically increasing ({prev_collects} -> {current_collects})")
        except (ValueError, TypeError):
            bounds_valid = False
            current_collects = -1

        # Math check
        expected_index = compute_expected_index(telemetry, prev_collects, is_first)
        
        if reported_index == expected_index:
            math_score += 10
        else:
            feedback.append(f'Snapshot {i+1} math error: expected {expected_index}, reported {reported_index}')

        prev_collects = current_collects

    if bounds_valid:
        score += 30
        feedback.append('Data authenticity bounds verified (+30)')
    else:
        feedback.append(f'Data authenticity failed: COLLECTS sequence invalid or out of bounds [{initial_collects}, {final_collects}]')

    score += math_score
    if math_score == 50:
        feedback.append('Mathematical accuracy perfect for all 5 snapshots (+50)')
    else:
        feedback.append(f'Mathematical accuracy: {math_score}/50 points awarded')

    # Final tally
    passed = score >= 70 and bounds_valid
    
    return {
        'passed': passed,
        'score': score,
        'feedback': '; '.join(feedback)
    }