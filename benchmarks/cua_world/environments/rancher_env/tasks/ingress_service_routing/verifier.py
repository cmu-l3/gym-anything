#!/usr/bin/env python3
"""
Verifier for ingress_service_routing task.

Scoring (100 points total, Pass Threshold: 70):
C1 (20 pts): frontend-svc exists with correct selector (app=frontend), targetPort 80, and >=1 endpoint
C2 (20 pts): api-svc exists with correct selector (app=api), targetPort 8080, and >=1 endpoint
C3 (20 pts): docs-svc exists with correct selector (app=docs), targetPort 3000, and >=1 endpoint
C4 (25 pts): Ingress web-apps-ingress exists with /, /api, /docs routing to correct services
C5 (15 pts): Ingress specifies ingressClassName: traefik

Anti-Gaming features:
- Requires endpoints to exist (prevents just creating services with random/wrong selectors).
- Validates that Services are ClusterIP (not LoadBalancer/NodePort).
- Both Services and Ingress must be created to pass.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_service(services, endpoints, svc_name, expected_selector, expected_port):
    """Evaluate a single Service's correctness."""
    svc = next((s for s in services if s.get('metadata', {}).get('name') == svc_name), None)
    if not svc:
        return 0, f"Service '{svc_name}' not found."

    # Check type
    if svc.get('spec', {}).get('type', 'ClusterIP') != 'ClusterIP':
        return 0, f"Service '{svc_name}' is not type ClusterIP."

    # Check selector
    selector = svc.get('spec', {}).get('selector', {})
    for k, v in expected_selector.items():
        if selector.get(k) != v:
            return 0, f"Service '{svc_name}' selector mismatch: expected {k}={v}, got {selector.get(k, 'None')}."

    # Check port mapping
    ports = svc.get('spec', {}).get('ports', [])
    port_match = False
    for p in ports:
        t_port = p.get('targetPort', p.get('port'))
        # Allow match on either 'port' or 'targetPort' to accommodate variations in configuration
        if str(t_port) == str(expected_port) or str(p.get('port')) == str(expected_port):
            port_match = True
            break
            
    if not port_match:
        return 0, f"Service '{svc_name}' does not correctly expose port {expected_port}."

    # Check endpoints
    ep = next((e for e in endpoints if e.get('metadata', {}).get('name') == svc_name), None)
    if not ep or not ep.get('subsets'):
        return 0, f"Service '{svc_name}' has no endpoints (selector may be wrong or pods not running)."

    has_addresses = False
    for sub in ep.get('subsets', []):
        if sub.get('addresses'):
            has_addresses = True
            break

    if not has_addresses:
        return 0, f"Service '{svc_name}' endpoints have no active addresses."

    return 20, f"Service '{svc_name}' is correctly configured with active endpoints."


def verify_ingress_service_routing(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function not available."}

    # Extract JSON result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    services = result.get('services', [])
    endpoints = result.get('endpoints', [])
    ingresses = result.get('ingresses', [])

    score = 0
    feedback_parts = []

    # C1: frontend-svc (20 points)
    c1_score, c1_msg = check_service(services, endpoints, 'frontend-svc', {'app': 'frontend'}, 80)
    score += c1_score
    feedback_parts.append(f"C1 ({c1_score}/20): {c1_msg}")

    # C2: api-svc (20 points)
    c2_score, c2_msg = check_service(services, endpoints, 'api-svc', {'app': 'api'}, 8080)
    score += c2_score
    feedback_parts.append(f"C2 ({c2_score}/20): {c2_msg}")

    # C3: docs-svc (20 points)
    c3_score, c3_msg = check_service(services, endpoints, 'docs-svc', {'app': 'docs'}, 3000)
    score += c3_score
    feedback_parts.append(f"C3 ({c3_score}/20): {c3_msg}")

    # C4 & C5: Ingress Evaluation
    c4_score = 0
    c5_score = 0
    
    # Locate Ingress
    ing = next((i for i in ingresses if i.get('metadata', {}).get('name') == 'web-apps-ingress'), None)
    if not ing and len(ingresses) == 1:
        # Fallback to the only ingress if the name is slightly different
        ing = ingresses[0]

    if not ing:
        feedback_parts.append("C4 (0/25): Ingress 'web-apps-ingress' not found.")
        feedback_parts.append("C5 (0/15): Ingress not found, cannot verify ingress class.")
    else:
        # C4: Check Paths
        rules = ing.get('spec', {}).get('rules', [])
        actual_paths = {}
        for rule in rules:
            for p in rule.get('http', {}).get('paths', []):
                path_val = p.get('path', '')
                backend = p.get('backend', {}).get('service', {})
                svc_name = backend.get('name', '')
                port = backend.get('port', {}).get('number', '')
                actual_paths[path_val] = {'service': svc_name, 'port': str(port)}

        expected_rules = [
            {'path': '/', 'service': 'frontend-svc', 'port': '80'},
            {'path': '/api', 'service': 'api-svc', 'port': '8080'},
            {'path': '/docs', 'service': 'docs-svc', 'port': '3000'}
        ]

        matches = 0
        missing = []
        for exp in expected_rules:
            # Handle lenient path matching (e.g. trailing slashes)
            act = actual_paths.get(exp['path'])
            if act is None:
                alt_path = exp['path'] + '/' if not exp['path'].endswith('/') else exp['path'].rstrip('/')
                act = actual_paths.get(alt_path)

            if act and act['service'] == exp['service'] and act['port'] == exp['port']:
                matches += 1
            else:
                missing.append(f"Path '{exp['path']}' -> {exp['service']}:{exp['port']}")

        if matches == 3:
            c4_score = 25
            feedback_parts.append("C4 (25/25): Ingress contains all 3 correct path rules.")
        else:
            feedback_parts.append(f"C4 (0/25): Ingress missing or incorrect rules for: {missing}")

        # C5: Ingress Class
        ing_class = ing.get('spec', {}).get('ingressClassName', '')
        annotations = ing.get('metadata', {}).get('annotations', {})
        
        if ing_class == 'traefik' or annotations.get('kubernetes.io/ingress.class') == 'traefik':
            c5_score = 15
            feedback_parts.append("C5 (15/15): Ingress uses correct 'traefik' class.")
        else:
            feedback_parts.append(f"C5 (0/15): Ingress class is not 'traefik' (found: {ing_class}).")

    score += c4_score
    score += c5_score

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }