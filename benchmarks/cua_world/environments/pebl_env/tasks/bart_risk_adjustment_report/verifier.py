"""
Verifier for bart_risk_adjustment_report task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. sub-99999 excluded (pumps=0 on all trials — impossible)       (25 pts)
  3. ADJMEANPUMPS within ±0.5 for ≥8 of 11 valid participants     (35 pts)
  4. Group mean ADJMEANPUMPS within ±0.3 of ground truth (4.3897) (30 pts)

Pass threshold: 60 pts

Ground truth computed from: real CNP OpenNeuro ds000030 BART data.
Source: Gorgolewski et al. (2017). Scientific Data. doi:10.1038/sdata.2017.93
Participants: sub-10159, sub-10171, sub-10189, sub-10206, sub-10217, sub-10225,
              sub-10235, sub-10249, sub-10280, sub-10292, sub-10304
sub-99999: pumps=0 on all trials (impossible — cashout requires ≥1 pump)

Max partial score check (Anti-Pattern 4):
  partial max = 17 (criterion 3 partial) = 17 < 60 threshold ✓
"""

import json
import os
import tempfile

CONTAMINATED = 'sub-99999'
PASS_THRESHOLD = 60
ADJMEANPUMPS_TOLERANCE = 0.5
GROUP_ADJMEANPUMPS_TOLERANCE = 0.3
MIN_CORRECT_PPTS = 8
GROUP_ADJMEANPUMPS_GT = 4.3897

# Ground truth ADJMEANPUMPS per valid participant (mean pumps on non-explosion trials only)
# Computed from real CNP ds000030 BART data
GROUND_TRUTH_ADJMEANPUMPS = {
    'sub-10159': 3.1538,
    'sub-10171': 5.8333,
    'sub-10189': 5.5000,
    'sub-10206': 5.1250,
    'sub-10217': 4.8000,
    'sub-10225': 4.2500,
    'sub-10235': 2.5000,
    'sub-10249': 3.2500,
    'sub-10280': 3.9167,
    'sub-10292': 6.8333,
    'sub-10304': 3.1250,
}


def verify_bart_risk_adjustment_report(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # --- Criterion 1: Output file exists and is valid JSON ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/bart_report.json', tmp_path)
        with open(tmp_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/bart_report.json not found.')
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

    # --- Criterion 2: sub-99999 excluded (pumps=0 on all trials = impossible) ---
    if is_excluded(CONTAMINATED):
        score += 25
        feedback_parts.append('[+25] sub-99999 correctly excluded (pumps=0 on all trials — data recording failure).')
    else:
        feedback_parts.append('[0] sub-99999 not excluded despite pumps=0 on all trials (impossible cashout).')

    # --- Criterion 3: ADJMEANPUMPS within tolerance for ≥8 valid participants ---
    correct_adjmean = 0
    for pid, gt_adj in GROUND_TRUTH_ADJMEANPUMPS.items():
        entry = part_map.get(pid)
        if entry is None or entry.get('excluded') in (True, 'true', 1, 'yes'):
            continue
        adj = (entry.get('adjmeanpumps') or entry.get('adj_mean_pumps') or
               entry.get('mean_pumps') or entry.get('adjusted_mean_pumps') or
               entry.get('adj_mean'))
        if adj is not None:
            try:
                diff = abs(float(adj) - gt_adj)
                if diff <= ADJMEANPUMPS_TOLERANCE:
                    correct_adjmean += 1
            except (TypeError, ValueError):
                pass

    if correct_adjmean >= MIN_CORRECT_PPTS:
        score += 35
        feedback_parts.append(f'[+35] ADJMEANPUMPS within ±{ADJMEANPUMPS_TOLERANCE} for {correct_adjmean}/11 valid participants.')
    elif correct_adjmean >= 5:
        partial = 17
        score += partial
        feedback_parts.append(f'[+{partial}] ADJMEANPUMPS within tolerance for {correct_adjmean}/11 participants (partial).')
    else:
        feedback_parts.append(f'[0] ADJMEANPUMPS within tolerance for only {correct_adjmean}/11 valid participants.')

    # --- Criterion 4: Group mean ADJMEANPUMPS ---
    group_adj = (report.get('group_adjmeanpumps') or report.get('group_mean_adjmeanpumps') or
                 report.get('mean_adjmeanpumps') or report.get('group_adj_mean_pumps') or
                 report.get('overall_adjmeanpumps'))
    if group_adj is not None:
        try:
            diff = abs(float(group_adj) - GROUP_ADJMEANPUMPS_GT)
            if diff <= GROUP_ADJMEANPUMPS_TOLERANCE:
                score += 30
                feedback_parts.append(
                    f'[+30] Group mean ADJMEANPUMPS {float(group_adj):.4f} within ±{GROUP_ADJMEANPUMPS_TOLERANCE} '
                    f'of ground truth {GROUP_ADJMEANPUMPS_GT}.'
                )
            else:
                feedback_parts.append(
                    f'[0] Group mean ADJMEANPUMPS {float(group_adj):.4f} differs from ground truth '
                    f'{GROUP_ADJMEANPUMPS_GT} by {diff:.4f}.'
                )
        except (TypeError, ValueError):
            feedback_parts.append('[0] Group mean ADJMEANPUMPS value could not be parsed.')
    else:
        feedback_parts.append('[0] "group_adjmeanpumps" key missing from report.')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }
