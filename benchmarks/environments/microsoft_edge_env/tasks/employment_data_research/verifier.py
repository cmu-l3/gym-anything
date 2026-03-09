#!/usr/bin/env python3
"""
Verifier for Employment Data Research task.

Scoring (100 points):
- Briefing file exists and modified after task start: 10 points
- Briefing contains a percentage value (e.g., "4.1%"): 15 points
- Briefing mentions all three required indicators: 15 points
- History shows visits to official government source (bls.gov or fred.stlouisfed.org): 25 points
- At least one data file was downloaded: 20 points
- "Labor Market Data" bookmark folder exists with official-source bookmarks: 15 points

Pass threshold: 65 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/employment_data_research_result.json"
PASS_THRESHOLD = 65


def verify_employment_data_research(traj, env_info, task_info):
    """Verify the Employment Data Research task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found — export script may not have run",
            }
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

        score = 0
        feedback_parts = []
        subscores = {}

        briefing = result.get("briefing", {})
        history = result.get("history", {})
        downloads = result.get("downloads", {})
        bookmarks = result.get("bookmarks", {})

        # Criterion 1: Briefing file exists and was modified after task start (10 pts)
        if briefing.get("exists") and briefing.get("modified_after_start"):
            score += 10
            subscores["briefing_exists"] = True
            feedback_parts.append("Briefing file created after task start (10/10)")
        elif briefing.get("exists"):
            score += 4
            subscores["briefing_exists"] = "stale"
            feedback_parts.append("Briefing exists but may be pre-existing (4/10)")
        else:
            subscores["briefing_exists"] = False
            feedback_parts.append("Briefing file not found at /home/ga/Desktop/labor_briefing.txt (0/10)")

        # Criterion 2: Briefing contains a percentage value (15 pts)
        if briefing.get("has_percentage"):
            score += 15
            subscores["has_percentage"] = True
            feedback_parts.append("Briefing contains numeric percentage values (15/15)")
        else:
            subscores["has_percentage"] = False
            feedback_parts.append("Briefing missing percentage values for economic indicators (0/15)")

        # Criterion 3: Briefing mentions all three required indicators (15 pts)
        indicators = {
            "unemployment": briefing.get("has_unemployment", False),
            "payroll/employment": briefing.get("has_payroll", False),
            "participation": briefing.get("has_participation", False),
        }
        found_indicators = sum(1 for v in indicators.values() if v)
        if found_indicators >= 3:
            score += 15
            subscores["indicators_covered"] = True
            feedback_parts.append("Briefing covers all three labor market indicators (15/15)")
        elif found_indicators == 2:
            score += 9
            subscores["indicators_covered"] = "partial"
            missing = [k for k, v in indicators.items() if not v]
            feedback_parts.append(f"Briefing covers 2/3 indicators (missing: {missing}) (9/15)")
        elif found_indicators == 1:
            score += 4
            subscores["indicators_covered"] = "minimal"
            feedback_parts.append(f"Briefing covers only 1/3 indicators (4/15)")
        else:
            subscores["indicators_covered"] = False
            feedback_parts.append("Briefing does not mention required labor market indicators (0/15)")

        # Criterion 4: History shows visits to official government sources (25 pts)
        visited_official = history.get("visited_official", False)
        bls_new = history.get("bls_new", False)
        fred_new = history.get("fred_new", False)
        if bls_new and fred_new:
            score += 25
            subscores["official_sources"] = True
            feedback_parts.append("Visited both BLS.gov and FRED (25/25)")
        elif visited_official:
            score += 15
            subscores["official_sources"] = "partial"
            source = "BLS.gov" if bls_new else "FRED" if fred_new else "Census.gov"
            feedback_parts.append(f"Visited one official source ({source}) (15/25)")
        else:
            subscores["official_sources"] = False
            feedback_parts.append("No visits to official government sources (bls.gov, fred.stlouisfed.org) detected (0/25)")

        # Criterion 5: At least one data file was downloaded (20 pts)
        has_downloads = downloads.get("has_new_downloads", False)
        official_dl = downloads.get("official_source_downloads", 0) > 0
        if has_downloads and official_dl:
            score += 20
            subscores["data_downloaded"] = True
            feedback_parts.append(f"Data file(s) downloaded from official sources (20/20)")
        elif has_downloads:
            score += 12
            subscores["data_downloaded"] = "partial"
            feedback_parts.append(f"File(s) downloaded but source not confirmed as official (12/20)")
        else:
            subscores["data_downloaded"] = False
            feedback_parts.append("No new data files detected in Downloads (0/20)")

        # Criterion 6: "Labor Market Data" bookmark folder with official sources (15 pts)
        folder_exists = bookmarks.get("labor_market_folder_exists", False)
        bm_count = bookmarks.get("labor_market_bookmark_count", 0)
        has_official_bm = bookmarks.get("labor_market_has_official", False)
        if folder_exists and bm_count >= 2 and has_official_bm:
            score += 15
            subscores["bookmark_folder"] = True
            feedback_parts.append(f"'Labor Market Data' folder with {bm_count} official-source bookmarks (15/15)")
        elif folder_exists and bm_count >= 1:
            score += 8
            subscores["bookmark_folder"] = "partial"
            feedback_parts.append(f"'Labor Market Data' folder exists with {bm_count} bookmark(s) (8/15)")
        elif folder_exists:
            score += 3
            subscores["bookmark_folder"] = "empty"
            feedback_parts.append("'Labor Market Data' folder exists but is empty (3/15)")
        else:
            subscores["bookmark_folder"] = False
            feedback_parts.append("No 'Labor Market Data' bookmark folder found (0/15)")

        score = min(score, 100)
        passed = score >= PASS_THRESHOLD

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores,
        }

    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
