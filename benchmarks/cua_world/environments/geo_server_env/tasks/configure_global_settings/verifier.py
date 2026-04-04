#!/usr/bin/env python3
"""
Verifier for configure_global_settings task.

Checks:
1. Proxy Base URL set correctly (REST + GetCapabilities)
2. Number of decimals set to 6
3. Verbose exceptions enabled
4. Charset is UTF-8
5. Logging profile is PRODUCTION_LOGGING
6. Contact info updated (Org + Person)
7. Report file created with correct content
8. GUI interaction detected (anti-gaming)
"""

import json
import tempfile
import os
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_global_settings(traj, env_info, task_info):
    """Verify GeoServer global settings configuration."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_proxy = metadata.get('expected_proxy_url', 'https://maps.cityplanning.example.com/geoserver')
    expected_decimals = metadata.get('expected_decimals', 6)
    expected_verbose = metadata.get('expected_verbose', True)
    expected_charset = metadata.get('expected_charset', 'UTF-8')
    expected_logging = metadata.get('expected_logging_profile', 'PRODUCTION_LOGGING')
    expected_org = metadata.get('expected_org', 'City Planning Department')
    expected_person = metadata.get('expected_person', 'GIS Administrator')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_global_settings_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Global Settings (REST API)
    settings = result.get('settings', {}).get('global', {})
    
    # Proxy Base URL (20 pts)
    current_proxy = settings.get('proxyBaseUrl', '')
    if current_proxy == expected_proxy:
        score += 20
        feedback_parts.append("Proxy Base URL set correctly")
    else:
        feedback_parts.append(f"Proxy Base URL incorrect: '{current_proxy}'")

    # Decimals (10 pts)
    current_decimals = settings.get('numDecimals')
    if current_decimals == expected_decimals:
        score += 10
        feedback_parts.append(f"Number of decimals correct: {current_decimals}")
    else:
        feedback_parts.append(f"Number of decimals incorrect: {current_decimals} (expected {expected_decimals})")

    # Verbose Exceptions (10 pts)
    current_verbose = settings.get('verbose')
    if current_verbose == expected_verbose:
        score += 10
        feedback_parts.append(f"Verbose exceptions enabled: {current_verbose}")
    else:
        feedback_parts.append(f"Verbose exceptions incorrect: {current_verbose}")

    # Charset (5 pts)
    current_charset = settings.get('charset', '')
    if current_charset == expected_charset:
        score += 5
        feedback_parts.append("Charset correct")
    else:
        feedback_parts.append(f"Charset incorrect: '{current_charset}'")

    # 2. Verify Logging Profile (15 pts)
    logging_info = result.get('logging', {}).get('logging', {})
    current_level = logging_info.get('level', '')
    # GeoServer might append .properties or not depending on version/context
    if expected_logging in current_level:
        score += 15
        feedback_parts.append(f"Logging profile correct: {current_level}")
    else:
        feedback_parts.append(f"Logging profile incorrect: '{current_level}'")

    # 3. Verify Contact Info (15 pts)
    contact = result.get('contact', {}).get('contact', {})
    
    current_org = contact.get('contactOrganization', '')
    if current_org == expected_org:
        score += 10
        feedback_parts.append("Contact organization correct")
    else:
        feedback_parts.append(f"Contact organization incorrect: '{current_org}'")

    current_person = contact.get('contactPerson', '')
    if current_person == expected_person:
        score += 5
        feedback_parts.append("Contact person correct")
    else:
        feedback_parts.append(f"Contact person incorrect: '{current_person}'")

    # 4. Verify Capabilities Document (15 pts)
    # Checks if the Proxy URL was actually applied to OGC output
    if result.get('capabilities_has_proxy'):
        score += 15
        feedback_parts.append("Proxy URL verified in WMS GetCapabilities")
    else:
        feedback_parts.append("Proxy URL NOT found in WMS GetCapabilities")

    # 5. Verify Report File (10 pts)
    report = result.get('report', {})
    if report.get('exists') and report.get('created_during_task'):
        try:
            content = base64.b64decode(report.get('content_base64', '')).decode('utf-8')
            lines = [l.strip() for l in content.split('\n') if l.strip()]
            
            # Check content vaguely matches expectations (robustness)
            content_ok = False
            if len(lines) >= 4:
                # Line 1: Proxy URL
                if expected_proxy in lines[0]:
                    # Line 2: Decimals
                    if str(expected_decimals) in lines[1]:
                        # Line 3: Logging
                        if "PRODUCTION" in lines[2].upper():
                            content_ok = True
            
            if content_ok:
                score += 10
                feedback_parts.append("Report file valid")
            else:
                score += 5
                feedback_parts.append("Report file exists but content mismatch")
        except Exception:
            feedback_parts.append("Report file unreadable")
    else:
        feedback_parts.append("Report file missing or not created during task")

    # 6. Anti-Gaming: GUI Interaction Check
    # If no GUI interaction was detected, the agent likely just used the REST API (which is a valid technical approach 
    # but the task description implies UI usage). However, for this task, the goal is configuration.
    # If the user strictly followed instructions "Log in... Navigate...", GUI interaction is expected.
    # We won't fail the task solely on this, but we'll note it.
    # However, if VLM is available, we use it for trajectory verification.
    
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=5)
        
        # Simple check: did the agent see the Global Settings page?
        vlm_result = query_vlm(
            images=frames,
            prompt="Does any of these screenshots show the GeoServer 'Global Settings' or 'Contact Information' page? Return JSON: {'settings_page_visible': bool}"
        )
        if vlm_result.get('parsed', {}).get('settings_page_visible', False):
            # Bonus or validation confirmation
            pass
        else:
            feedback_parts.append("(Note: Global settings page not clearly seen in trajectory)")

    # Pass Threshold: 60 points
    # Critical: Proxy URL and Logging must be correct
    critical_met = (current_proxy == expected_proxy) and (expected_logging in current_level)
    passed = (score >= 60) and critical_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }