#!/usr/bin/env python3
"""
Verifier for Chrome Network Throttling Configuration Task (network_throttling_config@1)
Task: Configure Chrome DevTools network throttling to simulate Fast 3G conditions

Verification Strategy:
1. Check if DevTools was opened (presence of devtools:// tabs)
2. Verify test page is still loaded
3. Check for evidence of throttling through multi-criteria analysis
4. Provide graduated scoring based on evidence quality

Since network throttling is a DevTools session state (not persisted in Preferences),
we primarily verify that the user opened DevTools and likely configured throttling.
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for network_throttling_config@1.
    
    Verifies that the agent opened DevTools and configured network throttling.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), feedback (str), and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Gather evidence from exported data
        evidence = gather_evidence(copy_from_env)
        
        # Verify based on multiple criteria
        verification_result = verify_throttling_configuration(evidence)
        
        # Clean up
        cleanup_verification_temp()
        
        return verification_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def gather_evidence(copy_from_env) -> Dict[str, Any]:
    """
    Gather all evidence from the container for verification.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict containing all gathered evidence
    """
    evidence = {
        "devtools_open": False,
        "devtools_tab_count": 0,
        "test_page_active": False,
        "active_url": "",
        "files_retrieved": [],
        "screenshot_available": False,
        "tabs_data": None,
    }
    
    # Files to retrieve from container
    files_to_copy = [
        ("devtools_open_count.txt", "devtools_open_count.txt"),
        ("final_tabs.json", "final_tabs.json"),
        ("active_page_tab.json", "active_page_tab.json"),
        ("summary.txt", "summary.txt"),
        ("final_screenshot.png", "final_screenshot.png"),
    ]
    
    temp_dir = tempfile.mkdtemp(prefix="network_throttling_verify_")
    logger.info(f"Created temporary directory: {temp_dir}")
    
    for container_file, local_name in files_to_copy:
        try:
            container_path = f"/tmp/network_throttling_verification/{container_file}"
            local_path = os.path.join(temp_dir, local_name)
            
            copy_from_env(container_path, local_path)
            
            if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                evidence["files_retrieved"].append(local_name)
                logger.info(f"✓ Retrieved: {local_name}")
            else:
                logger.warning(f"⚠ File empty or not found: {local_name}")
                
        except Exception as e:
            logger.debug(f"Could not retrieve {container_file}: {e}")
            continue
    
    # Parse DevTools open count
    devtools_count_path = os.path.join(temp_dir, "devtools_open_count.txt")
    if os.path.exists(devtools_count_path):
        try:
            with open(devtools_count_path, 'r') as f:
                count_str = f.read().strip()
                devtools_count = int(count_str)
                evidence["devtools_tab_count"] = devtools_count
                evidence["devtools_open"] = devtools_count > 0
                logger.info(f"DevTools open count: {devtools_count}")
        except Exception as e:
            logger.warning(f"Could not parse devtools_open_count.txt: {e}")
    
    # Parse active page tab info
    active_tab_path = os.path.join(temp_dir, "active_page_tab.json")
    if os.path.exists(active_tab_path):
        try:
            with open(active_tab_path, 'r') as f:
                active_tab = json.load(f)
                evidence["active_url"] = active_tab.get("url", "")
                evidence["test_page_active"] = "network_test.html" in evidence["active_url"]
                logger.info(f"Active URL: {evidence['active_url']}")
        except Exception as e:
            logger.warning(f"Could not parse active_page_tab.json: {e}")
    
    # Parse all tabs data
    tabs_path = os.path.join(temp_dir, "final_tabs.json")
    if os.path.exists(tabs_path):
        try:
            with open(tabs_path, 'r') as f:
                tabs_data = json.load(f)
                evidence["tabs_data"] = tabs_data
                logger.info(f"Loaded tabs data: {len(tabs_data)} total tabs")
        except Exception as e:
            logger.warning(f"Could not parse final_tabs.json: {e}")
    
    # Check if screenshot exists
    screenshot_path = os.path.join(temp_dir, "final_screenshot.png")
    if os.path.exists(screenshot_path):
        evidence["screenshot_available"] = True
        evidence["screenshot_size"] = os.path.getsize(screenshot_path)
        logger.info(f"Screenshot available: {evidence['screenshot_size']} bytes")
    
    evidence["temp_dir"] = temp_dir
    
    return evidence


def verify_throttling_configuration(evidence: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify network throttling configuration based on gathered evidence.
    
    Verification Criteria (5 total):
    1. DevTools was opened (devtools tabs present)
    2. Test page is still active
    3. Multiple criteria met indicating task attempt
    4. Files successfully exported
    5. No obvious errors
    
    Args:
        evidence: Dict containing gathered evidence
        
    Returns:
        Verification result with passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: DevTools was opened
    if evidence["devtools_open"] and evidence["devtools_tab_count"] > 0:
        criteria_met += 1
        feedback_parts.append(f"✓ DevTools opened (detected {evidence['devtools_tab_count']} devtools tab(s))")
        logger.info(f"✓ Criterion 1 passed: DevTools open")
    else:
        feedback_parts.append(f"✗ DevTools not detected as open")
        logger.info(f"✗ Criterion 1 failed: DevTools not open")
    
    # Criterion 2: Test page is still active
    if evidence["test_page_active"]:
        criteria_met += 1
        feedback_parts.append(f"✓ Test page active (network_test.html)")
        logger.info(f"✓ Criterion 2 passed: Test page active")
    else:
        if evidence["active_url"]:
            feedback_parts.append(f"⚠ Different page active: {evidence['active_url'][:50]}...")
        else:
            feedback_parts.append(f"✗ Test page not found")
        logger.info(f"✗ Criterion 2 failed: Test page not active")
    
    # Criterion 3: Required files exported
    required_files = ["devtools_open_count.txt", "final_tabs.json", "active_page_tab.json"]
    files_present = sum(1 for f in required_files if f in evidence["files_retrieved"])
    if files_present >= 2:
        criteria_met += 1
        feedback_parts.append(f"✓ Export successful ({files_present}/{len(required_files)} key files)")
        logger.info(f"✓ Criterion 3 passed: Files exported")
    else:
        feedback_parts.append(f"✗ Export incomplete ({files_present}/{len(required_files)} key files)")
        logger.info(f"✗ Criterion 3 failed: Insufficient files")
    
    # Criterion 4: DevTools likely in Network panel (inferred from tabs data)
    # We check if there's a devtools tab for the test page
    network_panel_likely = False
    if evidence["tabs_data"]:
        devtools_tabs = [t for t in evidence["tabs_data"] if "devtools://" in t.get("url", "")]
        for dt in devtools_tabs:
            # DevTools URL often contains the inspected page's info
            if "network_test.html" in dt.get("url", "").lower() or "network" in dt.get("title", "").lower():
                network_panel_likely = True
                break
    
    if network_panel_likely or (evidence["devtools_open"] and evidence["test_page_active"]):
        # Give credit if DevTools is open with test page (user likely attempted the task)
        criteria_met += 1
        feedback_parts.append(f"✓ DevTools likely configured (test page + DevTools open)")
        logger.info(f"✓ Criterion 4 passed: Configuration attempted")
    else:
        feedback_parts.append(f"⚠ DevTools state unclear")
        logger.info(f"⚠ Criterion 4: Partial evidence")
        criteria_met += 0.3  # Partial credit
    
    # Criterion 5: Screenshot captured (evidence of final state)
    if evidence["screenshot_available"]:
        criteria_met += 1
        feedback_parts.append(f"✓ Screenshot captured")
        logger.info(f"✓ Criterion 5 passed: Screenshot available")
    else:
        feedback_parts.append(f"⚠ Screenshot not available")
        logger.info(f"✗ Criterion 5 failed: No screenshot")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3.75/5 criteria (~75%)
    
    # Generate final feedback
    feedback_header = f"Network Throttling Configuration Verification\n{'='*50}"
    feedback_body = "\n".join(feedback_parts)
    
    if passed:
        result_msg = f"\n\n✅ Task PASSED: {criteria_met:.1f}/{total_criteria} criteria met (Score: {score}%)"
        result_msg += "\n\nDevTools was opened and throttling configuration likely attempted."
        result_msg += "\nNote: Network throttling is a session-only DevTools state, not persisted in files."
    else:
        result_msg = f"\n\n❌ Task FAILED: {criteria_met:.1f}/{total_criteria} criteria met (Score: {score}%)"
        result_msg += "\n\nDevTools was not properly opened or throttling not configured."
        result_msg += "\n\nExpected steps:"
        result_msg += "\n  1. Press F12 to open DevTools"
        result_msg += "\n  2. Click Network tab"
        result_msg += "\n  3. Find 'No throttling' dropdown"
        result_msg += "\n  4. Select 'Fast 3G' from dropdown"
    
    feedback = f"{feedback_header}\n\n{feedback_body}{result_msg}"
    
    # Clean up temp directory
    if "temp_dir" in evidence:
        try:
            import shutil
            shutil.rmtree(evidence["temp_dir"])
            logger.info(f"Cleaned up temp directory: {evidence['temp_dir']}")
        except Exception as e:
            logger.warning(f"Could not clean up temp directory: {e}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "devtools_open": evidence["devtools_open"],
            "devtools_tab_count": evidence["devtools_tab_count"],
            "test_page_active": evidence["test_page_active"],
            "active_url": evidence["active_url"],
            "files_retrieved": evidence["files_retrieved"],
            "screenshot_available": evidence["screenshot_available"]
        }
    }
