#!/usr/bin/env python3
"""
Verifier for compose_profiles_multi_team task.

Verifies that the user correctly configured Docker Compose profiles:
- Base services (postgres, redis) appear in ALL profiles (by having no profile set)
- frontend: nginx, storefront + base
- backend: api, worker + base
- debug: test-runner, prometheus + base
- full: all services + base

Logic relies on `docker compose --profile X config --services` output gathered in export script.
"""

import json
import tempfile
import os
import logging
import base64

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compose_profiles(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_profiles = metadata.get('profiles', {})
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Modification (10 pts)
    if result.get('file_modified', False):
        score += 10
        feedback_parts.append("Compose file modified (+10)")
    else:
        feedback_parts.append("Compose file NOT modified (+0)")
        return {"passed": False, "score": 0, "feedback": "Compose file was not modified"}

    # Helper to parse service string "svc1,svc2" -> set
    def parse_services(s):
        return set(s.split(',')) if s else set()

    # 2. Check Base Services / No Profile (15 pts)
    # If no profile is specified, ONLY services without profiles should load.
    # Requirement: Base services (postgres, redis) must have NO profile.
    # If they have no profile, they appear when no profile is active.
    actual_no_profile = parse_services(result.get('services_no_profile', ''))
    expected_base = set(['postgres', 'redis'])
    
    # Check if postgres and redis are present
    if expected_base.issubset(actual_no_profile):
        # Now check if we have EXTRA services. 
        # If the user forgot to add profiles to 'api', it would show up here too.
        extras = actual_no_profile - expected_base
        if not extras:
            score += 15
            feedback_parts.append("Base services configuration correct (+15)")
        else:
            score += 5
            feedback_parts.append(f"Base services present but extra services found: {extras} (+5)")
    else:
        feedback_parts.append(f"Missing base services in default config. Found: {actual_no_profile} (+0)")

    # Anti-gaming: Ensure base services didn't use `profiles: ["frontend", "backend" ...]` hack
    # The export script checks raw YAML if possible
    base_has_profiles = result.get('base_services_have_profiles_key', 'unknown')
    if base_has_profiles == "true":
        score -= 10
        feedback_parts.append("PENALTY: Base services should not have a 'profiles' key (-10)")
    
    # 3. Check Profiles (15 pts each = 60 pts)
    profiles_to_check = ['frontend', 'backend', 'debug', 'full']
    
    for profile in profiles_to_check:
        key = f"services_{profile}"
        actual = parse_services(result.get(key, ''))
        expected = set(expected_profiles.get(profile, []))
        
        # Check exact match
        if actual == expected:
            score += 15
            feedback_parts.append(f"Profile '{profile}' correct (+15)")
        else:
            # Check for partial credit
            missing = expected - actual
            extra = actual - expected
            if len(missing) == 0:
                # All required are there, but maybe some extras?
                # Actually for profiles, extras usually mean something shouldn't be there
                score += 10
                feedback_parts.append(f"Profile '{profile}' has extras: {extra} (+10)")
            elif len(actual) > 0 and len(actual.intersection(expected)) > len(expected) / 2:
                score += 5
                feedback_parts.append(f"Profile '{profile}' mostly correct (+5)")
            else:
                feedback_parts.append(f"Profile '{profile}' incorrect. Missing: {missing} (+0)")

    # 4. Verify YAML validity (5 pts)
    # If we got service lists back, the YAML is valid
    if result.get('services_full'):
        score += 5
    
    # 5. Check if backend was tested (10 pts)
    # The instructions asked to start backend, verify, then stop.
    # If they stopped it, running services should be empty.
    # If they left it running, it should contain backend services.
    current_running = parse_services(result.get('current_running_services', ''))
    
    # We give points if they left it clean OR if they left exactly backend running
    # This proves they likely ran it.
    if len(current_running) == 0:
        score += 10
        feedback_parts.append("Cleanup performed correctly (+10)")
    elif current_running == set(expected_profiles.get('backend', [])):
        score += 5
        feedback_parts.append("Backend profile left running (cleanup skipped) (+5)")
    else:
        feedback_parts.append("Unexpected running services found (+0)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }