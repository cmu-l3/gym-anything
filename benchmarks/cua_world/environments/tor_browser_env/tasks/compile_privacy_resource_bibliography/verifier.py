#!/usr/bin/env python3
"""
Verifier for compile_privacy_resource_bibliography task.

Checks that the agent successfully browsed the 4 specified privacy websites
and compiled a structured bibliography document with URLs, organization names,
and descriptive text.

Uses both file content analysis and browser history for verification.
"""

import json
import logging
import os
import re
import tempfile
from typing import Dict, Any, List

# Try importing VLM tools for optional trajectory check
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compile_privacy_resource_bibliography(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    required_urls = metadata.get('required_urls', [
        "eff.org/issues/anonymity",
        "torproject.org/about/history",
        "freedom.press",
        "privacyguides.org"
    ])
    
    required_orgs = metadata.get('required_orgs', [
        ["electronic frontier foundation", "eff "],
        ["tor project"],
        ["freedom of the press", "freedom.press"],
        ["privacy guides", "privacyguides"]
    ])

    # 1. Load JSON results
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Result JSON not found: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Load the actual bibliography text file
    file_content = ""
    tmp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_txt.close()
    if result.get("file_exists", False):
        try:
            copy_from_env("/tmp/bibliography_export.txt", tmp_txt.name)
            with open(tmp_txt.name, 'r', encoding='utf-8', errors='replace') as f:
                file_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read exported bibliography: {e}")
    if os.path.exists(tmp_txt.name):
        os.unlink(tmp_txt.name)

    file_content_lower = file_content.lower()
    
    # 3. Calculate Scoring
    score = 0
    feedback_parts = []
    
    # A. File Exists (15 pts - GATE)
    file_exists = result.get('file_exists', False)
    if file_exists:
        score += 15
        feedback_parts.append("File exists (15/15)")
    else:
        feedback_parts.append("File NOT found (0/15)")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) + " - Task failed.",
            "subscores": {"file_exists": False}
        }
        
    # B. File is new (created after task start) (5 pts)
    if result.get('file_is_new', False):
        score += 5
        feedback_parts.append("File is new (5/5)")
    else:
        feedback_parts.append("File predates task start (0/5)")
        
    # C. File size > 500 bytes (5 pts)
    file_size = result.get('file_size', 0)
    if file_size > 500:
        score += 5
        feedback_parts.append(f"File size OK ({file_size}B) (5/5)")
    else:
        feedback_parts.append(f"File too small ({file_size}B) (0/5)")

    # D. File contains all 4 required URLs (20 pts, 5 each)
    urls_found = 0
    for u in required_urls:
        if u in file_content_lower:
            urls_found += 1
            
    score += (urls_found * 5)
    feedback_parts.append(f"URLs found in text: {urls_found}/4 ({urls_found*5}/20)")
    
    # E. Section structure presence (10 pts)
    # Check for "Source" headers (e.g. ## Source 1, Source 2)
    source_headers = len(re.findall(r'source\s*\d', file_content_lower)) + len(re.findall(r'##\s*source', file_content_lower))
    if source_headers >= 3:
        score += 10
        feedback_parts.append("Section structure found (10/10)")
    elif source_headers > 0:
        score += 5
        feedback_parts.append("Partial section structure found (5/10)")
    else:
        feedback_parts.append("No 'Source' section structure found (0/10)")

    # F. Organization names (15 pts)
    orgs_found = 0
    for org_aliases in required_orgs:
        if any(alias in file_content_lower for alias in org_aliases):
            orgs_found += 1
            
    if orgs_found >= 3:
        score += 15
        feedback_parts.append(f"Org names found: {orgs_found} (15/15)")
    elif orgs_found == 2:
        score += 10
        feedback_parts.append("Org names found: 2 (10/15)")
    elif orgs_found == 1:
        score += 5
        feedback_parts.append("Org names found: 1 (5/15)")
    else:
        feedback_parts.append("No Org names found (0/15)")

    # G. Content Richness (10 pts)
    # Remove URLs, headers, and the word 'source' to see if real text remains
    clean_text = file_content_lower
    for u in required_urls:
        clean_text = clean_text.replace(u, '')
    clean_text = re.sub(r'https?://[^\s]+', '', clean_text)
    clean_text = re.sub(r'source\s*\d?', '', clean_text)
    clean_text = re.sub(r'[^a-z]', '', clean_text) # Only count alphabet chars
    
    if len(clean_text) > 200:
        score += 10
        feedback_parts.append("Descriptive content rich (10/10)")
    elif len(clean_text) > 50:
        score += 5
        feedback_parts.append("Descriptive content minimal (5/10)")
    else:
        feedback_parts.append("Missing descriptive content (0/10)")

    # H. Browser History Check (15 pts + 5 pts bonus for all 4)
    history_urls = result.get('history_urls', [])
    history_matches = 0
    for req_u in required_urls:
        if any(req_u in h_url for h_url in history_urls):
            history_matches += 1
            
    if history_matches >= 3:
        score += 15
        feedback_parts.append(f"Browser history verified >= 3 sites (15/15)")
        if history_matches == 4:
            score += 5
            feedback_parts.append("Bonus: All 4 sites in history (+5)")
    elif history_matches > 0:
        score += (history_matches * 5)
        feedback_parts.append(f"Browser history verified {history_matches} site(s) ({history_matches*5}/15)")
    else:
        feedback_parts.append("Sites NOT found in browser history (0/15)")

    # I. Optional Trajectory VLM Verification
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            if frames and final:
                vlm_prompt = "Did the agent actively use Tor Browser to view privacy websites and a text editor to write a bibliography document during this session? Answer YES or NO."
                vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
                if "YES" in str(vlm_res).upper():
                    feedback_parts.append("[VLM Verified Trajectory Workflow]")
                else:
                    feedback_parts.append("[VLM Workflow Questionable]")
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")

    # Pass threshold: 60 points
    passed = score >= 60
    
    # Cap score at 100 max
    final_score = min(100, score)

    logger.info(f"Score: {final_score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "file_exists": file_exists,
            "urls_extracted": urls_found,
            "orgs_extracted": orgs_found,
            "history_matches": history_matches,
            "rich_content": len(clean_text) > 200
        }
    }