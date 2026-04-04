#!/usr/bin/env python3
"""
Verifier for Press Freedom Analysis task.

Checks:
1. Firefox history for visits to required sources (RSF, Freedom House, CPJ).
2. Firefox bookmarks for organization and count.
3. JSON output file validity, structure, and data plausibility.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Plausibility Data Ranges (Anti-Gaming) ---
# These ranges are generous to account for year-to-year small variations,
# but strict enough to detect hallucinations or random guesses.
# Data reference: ~2023/2024 indices.

COUNTRY_RULES = {
    "norway": {
        "rsf_rank": (1, 10),              # Consistently top tier
        "fh_score": (90, 100),            # Consistently free
        "fh_status": ["Free"],
        "cpj_imprisoned": (0, 0)          # Rarely has imprisoned journalists
    },
    "united_states": {
        "rsf_rank": (20, 80),             # Fluctuate 40-50 usually
        "fh_score": (70, 95),             # Declined slightly but high
        "fh_status": ["Free"],
        "cpj_imprisoned": (0, 5)          # Occasional arrests, usually 0-2 long term
    },
    "brazil": {
        "rsf_rank": (50, 130),            # Mid-tier
        "fh_score": (50, 85),             # Free/Partly Free border
        "fh_status": ["Free", "Partly Free"],
        "cpj_imprisoned": (0, 5)
    },
    "india": {
        "rsf_rank": (130, 175),           # Poor ranking
        "fh_score": (40, 75),             # Partly Free
        "fh_status": ["Partly Free", "Not Free"], 
        "cpj_imprisoned": (0, 20)         # Often has several
    },
    "china": {
        "rsf_rank": (160, 180),           # Consistently bottom tier
        "fh_score": (0, 20),              # Not Free
        "fh_status": ["Not Free"],
        "cpj_imprisoned": (20, 200)       # World's worst jailer
    }
}

def verify_press_freedom_analysis(traj, env_info, task_info):
    """
    Verify the press freedom analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: Copy function not available"}

    # 1. Retrieve System State Result (exported by bash script)
    system_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp_sys:
        try:
            copy_from_env("/tmp/task_result.json", tmp_sys.name)
            with open(tmp_sys.name, 'r') as f:
                system_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load system result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve system state logs"}
        finally:
            if os.path.exists(tmp_sys.name):
                os.unlink(tmp_sys.name)

    # 2. Retrieve User Output File
    user_data = {}
    user_file_exists = system_result.get("output_file", {}).get("exists", False)
    user_file_path = system_result.get("output_file", {}).get("path", "")
    
    if user_file_exists:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp_user:
            try:
                copy_from_env(user_file_path, tmp_user.name)
                with open(tmp_user.name, 'r') as f:
                    user_data = json.load(f)
            except Exception as e:
                logger.error(f"Failed to load user json: {e}")
                # Don't fail yet, score will reflect invalid JSON
            finally:
                if os.path.exists(tmp_user.name):
                    os.unlink(tmp_user.name)

    # --- Scoring ---
    score = 0
    feedback = []

    # Criterion 1: History (20 pts)
    visits = system_result.get("history_visits", {})
    sources_visited = 0
    if visits.get("rsf", 0) > 0: sources_visited += 1
    if visits.get("freedom_house", 0) > 0: sources_visited += 1
    if visits.get("cpj", 0) > 0: sources_visited += 1

    if sources_visited == 3:
        score += 20
        feedback.append("Visited all 3 required sources (20/20)")
    elif sources_visited > 0:
        pts = sources_visited * 5
        score += pts
        feedback.append(f"Visited {sources_visited}/3 sources ({pts}/20)")
    else:
        feedback.append("No required sources visited (0/20)")

    # Criterion 2: Bookmarks (15 pts)
    bm_info = system_result.get("bookmarks", {})
    if bm_info.get("folder_exists"):
        score += 8
        count = bm_info.get("count", 0)
        domains = bm_info.get("domains_present", "")
        
        if count >= 5:
            score += 5
            feedback.append(f"Bookmark folder correct with {count} items (+13)")
        else:
            feedback.append(f"Bookmark folder exists but only {count}/5 items (+8)")
            
        # Diversity bonus (2 pts)
        diverse = 0
        if "rsf" in domains: diverse += 1
        if "fh" in domains: diverse += 1
        if "cpj" in domains: diverse += 1
        if diverse >= 2:
            score += 2
            feedback.append("Bookmarks cover multiple sources (+2)")
    else:
        feedback.append("Bookmark folder 'Press Freedom Research' not found (0/15)")

    # Criterion 3: JSON File Existence & Freshness (10 pts)
    file_info = system_result.get("output_file", {})
    if file_info.get("exists") and file_info.get("fresh"):
        score += 10
        feedback.append("Output JSON exists and is new (10/10)")
    elif file_info.get("exists"):
        score += 5
        feedback.append("Output JSON exists but timestamp is old (5/10)")
    else:
        feedback.append("Output JSON not found (0/10)")

    # Criterion 4: JSON Content & Plausibility (55 pts)
    # Only proceed if we parsed user data
    if user_data:
        countries_data = user_data.get("countries", {})
        
        # Structure check (5 pts)
        expected_keys = set(COUNTRY_RULES.keys())
        found_keys = set(k.lower() for k in countries_data.keys()) if isinstance(countries_data, dict) else set()
        
        if expected_keys.issubset(found_keys):
            score += 5
            feedback.append("All 5 countries present in JSON (5/5)")
        else:
            feedback.append(f"Missing countries in JSON: {expected_keys - found_keys} (0/5)")

        # Data Plausibility (50 pts, 10 per country)
        plausibility_score = 0
        
        for country, rules in COUNTRY_RULES.items():
            c_data = countries_data.get(country)
            # Try key variations if exact key not found (e.g., "United States" vs "united_states")
            if not c_data:
                for k, v in countries_data.items():
                    if k.lower().replace(" ", "_") == country:
                        c_data = v
                        break
            
            if not c_data:
                continue

            c_score = 0
            
            # RSF Rank (3 pts)
            try:
                rank = int(c_data.get("rsf_rank", -1))
                if rules["rsf_rank"][0] <= rank <= rules["rsf_rank"][1]:
                    c_score += 3
            except: pass

            # FH Score (3 pts)
            try:
                fh_s = int(c_data.get("freedom_house_score", -1))
                if rules["fh_score"][0] <= fh_s <= rules["fh_score"][1]:
                    c_score += 3
            except: pass

            # FH Status (2 pts)
            try:
                status = c_data.get("freedom_house_status", "Unknown")
                # Case insensitive check
                if any(s.lower() == status.lower() for s in rules["fh_status"]):
                    c_score += 2
            except: pass

            # CPJ (2 pts)
            try:
                cpj = int(c_data.get("cpj_journalists_imprisoned", -1))
                if rules["cpj_imprisoned"][0] <= cpj <= rules["cpj_imprisoned"][1]:
                    c_score += 2
                # Special check for China/high numbers
                elif country == "china" and cpj > 20: 
                    c_score += 2
            except: pass
            
            plausibility_score += c_score
        
        score += plausibility_score
        feedback.append(f"Data plausibility check: {plausibility_score}/50 pts")
        
        # Ordinal Check (Bonus/Sanity)
        # Verify Norway is better than China (lower RSF, higher FH)
        try:
            norway = countries_data.get("norway")
            china = countries_data.get("china")
            if norway and china:
                n_rsf = int(norway.get("rsf_rank"))
                c_rsf = int(china.get("rsf_rank"))
                if n_rsf < c_rsf:
                    feedback.append("Ordinal check passed: Norway rank < China rank")
                else:
                    score -= 10 # Penalize obvious fabrication
                    feedback.append("Ordinal check FAILED: Norway rank >= China rank (-10 pts)")
        except:
            pass

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }