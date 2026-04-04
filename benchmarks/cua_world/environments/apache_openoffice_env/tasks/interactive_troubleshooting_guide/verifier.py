#!/usr/bin/env python3
"""
Verifier for interactive_troubleshooting_guide task.
Verifies that the agent created an ODT document with functional interactive navigation elements.

Criteria:
1. File Creation & Existence (Gate)
2. Bookmarks: At least 4 distinct bookmarks created.
3. Hyperlinks: At least 4 internal links created.
4. Logic: Links must point to semantically relevant bookmarks (e.g., "Power" link -> "Power" section).
5. Structure: Headings used for sections.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_interactive_guide(traj, env_info, task_info):
    """
    Verify the interactive troubleshooting guide.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence & Validity (Gate)
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Output file 'Sentinel_Guide_Interactive.odt' was not created."
        }
    
    if not result.get("file_created_during_task", False):
        feedback.append("WARNING: File timestamp suggests it wasn't created during this task session.")
        # We don't fail immediately but this is suspicious
    
    if result.get("parse_error"):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"FAILED: Could not parse ODT file structure. File may be corrupted. Error: {result['parse_error']}"
        }

    # 2. Verify Bookmarks (30 pts)
    # Expect at least 4 bookmarks (one for each section: Power, Wifi, Image, Motion)
    bookmarks = result.get("bookmarks_found", [])
    if len(bookmarks) >= 4:
        score += 30
        feedback.append(f"SUCCESS: Found {len(bookmarks)} bookmarks ({', '.join(bookmarks[:3])}...).")
    elif len(bookmarks) > 0:
        score += 15
        feedback.append(f"PARTIAL: Found {len(bookmarks)} bookmarks, expected at least 4.")
    else:
        feedback.append("FAIL: No bookmarks found. Did you insert bookmarks at the start of each section?")

    # 3. Verify Hyperlinks (30 pts)
    # Expect at least 4 internal links
    links = result.get("internal_links", [])
    if len(links) >= 4:
        score += 30
        feedback.append(f"SUCCESS: Found {len(links)} internal hyperlinks.")
    elif len(links) > 0:
        score += 15
        feedback.append(f"PARTIAL: Found {len(links)} internal hyperlinks, expected at least 4.")
    else:
        feedback.append("FAIL: No internal hyperlinks found. Did you hyperlink the menu items to the bookmarks?")

    # 4. Verify Link Logic (30 pts)
    # Check if links match semantics. 
    # Logic: Text content of link should match the target bookmark name roughly.
    # Mappings expected:
    # "turn on"/"power" -> Bookmark "Power"
    # "offline"/"error" -> Bookmark "WiFi"
    # "blurry"/"image" -> Bookmark "Image"
    # "notifications"/"motion" -> Bookmark "Motion"
    
    logic_hits = 0
    valid_mappings = [
        (["turn on", "led", "power"], ["power", "batt"]),
        (["offline", "error", "wi-fi", "wifi"], ["wifi", "connect"]),
        (["blurry", "washed", "image"], ["image", "night", "vision"]),
        (["notification", "motion", "alert"], ["motion", "detect"])
    ]
    
    for link in links:
        link_text = link.get("text", "").lower()
        target = link.get("target", "").lower()
        
        match_found = False
        for keywords, targets in valid_mappings:
            if any(k in link_text for k in keywords):
                if any(t in target for t in targets):
                    match_found = True
                    break
        
        if match_found:
            logic_hits += 1
            
    # We expect at least 3 correct mappings for full points
    if logic_hits >= 3:
        score += 30
        feedback.append(f"SUCCESS: Hyperlinks correctly point to relevant sections ({logic_hits} valid links verified).")
    elif logic_hits >= 1:
        score += 15
        feedback.append(f"PARTIAL: Some hyperlinks point to relevant sections ({logic_hits} verified).")
    else:
        if len(links) > 0:
            feedback.append("FAIL: Hyperlinks exist but do not seem to point to the correct sections (e.g. 'Power' symptom should link to 'Power' bookmark).")
        else:
            feedback.append("FAIL: No links to verify logic.")

    # 5. Document Structure (10 pts)
    headings = result.get("headings_found", [])
    h1_count = sum(1 for h in headings if str(h.get("level")) == "1")
    
    if h1_count >= 4:
        score += 10
        feedback.append(f"SUCCESS: Document structure uses Heading 1 for sections ({h1_count} found).")
    else:
        feedback.append(f"FAIL: Expected at least 4 Heading 1 sections, found {h1_count}.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "\n".join(feedback)
    }