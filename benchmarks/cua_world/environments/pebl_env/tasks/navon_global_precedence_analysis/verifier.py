#!/usr/bin/env python3
"""
Verifier for navon_global_precedence_analysis task.

Computes ground truth directly from the agent's environment CSV copy 
to perfectly align with data generation variations, verifying the core logic.

Scoring (100 points):
- JSON Report valid & parsed: 10
- Anomaly exclusion correctly applied (accuracy <60% rule): 25
- Individual participant metrics accurate (within ±2ms): 30
- Group mean aggregations accurate (within ±2ms): 20
- Plot creation & validity verified via VLM: 15

Threshold: 70
"""

import json
import os
import tempfile
import csv
from collections import defaultdict
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def compute_gt(csv_path):
    """Calculates ground truth values from the CSV file based on task rules."""
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    # 1. Compute Accuracies
    acc_stats = defaultdict(lambda: {'global': {'c':0, 't':0}, 'local': {'c':0, 't':0}})
    for r in rows:
        p = r['participant_id']
        foc = r['attention_focus']
        acc_stats[p][foc]['c'] += int(r['correct'])
        acc_stats[p][foc]['t'] += 1
        
    valid_participants = []
    excluded_participants = []
    for p, stats in acc_stats.items():
        if stats['local']['t'] == 0: 
            continue
        l_acc = stats['local']['c'] / stats['local']['t']
        if l_acc < 0.60:
            excluded_participants.append(p)
        else:
            valid_participants.append(p)
            
    # 2. Compute RT Metrics
    gt_metrics = {}
    for p in valid_participants:
        p_rows = [r for r in rows if r['participant_id'] == p and int(r['correct']) == 1]
        
        rt_g_c = [int(r['rt_ms']) for r in p_rows if r['attention_focus'] == 'global' and r['congruency'] == 'congruent']
        rt_g_i = [int(r['rt_ms']) for r in p_rows if r['attention_focus'] == 'global' and r['congruency'] == 'incongruent']
        rt_l_c = [int(r['rt_ms']) for r in p_rows if r['attention_focus'] == 'local' and r['congruency'] == 'congruent']
        rt_l_i = [int(r['rt_ms']) for r in p_rows if r['attention_focus'] == 'local' and r['congruency'] == 'incongruent']
        rt_g = [int(r['rt_ms']) for r in p_rows if r['attention_focus'] == 'global']
        rt_l = [int(r['rt_ms']) for r in p_rows if r['attention_focus'] == 'local']
        
        m_g_c = sum(rt_g_c)/len(rt_g_c) if rt_g_c else 0
        m_g_i = sum(rt_g_i)/len(rt_g_i) if rt_g_i else 0
        m_l_c = sum(rt_l_c)/len(rt_l_c) if rt_l_c else 0
        m_l_i = sum(rt_l_i)/len(rt_l_i) if rt_l_i else 0
        m_g = sum(rt_g)/len(rt_g) if rt_g else 0
        m_l = sum(rt_l)/len(rt_l) if rt_l else 0
        
        gt_metrics[p] = {
            'global_advantage_ms': m_l - m_g,
            'global_interference_ms': m_l_i - m_l_c,
            'local_interference_ms': m_g_i - m_g_c
        }
        
    # 3. Compute Group Means
    gt_group = {
        'global_advantage_ms': sum(x['global_advantage_ms'] for x in gt_metrics.values()) / len(valid_participants) if valid_participants else 0,
        'global_interference_ms': sum(x['global_interference_ms'] for x in gt_metrics.values()) / len(valid_participants) if valid_participants else 0,
        'local_interference_ms': sum(x['local_interference_ms'] for x in gt_metrics.values()) / len(valid_participants) if valid_participants else 0
    }
    
    return gt_metrics, gt_group, excluded_participants


def verify_navon_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback = []

    # 1. Acquire & Parse Dataset to compute true Expected Ground Truth
    csv_tmp = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
    csv_path = csv_tmp.name
    csv_tmp.close()
    
    try:
        copy_from_env('/home/ga/pebl/data/navon_data.csv', csv_path)
        gt_metrics, gt_group, excluded_participants = compute_gt(csv_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or process source CSV: {e}"}
    finally:
        if os.path.exists(csv_path): 
            os.unlink(csv_path)

    if len(gt_metrics) < 10:
        return {"passed": False, "score": 0, "feedback": "Source data was maliciously modified or destroyed by agent."}

    # 2. Acquire & Parse Agent Report
    report_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    report_path = report_tmp.name
    report_tmp.close()
    
    report = None
    try:
        copy_from_env('/home/ga/pebl/analysis/navon_report.json', report_path)
        with open(report_path, 'r', encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback.append("[+10] Report exists and is valid JSON")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse report: {e}"}
    finally:
        if os.path.exists(report_path): 
            os.unlink(report_path)

    # Participant lookup map
    part_map = {}
    for entry in report.get('participants', []):
        pid = entry.get('id')
        if pid:
            part_map[str(pid)] = entry
            
    # 3. Anomaly Exclusion Check
    if 'sub-99' in excluded_participants:
        entry = part_map.get('sub-99')
        if entry and str(entry.get('excluded')).lower() in ('true', '1', 'yes'):
            score += 25
            feedback.append("[+25] Anomaly correctly excluded based on local focus accuracy threshold")
        else:
            feedback.append("[0] Anomaly sub-99 not correctly flagged/excluded")
            
    # 4. Individual Metrics Verification
    correct_metrics = 0
    total_metrics = 0
    
    for p, gt_m in gt_metrics.items():
        entry = part_map.get(str(p))
        if not entry or str(entry.get('excluded')).lower() in ('true', '1', 'yes'):
            continue
        
        for key in ['global_advantage_ms', 'global_interference_ms', 'local_interference_ms']:
            total_metrics += 1
            val = entry.get(key)
            if val is not None:
                try:
                    if abs(float(val) - gt_m[key]) <= 2.0:
                        correct_metrics += 1
                except ValueError:
                    pass
                    
    ratio = correct_metrics / total_metrics if total_metrics > 0 else 0
    metrics_score = int(30 * ratio)
    score += metrics_score
    feedback.append(f"[+{metrics_score}] Individual metrics ({correct_metrics}/{total_metrics} within ±2ms tolerance)")

    # 5. Group Means Verification
    grp = report.get('group_means', {})
    correct_grp = 0
    for key in ['global_advantage_ms', 'global_interference_ms', 'local_interference_ms']:
        val = grp.get(key)
        if val is not None:
            try:
                if abs(float(val) - gt_group[key]) <= 2.0:
                    correct_grp += 1
            except ValueError:
                pass
                
    grp_score = int((correct_grp / 3) * 20)
    score += grp_score
    feedback.append(f"[+{grp_score}] Group means ({correct_grp}/3 within ±2ms tolerance)")

    # 6. Plot Verification via Meta & VLM
    meta_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    meta_path = meta_tmp.name
    meta_tmp.close()
    
    plot_exists = False
    try:
        copy_from_env('/tmp/navon_meta.json', meta_path)
        with open(meta_path, 'r', encoding='utf-8') as f:
            meta = json.load(f)
            if meta.get('plot_exists') and meta.get('plot_created_during_task'):
                plot_exists = True
                score += 5
                feedback.append("[+5] Plot created during task execution (Anti-gaming verified)")
            elif meta.get('plot_exists'):
                feedback.append("[0] Plot exists but modified before task (Tampering detected)")
            else:
                feedback.append("[0] Plot file not found")
    except Exception:
        feedback.append("[0] Could not read metadata JSON")
    finally:
        if os.path.exists(meta_path): 
            os.unlink(meta_path)
        
    query_vlm = env_info.get('query_vlm')
    if plot_exists and query_vlm:
        plot_tmp = tempfile.NamedTemporaryFile(suffix='.png', delete=False)
        plot_img_path = plot_tmp.name
        plot_tmp.close()
        try:
            copy_from_env('/home/ga/pebl/analysis/navon_interaction_plot.png', plot_img_path)
            prompt = """You are evaluating an interaction plot generated from a Cognitive Psychology Navon Figures task.
            Determine if this image is a valid statistical plot (like a bar chart or line graph) representing Reaction Times across at least 4 key conditions (such as Global vs Local focus, and Congruent vs Incongruent).
            Respond strictly in JSON format without markdown wrappers: {"is_valid_plot": true/false}"""
            
            res = query_vlm(prompt=prompt, image=plot_img_path)
            if res and res.get('success'):
                parsed = res.get('parsed', {})
                if parsed.get('is_valid_plot', False):
                    score += 10
                    feedback.append("[+10] VLM verified the visual integrity of the interaction plot")
                else:
                    feedback.append("[0] VLM analyzed the plot but it lacked valid data visualization structure")
            else:
                feedback.append("[0] VLM verification request failed")
        except Exception as e:
            logger.error(f"VLM plotting error: {e}")
        finally:
            if os.path.exists(plot_img_path): 
                os.unlink(plot_img_path)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }