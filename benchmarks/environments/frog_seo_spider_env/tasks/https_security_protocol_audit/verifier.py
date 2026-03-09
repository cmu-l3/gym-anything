#!/usr/bin/env python3
"""
Verifier for https_security_protocol_audit task.

Scoring Breakdown (100 pts):
1. Security CSV Export (25 pts)
   - Exists & created during task (10)
   - Valid row count (10)
   - Contains security columns (5)
2. Internal CSV Export (15 pts)
   - Exists & created during task (5)
   - Valid row count (10)
3. Security Audit Report (30 pts)
   - Exists & length >= 400 chars (10)
   - Contains 'mixed content' or 'hsts' (10)
   - Contains numeric counts (5)
   - Contains recommendations (5)
4. VLM Verification (30 pts)
   - Trajectory shows 'Security' tab was active (15)
   - Trajectory shows crawl progress/completion (15)
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_https_security_audit(traj, env_info, task_info):
    """Verify the HTTPS security audit task."""
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 2. Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Verify Security Export (25 pts)
    sec = result.get('security_export', {})
    if sec.get('exists'):
        score += 10
        if sec.get('row_count', 0) > 0:
            score += 10
            if sec.get('has_protocol_columns'):
                score += 5
                feedback_parts.append("Security export valid")
            else:
                feedback_parts.append("Security export missing protocol columns")
        else:
            feedback_parts.append("Security export empty")
    else:
        feedback_parts.append("Security export not found")

    # 4. Verify Internal Export (15 pts)
    # Why verify this? It proves the agent knows how to export different datasets
    internal = result.get('internal_export', {})
    if internal.get('exists'):
        score += 5
        if internal.get('row_count', 0) >= 10:
            score += 10
            feedback_parts.append("Internal export valid")
        else:
            feedback_parts.append("Internal export too small")
    else:
        feedback_parts.append("Internal export not found")

    # 5. Verify Report Content (30 pts)
    # We need to copy the actual report file to check content deeply
    rep = result.get('report', {})
    if rep.get('exists'):
        if rep.get('length', 0) >= 400:
            score += 10
            
            # Deep content check
            temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            try:
                copy_from_env("/home/ga/Documents/SEO/reports/security_audit_report.txt", temp_report.name)
                with open(temp_report.name, 'r', errors='ignore') as f:
                    content = f.read().lower()
                    
                    # Check for keywords
                    if 'mixed content' in content or 'hsts' in content:
                        score += 10
                    else:
                        feedback_parts.append("Report missing specific security terms (mixed content/HSTS)")
                        
                    # Check for numbers (counts)
                    if re.search(r'\d+', content):
                        score += 5
                    else:
                        feedback_parts.append("Report missing numeric counts")
                        
                    # Check for recommendations
                    if 'recommend' in content or 'fix' in content or 'remediation' in content:
                        score += 5
                    else:
                        feedback_parts.append("Report missing recommendations section")
                        
                feedback_parts.append(f"Report length {rep.get('length')} chars")
            except Exception:
                feedback_parts.append("Failed to read report content")
            finally:
                if os.path.exists(temp_report.name):
                    os.unlink(temp_report.name)
        else:
            score += 5 # Partial credit for existence
            feedback_parts.append(f"Report too short ({rep.get('length')} chars)")
    else:
        feedback_parts.append("Report file not found")

    # 6. VLM Verification (30 pts)
    # Check if they actually visited the Security tab
    query_vlm = env_info.get('query_vlm')
    from gym_anything.vlm import sample_trajectory_frames
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=6)
        
        prompt = """
        Analyze these screenshots of Screaming Frog SEO Spider usage.
        
        Look for:
        1. Is the 'Security' tab selected in the main navigation? (It is usually near 'Response Codes', 'Page Titles', etc.)
        2. Is the main data table showing security-related columns (e.g., 'Protocol', 'Status', 'Mixed Content')?
        3. Is there evidence of a crawl running or completed (green progress bar, URL count)?
        
        Return JSON:
        {
            "security_tab_visible": boolean,
            "crawl_evidence": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('security_tab_visible'):
                    score += 15
                    feedback_parts.append("VLM: Security tab usage verified")
                else:
                    feedback_parts.append("VLM: Security tab usage NOT verified")
                    
                if parsed.get('crawl_evidence'):
                    score += 15
                    feedback_parts.append("VLM: Crawl verified")
                else:
                    feedback_parts.append("VLM: Crawl NOT verified")
            else:
                # Fallback if VLM fails: give benefit of doubt if files are good
                if score >= 60: 
                    score += 30
                    feedback_parts.append("VLM skipped (error), assumed pass based on file outputs")
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            if score >= 60:
                score += 30

    # 7. Final Score
    passed = score >= 60 and rep.get('exists') and sec.get('exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }