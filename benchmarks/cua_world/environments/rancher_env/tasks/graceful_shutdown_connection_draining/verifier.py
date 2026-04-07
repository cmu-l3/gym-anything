#!/usr/bin/env python3
import json
import tempfile
import os

def verify_graceful_shutdown(traj, env_info, task_info):
    """
    Verify the graceful shutdown configurations for 3 deployments.
    
    C1 (25 pts): Payment Processor
        - terminationGracePeriodSeconds == 60
        - preStop exec contains 'sleep 15' (allowing 'sleep 15', 'sleep', '15', '/bin/sh', '-c', etc.)
    C2 (25 pts): Cart Service
        - terminationGracePeriodSeconds == 45
        - preStop httpGet to /offline on port 80
    C3 (25 pts): Order Worker
        - terminationGracePeriodSeconds == 120
        - preStop exec contains '/usr/local/bin/checkpoint.sh'
    C4 (25 pts): Workload Health
        - All 3 deployments have status.readyReplicas >= 1
    
    Pass threshold: 75 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = '/tmp/graceful_shutdown_result.json'
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    deployments_list = result.get('deployments', {}).get('items', [])
    deployments = {d.get('metadata', {}).get('name'): d for d in deployments_list}

    score = 0
    feedback_parts = []
    
    # Check C1: payment-processor
    pp = deployments.get('payment-processor', {})
    pp_spec = pp.get('spec', {}).get('template', {}).get('spec', {})
    pp_tgps = pp_spec.get('terminationGracePeriodSeconds')
    pp_containers = pp_spec.get('containers', [])
    pp_prestop_exec = []
    if pp_containers:
        pp_prestop = pp_containers[0].get('lifecycle', {}).get('preStop', {})
        pp_prestop_exec = pp_prestop.get('exec', {}).get('command', [])
    
    pp_exec_str = " ".join(pp_prestop_exec)
    if pp_tgps == 60 and ("sleep" in pp_exec_str and "15" in pp_exec_str):
        score += 25
        feedback_parts.append("C1 PASS: payment-processor configured correctly (+25)")
    else:
        feedback_parts.append(f"C1 FAIL: payment-processor config incorrect (TGPS={pp_tgps}, exec={pp_exec_str})")

    # Check C2: cart-service
    cs = deployments.get('cart-service', {})
    cs_spec = cs.get('spec', {}).get('template', {}).get('spec', {})
    cs_tgps = cs_spec.get('terminationGracePeriodSeconds')
    cs_containers = cs_spec.get('containers', [])
    cs_http = {}
    if cs_containers:
        cs_prestop = cs_containers[0].get('lifecycle', {}).get('preStop', {})
        cs_http = cs_prestop.get('httpGet', {})
    
    cs_path = cs_http.get('path', '')
    cs_port = cs_http.get('port')
    if cs_tgps == 45 and cs_path == '/offline' and str(cs_port) == '80':
        score += 25
        feedback_parts.append("C2 PASS: cart-service configured correctly (+25)")
    else:
        feedback_parts.append(f"C2 FAIL: cart-service config incorrect (TGPS={cs_tgps}, path={cs_path}, port={cs_port})")

    # Check C3: order-worker
    ow = deployments.get('order-worker', {})
    ow_spec = ow.get('spec', {}).get('template', {}).get('spec', {})
    ow_tgps = ow_spec.get('terminationGracePeriodSeconds')
    ow_containers = ow_spec.get('containers', [])
    ow_prestop_exec = []
    if ow_containers:
        ow_prestop = ow_containers[0].get('lifecycle', {}).get('preStop', {})
        ow_prestop_exec = ow_prestop.get('exec', {}).get('command', [])
    
    ow_exec_str = " ".join(ow_prestop_exec)
    if ow_tgps == 120 and "/usr/local/bin/checkpoint.sh" in ow_exec_str:
        score += 25
        feedback_parts.append("C3 PASS: order-worker configured correctly (+25)")
    else:
        feedback_parts.append(f"C3 FAIL: order-worker config incorrect (TGPS={ow_tgps}, exec={ow_exec_str})")

    # Check C4: Workload Health
    healthy = True
    for name in ['payment-processor', 'cart-service', 'order-worker']:
        d = deployments.get(name, {})
        ready = d.get('status', {}).get('readyReplicas', 0)
        if ready < 1:
            healthy = False
            feedback_parts.append(f"C4 FAIL: {name} has {ready} ready replicas.")
            
    if healthy:
        score += 25
        feedback_parts.append("C4 PASS: All deployments are healthy (+25)")
    
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }