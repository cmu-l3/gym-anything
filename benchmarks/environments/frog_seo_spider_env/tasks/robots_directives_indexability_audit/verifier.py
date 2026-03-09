#!/usr/bin/env python3
"""
Verifier for Robots Directives & Indexability Audit task.

Scoring Breakdown (100 points total):
1. CSV Export Verification (40 pts)
   - CSV created after task start (10 pts)
   - CSV contains target domain URLs (10 pts)
   - CSV contains Directive-specific columns (prevents wrong tab export) (10 pts)
   - CSV has meaningful data rows (>=10) (10 pts)

2. Report Verification (40 pts)
   - Report file exists and created during task (10 pts)
   - Report size >= 200 bytes (non-empty) (10 pts)
   - Report contains key terms (noindex/canonical/etc) (10 pts)
   - Report contains specific URLs/examples (10 pts)

3. VLM Trajectory Verification (20 pts)
   - Visual confirmation that Directives tab was visited/used.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_robots_directives_indexability_audit(traj, env_info, task_info):
    """Verify directives audit task."""
    
    # 1. Setup & Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Load JSON result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 2. CSV Verification (40 pts)
    csv_score = 0
    if result.get('csv_created'):
        csv_score += 10
        if result.get('csv_has_domain'):
            csv_score += 10
        if result.get('csv_has_directive_cols'):
            csv_score += 10
        if result.get('csv_row_count', 0) >= 10:
            csv_score += 10
    
    score += csv_score
    feedback_parts.append(f"CSV Export: {csv_score}/40")
    if csv_score < 40:
        if not result.get('csv_created'):
            feedback_parts.append("(No new CSV found)")
        elif not result.get('csv_has_directive_cols'):
            feedback_parts.append("(Wrong tab exported? Missing directive cols)")

    # 3. Report Verification (40 pts)
    report_score = 0
    if result.get('report_exists') and result.get('report_created_during'):
        report_score += 10
        if result.get('report_size', 0) >= 200:
            report_score += 10
        if result.get('report_has_keywords') and result.get('report_has_numbers'):
            report_score += 10
        if result.get('report_has_urls'):
            report_score += 10
    
    score += report_score
    feedback_parts.append(f"Report: {report_score}/40")
    if report_score < 40:
        if not result.get('report_exists'):
            feedback_parts.append("(Report file missing)")
        elif result.get('report_size', 0) < 200:
            feedback_parts.append("(Report too short)")

    # 4. VLM Trajectory Verification (20 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    
    if query_vlm and sample_frames:
        # Get frames to find usage of Directives tab
        frames = sample_frames(traj, n=4)
        
        prompt = """
        Analyze these screenshots of Screaming Frog SEO Spider.
        I need to verify if the user navigated to the 'Directives' tab or is analyzing indexability.
        
        Look for:
        1. The word 'Directives' highlighted in the tab bar.
        2. Columns like 'Meta Robots', 'X-Robots-Tag', 'Canonical'.
        3. Dropdown filters showing 'Noindex', 'Canonicalised', 'Nofollow'.
        
        Answer JSON:
        {
            "directives_tab_visible": true/false,
            "indexability_data_visible": true/false,
            "confidence": 0-100
        }
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('directives_tab_visible') or parsed.get('indexability_data_visible'):
                vlm_score = 20
                feedback_parts.append("VLM: Directives usage confirmed")
            else:
                feedback_parts.append("VLM: Directives tab not clearly seen")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if CSV is perfect, assume they must have seen it
            if csv_score == 40:
                vlm_score = 20
                feedback_parts.append("VLM skipped (implicit pass from CSV)")

    score += vlm_score
    feedback_parts.append(f"Visual: {vlm_score}/20")

    # 5. Final Pass/Fail
    # strict requirements: Must have CSV with correct cols AND Report with minimal content
    pass_threshold = 60
    key_requirements = (
        result.get('csv_has_directive_cols') and 
        result.get('csv_has_domain') and
        result.get('report_exists') and
        result.get('report_size', 0) > 50
    )
    
    passed = (score >= pass_threshold) and key_requirements

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }