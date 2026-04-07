#!/usr/bin/env python3
"""
Verifier for telemetry_delta_compression task.

A ground data systems engineer evaluates the compressibility of a live
spacecraft telemetry stream by computing sequential differences (deltas).

Scoring breakdown (100 pts total, pass threshold = 70):
  10pts  File Existence & Freshness (Hard Gate)
  10pts  Schema Compliance (All required keys present)
  10pts  Array Bounds Correctness (raw_samples=25, deltas=24)
  20pts  Physical Realism Gate (Anti-gaming: data varies, reasonable max_delta, normal values)
  20pts  Delta Math Accuracy (Agent deltas match verifier's computation from raw_samples)
  20pts  Statistics Math Accuracy (Agent stats match verifier's computation)
  10pts  Logic Gate Correctness (compression_recommended == mean_abs_delta < 0.5)
 ---
 100pts total

Do-nothing invariant: passed=False (score 0 if file not created/new)
"""

import json
import os
import tempfile
import math


def verify_telemetry_delta_compression(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0,
                'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/telemetry_delta_compression_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/compression_analysis.json')

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

    # ── Step 2: File Existence & Freshness (Hard Gate: 10 pts) ──────────────
    if not file_exists:
        feedback.append('Output JSON file not found on Desktop.')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}

    if not file_is_new:
        feedback.append('Output JSON file predates task start (not created this session).')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('File exists and is new (+10)')

    # ── Step 3: Parse output JSON ───────────────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f'Output file is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f'Could not copy output file: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    # ── Step 4: Schema Compliance (10 pts) ──────────────────────────────────
    required_keys = {'target', 'packet', 'item', 'sample_count', 'raw_samples', 'deltas', 'statistics', 'compression_recommended'}
    missing_keys = required_keys - set(report.keys())
    
    if not missing_keys:
        score += 10
        feedback.append('Schema compliance verified (+10)')
    else:
        feedback.append(f'Missing required keys: {sorted(missing_keys)}.')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # Ensure statistics has the right subkeys
    stats = report.get('statistics', {})
    required_stats = {'max_abs_delta', 'mean_abs_delta', 'zero_delta_count'}
    missing_stats = required_stats - set(stats.keys() if isinstance(stats, dict) else [])
    if missing_stats:
        feedback.append(f'Missing statistics keys: {sorted(missing_stats)}.')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # ── Step 5: Array Bounds Correctness (10 pts) ───────────────────────────
    raw_samples = report.get('raw_samples', [])
    deltas = report.get('deltas', [])

    if not isinstance(raw_samples, list) or not isinstance(deltas, list):
        feedback.append('raw_samples or deltas is not a list.')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    if len(raw_samples) == 25 and len(deltas) == 24:
        score += 10
        feedback.append('Array bounds correct (25 samples, 24 deltas) (+10)')
    else:
        feedback.append(f'Array bounds incorrect: {len(raw_samples)} samples, {len(deltas)} deltas.')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # Ensure items are numbers
    try:
        raw_samples = [float(x) for x in raw_samples]
        agent_deltas = [float(x) for x in deltas]
    except (ValueError, TypeError):
        feedback.append('Non-numeric values found in arrays.')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # ── Step 6: Physical Realism Gate (20 pts) ──────────────────────────────
    # Anti-gaming: synthetic data tends to be either perfectly flat, totally random, or not match TEMP1 profiles
    mean_val = sum(raw_samples) / len(raw_samples)
    variance = sum((x - mean_val) ** 2 for x in raw_samples) / len(raw_samples)
    
    # Calculate truth deltas
    true_deltas = [raw_samples[i+1] - raw_samples[i] for i in range(24)]
    true_max_abs = max(abs(d) for d in true_deltas)

    physical_realistic = True
    if variance < 1e-6:
        feedback.append('Data fails realism check: Zero variance (perfectly flat).')
        physical_realistic = False
    elif true_max_abs >= 3.0:
        feedback.append(f'Data fails realism check: Unrealistic max delta step ({true_max_abs:.3f}).')
        physical_realistic = False
    elif mean_val < 5.0 or mean_val > 100.0:
        feedback.append(f'Data fails realism check: Mean TEMP1 outside normal range ({mean_val:.2f}).')
        physical_realistic = False

    if physical_realistic:
        score += 20
        feedback.append('Data passes physical realism check (+20)')

    # ── Step 7: Delta Math Accuracy (20 pts) ────────────────────────────────
    deltas_correct = True
    for i in range(24):
        if abs(agent_deltas[i] - true_deltas[i]) > 1e-4:
            deltas_correct = False
            break
            
    if deltas_correct:
        score += 20
        feedback.append('Delta math calculation is perfectly accurate (+20)')
    else:
        feedback.append('Delta math contains errors (does not match raw_samples).')

    # ── Step 8: Statistics Math Accuracy (20 pts) ───────────────────────────
    true_mean_abs = sum(abs(d) for d in true_deltas) / 24.0
    true_zero_count = sum(1 for d in true_deltas if abs(d) < 1e-6)

    try:
        agent_max = float(stats.get('max_abs_delta', -1))
        agent_mean = float(stats.get('mean_abs_delta', -1))
        agent_zero = int(stats.get('zero_delta_count', -1))
        
        stats_correct = True
        if abs(agent_max - true_max_abs) > 1e-4:
            stats_correct = False
        if abs(agent_mean - true_mean_abs) > 1e-4:
            stats_correct = False
        if agent_zero != true_zero_count:
            stats_correct = False

        if stats_correct:
            score += 20
            feedback.append('Statistics calculations are perfectly accurate (+20)')
        else:
            feedback.append(f'Statistics mismatch. Expected: max={true_max_abs:.3f}, mean={true_mean_abs:.3f}, zeros={true_zero_count}.')
            
    except (ValueError, TypeError):
        feedback.append('Statistics contain invalid non-numeric types.')

    # ── Step 9: Logic Gate Correctness (10 pts) ─────────────────────────────
    # Should recommend true if mean_abs_delta < 0.5 based on their OWN computed mean
    # (or the true mean, but let's test based on the rule applied to the true mean to be strict)
    expected_recommendation = (true_mean_abs < 0.5)
    agent_recommendation = report.get('compression_recommended')

    if isinstance(agent_recommendation, bool) and agent_recommendation == expected_recommendation:
        score += 10
        feedback.append('Logic evaluation is correct (+10)')
    else:
        feedback.append(f'Logic evaluation failed. Expected {expected_recommendation} based on mean {true_mean_abs:.3f}.')

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }