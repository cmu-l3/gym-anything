#!/usr/bin/env python3
"""
Verifier for Brain Tumor Edema Index Assessment task.

Scoring System (100 points total):
- Edema Volume Accuracy: 25 points (within ±25% of ground truth)
- Core Volume Accuracy: 25 points (within ±25% of ground truth)
- PEI Ratio Accuracy: 20 points (within ±30% of ground truth)
- Prognostic Classification: 15 points (correct Low/Moderate/High)
- Report Completeness: 10 points (all required fields present)
- Valid JSON: 5 points (file parses correctly)

Pass Threshold: 60 points with both volume accuracies achieved
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_tumor_edema_index(traj, env_info, task_info):
    """
    Verify the edema index task completion.
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    volume_error_max = thresholds.get('volume_error_max_percent', 25) / 100.0
    pei_error_max = thresholds.get('pei_error_max_percent', 30) / 100.0
    
    w_edema = weights.get('edema_volume_accuracy', 25)
    w_core = weights.get('core_volume_accuracy', 25)
    w_pei = weights.get('pei_ratio_accuracy', 20)
    w_class = weights.get('prognostic_classification', 15)
    w_completeness = weights.get('report_completeness', 10)
    w_json = weights.get('report_valid_json', 5)
    
    # Initialize scoring
    score = {
        'edema_volume_accuracy': 0,
        'core_volume_accuracy': 0,
        'pei_ratio_accuracy': 0,
        'prognostic_classification': 0,
        'report_completeness': 0,
        'report_valid_json': 0,
        'total': 0
    }
    feedback = []
    details = {}
    
    # Copy result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env('/tmp/edema_task_result.json', temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        feedback.append("3D Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": "; ".join(feedback)
        }
    
    if not result.get('report_exists', False):
        feedback.append("Agent report file not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "; ".join(feedback)
        }
    
    # Anti-gaming: check if report was created during task
    if not result.get('report_created_during_task', False):
        feedback.append("WARNING: Report timestamp suggests it was not created during task")
        details['anti_gaming_warning'] = True
    
    # Check JSON validity
    if result.get('report_valid_json', False):
        score['report_valid_json'] = w_json
        feedback.append(f"Report is valid JSON (+{w_json})")
    else:
        feedback.append("Report is NOT valid JSON")
        score['total'] = sum(v for k, v in score.items() if k != 'total')
        return {
            "passed": False,
            "score": score['total'],
            "feedback": "; ".join(feedback),
            "details": score
        }
    
    # Load agent report
    temp_agent = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_report = {}
    try:
        copy_from_env('/tmp/agent_edema_report.json', temp_agent.name)
        with open(temp_agent.name, 'r') as f:
            agent_report = json.load(f)
    except Exception as e:
        feedback.append(f"Could not parse agent report: {e}")
        score['total'] = sum(v for k, v in score.items() if k != 'total')
        return {
            "passed": False,
            "score": score['total'],
            "feedback": "; ".join(feedback),
            "details": score
        }
    finally:
        if os.path.exists(temp_agent.name):
            os.unlink(temp_agent.name)
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ground_truth = {}
    try:
        copy_from_env('/tmp/ground_truth_edema.json', temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        feedback.append(f"Could not load ground truth: {e}")
        score['total'] = sum(v for k, v in score.items() if k != 'total')
        return {
            "passed": False,
            "score": score['total'],
            "feedback": "; ".join(feedback),
            "details": score
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Store ground truth values in details
    details['ground_truth'] = {
        'edema_volume_ml': ground_truth.get('edema_volume_ml', 0),
        'core_volume_ml': ground_truth.get('core_volume_ml', 0),
        'pei_ratio': ground_truth.get('pei_ratio', 0),
        'prognostic_class': ground_truth.get('prognostic_class', '')
    }
    
    # ================================================================
    # Check report completeness
    # ================================================================
    required_fields = ['edema_volume_ml', 'core_volume_ml', 'pei_ratio', 'prognostic_class', 'patient_id']
    present_fields = [f for f in required_fields if f in agent_report and agent_report[f] not in [None, '', 'null']]
    
    completeness_ratio = len(present_fields) / len(required_fields)
    if completeness_ratio == 1.0:
        score['report_completeness'] = w_completeness
        feedback.append(f"All required fields present (+{w_completeness})")
    else:
        missing = set(required_fields) - set(present_fields)
        partial_score = int(w_completeness * completeness_ratio)
        score['report_completeness'] = partial_score
        feedback.append(f"Missing fields: {missing} (+{partial_score})")
    
    details['agent_report'] = agent_report
    
    # ================================================================
    # Verify edema volume (±25% tolerance)
    # ================================================================
    gt_edema = float(ground_truth.get('edema_volume_ml', 0))
    agent_edema = 0.0
    try:
        agent_edema = float(agent_report.get('edema_volume_ml', 0))
    except (ValueError, TypeError):
        agent_edema = 0.0
    
    details['edema_comparison'] = {
        'agent': agent_edema,
        'ground_truth': gt_edema
    }
    
    if gt_edema > 0 and agent_edema > 0:
        edema_error = abs(agent_edema - gt_edema) / gt_edema
        details['edema_comparison']['error_ratio'] = edema_error
        
        if edema_error <= volume_error_max:
            score['edema_volume_accuracy'] = w_edema
            feedback.append(f"Edema volume accurate: {agent_edema:.2f} vs {gt_edema:.2f} mL (error: {edema_error*100:.1f}%) (+{w_edema})")
        elif edema_error <= 0.50:
            partial = w_edema // 2
            score['edema_volume_accuracy'] = partial
            feedback.append(f"Edema volume partially accurate: {agent_edema:.2f} vs {gt_edema:.2f} mL (error: {edema_error*100:.1f}%) (+{partial})")
        else:
            feedback.append(f"Edema volume inaccurate: {agent_edema:.2f} vs {gt_edema:.2f} mL (error: {edema_error*100:.1f}%)")
    else:
        feedback.append(f"Could not verify edema volume: agent={agent_edema}, gt={gt_edema}")
    
    # ================================================================
    # Verify core volume (±25% tolerance)
    # ================================================================
    gt_core = float(ground_truth.get('core_volume_ml', 0))
    agent_core = 0.0
    try:
        agent_core = float(agent_report.get('core_volume_ml', 0))
    except (ValueError, TypeError):
        agent_core = 0.0
    
    details['core_comparison'] = {
        'agent': agent_core,
        'ground_truth': gt_core
    }
    
    if gt_core > 0 and agent_core > 0:
        core_error = abs(agent_core - gt_core) / gt_core
        details['core_comparison']['error_ratio'] = core_error
        
        if core_error <= volume_error_max:
            score['core_volume_accuracy'] = w_core
            feedback.append(f"Core volume accurate: {agent_core:.2f} vs {gt_core:.2f} mL (error: {core_error*100:.1f}%) (+{w_core})")
        elif core_error <= 0.50:
            partial = w_core // 2
            score['core_volume_accuracy'] = partial
            feedback.append(f"Core volume partially accurate: {agent_core:.2f} vs {gt_core:.2f} mL (error: {core_error*100:.1f}%) (+{partial})")
        else:
            feedback.append(f"Core volume inaccurate: {agent_core:.2f} vs {gt_core:.2f} mL (error: {core_error*100:.1f}%)")
    else:
        feedback.append(f"Could not verify core volume: agent={agent_core}, gt={gt_core}")
    
    # ================================================================
    # Verify PEI ratio (±30% tolerance)
    # ================================================================
    gt_pei = float(ground_truth.get('pei_ratio', 0))
    agent_pei = 0.0
    try:
        agent_pei = float(agent_report.get('pei_ratio', 0))
    except (ValueError, TypeError):
        agent_pei = 0.0
    
    details['pei_comparison'] = {
        'agent': agent_pei,
        'ground_truth': gt_pei
    }
    
    # Check internal consistency: does reported PEI match reported volumes?
    if agent_core > 0:
        calculated_pei = agent_edema / agent_core
        pei_consistency_error = abs(calculated_pei - agent_pei)
        if pei_consistency_error > 0.1:
            feedback.append(f"NOTE: Reported PEI ({agent_pei:.3f}) differs from calculation ({calculated_pei:.3f})")
            details['pei_comparison']['consistency_warning'] = True
    
    if gt_pei > 0 and agent_pei > 0:
        pei_error = abs(agent_pei - gt_pei) / gt_pei
        details['pei_comparison']['error_ratio'] = pei_error
        
        if pei_error <= pei_error_max:
            score['pei_ratio_accuracy'] = w_pei
            feedback.append(f"PEI ratio accurate: {agent_pei:.3f} vs {gt_pei:.3f} (error: {pei_error*100:.1f}%) (+{w_pei})")
        elif pei_error <= 0.50:
            partial = w_pei // 2
            score['pei_ratio_accuracy'] = partial
            feedback.append(f"PEI ratio partially accurate: {agent_pei:.3f} vs {gt_pei:.3f} (error: {pei_error*100:.1f}%) (+{partial})")
        else:
            feedback.append(f"PEI ratio inaccurate: {agent_pei:.3f} vs {gt_pei:.3f} (error: {pei_error*100:.1f}%)")
    elif gt_pei == 0 and agent_pei == 0:
        # Both zero is technically correct
        score['pei_ratio_accuracy'] = w_pei
        feedback.append(f"PEI ratio correct (both zero) (+{w_pei})")
    else:
        feedback.append(f"Could not verify PEI ratio: agent={agent_pei}, gt={gt_pei}")
    
    # ================================================================
    # Verify prognostic classification
    # ================================================================
    gt_class = ground_truth.get('prognostic_class', '').strip().lower()
    agent_class = str(agent_report.get('prognostic_class', '')).strip().lower()
    
    details['classification_comparison'] = {
        'agent': agent_class,
        'ground_truth': gt_class
    }
    
    if gt_class and agent_class:
        if gt_class == agent_class:
            score['prognostic_classification'] = w_class
            feedback.append(f"Prognostic classification correct: {agent_class.title()} (+{w_class})")
        else:
            # Check if classification is consistent with agent's reported PEI
            expected_class_from_agent_pei = None
            if agent_pei < 2.0:
                expected_class_from_agent_pei = 'low'
            elif agent_pei <= 4.0:
                expected_class_from_agent_pei = 'moderate'
            else:
                expected_class_from_agent_pei = 'high'
            
            if expected_class_from_agent_pei == agent_class:
                # Classification is wrong vs GT but consistent with agent's (wrong) PEI
                partial = w_class // 3
                score['prognostic_classification'] = partial
                feedback.append(f"Classification consistent with reported PEI but wrong vs GT: {agent_class.title()} vs {gt_class.title()} (+{partial})")
            else:
                feedback.append(f"Prognostic classification incorrect: {agent_class.title()} vs {gt_class.title()}")
    else:
        feedback.append("Could not verify prognostic classification (missing value)")
    
    # ================================================================
    # Calculate total score
    # ================================================================
    score['total'] = sum(v for k, v in score.items() if k != 'total')
    
    # Determine pass/fail
    # Must have ≥60 points AND both volume accuracies achieved (≥ full points)
    edema_vol_achieved = score['edema_volume_accuracy'] >= w_edema
    core_vol_achieved = score['core_volume_accuracy'] >= w_core
    
    passed = (score['total'] >= 60 and edema_vol_achieved and core_vol_achieved)
    
    feedback.append(f"Total score: {score['total']}/100")
    
    if passed:
        feedback.append("PASSED: Score ≥60 with both volume accuracies achieved")
    else:
        reasons = []
        if score['total'] < 60:
            reasons.append(f"Score {score['total']} < 60 threshold")
        if not edema_vol_achieved:
            reasons.append("Edema volume accuracy not achieved")
        if not core_vol_achieved:
            reasons.append("Core volume accuracy not achieved")
        feedback.append(f"FAILED: {'; '.join(reasons)}")
    
    return {
        "passed": passed,
        "score": score['total'],
        "feedback": "; ".join(feedback),
        "details": {
            "subscores": score,
            "comparisons": details,
            "thresholds": {
                "volume_error_max": volume_error_max,
                "pei_error_max": pei_error_max
            }
        }
    }


def main():
    """Test the verifier locally."""
    import shutil
    
    def mock_copy(src, dst):
        if os.path.exists(src):
            shutil.copy(src, dst)
        else:
            raise FileNotFoundError(f"Source not found: {src}")
    
    # Create mock data for testing
    test_result = {
        "sample_id": "BraTS2021_00000",
        "slicer_was_running": True,
        "report_exists": True,
        "report_valid_json": True,
        "report_created_during_task": True
    }
    
    test_gt = {
        "edema_volume_ml": 50.0,
        "core_volume_ml": 25.0,
        "pei_ratio": 2.0,
        "prognostic_class": "Moderate"
    }
    
    test_agent = {
        "edema_volume_ml": 48.5,
        "core_volume_ml": 24.2,
        "pei_ratio": 2.0,
        "prognostic_class": "Moderate",
        "patient_id": "BraTS2021_00000"
    }
    
    # Write test files
    with open('/tmp/edema_task_result.json', 'w') as f:
        json.dump(test_result, f)
    with open('/tmp/ground_truth_edema.json', 'w') as f:
        json.dump(test_gt, f)
    with open('/tmp/agent_edema_report.json', 'w') as f:
        json.dump(test_agent, f)
    
    env_info = {'copy_from_env': mock_copy}
    task_info = {'metadata': {}}
    
    result = verify_tumor_edema_index({}, env_info, task_info)
    
    print(f"Passed: {result['passed']}")
    print(f"Score: {result['score']}")
    print(f"Feedback: {result['feedback']}")
    print(f"Details: {json.dumps(result.get('details', {}), indent=2)}")
    
    # Cleanup
    for f in ['/tmp/edema_task_result.json', '/tmp/ground_truth_edema.json', '/tmp/agent_edema_report.json']:
        if os.path.exists(f):
            os.unlink(f)


if __name__ == "__main__":
    main()