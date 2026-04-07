#!/usr/bin/env python3
"""
Verifier for simon_delta_plot_analysis task.

Dynamically calculates the exact ground truth from the generated CSV using pandas
to ensure perfect alignment with the generated dataset, then evaluates the agent's JSON.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Contaminated participant s99 is excluded                      (20 pts)
  3. All 25 valid participants present                             (10 pts)
  4. Individual Simon effects match GT within ±5ms                 (20 pts)
  5. Group mean Simon effect matches GT within ±3ms                (15 pts)
  6. Delta plot keys exist (Q1-Q5)                                 (10 pts)
  7. Delta plot values match GT within ±8ms and pattern decreases  (15 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import pandas as pd
import numpy as np

PASS_THRESHOLD = 60
CONTAMINATED_PARTICIPANT = 's99'

def compute_ground_truth(csv_path):
    """Computes exact ground truth directly from the agent's target CSV data."""
    df = pd.read_csv(csv_path)
    
    # Filter valid correct trials
    df_valid = df[(df['correct'] == 1) & (df['participant'] != CONTAMINATED_PARTICIPANT)].copy()
    
    # Individual Simon effects
    gt_individuals = {}
    for p, p_df in df_valid.groupby('participant'):
        m_con = p_df[p_df['condition'] == 'congruent']['rt_ms'].mean()
        m_inc = p_df[p_df['condition'] == 'incongruent']['rt_ms'].mean()
        gt_individuals[p] = m_inc - m_con

    gt_group_mean = float(np.mean(list(gt_individuals.values())))
    
    # Delta Plot (Quintiles)
    def get_quintile_simon(p_df):
        # Calculate quantiles
        p_df = p_df.copy()
        p_df['q'] = pd.qcut(p_df['rt_ms'], 5, labels=['Q1','Q2','Q3','Q4','Q5'])
        res = {}
        for q in ['Q1','Q2','Q3','Q4','Q5']:
            q_df = p_df[p_df['q'] == q]
            m_con = q_df[q_df['condition'] == 'congruent']['rt_ms'].mean()
            m_inc = q_df[q_df['condition'] == 'incongruent']['rt_ms'].mean()
            if pd.isna(m_con) or pd.isna(m_inc):
                res[q] = 0.0
            else:
                res[q] = m_inc - m_con
        return pd.Series(res)

    q_effects = df_valid.groupby('participant').apply(get_quintile_simon)
    gt_delta_plot = q_effects.mean().to_dict()
    
    return gt_individuals, gt_group_mean, gt_delta_plot


def verify_simon_delta_plot_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # --- Step 1: Extract files ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json, \
         tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        json_path = tmp_json.name
        csv_path = tmp_csv.name

    try:
        copy_from_env('/home/ga/pebl/analysis/simon_report.json', json_path)
        with open(json_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/simon_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
        
    try:
        copy_from_env('/home/ga/pebl/data/simon_task_data.csv', csv_path)
        gt_individuals, gt_group_mean, gt_delta_plot = compute_ground_truth(csv_path)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f"Failed to compute Ground Truth: {e}"}
    finally:
        for p in [json_path, csv_path]:
            if os.path.exists(p): os.unlink(p)

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
        return False

    # --- Criterion 2: s99 excluded ---
    if is_excluded(CONTAMINATED_PARTICIPANT):
        score += 20
        feedback_parts.append('[+20] Participant s99 correctly excluded.')
    else:
        feedback_parts.append('[0] Participant s99 not properly excluded.')

    # --- Criterion 3: 25 real participants present ---
    real_pids = set(gt_individuals.keys())
    present_real = real_pids.intersection(part_map.keys())
    
    if len(present_real) == 25:
        score += 10
        feedback_parts.append('[+10] All 25 valid participants present.')
    else:
        feedback_parts.append(f'[0] Only {len(present_real)}/25 valid participants present.')

    # --- Criterion 4: Individual Simon effects within ±5ms ---
    correct_simon = 0
    for pid in present_real:
        entry = part_map.get(pid, {})
        agent_se = entry.get('simon_effect_ms')
        if agent_se is not None:
            try:
                if abs(float(agent_se) - gt_individuals[pid]) <= 5.0:
                    correct_simon += 1
            except (TypeError, ValueError):
                pass

    if correct_simon >= 20:
        score += 20
        feedback_parts.append(f'[+20] Individual Simon effects highly accurate ({correct_simon}/25).')
    elif correct_simon >= 10:
        score += 10
        feedback_parts.append(f'[+10] Individual Simon effects partially accurate ({correct_simon}/25).')
    else:
        feedback_parts.append(f'[0] Individual Simon effects inaccurate (only {correct_simon}/25 correct).')

    # --- Criterion 5: Group mean Simon effect within ±3ms ---
    agent_group_mean = report.get('group_mean_simon_effect_ms')
    if agent_group_mean is not None:
        try:
            if abs(float(agent_group_mean) - gt_group_mean) <= 3.0:
                score += 15
                feedback_parts.append('[+15] Group mean Simon effect correct.')
            else:
                feedback_parts.append(f'[0] Group mean incorrect (got {agent_group_mean}, expected ~{gt_group_mean:.1f}).')
        except (TypeError, ValueError):
            feedback_parts.append('[0] Invalid group mean value type.')
    else:
        feedback_parts.append('[0] group_mean_simon_effect_ms key missing.')

    # --- Criterion 6 & 7: Delta Plot ---
    agent_dp = report.get('group_delta_plot')
    if isinstance(agent_dp, dict) and all(q in agent_dp for q in ['Q1','Q2','Q3','Q4','Q5']):
        score += 10
        feedback_parts.append('[+10] Delta plot structure correct.')
        
        # Check values
        dp_correct = True
        for q in ['Q1','Q2','Q3','Q4','Q5']:
            try:
                if abs(float(agent_dp[q]) - gt_delta_plot[q]) > 8.0:
                    dp_correct = False
            except:
                dp_correct = False
        
        # Check characteristic pattern (decreasing slope)
        try:
            q1_val = float(agent_dp['Q1'])
            q5_val = float(agent_dp['Q5'])
            pattern_ok = (q1_val - q5_val) > 15.0
            
            if dp_correct and pattern_ok:
                score += 15
                feedback_parts.append('[+15] Delta plot values accurate and reveal expected downward slope.')
            elif pattern_ok:
                score += 7
                feedback_parts.append('[+7] Delta plot shows correct downward trend, but specific values differ slightly.')
            else:
                feedback_parts.append('[0] Delta plot lacks the characteristic downward signature or has incorrect values.')
        except:
            feedback_parts.append('[0] Failed to parse delta plot values.')
    else:
        feedback_parts.append('[0] Missing or malformed group_delta_plot (needs Q1-Q5).')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }