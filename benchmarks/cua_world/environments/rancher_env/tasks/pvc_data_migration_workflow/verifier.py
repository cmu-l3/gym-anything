#!/usr/bin/env python3
"""
Verifier for pvc_data_migration_workflow task.

Scoring System (100 points total, pass threshold: 80):
C1 (20 pts): New PVC `catalog-data-v2` exists, requests 5Gi, and is Bound.
C2 (20 pts): `catalog-service` Deployment uses ONLY `catalog-data-v2` (legacy removed).
C3 (20 pts): `catalog-service` has exactly 1 Ready pod in Running state.
C4 (40 pts): Data integrity - Both chinook.db and metadata JSON hashes match ground truth.

Anti-gaming:
- The metadata file has a randomized UUID, so the agent cannot just recreate the files. They MUST be copied from the old volume.
"""

import json
import os
import tempfile

def verify_pvc_data_migration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    result_file = '/tmp/pvc_data_migration_result.json'
    gt_file = '/tmp/ground_truth_checksums.json'

    score = 0
    feedback_parts = []

    try:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp_res:
            res_path = tmp_res.name
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp_gt:
            gt_path = tmp_gt.name

        copy_from_env(result_file, res_path)
        copy_from_env(gt_file, gt_path)

        with open(res_path, 'r') as f:
            result = json.load(f)
        with open(gt_path, 'r') as f:
            ground_truth = json.load(f)

        os.unlink(res_path)
        os.unlink(gt_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification files: {e}"}

    # ── C1: New PVC exists, 5Gi, Bound (20 pts) ────────────────────────────────
    pvcs = result.get('pvcs', [])
    new_pvc = next((p for p in pvcs if p.get('metadata', {}).get('name') == 'catalog-data-v2'), None)

    c1_pass = False
    if new_pvc:
        phase = new_pvc.get('status', {}).get('phase')
        capacity = new_pvc.get('spec', {}).get('resources', {}).get('requests', {}).get('storage')
        if phase == 'Bound' and capacity == '5Gi':
            c1_pass = True
            score += 20
            feedback_parts.append("PASS C1: catalog-data-v2 PVC created correctly (5Gi, Bound)")
        else:
            feedback_parts.append(f"FAIL C1: catalog-data-v2 PVC exists but phase={phase}, capacity={capacity}")
    else:
        feedback_parts.append("FAIL C1: catalog-data-v2 PVC not found")

    # ── C2: Deployment uses ONLY the new PVC (20 pts) ─────────────────────────
    deployment = result.get('deployment', {})
    volumes = deployment.get('spec', {}).get('template', {}).get('spec', {}).get('volumes', [])
    
    uses_v2 = False
    uses_legacy = False

    for vol in volumes:
        claim_name = vol.get('persistentVolumeClaim', {}).get('claimName', '')
        if claim_name == 'catalog-data-v2':
            uses_v2 = True
        elif claim_name == 'catalog-data-legacy':
            uses_legacy = True

    if uses_v2 and not uses_legacy:
        score += 20
        feedback_parts.append("PASS C2: Deployment exclusively mounts catalog-data-v2")
    else:
        if not uses_v2:
            feedback_parts.append("FAIL C2: Deployment does not mount catalog-data-v2")
        if uses_legacy:
            feedback_parts.append("FAIL C2: Deployment still mounts catalog-data-legacy (legacy reference not removed)")

    # ── C3: Deployment pod is Running (20 pts) ────────────────────────────────
    pods = result.get('pods', [])
    running_pods = [p for p in pods if p.get('status', {}).get('phase') == 'Running']
    
    if len(running_pods) >= 1:
        score += 20
        feedback_parts.append(f"PASS C3: {len(running_pods)} catalog-service pod(s) Running")
    else:
        feedback_parts.append("FAIL C3: No catalog-service pods are in Running phase")

    # ── C4: Data Integrity (40 pts) ───────────────────────────────────────────
    hashes = result.get('data_hashes', {})
    agent_chinook = hashes.get('chinook', '')
    agent_meta = hashes.get('metadata', '')
    
    gt_chinook = ground_truth.get('chinook', 'GT_MISSING_1')
    gt_meta = ground_truth.get('metadata', 'GT_MISSING_2')

    c4_pass = False
    if agent_chinook == gt_chinook and agent_meta == gt_meta:
        c4_pass = True
        score += 40
        feedback_parts.append("PASS C4: Data integrity verified. All files safely migrated.")
    else:
        if not agent_chinook or not agent_meta:
            feedback_parts.append("FAIL C4: Missing files in the new volume mount path")
        else:
            feedback_parts.append("FAIL C4: Checksum mismatch. Data was corrupted, lost, or synthetically regenerated.")

    # ── Final Evaluation ──────────────────────────────────────────────────────
    pass_threshold = task_info.get('metadata', {}).get('pass_threshold', 80)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }