#!/usr/bin/env python3
"""
Verifier for private_registry_auth_migration task.

Scoring system (100 points total, Pass threshold: 75 points):
- C1: 25 points - Secret 'corp-registry-auth' exists and is type 'kubernetes.io/dockerconfigjson'
- C2: 25 points - Secret contains correct 'svc_k8s_pull' creds for 'harbor.corp.local'
- C3: 25 points - 'default' ServiceAccount has 'corp-registry-auth' in its imagePullSecrets
- C4: 25 points - All 3 deployments (frontend, backend, cache) are updated to harbor.corp.local images
"""

import json
import base64
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_private_registry_auth_migration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available in env_info"}

    result_path = '/tmp/registry_migration_result.json'
    score = 0
    feedback_parts = []

    try:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name

        copy_from_env(result_path, tmp_path)

        with open(tmp_path, 'r') as f:
            result = json.load(f)

        os.unlink(tmp_path)
    except (FileNotFoundError, json.JSONDecodeError, Exception) as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Failed to read result file: {e}'
        }

    # C1: Secret Existence
    secret = result.get('secret', {})
    secret_exists = secret.get('metadata', {}).get('name') == 'corp-registry-auth'
    secret_type = secret.get('type') == 'kubernetes.io/dockerconfigjson'
    
    if secret_exists and secret_type:
        score += 25
        feedback_parts.append("PASS C1: Secret 'corp-registry-auth' exists and is correct type (+25)")
    else:
        if secret_exists:
            feedback_parts.append("FAIL C1: Secret exists but has wrong type")
        else:
            feedback_parts.append("FAIL C1: Secret 'corp-registry-auth' not found")

    # C2: Secret Content (Authenticity and Integrity)
    parsed_creds_valid = False
    secret_data = secret.get('data', {}).get('.dockerconfigjson', '')
    if secret_data:
        try:
            decoded = base64.b64decode(secret_data).decode('utf-8')
            docker_cfg = json.loads(decoded)
            auths = docker_cfg.get('auths', {})
            
            harbor_auth = None
            for key, val in auths.items():
                if 'harbor.corp.local' in key:
                    harbor_auth = val
                    break
            
            if harbor_auth:
                if harbor_auth.get('username') == 'svc_k8s_pull' and harbor_auth.get('password') == 'SecureToken-9988776655':
                    parsed_creds_valid = True
                elif 'auth' in harbor_auth:
                    auth_str = base64.b64decode(harbor_auth['auth']).decode('utf-8')
                    if auth_str == 'svc_k8s_pull:SecureToken-9988776655':
                        parsed_creds_valid = True
        except Exception:
            pass

    if parsed_creds_valid:
        score += 25
        feedback_parts.append("PASS C2: Secret contains correct base64-decoded credentials for harbor.corp.local (+25)")
    else:
        feedback_parts.append("FAIL C2: Secret does not contain correct credentials for harbor.corp.local")

    # C3: ServiceAccount Binding
    sa = result.get('serviceaccount', {})
    image_pull_secrets = sa.get('imagePullSecrets', [])
    has_pull_secret = any(s.get('name') == 'corp-registry-auth' for s in image_pull_secrets)
    
    if has_pull_secret:
        score += 25
        feedback_parts.append("PASS C3: 'default' ServiceAccount accurately references 'corp-registry-auth' (+25)")
    else:
        feedback_parts.append("FAIL C3: 'default' ServiceAccount does not reference the imagePullSecret")

    # C4: Deployment Migration Execution
    deploys = result.get('deployments', {}).get('items', [])
    expected_suffixes = {
        'frontend': 'nginx:1.24',
        'backend': 'node:18',
        'cache': 'redis:7.0'
    }
    
    migrated_count = 0
    for d in deploys:
        name = d.get('metadata', {}).get('name')
        containers = d.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
        if name in expected_suffixes and containers:
            image = containers[0].get('image', '')
            if image.startswith('harbor.corp.local/') and image.endswith(expected_suffixes[name]):
                migrated_count += 1
                
    if migrated_count == 3:
        score += 25
        feedback_parts.append("PASS C4: All 3 deployments updated to use harbor.corp.local images (+25)")
    else:
        feedback_parts.append(f"FAIL C4: Only {migrated_count}/3 deployments updated correctly")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }