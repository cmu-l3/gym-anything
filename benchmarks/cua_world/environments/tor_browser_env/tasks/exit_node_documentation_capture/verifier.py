#!/usr/bin/env python3
import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exit_node_documentation_capture(traj, env_info, task_info):
    """
    Scoring System (100 points):
    - Directory & History: 10 pts
    - Source File Exists (>1KB) and is NEW: 15 pts (Gate)
    - IP File Exists and is NEW: 15 pts (Gate)
    - Source Content is Valid Tor Check HTML: 15 pts
    - Data Cross-Match (IP in HTML): 20 pts
    - VLM Trajectory (Agent viewed page source): 25 pts
    
    Pass threshold: >=65 points AND both Gates must be met.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)
            
    # Evaluate Directory and History (10 pts)
    if result.get('dir_exists') and result.get('history_verified'):
        score += 10
        feedback_parts.append("Directory created and history verified")
    else:
        feedback_parts.append("Directory missing or history not verified")
        
    # Evaluate HTML File Gate (15 pts)
    html_exists = result.get('html_exists')
    html_new = result.get('html_new')
    html_size = result.get('html_size', 0)
    
    if html_exists and html_new and html_size > 1000:
        score += 15
        feedback_parts.append("Source file exists and is appropriately sized")
        gate_html_passed = True
    else:
        feedback_parts.append(f"Source file validation failed (exists: {html_exists}, new: {html_new}, size: {html_size})")
        gate_html_passed = False
        
    # Evaluate IP File Gate (15 pts)
    ip_exists = result.get('ip_exists')
    ip_new = result.get('ip_new')
    ip_content = result.get('ip_content', '').strip()
    
    # Simple IP regex match (captures IPv4 and compressed/uncompressed IPv6)
    ip_pattern = r"([0-9]{1,3}(?:\.[0-9]{1,3}){3}|[a-fA-F0-9:]+:[a-fA-F0-9:]+)"
    ip_match = re.search(ip_pattern, ip_content)
    
    if ip_exists and ip_new and ip_match:
        extracted_ip = ip_match.group(0)
        score += 15
        feedback_parts.append(f"IP file valid, extracted IP: {extracted_ip}")
        gate_ip_passed = True
    else:
        extracted_ip = None
        feedback_parts.append(f"IP file validation failed (exists: {ip_exists}, new: {ip_new}, content_match: {bool(ip_match)})")
        gate_ip_passed = False
        
    # 2. Read check_source.html
    html_content = ""
    if html_exists:
        tmp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
        tmp_html.close()
        try:
            copy_from_env("/tmp/check_source.html", tmp_html.name)
            with open(tmp_html.name, 'r', encoding='utf-8', errors='ignore') as f:
                html_content = f.read()
        except Exception as e:
            logger.warning(f"Failed to read check_source.html from env: {e}")
        finally:
            if os.path.exists(tmp_html.name):
                os.unlink(tmp_html.name)
                
    # Validate HTML Content (15 pts)
    if html_content and ("check.torproject.org" in html_content.lower() or "configured to use tor" in html_content.lower()):
        score += 15
        feedback_parts.append("Source content verified as Tor check page")
    else:
        feedback_parts.append("Source content invalid or missing Tor markers")
        
    # Data Cross-Match (20 pts)
    # Proof the agent copied the actual IP bound to this specific session dynamically
    if extracted_ip and html_content and extracted_ip in html_content:
        score += 20
        feedback_parts.append("Anti-gaming passed: IP found inside saved HTML source")
    else:
        feedback_parts.append("Anti-gaming failed: Extracted IP not found in saved HTML source")

    # 3. VLM Verification (25 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        prompt = (
            "Review these frames from an agent interacting with Tor Browser. "
            "Did the agent at any point view the raw HTML page source or use Developer Tools (Inspector/Network) "
            "while visiting check.torproject.org? Look for a 'view-source:' URL or the developer tools panel "
            "open at the bottom/side. Reply strictly with 'YES' if they viewed the source code, or 'NO' if they did not."
        )
        
        vlm_response = query_vlm(images=frames + [final], prompt=prompt)
        
        if vlm_response and 'YES' in vlm_response.upper():
            score += 25
            feedback_parts.append("VLM verified source code viewing")
        else:
            feedback_parts.append("VLM could not verify source code viewing")
            
    except Exception as e:
        logger.warning(f"VLM verification failed/unavailable: {e}")
        feedback_parts.append("VLM verification skipped/failed")

    # Final decision logic
    passed = score >= 65 and gate_html_passed and gate_ip_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }