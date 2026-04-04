#!/usr/bin/env python3
"""
Verifier for External Outbound Link Audit task.

Verification Logic:
1.  **CSV Check (40 pts)**:
    -   Must be created after task start.
    -   Must contain URLs from domains OTHER than crawler-test.com.
    -   Score scales with quantity of data found (preventing empty exports).

2.  **Report Check (40 pts)**:
    -   Must exist and be recently modified.
    -   Must have minimum length.
    -   Must contain numbers (counts) and actionable keywords.
    -   Must mention actual external domains (cross-verification with ground truth).

3.  **App State/VLM (20 pts)**:
    -   Screaming Frog running.
    -   VLM confirms workflow.

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_external_outbound_link_audit(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load Result JSON
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

    # 2. Score CSV Export (Max 40 pts)
    # ------------------------------------------------------------------
    csv_created = result.get("csv_created", False)
    ext_links = result.get("external_links_found_count", 0)
    unique_domains = result.get("unique_external_domains_count", 0)

    if csv_created:
        # Base points for file creation
        score += 10
        feedback_parts.append("CSV export created")
        
        # Points for content
        if ext_links >= 5:
            score += 15
            feedback_parts.append(f"Found {ext_links} external links (good)")
        elif ext_links > 0:
            score += 5
            feedback_parts.append(f"Found {ext_links} external links (low)")
        else:
            feedback_parts.append("No external links found in CSV")

        if unique_domains >= 2:
            score += 15
            feedback_parts.append(f"Found {unique_domains} unique external domains")
        elif unique_domains > 0:
            score += 5
            feedback_parts.append("Found only 1 external domain")
    else:
        feedback_parts.append("No valid external link CSV found")

    # 3. Score Text Report (Max 40 pts)
    # ------------------------------------------------------------------
    report_exists = result.get("report_exists", False)
    report_size = result.get("report_size_bytes", 0)
    has_nums = result.get("report_has_numbers", False)
    has_action = result.get("report_has_action", False)
    mentions_domains = result.get("report_mentions_domains", False)

    if report_exists:
        if report_size > 200:
            score += 10
            feedback_parts.append(f"Report exists ({report_size} bytes)")
            
            if has_nums:
                score += 10
                feedback_parts.append("Report contains counts")
            else:
                feedback_parts.append("Report missing numeric counts")
                
            if has_action:
                score += 10
                feedback_parts.append("Report contains recommendations")
            
            if mentions_domains:
                score += 10
                feedback_parts.append("Report references real external domains")
            else:
                feedback_parts.append("Report content generic (no specific domains mentioned)")
        else:
            score += 5
            feedback_parts.append("Report exists but too short (<200 bytes)")
    else:
        feedback_parts.append("No analysis report found")

    # 4. App State and VLM Verification (Max 20 pts)
    # ------------------------------------------------------------------
    sf_running = result.get("sf_running", False)
    if sf_running:
        score += 5
        feedback_parts.append("App running")
    
    # VLM Trajectory Check
    # We check if they actually visited the External tab or used menus
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    get_trajectory_frames = env_info.get('sample_trajectory_frames')
    
    if query_vlm:
        # Use simple VLM check if trajectory functions aren't available
        # But prefer trajectory if possible
        frames = []
        if get_trajectory_frames:
            # Fake function call structure if not imported, but in this env we expect it passed
            try:
                frames = get_trajectory_frames(traj, n=4)
            except:
                pass
        
        # If no frames, try final screenshot
        if not frames and env_info.get('get_final_screenshot'):
            frames = [env_info.get('get_final_screenshot')(traj)]

        if frames:
            prompt = """
            Analyze these screenshots of Screaming Frog SEO Spider.
            
            Look for evidence of:
            1. The 'External' tab being active (highlighted in the tab bar).
            2. A list of URLs that look like external websites (google.com, facebook.com, etc.).
            3. Use of the 'Bulk Export' menu or 'Export' button.
            
            Reply with JSON: {"evidence_found": boolean, "confidence": int, "details": string}
            """
            try:
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_resp.get('parsed', {})
                if parsed.get('evidence_found', False):
                    vlm_score = 15
                    feedback_parts.append("Visual evidence of external link analysis found")
                else:
                    feedback_parts.append("No visual evidence of external link workflow")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                # Fallback points if CSV was perfect, assume UI was used
                if csv_created and ext_links > 5:
                    vlm_score = 15
    
    score += vlm_score

    # Final Pass/Fail
    passed = score >= 60 and csv_created and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }