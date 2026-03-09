#!/usr/bin/env python3
"""
Verifier for urban_rural_facility_analysis task.

Scoring (100 points total):
- Org Unit Groups Created (20 pts): 'Urban Facilities' and 'Rural Facilities' exist
- Group Set Created (20 pts): 'Facility Location' exists and contains the groups
- Data Dimension Enabled (10 pts): Group Set is marked as data dimension
- Facilities Assigned (20 pts): Bo Gov (Urban) and Ngelehun (Rural) assigned correctly
- Resource Tables Updated (10 pts): Analytics tables generated recently
- Visualization Saved (20 pts): Chart exists using the new dimension

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

def parse_dhis_date(date_str):
    """Parse DHIS2 ISO date string to datetime object."""
    if not date_str:
        return datetime.min.replace(tzinfo=timezone.utc)
    try:
        # Handle formats like "2023-10-25T14:30:00.000" or "2023-10-25T14:30:00.000+0000"
        return datetime.fromisoformat(date_str.replace('Z', '+00:00'))
    except ValueError:
        try:
            # Fallback for simple split if isoformat fails
            return datetime.strptime(date_str.split('.')[0], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
        except:
            return datetime.min.replace(tzinfo=timezone.utc)

def verify_urban_rural_facility_analysis(traj, env_info, task_info):
    """Verify metadata configuration and visualization for Urban/Rural analysis."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/urban_rural_analysis_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"System error reading results: {e}"}

    score = 0
    feedback_parts = []
    
    # Parse Task Start Time
    task_start_iso = result.get('task_start_iso', '')
    task_start_dt = parse_dhis_date(task_start_iso)

    # 1. Verify Groups Created (20 pts)
    groups_data = result.get('groups_data', {}).get('organisationUnitGroups', [])
    urban_group = next((g for g in groups_data if 'urban' in g.get('name', '').lower()), None)
    rural_group = next((g for g in groups_data if 'rural' in g.get('name', '').lower()), None)
    
    if urban_group and rural_group:
        score += 20
        feedback_parts.append("Org Unit Groups 'Urban' and 'Rural' created (+20)")
    elif urban_group or rural_group:
        score += 10
        feedback_parts.append("One Org Unit Group created (+10)")
    else:
        feedback_parts.append("Org Unit Groups not found")

    # 2. Verify Group Set Created & Linked (20 pts)
    group_sets_data = result.get('group_sets_data', {}).get('organisationUnitGroupSets', [])
    location_set = next((gs for gs in group_sets_data if 'facility location' in gs.get('name', '').lower()), None)
    
    group_set_id = None
    if location_set:
        group_set_id = location_set.get('id')
        # Check if groups are linked
        linked_groups = location_set.get('organisationUnitGroups', [])
        linked_ids = [g.get('id') for g in linked_groups]
        
        urban_linked = urban_group and urban_group.get('id') in linked_ids
        rural_linked = rural_group and rural_group.get('id') in linked_ids
        
        if urban_linked and rural_linked:
            score += 20
            feedback_parts.append("Group Set created and fully linked (+20)")
        elif urban_linked or rural_linked:
            score += 10
            feedback_parts.append("Group Set created but partially linked (+10)")
        else:
            score += 5
            feedback_parts.append("Group Set created but empty (+5)")
    else:
        feedback_parts.append("Group Set 'Facility Location' not found")

    # 3. Verify Data Dimension Enabled (10 pts)
    if location_set and location_set.get('dataDimension', False):
        score += 10
        feedback_parts.append("Data Dimension enabled (+10)")
    elif location_set:
        feedback_parts.append("Data Dimension NOT enabled")

    # 4. Verify Facility Assignments (20 pts)
    # Bo Gov -> Urban
    bo_gov_groups = result.get('bo_gov_groups', {}).get('organisationUnitGroups', [])
    bo_is_urban = urban_group and any(g.get('id') == urban_group.get('id') for g in bo_gov_groups)
    
    # Ngelehun -> Rural
    ngelehun_groups = result.get('ngelehun_groups', {}).get('organisationUnitGroups', [])
    ngelehun_is_rural = rural_group and any(g.get('id') == rural_group.get('id') for g in ngelehun_groups)
    
    if bo_is_urban:
        score += 10
        feedback_parts.append("Bo Gov assigned to Urban (+10)")
    
    if ngelehun_is_rural:
        score += 10
        feedback_parts.append("Ngelehun assigned to Rural (+10)")

    # 5. Verify Resource Tables Updated (10 pts)
    # Check system info for last analytics generation
    system_info = result.get('system_info', {})
    last_analytics_str = system_info.get('lastAnalyticsTableSuccess')
    
    analytics_updated = False
    if last_analytics_str:
        # Format usually: "2023-10-25T14:30:00.000"
        last_analytics_dt = parse_dhis_date(last_analytics_str)
        # Allow a small buffer (e.g., system clock skew), but generally should be after start
        if last_analytics_dt >= task_start_dt:
            analytics_updated = True
            
    if analytics_updated:
        score += 10
        feedback_parts.append("Analytics tables generated (+10)")
    else:
        feedback_parts.append("Analytics tables NOT updated after task start")

    # 6. Verify Visualization (20 pts)
    visualizations = result.get('visualizations_data', {}).get('visualizations', [])
    
    # Filter for ones created after task start (approx)
    valid_viz = []
    for viz in visualizations:
        created_dt = parse_dhis_date(viz.get('created'))
        if created_dt >= task_start_dt:
            valid_viz.append(viz)
            
    # Check if any uses the new dimension
    # The new dimension ID is the Group Set ID
    viz_correct = False
    if group_set_id:
        for viz in valid_viz:
            # Check dimensions (columns, rows, filters)
            dims = viz.get('columnDimensions', []) + viz.get('rowDimensions', []) + viz.get('filterDimensions', [])
            if any(d == group_set_id for d in dims):
                viz_correct = True
                break
    
    if viz_correct:
        score += 20
        feedback_parts.append("Visualization created using new dimension (+20)")
    elif valid_viz:
        score += 5 # Partial credit for creating a viz
        feedback_parts.append("Visualization created but missing specific dimension (+5)")
    else:
        feedback_parts.append("No new visualization found")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }