"""
Verifier for ftt_motor_kinetics_analysis task.

This verifier dynamically computes the EXACT ground truth from the raw CSV 
data generated during setup, and evaluates the agent's JSON report against it.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Artifact detection: Corrupted participant P99 is excluded     (20 pts)
  3. Total taps & Mean ITI correct (within ±0.5ms)                 (30 pts)
  4. Clinical Indices: Asymmetry & Fatigue correct (within ±0.1%)  (25 pts)
  5. Group mean statistics correct (within ±0.1%)                  (15 pts)

Pass threshold: 60 pts
"""

import json
import os
import csv
import tempfile
import statistics

PASS_THRESHOLD = 60
CONTAMINATED_ID = 'P99'

def compute_ground_truth(csv_path):
    """Dynamically computes the correct metrics from the raw CSV."""
    data = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append(row)
            
    # Group data by participant
    participants = {}
    for r in data:
        pid = r['participant_id']
        if pid not in participants:
            participants[pid] = {'dominant': [], 'nondominant': []}
        participants[pid][r['hand']].append(r)
        
    gt = {}
    group_asym = []
    group_fatigue = []
    
    for pid, hands in participants.items():
        if pid == CONTAMINATED_ID:
            continue
            
        dom_taps = len(hands['dominant'])
        nondom_taps = len(hands['nondominant'])
        
        dom_iti = statistics.mean([float(r['iti_ms']) for r in hands['dominant']]) if dom_taps else 0
        nondom_iti = statistics.mean([float(r['iti_ms']) for r in hands['nondominant']]) if nondom_taps else 0
        
        asym = ((dom_taps - nondom_taps) / dom_taps) * 100 if dom_taps else 0
        
        dom_t1 = len([r for r in hands['dominant'] if str(r['trial']) == '1'])
        dom_t3 = len([r for r in hands['dominant'] if str(r['trial']) == '3'])
        fatigue = ((dom_t1 - dom_t3) / dom_t1) * 100 if dom_t1 else 0
        
        gt[pid] = {
            'dominant_total_taps': dom_taps,
            'nondominant_total_taps': nondom_taps,
            'dominant_mean_iti_ms': dom_iti,
            'nondominant_mean_iti_ms': nondom_iti,
            'asymmetry_index_percent': asym,
            'fatigue_index_percent': fatigue
        }
        group_asym.append(asym)
        group_fatigue.append(fatigue)
        
    group_gt = {
        'group_mean_asymmetry_percent': statistics.mean(group_asym),
        'group_mean_fatigue_percent': statistics.mean(group_fatigue)
    }
    
    return gt, group_gt

def verify_ftt_motor_kinetics_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # Prepare temp files
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json, \
         tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        json_path = tmp_json.name
        csv_path = tmp_csv.name

    try:
        # 1. Check if raw CSV exists and fetch it (to compute dynamic GT)
        try:
            copy_from_env('/home/ga/pebl/data/ftt_tap_data.csv', csv_path)
            gt_per_participant, gt_group = compute_ground_truth(csv_path)
        except Exception as e:
            return {'passed': False, 'score': 0, 'feedback': f'Failed to parse raw data for GT generation: {e}'}

        # 2. Check if agent's output JSON exists
        try:
            copy_from_env('/home/ga/pebl/analysis/ftt_report.json', json_path)
            with open(json_path, encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback_parts.append('[+10] Output file found and valid JSON.')
        except FileNotFoundError:
            feedback_parts.append('[0] Output file /home/ga/pebl/analysis/ftt_report.json not found.')
            return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
        except json.JSONDecodeError as e:
            feedback_parts.append(f'[0] Output file is not valid JSON: {e}')
            return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}

        participants_list = report.get('participants', [])
        part_map = {str(p.get('id', p.get('participant_id'))): p for p in participants_list if 'id' in p or 'participant_id' in p}

        # --- Criterion 2: Artifact detection (P99 excluded) ---
        p99_entry = part_map.get(CONTAMINATED_ID)
        if p99_entry and p99_entry.get('excluded') in (True, 'true', 1, 'yes'):
            score += 20
            feedback_parts.append('[+20] Hardware artifact (P99) correctly identified and excluded.')
        else:
            feedback_parts.append('[0] Hardware artifact (P99) NOT excluded.')

        # Variables for aggregated scoring
        correct_taps_iti = 0
        correct_indices = 0
        n_valid = len(gt_per_participant)

        # Evaluate metrics for valid participants
        for pid, gt in gt_per_participant.items():
            entry = part_map.get(pid, {})
            
            # Extract agent's metrics safely
            try:
                a_dom_taps = float(entry.get('dominant_total_taps', -999))
                a_nondom_taps = float(entry.get('nondominant_total_taps', -999))
                a_dom_iti = float(entry.get('dominant_mean_iti_ms', -999))
                a_nondom_iti = float(entry.get('nondominant_mean_iti_ms', -999))
                
                a_asym = float(entry.get('asymmetry_index_percent', -999))
                a_fatigue = float(entry.get('fatigue_index_percent', -999))
                
                # Check Basic Metrics (Total Taps and Mean ITI) -> ±0.5 tolerance
                if (abs(a_dom_taps - gt['dominant_total_taps']) <= 0.5 and
                    abs(a_nondom_taps - gt['nondominant_total_taps']) <= 0.5 and
                    abs(a_dom_iti - gt['dominant_mean_iti_ms']) <= 0.5 and
                    abs(a_nondom_iti - gt['nondominant_mean_iti_ms']) <= 0.5):
                    correct_taps_iti += 1
                
                # Check Clinical Indices (Asymmetry & Fatigue) -> ±0.1% tolerance
                if (abs(a_asym - gt['asymmetry_index_percent']) <= 0.1 and
                    abs(a_fatigue - gt['fatigue_index_percent']) <= 0.1):
                    correct_indices += 1
            except (ValueError, TypeError):
                continue

        # --- Criterion 3: Total taps & Mean ITI ---
        if correct_taps_iti == n_valid:
            score += 30
            feedback_parts.append(f'[+30] Basic metrics (Taps/ITI) correct for all {n_valid} participants.')
        elif correct_taps_iti > 0:
            partial = int(30 * (correct_taps_iti / n_valid))
            score += partial
            feedback_parts.append(f'[+{partial}] Basic metrics correct for {correct_taps_iti}/{n_valid} participants.')
        else:
            feedback_parts.append('[0] Basic metrics (Taps/ITI) incorrect or missing.')

        # --- Criterion 4: Clinical Indices ---
        if correct_indices == n_valid:
            score += 25
            feedback_parts.append(f'[+25] Clinical indices (Asymmetry/Fatigue) correct for all {n_valid} participants.')
        elif correct_indices > 0:
            partial = int(25 * (correct_indices / n_valid))
            score += partial
            feedback_parts.append(f'[+{partial}] Clinical indices correct for {correct_indices}/{n_valid} participants.')
        else:
            feedback_parts.append('[0] Clinical indices incorrect or missing.')

        # --- Criterion 5: Group mean statistics ---
        try:
            a_grp_asym = float(report.get('group_mean_asymmetry_percent', -999))
            a_grp_fatigue = float(report.get('group_mean_fatigue_percent', -999))
            
            grp_asym_pass = abs(a_grp_asym - gt_group['group_mean_asymmetry_percent']) <= 0.1
            grp_fatigue_pass = abs(a_grp_fatigue - gt_group['group_mean_fatigue_percent']) <= 0.1
            
            if grp_asym_pass and grp_fatigue_pass:
                score += 15
                feedback_parts.append('[+15] Group mean statistics are strictly correct.')
            elif grp_asym_pass or grp_fatigue_pass:
                score += 7
                feedback_parts.append('[+7] Group mean statistics partially correct.')
            else:
                feedback_parts.append('[0] Group mean statistics incorrect.')
        except (ValueError, TypeError):
            feedback_parts.append('[0] Group mean statistics missing or invalid format.')

    finally:
        # Cleanup
        for p in [json_path, csv_path]:
            try:
                if os.path.exists(p):
                    os.unlink(p)
            except Exception:
                pass

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }