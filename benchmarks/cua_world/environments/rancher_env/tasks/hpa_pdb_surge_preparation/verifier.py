#!/usr/bin/env python3
"""
Verifier for hpa_pdb_surge_preparation task.

Scoring (100 points total, Pass threshold: 70):
For each of the 4 microservices:
- HPA is correct (15 points)
- PDB is correct (10 points)

Verifies programmatic definitions natively without visual/VLM dependencies as K8s state is ground truth.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_hpa_pdb_surge_preparation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve output
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/hpa_pdb_result.json", tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    hpas = result.get("hpas", {}).get("items", [])
    pdbs = result.get("pdbs", {}).get("items", [])

    score = 0
    feedback_parts = []

    def check_hpa(target_name, expected_min, expected_max, expected_cpu):
        for hpa in hpas:
            spec = hpa.get("spec", {})
            ref = spec.get("scaleTargetRef", {})
            if ref.get("name") == target_name:
                actual_min = spec.get("minReplicas")
                actual_max = spec.get("maxReplicas")
                
                # Retrieve CPU target generically, covering both autoscaling/v1 and autoscaling/v2(beta)
                actual_cpu = None
                if "targetCPUUtilizationPercentage" in spec:
                    actual_cpu = spec["targetCPUUtilizationPercentage"]
                elif "metrics" in spec:
                    for m in spec["metrics"]:
                        if m.get("type") == "Resource" and m.get("resource", {}).get("name") == "cpu":
                            target = m.get("resource", {}).get("target", {})
                            actual_cpu = target.get("averageUtilization")

                if actual_min == expected_min and actual_max == expected_max and actual_cpu == expected_cpu:
                    return True, f"HPA correct for {target_name}"
                else:
                    return False, f"HPA mismatch for {target_name} (Got min:{actual_min}, max:{actual_max}, cpu:{actual_cpu})"
        return False, f"No HPA targeting {target_name} found"

    def check_pdb(target_name, expected_key, expected_val):
        for pdb in pdbs:
            spec = pdb.get("spec", {})
            selector = spec.get("selector", {}).get("matchLabels", {})
            
            # Check if this PDB selects the target application
            if selector.get("app") == target_name:
                other_key = "maxUnavailable" if expected_key == "minAvailable" else "minAvailable"
                
                # Validate mutually exclusive constraints 
                if expected_key in spec and other_key not in spec:
                    val = spec[expected_key]
                    if str(val) == str(expected_val):
                        return True, f"PDB correct for {target_name}"
                    return False, f"PDB mismatch for {target_name} (Got {expected_key}={val})"
                
                return False, f"PDB keys invalid for {target_name} (Got min:{spec.get('minAvailable')} max:{spec.get('maxUnavailable')})"
        return False, f"No PDB selecting app:{target_name} found"

    # Evaluate checkout-api
    ok, msg = check_hpa("checkout-api", 2, 10, 70)
    if ok:
        score += 15
        feedback_parts.append(f"PASS C1: {msg}")
    else:
        feedback_parts.append(f"FAIL C1: {msg}")

    ok, msg = check_pdb("checkout-api", "minAvailable", 1)
    if ok:
        score += 10
        feedback_parts.append(f"PASS C2: {msg}")
    else:
        feedback_parts.append(f"FAIL C2: {msg}")

    # Evaluate product-catalog
    ok, msg = check_hpa("product-catalog", 3, 15, 60)
    if ok:
        score += 15
        feedback_parts.append(f"PASS C3: {msg}")
    else:
        feedback_parts.append(f"FAIL C3: {msg}")

    ok, msg = check_pdb("product-catalog", "minAvailable", 2)
    if ok:
        score += 10
        feedback_parts.append(f"PASS C4: {msg}")
    else:
        feedback_parts.append(f"FAIL C4: {msg}")

    # Evaluate search-service
    ok, msg = check_hpa("search-service", 2, 12, 65)
    if ok:
        score += 15
        feedback_parts.append(f"PASS C5: {msg}")
    else:
        feedback_parts.append(f"FAIL C5: {msg}")

    ok, msg = check_pdb("search-service", "maxUnavailable", 1)
    if ok:
        score += 10
        feedback_parts.append(f"PASS C6: {msg}")
    else:
        feedback_parts.append(f"FAIL C6: {msg}")

    # Evaluate payment-gateway
    ok, msg = check_hpa("payment-gateway", 2, 6, 50)
    if ok:
        score += 15
        feedback_parts.append(f"PASS C7: {msg}")
    else:
        feedback_parts.append(f"FAIL C7: {msg}")

    ok, msg = check_pdb("payment-gateway", "minAvailable", 2)
    if ok:
        score += 10
        feedback_parts.append(f"PASS C8: {msg}")
    else:
        feedback_parts.append(f"FAIL C8: {msg}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }