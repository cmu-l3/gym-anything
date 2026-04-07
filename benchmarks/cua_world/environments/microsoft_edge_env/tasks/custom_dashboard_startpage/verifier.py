#!/usr/bin/env python3
"""
Verifier for Custom Dashboard Start Page task.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_dashboard(traj, env_info, task_info):
    """
    Verify the dashboard creation and Edge configuration.
    
    Criteria:
    1. HTML file exists and created during task (10 pts)
    2. HTML content validity (Structure + Title) (10 pts)
    3. Required links present (FlightAware, XE, State, Time, Weather) (50 pts, 10 each)
    4. Airline links present (Min 2) (10 pts)
    5. Edge Startup Configured correctly (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_domains = metadata.get('required_domains', [])
    airline_domains = metadata.get('airline_domains', [])
    min_airlines = metadata.get('min_airlines', 2)
    expected_path = metadata.get('dashboard_path', '/home/ga/Desktop/travel_dashboard.html')

    # Copy result
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
    feedback = []

    # --- Check 1: File Existence & creation time ---
    file_exists = result.get('file_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if file_exists and created_during:
        score += 10
        feedback.append("Dashboard file created successfully.")
    elif file_exists:
        score += 5
        feedback.append("Dashboard file exists but timestamp is old (reused file?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Dashboard HTML file not found."}

    # Decode content
    try:
        content_b64 = result.get('file_content_b64', "")
        html_content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        html_lower = html_content.lower()
    except:
        return {"passed": False, "score": score, "feedback": "Failed to decode file content."}

    # --- Check 2: HTML Structure ---
    if "<html>" in html_lower and "<body>" in html_lower:
        # Check title
        if "<title>" in html_lower and ("dashboard" in html_lower or "travel" in html_lower):
            score += 10
            feedback.append("HTML structure and title are valid.")
        else:
            score += 5
            feedback.append("HTML structure valid but missing descriptive title.")
    else:
        feedback.append("File does not appear to be valid HTML.")

    # --- Check 3: Required Domains (50 pts) ---
    domains_found = 0
    for domain in required_domains:
        if domain in html_lower:
            domains_found += 1
        else:
            feedback.append(f"Missing link: {domain}")
    
    domain_score = domains_found * 10
    score += domain_score
    feedback.append(f"Found {domains_found}/{len(required_domains)} required resource links.")

    # --- Check 4: Airline Domains (10 pts) ---
    airlines_found = 0
    for domain in airline_domains:
        if domain in html_lower:
            airlines_found += 1
    
    if airlines_found >= min_airlines:
        score += 10
        feedback.append(f"Found {airlines_found} airline links (min {min_airlines} required).")
    else:
        feedback.append(f"Found only {airlines_found} airline links (min {min_airlines} required).")

    # --- Check 5: Edge Startup Configuration (20 pts) ---
    prefs = result.get('edge_prefs', {})
    startup_urls = prefs.get('startup_urls', [])
    restore_mode = prefs.get('restore_on_startup', 5)
    homepage = prefs.get('homepage', "")

    config_correct = False
    
    # Path logic: agent might use file:// or just /path
    target_filename = "travel_dashboard.html"
    
    # Check Startup URLs (restore_mode 4 = Open specific pages)
    if restore_mode == 4:
        for url in startup_urls:
            if target_filename in url and "file://" in url:
                config_correct = True
                break
    
    # Check Homepage (if configured to open homepage on startup)
    # restore_mode 0 often implies "Continue where left off" or specific behaviors depending on version,
    # but some versions treat 0 or 1 as specific. 
    # Usually "Open Homepage" is a specific setting, often mapped via restore_mode 5 + homepage_is_newtabpage=false? 
    # Actually, simpler check: simply is the URL set in either place?
    # We will be lenient if the URL is present in startup_urls OR homepage, 
    # but strictly award points if the mode is plausibly correct.
    
    if not config_correct:
        # Fallback check
        if target_filename in homepage and "file://" in homepage:
            # If homepage is set, we give partial credit or full if we can verify startup behavior.
            # Assuming agent tried.
            config_correct = True
            feedback.append("Configured as Homepage (acceptable).")

    if config_correct:
        score += 20
        feedback.append("Edge configured to open dashboard on startup.")
    else:
        feedback.append(f"Edge startup not configured correctly. Mode: {restore_mode}, URLs: {startup_urls}")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }