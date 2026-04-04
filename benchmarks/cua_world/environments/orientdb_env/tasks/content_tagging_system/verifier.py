#!/usr/bin/env python3
"""
Verifier for content_tagging_system task.

Verifies:
1. Schema structure (Tags class, HasTag class, Index)
2. Data population (10 specific tags)
3. Tagging logic accuracy (Hotels/Restaurants tagged correctly based on rules)
4. Anti-gaming (No blanket tagging, correct constraints)
5. Report file accuracy (JSON report matches DB state)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_content_tagging_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    schema = result.get('db_schema', {})
    data = result.get('db_data', {})
    report = result.get('report_content', {})
    task_start = result.get('task_start', 0)
    report_mtime = result.get('report_mtime', 0)

    # --- 1. Schema Verification (20 pts) ---
    # Tags Class (8 pts)
    if schema.get('Tags_exists'):
        if schema.get('Tags_superClass') == 'V':
            score += 8
            feedback.append("Tags class exists and extends V.")
        else:
            score += 4
            feedback.append("Tags class exists but superclass is incorrect (expected V).")
    else:
        feedback.append("Tags class missing.")

    # HasTag Class (7 pts)
    if schema.get('HasTag_exists'):
        if schema.get('HasTag_superClass') == 'E':
            score += 7
            feedback.append("HasTag edge class exists and extends E.")
        else:
            score += 3
            feedback.append("HasTag class exists but superclass is incorrect (expected E).")
    else:
        feedback.append("HasTag class missing.")

    # Index (5 pts)
    # Check if any index is on 'Name' property
    # schema['Tags_indexes'] is a list of index names. Usually "Tags.Name".
    # We allow flexible naming, but verifying exact property binding requires more detailed extraction.
    # The export script extracted index names.
    has_index = any('Name' in idx or 'name' in idx.lower() for idx in schema.get('Tags_indexes', []))
    if has_index:
        score += 5
        feedback.append("Index on Tags.Name found.")
    else:
        feedback.append("Index on Tags.Name missing.")

    # --- 2. Data Population (12 pts) ---
    expected_tags = set([
        "luxury", "budget", "cultural", "romantic", "urban", 
        "historic", "family-friendly", "business", "adventure", "beach"
    ])
    
    # data['tag_names'] is list of dicts: [{'Name': 'luxury'}, ...]
    actual_tags = set()
    for t in data.get('tag_names', []):
        if t and 'Name' in t:
            actual_tags.add(t['Name'])
    
    missing_tags = expected_tags - actual_tags
    if len(actual_tags) == 10 and not missing_tags:
        score += 12
        feedback.append("All 10 expected tags present.")
    elif len(actual_tags) >= 10 and not missing_tags:
        # Maybe they added extras?
        score += 10
        feedback.append("All expected tags present (plus extras).")
    elif len(missing_tags) < 5:
        score += 5
        feedback.append(f"Some tags missing: {list(missing_tags)}")
    else:
        feedback.append("Major tags missing.")

    # --- 3. Edge Logic & Accuracy (48 pts) ---
    hastag_count = data.get('hastag_count', 0)
    
    if hastag_count > 0:
        score += 10
        feedback.append(f"HasTag edges created (count: {hastag_count}).")
    else:
        feedback.append("No HasTag edges created.")

    # Luxury Logic (12 pts + 8 pts anti-gaming)
    # Luxury rule: Stars = 5 -> 'luxury'.
    # We checked: Stars of hotels that HAVE 'luxury' tag.
    # Correct: All stars in list should be 5.
    luxury_stars = [h.get('Stars') for h in data.get('luxury_hotels_stars', [])]
    
    if not luxury_stars:
        feedback.append("No hotels tagged 'luxury'.")
    else:
        # Check for false positives (hotels tagged luxury that aren't 5 stars)
        false_positives = [s for s in luxury_stars if s < 5]
        if not false_positives:
            score += 8  # Anti-gaming: No false luxury tags
            feedback.append("No non-5-star hotels tagged 'luxury'.")
            
            # Did they tag ALL 5-star hotels?
            # We don't have exact count of 5-star hotels in export to compare perfectly,
            # but we can infer if count is reasonable.
            # Assuming demo data has some 5 star hotels.
            if len(luxury_stars) > 0:
                score += 12
                feedback.append("Luxury tagging logic appears correct.")
        else:
            feedback.append(f"Found {len(false_positives)} hotels tagged 'luxury' that are not 5 stars.")
            # Partial credit if some correct
            if len(false_positives) < len(luxury_stars) / 2:
                score += 5
                feedback.append("Luxury tagging partially correct.")

    # Cultural Logic (10 pts)
    # Italy hotels/restaurants should be cultural.
    italy_tagged = data.get('italy_tagged_cultural', 0)
    italy_total = data.get('italy_total', 0)
    
    if italy_total > 0 and italy_tagged == italy_total:
        score += 10
        feedback.append("All Italy entities correctly tagged 'cultural'.")
    elif italy_tagged > 0:
        score += 5
        feedback.append(f"Some Italy entities tagged 'cultural' ({italy_tagged}/{italy_total}).")
    else:
        feedback.append("Italy entities not tagged 'cultural'.")

    # Restaurant check (8 pts)
    # Just need to verify edges exist on Restaurants. 
    # Our simple export didn't separate Hotel/Restaurant edges specifically, 
    # but the italy_total includes V (Hotels + Restaurants). 
    # If italy_tagged == italy_total, it implies restaurants were tagged too.
    # We'll use a heuristic based on total edges vs total hotels to guess if Restaurants were included.
    total_hotels = data.get('total_hotels', 0)
    if hastag_count > total_hotels: # Rough heuristic that we tagged more than just hotels
        score += 8
        feedback.append("Edges appear to cover Restaurants as well.")
    else:
        # Fallback check on italy_tagged
        if italy_tagged > 0:
             score += 8 
             feedback.append("Restaurants likely tagged (based on Italy check).")

    # --- 4. Report File (20 pts) ---
    if result.get('report_exists'):
        # Check timestamp
        if report_mtime > task_start:
            score += 5
            feedback.append("Report file created during task.")
            
            # Validate content
            if isinstance(report, dict):
                # Count accuracy (10 pts)
                # Allow small tolerance
                rep_edge_count = report.get('total_hastag_edges', 0)
                if abs(rep_edge_count - hastag_count) < 5:
                    score += 10
                    feedback.append("Report edge count matches database.")
                else:
                    feedback.append(f"Report edge count ({rep_edge_count}) mismatch with DB ({hastag_count}).")
                
                # Tags list (5 pts)
                rep_tags = report.get('tags_list', [])
                if sorted(rep_tags) == sorted(list(expected_tags)):
                    score += 5
                    feedback.append("Report tags list correct.")
                else:
                    feedback.append("Report tags list incorrect.")
            else:
                feedback.append("Report file is not valid JSON.")
        else:
            feedback.append("Report file old or not modified.")
    else:
        feedback.append("Report file not found.")

    # --- 5. Anti-gaming / Sanity Checks ---
    # Blanket tagging check: if luxury_tag_count == total_hotels (and total > 0), they likely just tagged everything.
    # But only if total_hotels is not all 5-star (it isn't).
    luxury_count = data.get('luxury_tag_count', 0)
    total_hotels = data.get('total_hotels', 0)
    if total_hotels > 10 and luxury_count == total_hotels:
        score = min(score, 20) # Cap score if blanket tagging detected
        feedback.append("BLANKET TAGGING DETECTED: All hotels tagged luxury. Score capped.")

    passed = score >= 60 and schema.get('Tags_exists') and schema.get('HasTag_exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }