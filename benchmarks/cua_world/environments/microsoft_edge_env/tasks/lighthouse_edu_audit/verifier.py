#!/usr/bin/env python3
"""
Verifier for Lighthouse Accessibility and Performance Audit task.

Verification Logic:
1. Report File Analysis:
   - Must exist and be modified after task start.
   - Must be > 400 bytes (non-trivial).
   - Must contain names of all 3 target sites.
   - Must contain keywords "performance" and "accessibility".
   - Must contain numerical scores (0-100).
   - Must contain recommendation language.

2. Browser History Analysis:
   - Must show visits to Khan Academy, Coursera, and MIT OCW *after* task start.

Scoring Breakdown (100 pts total):
- File Mechanics (15 pts): Exists (10), Non-trivial size (5)
- History Verification (30 pts): 10 pts per site visited
- Report Content (55 pts):
  - Mentions sites: 8 pts each (24 total)
  - Keywords (perf/access): 5 pts each (10 total)
  - Scores present: 11 pts
  - Recommendation/Synthesis: 10 pts

Pass Threshold: 65 points
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_lighthouse_audit(traj, env_info, task_info):
    """Verify the Lighthouse Audit task."""
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env unavailable"}

    # Temp files
    result_json_path = tempfile.mktemp(suffix=".json")
    
    try:
        # Copy JSON result
        copy_from_env("/tmp/lighthouse_edu_audit_result.json", result_json_path)
        
        with open(result_json_path, "r") as f:
            data = json.load(f)
            
        report_data = data.get("report", {})
        history_data = data.get("history", {})
        
        score = 0
        feedback = []
        
        # --- CRITERION 1: File Mechanics (15 pts) ---
        if report_data.get("exists") and report_data.get("modified_after_start"):
            score += 10
            feedback.append("Report file created successfully (+10).")
            
            if report_data.get("size", 0) > 400:
                score += 5
                feedback.append("Report has sufficient content depth (+5).")
            else:
                feedback.append("Report is too short/trivial.")
        else:
            feedback.append("Report file not found or pre-dated task start.")
            # If no report, major penalty, but we check history
        
        # --- CRITERION 2: History Verification (30 pts) ---
        sites_visited = 0
        if history_data.get("khan_visited"):
            score += 10
            sites_visited += 1
            feedback.append("Verified visit to Khan Academy (+10).")
        else:
            feedback.append("Khan Academy not found in history.")
            
        if history_data.get("coursera_visited"):
            score += 10
            sites_visited += 1
            feedback.append("Verified visit to Coursera (+10).")
        else:
            feedback.append("Coursera not found in history.")
            
        if history_data.get("mit_visited"):
            score += 10
            sites_visited += 1
            feedback.append("Verified visit to MIT OCW (+10).")
        else:
            feedback.append("MIT OCW not found in history.")

        # --- CRITERION 3: Report Content Analysis (55 pts) ---
        content = report_data.get("content_preview", "").lower()
        
        if content:
            # Check for site mentions (24 pts)
            if "khan" in content:
                score += 8
            else:
                feedback.append("Report missing mention of Khan Academy.")
                
            if "coursera" in content:
                score += 8
            else:
                feedback.append("Report missing mention of Coursera.")
                
            if "mit" in content or "ocw" in content:
                score += 8
            else:
                feedback.append("Report missing mention of MIT OCW.")
            
            # Check for audit keywords (10 pts)
            if "performance" in content:
                score += 5
            else:
                feedback.append("Report missing 'Performance' keyword.")
                
            if "accessibility" in content:
                score += 5
            else:
                feedback.append("Report missing 'Accessibility' keyword.")
            
            # Check for numerical scores (11 pts)
            # Regex looks for 2-3 digit numbers potentially followed by %, /100, or just standing alone
            # Matches: 95, 100, 82%, 82/100
            scores = re.findall(r'\b\d{2,3}(?:/100|%)?\b', content)
            unique_scores = set(scores)
            
            if len(unique_scores) >= 3:
                score += 11
                feedback.append(f"Found numerical scores in report (+11).")
            else:
                feedback.append("Report lacks distinct numerical scores for the sites.")
            
            # Check for recommendation language (10 pts)
            rec_keywords = ["recommend", "adopt", "suitable", "conclusion", "summary", "verdict", "score"]
            if any(k in content for k in rec_keywords):
                score += 10
                feedback.append("Report includes recommendation/synthesis (+10).")
            else:
                feedback.append("Report lacks clear recommendation language.")

        # --- FINAL EVALUATION ---
        passed = score >= 65
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }
        
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)