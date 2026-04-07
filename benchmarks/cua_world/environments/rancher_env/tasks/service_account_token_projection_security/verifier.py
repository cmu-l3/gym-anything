#!/usr/bin/env python3
"""
Verifier for service_account_token_projection_security task.

Scoring (100 points total, Pass threshold: 80):
- C1 (15 pts): public-api automountServiceAccountToken is False
- C2 (15 pts): k8s-sync-worker SA exists and is used by the deployment
- C3 (15 pts): vault-auth-proxy automountServiceAccountToken is False
- C4 (20 pts): vault-auth-proxy has projected volume (audience: vault, exp: 7200) mounted at correct path
- C5 (20 pts): All three deployments have >= 1 Running pod (ensures syntax is valid and schedulable)
- C6 (15 pts): VLM verifies agent actively worked in the environment (terminal or Rancher UI)
"""

import json
import tempfile
import os
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logger = logging.getLogger(__name__)


def verify_service_account_token_projection_security(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/task_result.json"
    
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result file: {e}"}

    score = 0
    feedback_parts = []

    # C1: public-api secured
    pub_api = result.get("public_api", {})
    if pub_api.get("automount") is False:
        score += 15
        feedback_parts.append("C1 PASS (15): public-api automountServiceAccountToken is disabled")
    else:
        feedback_parts.append("C1 FAIL (0): public-api automountServiceAccountToken is true or omitted")

    # C2: k8s-sync-worker SA
    sync_worker = result.get("k8s_sync_worker", {})
    sa_exists = result.get("sa_exists", False)
    uses_sa = sync_worker.get("sa_name") == "sync-worker-sa"
    
    if sa_exists and uses_sa:
        score += 15
        feedback_parts.append("C2 PASS (15): k8s-sync-worker uses dedicated sync-worker-sa")
    else:
        feedback_parts.append(f"C2 FAIL (0): SA exists: {sa_exists}, Uses SA: {uses_sa}")

    # C3: vault-auth-proxy secured (no default token)
    vault_proxy = result.get("vault_auth_proxy", {})
    if vault_proxy.get("automount") is False:
        score += 15
        feedback_parts.append("C3 PASS (15): vault-auth-proxy automountServiceAccountToken is disabled")
    else:
        feedback_parts.append("C3 FAIL (0): vault-auth-proxy automountServiceAccountToken is true or omitted")

    # C4: vault-auth-proxy projected volume
    c4_pass = False
    for pv_item in vault_proxy.get("projected_vols", []):
        name = pv_item.get("name")
        pv = pv_item.get("projected", {})
        has_correct_token = False
        
        for src in pv.get("sources", []):
            token = src.get("serviceAccountToken")
            if token and token.get("audience") == "vault" and str(token.get("expirationSeconds")) == "7200":
                has_correct_token = True
                break
                
        if has_correct_token:
            for m in vault_proxy.get("mounts", []):
                if m.get("name") == name and m.get("mountPath") == "/var/run/secrets/kubernetes.io/vault":
                    c4_pass = True
                    break
                    
        if c4_pass:
            break

    if c4_pass:
        score += 20
        feedback_parts.append("C4 PASS (20): vault-auth-proxy has properly bound projected token volume")
    else:
        feedback_parts.append("C4 FAIL (0): vault-auth-proxy lacks correct projected token volume or mount")

    # C5: All Workloads Running
    running_counts = result.get("pods_running", {})
    if running_counts.get("public-api", 0) >= 1 and \
       running_counts.get("k8s-sync-worker", 0) >= 1 and \
       running_counts.get("vault-auth-proxy", 0) >= 1:
        score += 20
        feedback_parts.append("C5 PASS (20): All deployments successfully rolled out and are Running")
    else:
        feedback_parts.append(f"C5 FAIL (0): Pods running state: {running_counts} (Syntax error or Pending)")

    # C6: VLM Trajectory check
    c6_score = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            Look at these screenshots from a session. 
            Did the user use the terminal (kubectl) or the Rancher UI to edit Kubernetes configurations 
            (Deployments/Pods/ServiceAccounts) or view the identity_security_spec.yaml file?
            Reply in JSON format: {"edited_k8s": true/false}
            """
            vlm_resp = query_vlm(images=images, prompt=prompt)
            if vlm_resp and vlm_resp.get("parsed", {}).get("edited_k8s", False):
                c6_score = 15
                feedback_parts.append("C6 PASS (15): VLM confirmed trajectory activity")
            else:
                feedback_parts.append("C6 FAIL (0): VLM did not detect relevant cluster activity")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("C6 FAIL (0): VLM error")
    else:
        # Give benefit of the doubt if VLM is unavailable
        c6_score = 15
        feedback_parts.append("C6 PASS (15): VLM unavailable, auto-granting activity points")
        
    score += c6_score

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 80)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }