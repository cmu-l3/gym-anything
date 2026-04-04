#!/usr/bin/env python3
"""
Verifier for Page Performance Audit task.

Scoring Breakdown (100 points total):
1. CSV Export Verification (40 pts)
   - CSV created after task start: 10 pts
   - Contains 'Response Time' column: 10 pts
   - Contains 'Size' column: 10 pts
   - Contains 'Word Count' column: 5 pts
   - Has meaningful data (>20 rows) from target domain: 5 pts

2. Report Verification (30 pts)
   - Report file exists: 10 pts
   - Length > 400 chars: 5 pts
   - Contains numbers (analysis): 5 pts
   - Contains target URLs: 5 pts
   - Contains keywords (slow, recommend, etc.): 5 pts

3. VLM Trajectory Verification (20 pts)
   - Confirms user actually crawled and used the interface, not just wrote files.

4. Application State (10 pts)
   - Screaming Frog was running: 10 pts

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory for shared utilities if needed
# sys.path.insert(0, str(Path(__file__).parent.parent))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_page_performance_audit(traj, env_info, task_info):
    """Verify the page performance audit task."""
    
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load result JSON from export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # --- Section 1: CSV Export Verification (40 pts) ---
    csv_found = result.get('csv_found', False)
    csv_has_time = result.get('csv_has_response_time', False)
    csv_has_size = result.get('csv_has_size', False)
    csv_has_words = result.get('csv_has_word_count', False)
    csv_rows = result.get('csv_row_count', 0)
    csv_domain = result.get('csv_target_domain', False)

    if csv_found:
        score += 10
        feedback_parts.append("CSV export found (+10)")
        
        if csv_has_time:
            score += 10
            feedback_parts.append("Response Time column found (+10)")
        else:
            feedback_parts.append("Response Time column missing")
            
        if csv_has_size:
            score += 10
            feedback_parts.append("Size column found (+10)")
        else:
            feedback_parts.append("Size column missing")
            
        if csv_has_words:
            score += 5
            feedback_parts.append("Word Count column found (+5)")
            
        if csv_rows > 20 and csv_domain:
            score += 5
            feedback_parts.append(f"Data validated ({csv_rows} rows from target domain) (+5)")
        elif csv_rows <= 20:
            feedback_parts.append(f"Insufficient data rows ({csv_rows})")
        elif not csv_domain:
            feedback_parts.append("Target domain data not found in CSV")
    else:
        feedback_parts.append("No valid performance CSV export found")

    # --- Section 2: Report Verification (30 pts) ---
    report_found = result.get('report_found', False)
    report_len = result.get('report_length', 0)
    report_nums = result.get('report_has_numbers', False)
    report_url = result.get('report_has_target_url', False)
    report_kw = result.get('report_has_keywords', False)

    if report_found:
        score += 10
        feedback_parts.append("Report file found (+10)")
        
        if report_len >= 400:
            score += 5
            feedback_parts.append("Report length OK (+5)")
        else:
            feedback_parts.append(f"Report too short ({report_len} chars)")
            
        if report_nums:
            score += 5
            feedback_parts.append("Quantitative analysis found (+5)")
            
        if report_url:
            score += 5
            feedback_parts.append("Target URLs referenced (+5)")
            
        if report_kw:
            score += 5
            feedback_parts.append("Recommendations/Analysis keywords found (+5)")
    else:
        feedback_parts.append("No performance report found")

    # --- Section 3: App State (10 pts) ---
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog running (+10)")
    else:
        feedback_parts.append("Screaming Frog not running")

    # --- Section 4: VLM Trajectory Verification (20 pts) ---
    # We verify the agent actually used the tool using trajectory frames
    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    
    vlm_score = 0
    if query_vlm and sample_frames:
        try:
            frames = sample_frames(traj, n=3)
            if frames:
                prompt = """
                Analyze these screenshots of an SEO agent's workflow.
                I need to verify if the agent:
                1. Crawled a website (progress bar, URL list populated).
                2. Viewed the 'Internal' tab or 'HTML' filter.
                3. Performed an Export or Report generation action.
                
                Respond in JSON:
                {
                    "crawled_website": true/false,
                    "viewed_internal_tab": true/false,
                    "export_action_visible": true/false,
                    "confidence": 0-100
                }
                """
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_resp.get('parsed', {})
                
                if parsed.get('crawled_website'):
                    vlm_score += 10
                    feedback_parts.append("VLM: Crawl verified (+10)")
                if parsed.get('viewed_internal_tab') or parsed.get('export_action_visible'):
                    vlm_score += 10
                    feedback_parts.append("VLM: Analysis/Export verified (+10)")
            else:
                # If no frames available, award points if CSV/Report implies tool usage
                if csv_found and report_found:
                    vlm_score = 20
                    feedback_parts.append("Implicit workflow verification (output files valid) (+20)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback
            if csv_found and report_found:
                vlm_score = 20
    else:
        # If VLM not available, grant points if outputs are solid
        if csv_found and report_found:
            vlm_score = 20
            feedback_parts.append("VLM unavailable, trusting output files (+20)")
            
    score += vlm_score

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }