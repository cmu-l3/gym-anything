#!/usr/bin/env python3
"""
Verifier for OrientDB Query Optimization task.

Scoring Criteria:
1. Index Creation (50 pts total):
   - Hotels.City index exists (15 pts)
   - Hotels(Country, Stars) composite index exists (20 pts)
   - Profiles.Nationality index exists (15 pts)
2. Performance Validation (30 pts total):
   - Query 1 uses index (10 pts)
   - Query 2 uses index (10 pts)
   - Query 3 uses index (10 pts)
3. Report (20 pts total):
   - File exists and valid (10 pts)
   - Content check (10 pts)
"""

import json
import os
import tempfile
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_query_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criteria 1: Index Analysis (50 pts) ---
    indexes = result.get("current_indexes", [])
    
    # Check Hotels.City
    hotels_city_idx = next((idx for idx in indexes if idx['class'] == 'Hotels' and 'City' in idx['fields'] and len(idx['fields']) == 1), None)
    if hotels_city_idx:
        score += 15
        feedback.append(f"✓ Index on Hotels.City found ({hotels_city_idx['name']})")
    else:
        feedback.append("✗ Index on Hotels.City NOT found")

    # Check Hotels(Country, Stars) composite
    # Note: OrientDB fields in index definition might be ordered
    hotels_comp_idx = next((idx for idx in indexes if idx['class'] == 'Hotels' and 'Country' in idx['fields'] and 'Stars' in idx['fields'] and len(idx['fields']) == 2), None)
    if hotels_comp_idx:
        score += 20
        feedback.append(f"✓ Composite index on Hotels(Country, Stars) found ({hotels_comp_idx['name']})")
    else:
        # Partial credit if they made separate indexes instead of composite (common mistake)
        country_idx = next((idx for idx in indexes if idx['class'] == 'Hotels' and 'Country' in idx['fields']), None)
        stars_idx = next((idx for idx in indexes if idx['class'] == 'Hotels' and 'Stars' in idx['fields']), None)
        if country_idx and stars_idx:
            score += 10
            feedback.append("⚠ Separate indexes found instead of composite for Country/Stars (Partial credit)")
        else:
            feedback.append("✗ Composite index on Hotels(Country, Stars) NOT found")

    # Check Profiles.Nationality
    prof_nat_idx = next((idx for idx in indexes if idx['class'] == 'Profiles' and 'Nationality' in idx['fields']), None)
    if prof_nat_idx:
        score += 15
        feedback.append(f"✓ Index on Profiles.Nationality found ({prof_nat_idx['name']})")
    else:
        feedback.append("✗ Index on Profiles.Nationality NOT found")

    # --- Criteria 2: Query Optimization Status (30 pts) ---
    opt_status = result.get("optimization_status", {})
    
    if opt_status.get("query1_hotels_city"):
        score += 10
        feedback.append("✓ Query 1 (Rome) uses index")
    else:
        feedback.append("✗ Query 1 (Rome) still doing full scan")

    if opt_status.get("query2_hotels_composite"):
        score += 10
        feedback.append("✓ Query 2 (Italy/Stars) uses index")
    else:
        feedback.append("✗ Query 2 (Italy/Stars) still doing full scan")

    if opt_status.get("query3_profiles_nationality"):
        score += 10
        feedback.append("✓ Query 3 (British) uses index")
    else:
        feedback.append("✗ Query 3 (British) still doing full scan")

    # --- Criteria 3: Report Validation (20 pts) ---
    report = result.get("report", {})
    if report.get("exists") and report.get("created_during_task") and report.get("size", 0) > 50:
        score += 10
        feedback.append("✓ Report file created")
        
        # Check content
        try:
            content = base64.b64decode(report.get("content_base64", "")).decode('utf-8', errors='ignore').lower()
            keywords = ["explain", "index", "scan", "hotels", "profiles"]
            found_kw = [kw for kw in keywords if kw in content]
            if len(found_kw) >= 3:
                score += 10
                feedback.append("✓ Report content looks valid (contains diagnostic keywords)")
            else:
                feedback.append("⚠ Report content sparse (missing diagnostic keywords)")
        except:
            feedback.append("⚠ Could not analyze report content")
    else:
        feedback.append("✗ Report file missing, empty, or not created during task")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }