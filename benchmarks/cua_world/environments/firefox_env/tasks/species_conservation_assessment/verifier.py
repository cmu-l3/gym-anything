#!/usr/bin/env python3
"""
Verifier for species_conservation_assessment task.

Scoring (100 pts total):
1. History Evidence (15 pts): Visits to ≥2 of the 3 required domains.
2. Bookmarks (20 pts): Folder 'Conservation Assessment' exists (10) and has ≥5 bookmarks (10).
3. Output File (10 pts): JSON file exists and is fresh.
4. Content Accuracy (55 pts):
   - All 5 species present (10 pts)
   - Correct IUCN status codes (20 pts, 4 per species)
   - Correct ESA status (10 pts, 2 per species)
   - Scientific names correct (5 pts, 1 per species)
   - Trends & Threats fields populated (10 pts, 2 per species)
"""

import json
import logging
import os
import tempfile
import re

logger = logging.getLogger(__name__)

# Ground Truth Data
SPECIES_KEYS = [
    "red_wolf", "california_condor", "black_footed_ferret", "whooping_crane", "florida_manatee"
]

def normalize_text(text):
    if not text: return ""
    return re.sub(r'\s+', ' ', str(text).strip().lower())

def verify_species_conservation_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result from environment
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp_file.name)
        with open(tmp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load task result JSON"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    score = 0
    feedback = []
    
    # --- 1. History Evidence (15 pts) ---
    hist = result.get("history", {})
    domains_visited = 0
    if hist.get("iucn_visits", 0) > 0: domains_visited += 1
    if hist.get("ecos_visits", 0) > 0: domains_visited += 1
    if hist.get("natureserve_visits", 0) > 0: domains_visited += 1
    
    if domains_visited >= 2:
        score += 15
        feedback.append(f"History: Visited {domains_visited}/3 required domains (+15)")
    elif domains_visited == 1:
        score += 5
        feedback.append("History: Visited only 1/3 required domains (+5)")
    else:
        feedback.append("History: No required biodiversity databases visited")

    # --- 2. Bookmarks (20 pts) ---
    bm = result.get("bookmarks", {})
    if bm.get("folder_exists", 0):
        score += 10
        feedback.append("Bookmarks: Folder found (+10)")
        count = bm.get("count", 0)
        if count >= 5:
            score += 10
            feedback.append(f"Bookmarks: {count} bookmarks found (>=5) (+10)")
        else:
            feedback.append(f"Bookmarks: Only {count} bookmarks found (<5)")
    else:
        feedback.append("Bookmarks: 'Conservation Assessment' folder not found")

    # --- 3. Output File (10 pts) ---
    file_info = result.get("file", {})
    if file_info.get("exists", 0) and file_info.get("fresh", 0):
        score += 10
        feedback.append("File: JSON output exists and is fresh (+10)")
        content = file_info.get("content", {})
    else:
        feedback.append("File: JSON output missing or stale")
        # Stop here if no file to analyze
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # --- 4. Content Analysis (55 pts) ---
    ground_truth = task_info.get("metadata", {}).get("species_ground_truth", {})
    
    # A. Species Presence (10 pts)
    species_found = [k for k in SPECIES_KEYS if k in content]
    if len(species_found) == 5:
        score += 10
        feedback.append("Content: All 5 species present (+10)")
    else:
        pts = len(species_found) * 2
        score += pts
        feedback.append(f"Content: {len(species_found)}/5 species found (+{pts})")

    # Detailed checks
    iucn_score = 0
    esa_score = 0
    sci_name_score = 0
    details_score = 0
    
    for key in species_found:
        entry = content.get(key, {})
        gt = ground_truth.get(key, {})
        
        # IUCN Status (4 pts each)
        # Allow code (CR) or full text match
        user_iucn = normalize_text(entry.get("iucn_status", ""))
        valid_iucn = [normalize_text(x) for x in gt.get("iucn_status", [])]
        
        # Check if user input contains the code (e.g. "CR" in "CR - Critically Endangered")
        match = False
        for v in valid_iucn:
            if v in user_iucn or user_iucn in v:
                match = True
                break
        
        if match and user_iucn:
            iucn_score += 4
            
        # ESA Status (2 pts each)
        user_esa = normalize_text(entry.get("esa_status", ""))
        valid_esa = [normalize_text(x) for x in gt.get("esa_status", [])]
        if any(v in user_esa for v in valid_esa) and user_esa:
            esa_score += 2
            
        # Scientific Name (1 pt each)
        user_sci = normalize_text(entry.get("scientific_name", ""))
        valid_sci = normalize_text(gt.get("scientific_name", ""))
        if valid_sci in user_sci and user_sci:
            sci_name_score += 1
            
        # Trend and Threats (2 pts each if present and non-empty)
        trend = entry.get("population_trend", "")
        threats = entry.get("primary_threats", [])
        if trend and isinstance(threats, list) and len(threats) >= 2:
            details_score += 2

    score += iucn_score
    score += esa_score
    score += sci_name_score
    score += details_score
    
    feedback.append(f"Data Quality: IUCN ({iucn_score}/20), ESA ({esa_score}/10), SciName ({sci_name_score}/5), Details ({details_score}/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }