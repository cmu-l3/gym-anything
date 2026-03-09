#!/usr/bin/env python3
"""
Verifier for intervention_cohort_analysis_setup task.

Scoring Criteria (100 pts total):
1. [20 pts] 'Malaria Pilot Sites' group exists and has >0 members.
2. [20 pts] 'Malaria Control Sites' group exists and has >0 members.
3. [20 pts] 'Malaria Pilot Status' group set exists and contains the two groups.
4. [20 pts] Analytics Tables were updated (timestamp check).
5. [20 pts] Visualization 'Pilot vs Control Malaria 2023' exists AND uses the group set as a dimension.

Pass threshold: 80 points.
"""

import json
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_dhis2_date(date_str):
    """Parses DHIS2 ISO date strings, handling Z and millisecond variations."""
    if not date_str:
        return None
    try:
        # Handle '2023-10-25T10:00:00.123Z' or '2023-10-25T10:00:00'
        clean_str = date_str.replace("Z", "")
        # Truncate microseconds if present for simpler comparison
        if "." in clean_str:
            clean_str = clean_str.split(".")[0]
        return datetime.fromisoformat(clean_str)
    except Exception as e:
        logger.warning(f"Date parse error for {date_str}: {e}")
        return None

def verify_intervention_cohort_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: API unavailable"}

    # Load result
    result_path = "/tmp/verifier_result.json"
    try:
        copy_from_env("/tmp/task_result.json", result_path)
        with open(result_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []
    
    # Data extraction
    groups = data.get("groups_data", {}).get("organisationUnitGroups", [])
    group_sets = data.get("group_sets_data", {}).get("organisationUnitGroupSets", [])
    vizs = data.get("visualizations_data", {}).get("visualizations", [])
    
    init_analytics = parse_dhis2_date(data.get("initial_analytics_time"))
    curr_analytics = parse_dhis2_date(data.get("current_analytics_time"))
    task_start_ts = data.get("task_start_timestamp", 0)

    # 1. Verify Groups (40 pts)
    pilot_group = next((g for g in groups if "pilot sites" in g.get("name", "").lower()), None)
    control_group = next((g for g in groups if "control sites" in g.get("name", "").lower()), None)

    if pilot_group and len(pilot_group.get("organisationUnits", [])) > 0:
        score += 20
        feedback.append("✅ Pilot Sites group created with members.")
    else:
        feedback.append("❌ Pilot Sites group missing or empty.")

    if control_group and len(control_group.get("organisationUnits", [])) > 0:
        score += 20
        feedback.append("✅ Control Sites group created with members.")
    else:
        feedback.append("❌ Control Sites group missing or empty.")

    # 2. Verify Group Set (20 pts)
    group_set = next((s for s in group_sets if "pilot status" in s.get("name", "").lower()), None)
    
    group_set_valid = False
    if group_set:
        # Check membership
        set_group_ids = [g["id"] for g in group_set.get("organisationUnitGroups", [])]
        pilot_id = pilot_group.get("id") if pilot_group else "n/a"
        control_id = control_group.get("id") if control_group else "n/a"
        
        if pilot_id in set_group_ids and control_id in set_group_ids:
            score += 20
            feedback.append("✅ Group Set created and contains both groups.")
            group_set_valid = True
            group_set_id = group_set.get("id")
        else:
            feedback.append("❌ Group Set exists but does not contain both Pilot and Control groups.")
    else:
        feedback.append("❌ 'Malaria Pilot Status' Group Set not found.")

    # 3. Verify Analytics Update (20 pts)
    analytics_updated = False
    if curr_analytics and init_analytics:
        if curr_analytics > init_analytics:
            analytics_updated = True
    elif curr_analytics and not init_analytics:
        # If no initial time recorded, but we have a current time, assume updated if verification passes
        # But stricter check: check if curr_analytics is recent (close to now)
        # We'll rely on the delta check mostly.
        analytics_updated = True
        
    if analytics_updated:
        score += 20
        feedback.append("✅ Analytics Tables were updated.")
    else:
        feedback.append("❌ Analytics Tables NOT updated (timestamp unchanged).")

    # 4. Verify Visualization (20 pts)
    # The visualization MUST use the Group Set as a dimension. 
    # This implies the user successfully ran analytics (otherwise the dimension isn't available).
    target_viz = next((v for v in vizs if "pilot vs control" in v.get("name", "").lower()), None)
    
    if target_viz:
        # Check dimensions
        dims = target_viz.get("columns", []) + target_viz.get("rows", []) + target_viz.get("filters", [])
        
        # We look for the Group Set ID in the 'dimension' field of the viz configuration
        # Group set dimensions usually look like 'ougs.{GroupSetID}' or just the ID depending on API version
        used_dimension = False
        if group_set_valid:
            for dim in dims:
                d_id = dim.get("dimension", "")
                if group_set_id in d_id: # d_id might be 'ougs.UID'
                    used_dimension = True
                    break
        
        if used_dimension:
            score += 20
            feedback.append("✅ Visualization created using the correct Group Set dimension.")
        else:
            feedback.append("❌ Visualization exists but does not use the 'Malaria Pilot Status' dimension.")
    else:
        feedback.append("❌ Visualization 'Pilot vs Control Malaria 2023' not found.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }