#!/usr/bin/env python3
"""Verifier for tor_network_leak_audit task.

Checks:
1. Did the agent create the report?
2. Did the agent identify the correct SOCKS Proxy, Telemetry Status, and DNS leak status?
3. Are the raw HTML and screenshot evidence files saved?
4. VLM Check to confirm diagnostic pages were accessed in the trajectory.
"""

import json
import logging
import os
import re
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tor_network_leak_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    # 1. Load result JSON
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task_result.json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve results"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)
            
    # Onion Visited (10 points)
    if result.get("onion_visited"):
        score += 10
        feedback_parts.append("DuckDuckGo Onion visited (10/10)")
    else:
        feedback_parts.append("DuckDuckGo Onion not visited (0/10)")

    # 2. Verify Audit Report File
    report_meta = result.get("report_file", {})
    if report_meta.get("exists") and report_meta.get("created_during_task"):
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env("/home/ga/Documents/tor_leak_audit.txt", tmp_report.name)
            with open(tmp_report.name, 'r') as f:
                report_content = f.read()
            
            score += 10
            feedback_parts.append("Audit Report exists (10/10)")
            
            # Regex Validation
            telemetry_match = re.search(r"Telemetry Status:\s*(Disabled)", report_content, re.IGNORECASE)
            if telemetry_match:
                score += 15
                feedback_parts.append("Telemetry Status correct (15/15)")
            else:
                feedback_parts.append("Telemetry Status incorrect/missing (0/15)")
                
            dns_match = re.search(r"DNS Leaks Detected:\s*(No|False)", report_content, re.IGNORECASE)
            if dns_match:
                score += 10
                feedback_parts.append("DNS Leak Status correct (10/10)")
            else:
                feedback_parts.append("DNS Leak Status incorrect/missing (0/10)")
                
            # Usually 127.0.0.1:9150 for tor browser, we'll allow 915x
            socks_match = re.search(r"Active SOCKS Proxy:\s*(127\.0\.0\.1:915\d)", report_content, re.IGNORECASE)
            gate_socks_passed = False
            if socks_match:
                score += 25
                gate_socks_passed = True
                feedback_parts.append(f"SOCKS Proxy correct [{socks_match.group(1)}] (25/25)")
            else:
                feedback_parts.append("SOCKS Proxy incorrect/missing (0/25)")

        except Exception as e:
            logger.error(f"Failed to read report: {e}")
            feedback_parts.append("Report file could not be read.")
            gate_socks_passed = False
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("Audit Report NOT created (0/60)")
        gate_socks_passed = False

    # 3. Verify HTML source save
    html_meta = result.get("html_file", {})
    if html_meta.get("exists") and html_meta.get("created_during_task") and html_meta.get("size_bytes", 0) > 500:
        tmp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
        tmp_html.close()
        try:
            copy_from_env("/home/ga/Documents/sockets_source.html", tmp_html.name)
            with open(tmp_html.name, 'r', encoding='utf-8', errors='ignore') as f:
                html_content = f.read()
            
            # Must contain networking traces
            if "127.0.0.1" in html_content and ("9150" in html_content or "915" in html_content):
                score += 20
                feedback_parts.append("Sockets HTML saved correctly (20/20)")
            else:
                score += 10
                feedback_parts.append("Sockets HTML saved but missing expected connection traces (10/20)")
        except Exception as e:
            feedback_parts.append("Failed to evaluate HTML.")
        finally:
            if os.path.exists(tmp_html.name):
                os.unlink(tmp_html.name)
    else:
        feedback_parts.append("Sockets HTML NOT saved correctly (0/20)")

    # 4. Verify Image save
    img_meta = result.get("image_file", {})
    if img_meta.get("exists") and img_meta.get("created_during_task") and img_meta.get("size_bytes", 0) > 0:
        score += 10
        feedback_parts.append("Telemetry Screenshot saved (10/10)")
    else:
        feedback_parts.append("Telemetry Screenshot NOT saved (0/10)")

    # 5. Optional VLM anti-gaming check
    # Check if the agent actually looked at about:networking or about:telemetry
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = ("Look at these screenshots from a web browsing session. "
                      "Do any of them show internal browser diagnostic pages like 'about:networking' "
                      "or 'about:telemetry'? Answer 'YES' or 'NO'.")
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if "YES" in vlm_res.upper():
                feedback_parts.append("VLM confirms diagnostic pages accessed")
            else:
                feedback_parts.append("Warning: VLM did not see diagnostic pages accessed in sampled frames")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Pass threshold is 70 points AND SOCKS proxy gate
    passed = (score >= 70) and gate_socks_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }