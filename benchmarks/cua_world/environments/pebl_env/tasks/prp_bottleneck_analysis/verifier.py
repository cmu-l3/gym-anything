"""
Verifier for prp_bottleneck_analysis task.

Scoring (100 pts total):
  1. Output file exists and parses as valid JSON matching schema   (10 pts)
  2. P99 is explicitly in 'excluded_participants' with a reason    (20 pts)
  3. Dual-Correct Filtering & Participant Means (±1.5 ms tol)      (35 pts)
  4. PRP Effect calculated correctly for valid participants        (15 pts)
  5. Group SOA means accurately aggregated                         (20 pts)

Pass threshold: 60 pts
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAMINATED_PARTICIPANT = 'P99'
SOAS = ['50', '150', '300', '500', '900']
RT_TOLERANCE_MS = 1.5

def compute_ground_truth(csv_path):
    """
    Dynamically computes the exact ground truth from the dataset.
    This ensures complete resilience against rounding and strict filtering checks.
    """
    gt = {
        'participants': {},
        'group_soa_means': {soa: {'rt1': [], 'rt2': []} for soa in SOAS}
    }
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            soa = str(row['soa_ms'])
            
            # Skip P99 for aggregation
            if pid == CONTAMINATED_PARTICIPANT:
                continue
                
            # FILTER: Must be correct on BOTH tasks!
            # If the agent ignores this filter, their means will easily drift 15-30ms out of tolerance.
            if row['t1_correct'] == '1' and row['t2_correct'] == '1':
                if pid not in gt['participants']:
                    gt['participants'][pid] = {s: {'rt1': [], 'rt2': []} for s in SOAS}
                
                gt['participants'][pid][soa]['rt1'].append(float(row['rt1_ms']))
                gt['participants'][pid][soa]['rt2'].append(float(row['rt2_ms']))
                
    # Calculate Participant Means & PRP Effect
    for pid, data in gt['participants'].items():
        for soa in SOAS:
            rt1_list = data[soa]['rt1']
            rt2_list = data[soa]['rt2']
            data[soa]['mean_rt1'] = sum(rt1_list) / len(rt1_list) if rt1_list else 0
            data[soa]['mean_rt2'] = sum(rt2_list) / len(rt2_list) if rt2_list else 0
            
            # Add to group pool
            gt['group_soa_means'][soa]['rt1'].append(data[soa]['mean_rt1'])
            gt['group_soa_means'][soa]['rt2'].append(data[soa]['mean_rt2'])
            
        data['prp_effect_ms'] = data['50']['mean_rt2'] - data['900']['mean_rt2']
        
    # Calculate Group Means
    for soa in SOAS:
        grp_rt1 = gt['group_soa_means'][soa]['rt1']
        grp_rt2 = gt['group_soa_means'][soa]['rt2']
        gt['group_soa_means'][soa]['mean_rt1'] = sum(grp_rt1) / len(grp_rt1) if grp_rt1 else 0
        gt['group_soa_means'][soa]['mean_rt2'] = sum(grp_rt2) / len(grp_rt2) if grp_rt2 else 0

    return gt

def verify_prp_bottleneck_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # Get data files
    tmp_data = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
    tmp_report = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    report = None
    
    try:
        # Get raw data to calculate exact ground truth dynamically
        copy_from_env('/home/ga/pebl/data/prp_dual_task_data.csv', tmp_data.name)
        gt = compute_ground_truth(tmp_data.name)
        
        # Get agent's report
        copy_from_env('/home/ga/pebl/analysis/prp_report.json', tmp_report.name)
        with open(tmp_report.name, encoding='utf-8') as f:
            report = json.load(f)
            
        score += 10
        feedback_parts.append("[+10] Output file found and parses as valid JSON.")
    except FileNotFoundError:
        feedback_parts.append("[0] Required file missing (either dataset or report JSON).")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f"[0] Output file is not valid JSON: {e}")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    finally:
        for tmp_path in [tmp_data.name, tmp_report.name]:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    # Prepare maps
    excluded_list = report.get('excluded_participants', [])
    participants_list = report.get('participants', [])
    agent_group = report.get('group_soa_means', {})
    
    agent_parts = {str(p.get('id', '')): p for p in participants_list}
    agent_excluded_ids = [str(p.get('id', '')) for p in excluded_list]

    # --- Criterion 2: Exclude P99 (20 pts) ---
    if CONTAMINATED_PARTICIPANT in agent_excluded_ids:
        score += 20
        feedback_parts.append(f"[+20] Anomalous participant {CONTAMINATED_PARTICIPANT} correctly excluded.")
    else:
        feedback_parts.append(f"[0] {CONTAMINATED_PARTICIPANT} not found in 'excluded_participants'.")

    # --- Criterion 3: Dual-Correct Filtering & Individual Means (35 pts) ---
    correct_means_count = 0
    total_expected = len(gt['participants'])
    
    for pid, gt_data in gt['participants'].items():
        if pid not in agent_parts:
            continue
            
        agent_p_data = agent_parts[pid].get('soa_means', {})
        part_matches = True
        
        for soa in SOAS:
            agt_soa = agent_p_data.get(soa, {})
            agt_rt1 = float(agt_soa.get('mean_rt1', 0))
            agt_rt2 = float(agt_soa.get('mean_rt2', 0))
            
            # If the filter was ignored, error differences push it out of ±1.5ms tolerance
            if abs(agt_rt1 - gt_data[soa]['mean_rt1']) > RT_TOLERANCE_MS or \
               abs(agt_rt2 - gt_data[soa]['mean_rt2']) > RT_TOLERANCE_MS:
                part_matches = False
                break
                
        if part_matches:
            correct_means_count += 1

    if correct_means_count == total_expected:
        score += 35
        feedback_parts.append(f"[+35] Dual-correct trial filtering and participant RT means accurate for all {total_expected} participants.")
    elif correct_means_count > 0:
        partial = int(35 * (correct_means_count / total_expected))
        score += partial
        feedback_parts.append(f"[+{partial}] Participant means accurate for {correct_means_count}/{total_expected} participants (partial credit).")
    else:
        feedback_parts.append("[0] Participant means inaccurate (likely failed to filter for dual-correct trials).")

    # --- Criterion 4: PRP Effect Calculation (15 pts) ---
    prp_correct = 0
    for pid, gt_data in gt['participants'].items():
        if pid in agent_parts:
            agt_prp = float(agent_parts[pid].get('prp_effect_ms', 0))
            if abs(agt_prp - gt_data['prp_effect_ms']) <= RT_TOLERANCE_MS:
                prp_correct += 1
                
    if prp_correct == total_expected:
        score += 15
        feedback_parts.append("[+15] PRP effect magnitude correctly computed for all participants.")
    elif prp_correct > 0:
        partial = int(15 * (prp_correct / total_expected))
        score += partial
        feedback_parts.append(f"[+{partial}] PRP effect correct for {prp_correct}/{total_expected} participants.")
    else:
        feedback_parts.append("[0] PRP effect incorrectly computed.")

    # --- Criterion 5: Group SOA Means (20 pts) ---
    group_correct = 0
    for soa in SOAS:
        if str(soa) in agent_group:
            agt_rt1 = float(agent_group[str(soa)].get('mean_rt1', 0))
            agt_rt2 = float(agent_group[str(soa)].get('mean_rt2', 0))
            gt_rt1 = gt['group_soa_means'][soa]['mean_rt1']
            gt_rt2 = gt['group_soa_means'][soa]['mean_rt2']
            
            if abs(agt_rt1 - gt_rt1) <= RT_TOLERANCE_MS and abs(agt_rt2 - gt_rt2) <= RT_TOLERANCE_MS:
                group_correct += 1

    if group_correct == len(SOAS):
        score += 20
        feedback_parts.append("[+20] Group SOA means accurately aggregated.")
    elif group_correct > 0:
        partial = int(20 * (group_correct / len(SOAS)))
        score += partial
        feedback_parts.append(f"[+{partial}] Group SOA means partially correct ({group_correct}/{len(SOAS)} SOAs).")
    else:
        feedback_parts.append("[0] Group SOA means incorrect.")

    passed = score >= 60 and correct_means_count > 10
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }