#!/usr/bin/env python3

import json
import tempfile
import os

def verify_qos_class_guarantee_remediation(traj, env_info, task_info):
    """
    Verify the QoS Class Remediation task.
    
    C1 (25 pts): auth-service pods are Running with qosClass == Guaranteed
    C2 (25 pts): payment-api pods are Running with qosClass == Guaranteed
    C3 (15 pts): payment-api achieved Guaranteed WITHOUT deleting config-loader init-container
    C4 (35 pts): data-warehouse-sync pods are Running with qosClass in [Burstable, BestEffort]
    
    Pass threshold: 75
    """
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    result_path = '/tmp/qos_task_result.json'
    score = 0
    feedback_parts = []

    try:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name

        copy_from_env(result_path, tmp_path)

        with open(tmp_path, 'r') as f:
            result = json.load(f)

        os.unlink(tmp_path)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Failed to read result file: {e}'}

    # Helper function to evaluate pod states
    def evaluate_pods(pods, expected_qos):
        running_pods = [p for p in pods if p.get('phase') == 'Running']
        if not running_pods:
            return False, "No running pods"
        
        # Ensure at least one running pod has the expected QoS
        for p in running_pods:
            qos = p.get('qosClass')
            if isinstance(expected_qos, list):
                if qos in expected_qos:
                    return True, f"Running ({qos})"
            else:
                if qos == expected_qos:
                    return True, f"Running ({qos})"
                    
        return False, f"Running but incorrect QoS (got {running_pods[0].get('qosClass')})"

    # C1: auth-service (Guaranteed)
    auth_pods = result.get('auth_service', [])
    c1_pass, c1_msg = evaluate_pods(auth_pods, 'Guaranteed')
    if c1_pass:
        score += 25
        feedback_parts.append('PASS C1 (25): auth-service is Guaranteed and Running')
    else:
        feedback_parts.append(f'FAIL C1 (0): auth-service {c1_msg}')

    # C2: payment-api (Guaranteed)
    pay_pods = result.get('payment_api', [])
    c2_pass, c2_msg = evaluate_pods(pay_pods, 'Guaranteed')
    if c2_pass:
        score += 25
        feedback_parts.append('PASS C2 (25): payment-api is Guaranteed and Running')
    else:
        feedback_parts.append(f'FAIL C2 (0): payment-api {c2_msg}')

    # C3: payment-api init-container preserved
    # Only award C3 if C2 passed AND the init container is still present.
    # This prevents gaining points by just taking the shortcut of deleting the init container.
    c3_pass = False
    if c2_pass:
        for p in pay_pods:
            if p.get('phase') == 'Running' and p.get('qosClass') == 'Guaranteed':
                if 'config-loader' in p.get('init_containers', []):
                    c3_pass = True
                    break
                    
    if c3_pass:
        score += 15
        feedback_parts.append('PASS C3 (15): payment-api config-loader init-container preserved')
    else:
        if c2_pass:
            feedback_parts.append('FAIL C3 (0): payment-api achieved Guaranteed by incorrectly deleting the init-container')
        else:
            feedback_parts.append('FAIL C3 (0): payment-api did not achieve Guaranteed status')

    # C4: data-warehouse-sync (Burstable or BestEffort)
    dws_pods = result.get('data_warehouse_sync', [])
    c4_pass, c4_msg = evaluate_pods(dws_pods, ['Burstable', 'BestEffort'])
    if c4_pass:
        score += 35
        feedback_parts.append(f'PASS C4 (35): data-warehouse-sync is correctly demoted to preemptible QoS {c4_msg}')
    else:
        feedback_parts.append(f'FAIL C4 (0): data-warehouse-sync {c4_msg}')

    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': " | ".join(feedback_parts)
    }