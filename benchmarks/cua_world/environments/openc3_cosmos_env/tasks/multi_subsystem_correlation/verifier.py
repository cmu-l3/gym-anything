#!/usr/bin/env python3
"""
Verifier for multi_subsystem_correlation task.

A mission analyst must collect synchronized telemetry from INST HEALTH_STATUS
and INST ADCS, compute the Pearson correlation matrix, and write a structured 
JSON report to /home/ga/Desktop/correlation_report.json.

Scoring breakdown (100 pts total, pass threshold = 60):
  10pts  Export metadata JSON readable
  10pts  Output file exists on Desktop
  10pts  Output file created after task start [hard gate — no content credit if old]
  10pts  Valid JSON with all 4 required top-level keys
  15pts  sample_count >= 20
   5pts  items array contains exactly the 6 expected telemetry items
  20pts  correlation_matrix is 6x6 with all values in [-1, 1] (or NaN/None tolerated)
  10pts  correlation_matrix diagonal is approx 1.0 and matrix is symmetric
  10pts  notable_correlations has >= 1 valid cross-subsystem entry
 ---
 100pts total

Do-nothing invariant: passed=False (score <= 10)
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multi_subsystem_correlation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/multi_subsystem_correlation_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/correlation_report.json')
    min_samples = meta.get('min_samples', 20)
    health_items = {i.lower() for i in meta.get('health_status_items', ['temp1', 'temp2', 'temp3', 'temp4'])}
    adcs_items = {i.lower() for i in meta.get('adcs_items', ['q1', 'q2'])}

    score = 0
    feedback = []

    # ── Step 1: Read export metadata ────────────────────────────────────────
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
        score += 10
        feedback.append('Export metadata readable (+10)')
    except Exception as e:
        feedback.append(f'Export metadata not found: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        try:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)
        except Exception:
            pass

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)

    if not file_exists:
        feedback.append('Correlation report not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Correlation report exists on Desktop (+10)')

    # Hard gate: file must have been created during the session
    if not file_is_new:
        feedback.append('Correlation report predates task start — not created this session (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Correlation report created during this session (+10)')

    # ── Step 2: Parse audit JSON ─────────────────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f'Audit file is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f'Could not copy audit file: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)
        except Exception:
            pass

    # ── Step 3: Required top-level keys ─────────────────────────────────────
    required_keys = {'sample_count', 'items', 'correlation_matrix', 'notable_correlations'}
    missing_keys = required_keys - set(report.keys())
    if not missing_keys:
        score += 10
        feedback.append('All 4 required top-level keys present (+10)')
    else:
        feedback.append(f'Missing required keys: {sorted(missing_keys)} — stopping here')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # ── Step 4: sample_count >= 20 ──────────────────────────────────────────
    try:
        sample_count = int(report.get('sample_count', 0))
        if sample_count >= min_samples:
            score += 15
            feedback.append(f'Sufficient sample count ({sample_count} >= {min_samples}) (+15)')
        else:
            feedback.append(f'Insufficient sample count ({sample_count} < {min_samples})')
    except (ValueError, TypeError):
        feedback.append('sample_count is not a valid integer')

    # ── Step 5: items match exactly the 6 requested ─────────────────────────
    items = report.get('items', [])
    if isinstance(items, list):
        items_lower = {str(i).lower() for i in items}
        expected_items = health_items.union(adcs_items)
        if items_lower == expected_items:
            score += 5
            feedback.append('Items array contains exactly the 6 expected telemetry items (+5)')
        else:
            feedback.append(f'Items array mismatch. Found: {items_lower}, Expected: {expected_items}')
    else:
        feedback.append('Items is not a list')

    # ── Step 6: correlation_matrix shape and range bounds ───────────────────
    matrix = report.get('correlation_matrix')
    matrix_valid_shape = False
    if isinstance(matrix, list) and len(matrix) == 6:
        if all(isinstance(row, list) and len(row) == 6 for row in matrix):
            matrix_valid_shape = True

    if matrix_valid_shape:
        # Check ranges
        in_range = True
        for i in range(6):
            for j in range(6):
                val = matrix[i][j]
                if val is not None and not math.isnan(float(val)):
                    fval = float(val)
                    if fval < -1.05 or fval > 1.05:  # small tolerance for float parsing
                        in_range = False
        
        if in_range:
            score += 20
            feedback.append('correlation_matrix is 6x6 with valid bounds [-1, 1] (+20)')
            
            # ── Step 7: Matrix diagonal & symmetry ──────────────────────────
            diagonal_ok = True
            symmetry_ok = True
            
            for i in range(6):
                diag_val = matrix[i][i]
                if diag_val is None or math.isnan(float(diag_val)):
                    # Allow NaN on diagonal if variance was zero, but heavily penalizes fake matrices
                    pass
                elif abs(float(diag_val) - 1.0) > 0.05:
                    diagonal_ok = False
                
                for j in range(i+1, 6):
                    v1 = matrix[i][j]
                    v2 = matrix[j][i]
                    if v1 is not None and v2 is not None and not math.isnan(float(v1)) and not math.isnan(float(v2)):
                        if abs(float(v1) - float(v2)) > 0.05:
                            symmetry_ok = False
            
            if diagonal_ok and symmetry_ok:
                score += 10
                feedback.append('Matrix diagonal is ~1.0 and is symmetric (+10)')
            else:
                feedback.append(f'Matrix is structurally invalid (diagonal_ok={diagonal_ok}, symmetry_ok={symmetry_ok})')
        else:
            feedback.append('correlation_matrix contains values outside [-1, 1]')
    else:
        feedback.append('correlation_matrix is not a valid 6x6 numerical matrix')

    # ── Step 8: notable_correlations cross-subsystem check ──────────────────
    notable = report.get('notable_correlations', [])
    valid_cross = False
    
    if isinstance(notable, list):
        for entry in notable:
            if isinstance(entry, dict):
                pair = entry.get('pair')
                if isinstance(pair, list) and len(pair) == 2:
                    p1 = str(pair[0]).lower()
                    p2 = str(pair[1]).lower()
                    
                    # Cross subsystem: (Health & ADCS) OR (ADCS & Health)
                    if (p1 in health_items and p2 in adcs_items) or (p1 in adcs_items and p2 in health_items):
                        valid_cross = True
                        break

    if valid_cross:
        score += 10
        feedback.append('notable_correlations contains >= 1 valid cross-subsystem entry (+10)')
    else:
        feedback.append('notable_correlations missing valid cross-subsystem pair (HEALTH_STATUS vs ADCS)')

    # ── Final Status ────────────────────────────────────────────────────────
    passed = score >= 60

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }