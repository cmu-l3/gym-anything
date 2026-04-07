#!/usr/bin/env python3
"""
Verifier for Client Storage Privacy Audit task.

Scoring Breakdown (100 points):
1. Report Status (10 pts): Exists and modified during task.
2. Verified Navigation (30 pts): Browser history confirms visits to Wikipedia, GitHub, Reddit.
3. Report Content - Coverage (10 pts): Mentions all 3 domains.
4. Report Content - Terminology (20 pts): Mentions Cookies, Local Storage, IndexedDB.
5. Report Content - Specificity (20 pts): Contains specific cookie names/keys (anti-gaming).
6. Report Quality (10 pts): Length > 500 chars (not just a placeholder).

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

def verify_client_storage_privacy_audit(traj, env_info, task_info):
    """Verify the privacy audit task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Temp files for result JSON and report text
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    tmp_result.close()
    tmp_report.close()

    try:
        # 1. Fetch JSON result
        try:
            copy_from_env("/tmp/task_result.json", tmp_result.name)
            with open(tmp_result.name, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

        # 2. Fetch Report Content (if exists)
        report_content = ""
        if result.get("report", {}).get("exists"):
            try:
                copy_from_env("/home/ga/Desktop/storage_audit_report.txt", tmp_report.name)
                with open(tmp_report.name, "r", errors="ignore") as f:
                    report_content = f.read()
            except Exception as e:
                logger.warning(f"Failed to copy report file despite existence flag: {e}")

        # --- SCORING ---
        score = 0
        feedback = []

        report_meta = result.get("report", {})
        history = result.get("history", {})
        
        # Criterion 1: Report Status (10 pts)
        if report_meta.get("exists") and report_meta.get("modified_after_start"):
            score += 10
            feedback.append("Report created successfully (10/10)")
        elif report_meta.get("exists"):
            score += 5
            feedback.append("Report exists but pre-dates task start (5/10)")
        else:
            feedback.append("Report file not found (0/10)")

        # Criterion 2: Verified Navigation (30 pts)
        sites_visited = 0
        if history.get("wikipedia"): sites_visited += 1
        if history.get("github"): sites_visited += 1
        if history.get("reddit"): sites_visited += 1
        
        hist_score = sites_visited * 10
        score += hist_score
        feedback.append(f"Browser history confirms {sites_visited}/3 sites visited ({hist_score}/30)")

        # Analyze Report Content
        lower_content = report_content.lower()
        
        # Criterion 3: Report Coverage (10 pts)
        # Check if domains are mentioned in text
        domains_mentioned = 0
        if "wikipedia" in lower_content: domains_mentioned += 1
        if "github" in lower_content: domains_mentioned += 1
        if "reddit" in lower_content: domains_mentioned += 1
        
        if domains_mentioned == 3:
            score += 10
            feedback.append("Report mentions all 3 target sites (10/10)")
        elif domains_mentioned > 0:
            score += 5
            feedback.append(f"Report mentions {domains_mentioned}/3 sites (5/10)")
        else:
            feedback.append("Report does not mention target sites (0/10)")

        # Criterion 4: Terminology (20 pts)
        terms = ["cookie", "local storage", "indexeddb", "session storage"]
        found_terms = [t for t in terms if t in lower_content]
        
        term_score = min(20, len(found_terms) * 5) # 5 pts per term, max 20
        score += term_score
        feedback.append(f"Report uses {len(found_terms)} correct technical terms ({term_score}/20)")

        # Criterion 5: Specificity (20 pts)
        # Look for specific known keys/cookies to prove actual inspection
        # Wikipedia: WMF-Last-Access, GeoIP, centralauth
        # GitHub: _gh_sess, logged_in, color_mode
        # Reddit: csv, edgebucket, loid
        indicators = [
            "wmf-last-access", "geoip", "centralauth",
            "_gh_sess", "logged_in", "color_mode",
            "edgebucket", "loid"
        ]
        found_indicators = [i for i in indicators if i in lower_content]
        
        if len(found_indicators) >= 3:
            score += 20
            feedback.append(f"Report contains specific storage keys/cookie names ({len(found_indicators)} found) (20/20)")
        elif len(found_indicators) > 0:
            score += 10
            feedback.append("Report contains few specific storage keys (10/20)")
        else:
            feedback.append("Report lacks specific technical details (cookie/key names) (0/20)")

        # Criterion 6: Report Quality (10 pts)
        if len(report_content) > 500:
            score += 10
            feedback.append("Report is of sufficient length (10/10)")
        elif len(report_content) > 100:
            score += 5
            feedback.append("Report is very short (5/10)")
        else:
            feedback.append("Report is empty or trivial (0/10)")

        # Final Verification
        passed = score >= 60 and sites_visited >= 2 and len(report_content) > 100
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(tmp_result.name): os.unlink(tmp_result.name)
        if os.path.exists(tmp_report.name): os.unlink(tmp_report.name)