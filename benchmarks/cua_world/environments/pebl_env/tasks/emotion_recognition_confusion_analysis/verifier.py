#!/usr/bin/env python3
"""
Verifier for emotion_recognition_confusion_analysis task.

Checks:
1. Valid JSON format and file creation timestamps (10 pts)
2. Bot correctly excluded (<25% accuracy constraint) (20 pts)
3. Amygdala Deficit correctly excluded (Fear < 10%, others > 70%) (20 pts)
4. Individual accuracies properly computed (checked against ground truth) (20 pts)
5. Group confusion matrix probabilities computed correctly (15 pts)
6. Group confusion matrix rows normalized correctly to 1.0 (15 pts)

Pass threshold: 65 points + key constraints met
"""

import json
import os
import tempfile

def verify_emotion_recognition_confusion_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Check Metadata
    meta = {}
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        try:
            copy_from_env('/tmp/task_meta.json', tmp.name)
            with open(tmp.name, 'r') as f:
                meta = json.load(f)
        except Exception:
            pass
        finally:
            os.unlink(tmp.name)

    if not meta.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    if not meta.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file was not created or modified during the task window."}

    # 2. Load Ground Truth
    gt = {}
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        try:
            copy_from_env('/tmp/ground_truth.json', tmp.name)
            with open(tmp.name, 'r') as f:
                gt = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
        finally:
            os.unlink(tmp.name)

    # 3. Load Agent JSON Report
    report = {}
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        try:
            copy_from_env('/home/ga/pebl/analysis/emotion_report.json', tmp.name)
            with open(tmp.name, 'r') as f:
                report = json.load(f)
            score += 10
            feedback.append("[+10] Valid JSON output found.")
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Output file is not valid JSON: {e}"}
        finally:
            os.unlink(tmp.name)

    part_list = report.get('participants', [])
    part_map = {str(p.get('id')): p for p in part_list if 'id' in p}

    # 4. Bot Exclusion Check (sub-BOT)
    bot_excluded = False
    bot_entry = part_map.get('sub-BOT')
    if bot_entry and str(bot_entry.get('excluded')).lower() == 'true':
        score += 20
        bot_excluded = True
        feedback.append("[+20] Correctly excluded random responder (sub-BOT).")
    else:
        feedback.append("[0] Failed to exclude sub-BOT.")

    # 5. Amygdala Deficit Exclusion Check (sub-AMY)
    amy_excluded = False
    amy_entry = part_map.get('sub-AMY')
    if amy_entry and str(amy_entry.get('excluded')).lower() == 'true':
        score += 20
        amy_excluded = True
        feedback.append("[+20] Correctly excluded Amygdala deficit case (sub-AMY).")
    else:
        feedback.append("[0] Failed to exclude sub-AMY.")

    # 6. Check Individual Accuracies
    acc_correct = True
    test_ppts = ['sub-01', 'sub-10', 'sub-25']
    for p in test_ppts:
        if p not in part_map:
            acc_correct = False
            continue
        entry = part_map[p]
        gt_indiv = gt['individual'].get(p, {})
        
        try:
            o_acc = float(entry.get('overall_accuracy', -1))
            if abs(o_acc - gt_indiv.get('overall', 0)) > 0.02:
                acc_correct = False
            
            em_accs = entry.get('emotion_accuracy', {})
            for em, acc in gt_indiv.get('emotions', {}).items():
                a_acc = None
                for k, v in em_accs.items():
                    if k.lower() == em.lower():
                        a_acc = float(v)
                        break
                if a_acc is None or abs(a_acc - acc) > 0.02:
                    acc_correct = False
        except (ValueError, TypeError):
            acc_correct = False

    if acc_correct:
        score += 20
        feedback.append("[+20] Individual accuracies calculated correctly.")
    else:
        feedback.append("[0] Individual accuracies incorrect or missing.")

    # 7. Check Group Matrix Calculation
    matrix_correct = True
    agent_matrix = report.get('group_confusion_matrix', {})
    gt_matrix = gt.get('matrix', {})
    
    def get_ci(d, key):
        """Case-insensitive dictionary lookup."""
        if not isinstance(d, dict): return None
        for k, v in d.items():
            if k.lower() == key.lower():
                return v
        return None

    for te, responses in gt_matrix.items():
        agent_row = get_ci(agent_matrix, te)
        if not agent_row:
            matrix_correct = False
            break
        for re, prob in responses.items():
            agent_prob = get_ci(agent_row, re)
            if agent_prob is None:
                matrix_correct = False
                break
            try:
                if abs(float(agent_prob) - prob) > 0.025:
                    matrix_correct = False
                    break
            except (ValueError, TypeError):
                matrix_correct = False
                break

    if matrix_correct:
        score += 15
        feedback.append("[+15] Group confusion matrix calculated correctly.")
    else:
        feedback.append("[0] Group confusion matrix incorrect.")

    # 8. Check Matrix Normalization
    matrix_normalized = True
    for te in gt_matrix.keys():
        agent_row = get_ci(agent_matrix, te)
        if not agent_row:
            matrix_normalized = False
            break
        try:
            row_sum = sum(float(v) for v in agent_row.values())
            if abs(row_sum - 1.0) > 0.005:
                matrix_normalized = False
        except (ValueError, TypeError):
            matrix_normalized = False

    if matrix_normalized:
        score += 15
        feedback.append("[+15] Group confusion matrix is properly normalized.")
    else:
        feedback.append("[0] Group confusion matrix rows do not sum to 1.0.")

    passed = (score >= 65) and (bot_excluded or amy_excluded) and matrix_normalized

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }