#!/usr/bin/env python3
"""
Verifier for fcc_broadband_map_research task.

Verifies:
1. Browser History: User visited broadbandmap.fcc.gov
2. Bookmarks: "ISP Research" folder exists
3. Output File: Valid JSON structure with data for 3 cities
4. Data Accuracy: Wired providers (Fiber/Cable/DSL) with plausible speeds

Pass Threshold: 70/100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth keywords for validation
# We accept major providers known to be in these areas
VALID_PROVIDERS = {
    "seattle": ["comcast", "xfinity", "centurylink", "lumen", "quantum", "astound", "wave", "ziply"],
    "austin": ["google", "fiber", "at&t", "att", "spectrum", "charter", "grande", "astound"],
    "portland": ["fidium", "consolidated", "spectrum", "charter", "firstlight", "gwi", "gonetspeed"]
}

INVALID_TECHS = ["satellite", "fixed wireless", "starlink", "hughesnet", "viasat", "t-mobile", "verizon 5g"]

def verify_fcc_broadband_map_research(traj, env_info, task_info):
    """Verify the FCC broadband research task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Retrieve Browser State Result
    browser_result = {}
    try:
        tmp_browser = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_browser.close()
        copy_from_env("/tmp/task_result.json", tmp_browser.name)
        with open(tmp_browser.name, 'r') as f:
            browser_result = json.load(f)
        os.unlink(tmp_browser.name)
    except Exception as e:
        logger.error(f"Failed to load browser result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve browser state check"}

    # 2. Retrieve User Report
    user_report = {}
    report_exists = browser_result.get("report_exists", False)
    report_path = browser_result.get("report_path", "")
    
    if report_exists and report_path:
        try:
            tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            tmp_report.close()
            copy_from_env(report_path, tmp_report.name)
            with open(tmp_report.name, 'r') as f:
                user_report = json.load(f)
            os.unlink(tmp_report.name)
        except Exception as e:
            logger.error(f"Failed to load user report: {e}")
            # We continue, but user_report will be empty

    # --- SCORING LOGIC ---
    score = 0
    feedback_parts = []
    
    # Criterion 1: Browser History (10 pts)
    if browser_result.get("fcc_visits", 0) > 0:
        score += 10
        feedback_parts.append("FCC Map visited (+10)")
    else:
        feedback_parts.append("FCC Map NOT visited (+0)")

    # Criterion 2: Bookmarks (10 pts)
    if browser_result.get("bookmark_folder_exists", False):
        score += 10
        feedback_parts.append("'ISP Research' bookmark folder found (+10)")
    else:
        feedback_parts.append("Bookmark folder missing (+0)")

    # Criterion 3: JSON Report Structure (10 pts)
    required_keys = ["seattle_wa", "austin_tx", "portland_me"]
    if report_exists and all(k in user_report for k in required_keys):
        score += 10
        feedback_parts.append("Report JSON structure valid (+10)")
    elif report_exists:
        score += 5
        feedback_parts.append("Report exists but missing some cities (+5)")
    else:
        feedback_parts.append("Report file missing (+0)")

    # Criterion 4: Data Accuracy (60 pts total - 20 per city)
    for city_key, location_name in [("seattle_wa", "Seattle"), ("austin_tx", "Austin"), ("portland_me", "Portland")]:
        city_data = user_report.get(city_key, {})
        if not city_data:
            feedback_parts.append(f"{location_name}: No data (+0)")
            continue

        provider = str(city_data.get("fastest_provider", "")).lower()
        tech = str(city_data.get("technology", "")).lower()
        speed = city_data.get("max_download_mbps", 0)
        
        # Check 1: Provider validity (10 pts)
        # We accept generic "Fiber" or "Cable" in provider name if specific brand missed, but prefer brand.
        valid_brands = VALID_PROVIDERS.get(location_name.lower(), [])
        brand_match = any(b in provider for b in valid_brands)
        
        # Check 2: Technology validity (must be wired)
        is_wireless = any(w in tech for w in INVALID_TECHS) or any(w in provider for w in INVALID_TECHS)
        is_wired = any(t in tech for t in ["fiber", "cable", "copper", "dsl", "wire"]) or \
                   any(t in provider for t in ["fiber", "cable", "dsl"])
        
        # Check 3: Speed Plausibility (Speed >= 50 for wired)
        speed_ok = isinstance(speed, (int, float)) and speed >= 50

        city_score = 0
        city_feedback = []

        if is_wireless:
            city_feedback.append("Wireless/Satellite selected (Fail)")
        elif not is_wired and not brand_match:
             city_feedback.append("Unknown/Invalid provider/tech")
        else:
            # It seems wired.
            if brand_match:
                city_score += 10
                city_feedback.append("Provider valid")
            elif is_wired:
                city_score += 5 # Partial credit if tech is right but provider name is generic/unknown
                city_feedback.append("Provider generic/unknown")
            
            if speed_ok:
                city_score += 10
                city_feedback.append("Speed plausible")
            else:
                city_feedback.append(f"Speed low/invalid ({speed})")

        score += city_score
        feedback_parts.append(f"{location_name}: {', '.join(city_feedback)} (+{city_score})")

    # Criterion 5: Anti-gaming (Time check)
    if browser_result.get("report_exists") and not browser_result.get("report_fresh"):
        score = 0
        feedback_parts = ["ANTI-GAMING: Report file is old (pre-dates task start). Score reset to 0."]

    # Final result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }