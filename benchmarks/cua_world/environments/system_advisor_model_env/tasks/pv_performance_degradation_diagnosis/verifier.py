#!/usr/bin/env python3
"""Verifier for pv_performance_degradation_diagnosis task.

Tests whether the agent correctly:
1. Read the client system report
2. Used PySAM to run parametric sweep (42 combinations of soiling x degradation)
3. Found the combination that best fits observed Year 4 production (35,290 kWh)
4. Provided physically coherent root cause analysis and recommendations

Scoring (100 points):
- File exists: 10
- File created during task: 10
- PySAM used for simulation: 10
- Parametric sweep performed (20+ combinations): 15
- Best fit error < 10% of observed Year 4: 20
- Observed production data included: 10
- Root cause analysis and recommendations present: 15
- Best fit soiling/degradation in physically plausible range: 10

Pass threshold: 60 points AND (file_exists AND file_modified AND python_ran)
"""

import json
import os
import tempfile


def _independent_file_check(copy_from_env):
    """Independently verify the agent's output file structure."""
    path = "/home/ga/Documents/SAM_Projects/LasVegas_Performance_Diagnosis.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)

        raw_str = json.dumps(raw).lower()
        details = {'raw_file_found': True}

        # Check for diagnosis-specific terminology
        diag_terms = ['soiling', 'degradation', 'sweep', 'best_fit', 'root_cause',
                      'las vegas', 'year4', 'observed', 'error_pct', 'recommended']
        details['diag_term_count'] = sum(1 for t in diag_terms if t in raw_str)

        # Check sweep results count
        sweep_results = None
        for key in ['sweep_results', 'results', 'parametric_results', 'combinations']:
            if key in raw and isinstance(raw[key], list):
                sweep_results = raw[key]
                break
        details['sweep_count'] = len(sweep_results) if sweep_results else 0

        # Check for observed Year 4 value close to 35290
        details['has_observed_year4'] = '35290' in raw_str or '35,290' in raw_str

        # Check best fit present
        details['has_best_fit'] = any(k in raw for k in ['best_fit', 'best_combination', 'optimal_fit'])

        # Check root cause present
        rca = raw.get('root_cause_analysis', '') or raw.get('root_cause', '') or raw.get('diagnosis', '')
        details['has_root_cause'] = isinstance(rca, str) and len(rca) > 30

        # Check recommendations
        rec = raw.get('recommended_actions') or raw.get('recommendations') or raw.get('action_items')
        details['has_recommendations'] = isinstance(rec, list) and len(rec) >= 1

        details['looks_complete'] = (
            details['diag_term_count'] >= 4
            and details['sweep_count'] >= 20
            and details['has_best_fit']
            and (details['has_root_cause'] or details['has_recommendations'])
        )

        return True, details
    except Exception as e:
        return False, {'raw_file_found': False, 'error': str(e)}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def verify_pv_performance_degradation_diagnosis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sweep_count = metadata.get('expected_sweep_count', 42)
    observed_year4 = metadata.get('observed_year4_kwh', 35290)
    best_fit_error_max = metadata.get('expected_best_fit_error_max_pct', 10.0)
    gt_soiling = metadata.get('ground_truth_soiling_pct', 8.0)
    gt_degradation = metadata.get('ground_truth_degradation_pct_per_yr', 0.9)

    # Read export result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: File exists (10 points)
    file_exists = result.get('file_exists') is True or str(result.get('file_exists')) == 'true'
    if file_exists:
        score += 10
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file NOT found")

    # Criterion 2: File created during task (10 points)
    file_modified = result.get('file_modified') is True or str(result.get('file_modified')) == 'true'
    if file_modified:
        score += 10
        feedback_parts.append("File created during task")
    elif file_exists:
        score += 2
        feedback_parts.append("File exists but pre-dates task start")
    else:
        feedback_parts.append("File not modified during task")

    # Criterion 3: PySAM used for simulation (10 points)
    pysam_used = result.get('pysam_used') is True or str(result.get('pysam_used')) == 'true'
    python_ran = result.get('python_ran') is True or str(result.get('python_ran')) == 'true'
    sweep_detected = result.get('sweep_detected') is True or str(result.get('sweep_detected')) == 'true'

    if pysam_used:
        score += 10
        feedback_parts.append("PySAM simulation confirmed in Python code")
    elif python_ran:
        score += 4
        feedback_parts.append("Python used but PySAM import not confirmed")
    else:
        feedback_parts.append("No PySAM/Python execution detected")

    # Criterion 4: Parametric sweep performed (15 points)
    try:
        num_sweep = int(result.get('num_sweep_results', '0'))
    except (ValueError, TypeError):
        num_sweep = 0

    if num_sweep >= expected_sweep_count:
        score += 15
        feedback_parts.append(f"Full parametric sweep: {num_sweep} combinations")
    elif num_sweep >= 20:
        score += 10
        feedback_parts.append(f"Partial sweep: {num_sweep} combinations (expected {expected_sweep_count})")
    elif num_sweep >= 10:
        score += 6
        feedback_parts.append(f"Minimal sweep: {num_sweep} combinations (expected {expected_sweep_count})")
    elif num_sweep >= 3:
        score += 3
        feedback_parts.append(f"Very few combinations: {num_sweep} (expected {expected_sweep_count})")
    elif sweep_detected:
        score += 2
        feedback_parts.append("Sweep code detected but few results in output")
    else:
        feedback_parts.append("No parametric sweep data found")

    # Criterion 5: Best fit error < 10% (20 points - most important)
    try:
        best_error_pct = float(result.get('best_fit_error_pct', '100'))
    except (ValueError, TypeError):
        best_error_pct = 100.0

    if best_error_pct >= 0:
        if best_error_pct <= 2.0:
            score += 20
            feedback_parts.append(f"Excellent fit: {best_error_pct:.1f}% error vs observed Year 4")
        elif best_error_pct <= 5.0:
            score += 16
            feedback_parts.append(f"Good fit: {best_error_pct:.1f}% error vs observed Year 4")
        elif best_error_pct <= best_fit_error_max:
            score += 10
            feedback_parts.append(f"Acceptable fit: {best_error_pct:.1f}% error vs observed Year 4")
        elif best_error_pct <= 20.0:
            score += 5
            feedback_parts.append(f"Poor fit: {best_error_pct:.1f}% error vs observed Year 4")
        else:
            feedback_parts.append(f"No acceptable fit found: {best_error_pct:.1f}% error")
    else:
        feedback_parts.append("Best fit error could not be computed")

    # Criterion 6: Observed production data included in output (10 points)
    has_observed = result.get('has_observed_data') is True or str(result.get('has_observed_data')) == 'true'
    if has_observed:
        score += 10
        feedback_parts.append("Observed production data (including Year 4=35,290 kWh) included in output")
    else:
        feedback_parts.append("Observed production data not found in output JSON")

    # Criterion 7: Root cause analysis and recommendations present (15 points)
    has_recommendations = result.get('has_recommendations') is True or str(result.get('has_recommendations')) == 'true'
    if has_recommendations:
        score += 15
        feedback_parts.append("Root cause analysis and/or recommendations provided")
    else:
        feedback_parts.append("Root cause analysis or recommendations missing")

    # Criterion 8: Best fit values physically plausible (10 points)
    try:
        best_soiling = float(result.get('best_fit_soiling', '0'))
        best_degr = float(result.get('best_fit_degradation', '0'))
    except (ValueError, TypeError):
        best_soiling = 0.0
        best_degr = 0.0

    if best_soiling > 0 and best_degr > 0:
        # Ground truth: soiling=8%, degradation=0.9%/yr
        # Accept ±2 steps in either direction for partial credit
        soiling_reasonable = 2.0 <= best_soiling <= 14.0
        degr_reasonable = 0.3 <= best_degr <= 1.8
        soiling_close = abs(best_soiling - gt_soiling) <= 4.0
        degr_close = abs(best_degr - gt_degradation) <= 0.4

        if soiling_close and degr_close:
            score += 10
            feedback_parts.append(
                f"Best fit near ground truth: soiling={best_soiling:.0f}%, degradation={best_degr:.1f}%/yr "
                f"(GT: soiling={gt_soiling:.0f}%, degr={gt_degradation:.1f}%/yr)"
            )
        elif soiling_reasonable and degr_reasonable:
            score += 5
            feedback_parts.append(
                f"Best fit physically plausible: soiling={best_soiling:.0f}%, degradation={best_degr:.1f}%/yr"
            )
        else:
            feedback_parts.append(
                f"Best fit values unusual: soiling={best_soiling:.0f}%, degradation={best_degr:.1f}%/yr"
            )
    else:
        feedback_parts.append("Best fit soiling/degradation values not found")

    # Independent cross-check
    raw_found, raw_details = _independent_file_check(copy_from_env)
    if raw_found and raw_details.get('looks_complete'):
        feedback_parts.append(
            f"Cross-check PASSED: {raw_details['sweep_count']} sweep results, "
            f"{raw_details['diag_term_count']} diagnostic terms, "
            f"best_fit={'yes' if raw_details['has_best_fit'] else 'no'}, "
            f"root_cause={'yes' if raw_details['has_root_cause'] else 'no'}"
        )
    elif raw_found:
        feedback_parts.append(
            f"Cross-check PARTIAL: {raw_details.get('sweep_count', 0)} sweep results, "
            f"{raw_details.get('diag_term_count', 0)} diagnostic terms"
        )

    # Anti-bypass
    if not python_ran:
        feedback_parts.append("ANTI-BYPASS: No Python/PySAM execution detected")
        score = min(score, 20)

    score = min(score, 100)
    key_criteria_met = file_exists and file_modified and python_ran
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
