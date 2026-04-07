"""
Verifier for stop_signal_ssrt_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. sub-99999 excluded (GO RT=15-25ms — impossible human RT)      (25 pts)
  3. SSRT within ±50ms for ≥8 of 11 valid participants            (35 pts)
  4. Group mean SSRT within ±30ms of ground truth (247.4 ms)      (30 pts)

Pass threshold: 60 pts

Ground truth computed from: real CNP OpenNeuro ds000030 Stop Signal Task data.
Source: Gorgolewski et al. (2017). Scientific Data. doi:10.1038/sdata.2017.93
Method: Integration method — SSRT = nth_percentile(GoRT) - mean(SSD)
        where n = proportion of UnsuccessfulStop trials

sub-99999: GO RT=15-25ms (impossible; human minimum is ~100ms),
           100% SuccessfulStop rate (SST is designed to produce ~50% stop success)

Max partial score check (Anti-Pattern 4):
  partial max = 17 (criterion 3 partial) = 17 < 60 threshold ✓
"""

import json
import os
import tempfile

CONTAMINATED = 'sub-99999'
PASS_THRESHOLD = 60
SSRT_TOLERANCE = 50.0    # ±50ms
GROUP_SSRT_TOLERANCE = 30.0
MIN_CORRECT_PPTS = 8
GROUP_SSRT_GT = 247.4

# Ground truth SSRT per valid participant (ms), integration method
# Computed from real CNP ds000030 Stop Signal Task data
GROUND_TRUTH_SSRT = {
    'sub-10159': 192.9,
    'sub-10171': 188.5,
    'sub-10189': 332.3,
    'sub-10206': 243.3,
    'sub-10217': 250.8,
    'sub-10225': 242.7,
    'sub-10235': 301.3,
    'sub-10249': 346.6,
    'sub-10280': 221.3,
    'sub-10292': 224.5,
    'sub-10304': 176.9,
}


def verify_stop_signal_ssrt_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # --- Criterion 1: Output file exists and is valid JSON ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/ssrt_report.json', tmp_path)
        with open(tmp_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/ssrt_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    # Build participant lookup
    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = (entry.get('id') or entry.get('participant_id') or entry.get('participant'))
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        if entry and entry.get('flagged') in (True, 'true', 1, 'yes'):
            return True
        if pid not in part_map:
            excluded_list = report.get('excluded', [])
            if isinstance(excluded_list, list) and pid in excluded_list:
                return True
        return False

    # --- Criterion 2: sub-99999 excluded (GO RT=15-25ms = impossible) ---
    if is_excluded(CONTAMINATED):
        score += 25
        feedback_parts.append('[+25] sub-99999 correctly excluded (GO RT<30ms — physiologically impossible).')
    else:
        feedback_parts.append('[0] sub-99999 not excluded despite GO RT<30ms on all trials (impossible human RT).')

    # --- Criterion 3: SSRT within tolerance for ≥8 valid participants ---
    correct_ssrt = 0
    for pid, gt_ssrt in GROUND_TRUTH_SSRT.items():
        entry = part_map.get(pid)
        if entry is None or entry.get('excluded') in (True, 'true', 1, 'yes'):
            continue
        ssrt = (entry.get('ssrt_ms') or entry.get('ssrt') or
                entry.get('stop_signal_rt') or entry.get('SSRT'))
        if ssrt is not None:
            try:
                diff = abs(float(ssrt) - gt_ssrt)
                if diff <= SSRT_TOLERANCE:
                    correct_ssrt += 1
            except (TypeError, ValueError):
                pass

    if correct_ssrt >= MIN_CORRECT_PPTS:
        score += 35
        feedback_parts.append(f'[+35] SSRT within ±{SSRT_TOLERANCE}ms for {correct_ssrt}/11 valid participants.')
    elif correct_ssrt >= 5:
        partial = 17
        score += partial
        feedback_parts.append(f'[+{partial}] SSRT within tolerance for {correct_ssrt}/11 participants (partial).')
    else:
        feedback_parts.append(f'[0] SSRT within tolerance for only {correct_ssrt}/11 valid participants.')

    # --- Criterion 4: Group mean SSRT ---
    group_ssrt = (report.get('group_mean_ssrt_ms') or report.get('group_ssrt_ms') or
                  report.get('mean_ssrt_ms') or report.get('group_mean_ssrt') or
                  report.get('overall_ssrt_ms'))
    if group_ssrt is not None:
        try:
            diff = abs(float(group_ssrt) - GROUP_SSRT_GT)
            if diff <= GROUP_SSRT_TOLERANCE:
                score += 30
                feedback_parts.append(
                    f'[+30] Group mean SSRT {float(group_ssrt):.1f}ms within ±{GROUP_SSRT_TOLERANCE}ms '
                    f'of ground truth {GROUP_SSRT_GT}ms.'
                )
            else:
                feedback_parts.append(
                    f'[0] Group mean SSRT {float(group_ssrt):.1f}ms differs from ground truth '
                    f'{GROUP_SSRT_GT}ms by {diff:.1f}ms.'
                )
        except (TypeError, ValueError):
            feedback_parts.append('[0] Group mean SSRT value could not be parsed.')
    else:
        feedback_parts.append('[0] "group_mean_ssrt_ms" key missing from report.')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }
