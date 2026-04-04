#!/usr/bin/env python3
"""
Verifier for refactor_region_graph task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_region_graph(traj, env_info, task_info):
    """
    Verify the graph refactoring task.
    
    Criteria:
    1. 'Regions' class exists (10 pts)
    2. 'InRegion' edge class exists (10 pts)
    3. 'Regions.Name' has a UNIQUE index (10 pts)
    4. Exactly 4 unique regions exist (European, American, Asian, Oceanian) (20 pts)
    5. All 12 countries have an outgoing InRegion edge (20 pts)
    6. The connections are semantically correct (e.g. Italy -> European) (30 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Extract data from result
    schema = result.get('schema', {})
    classes = {c['name']: c for c in schema.get('classes', [])}
    region_count = result.get('region_count', 0)
    region_names = set(result.get('region_names', []))
    edge_count = result.get('edge_count', 0)
    connections = result.get('connections', [])
    
    # 1. Check Classes Existence
    if 'Regions' in classes:
        score += 10
        feedback_parts.append("Regions class created")
    else:
        feedback_parts.append("Regions class missing")

    if 'InRegion' in classes:
        score += 10
        feedback_parts.append("InRegion edge class created")
    else:
        feedback_parts.append("InRegion edge class missing")
        
    # 2. Check Index on Regions.Name
    index_found = False
    if 'Regions' in classes:
        regions_cls = classes['Regions']
        indexes = regions_cls.get('indexes', [])
        for idx in indexes:
            # Check if index is on "Name" property and is UNIQUE
            props = idx.get('fields', [])
            idx_type = idx.get('type', '')
            if 'Name' in props and idx_type == 'UNIQUE':
                index_found = True
                break
    
    if index_found:
        score += 10
        feedback_parts.append("UNIQUE index on Regions.Name found")
    else:
        feedback_parts.append("Missing UNIQUE index on Regions.Name")

    # 3. Check Region Data
    expected_regions = {"European", "American", "Asian", "Oceanian"}
    
    # Exact match of region set
    if region_names == expected_regions:
        score += 20
        feedback_parts.append("Regions data is correct (4 unique regions)")
    elif len(region_names) == 4:
        # Count matches but maybe names differ slightly (case sensitivity?)
        score += 10
        feedback_parts.append(f"Region count is 4, but names differ: {region_names}")
    else:
        feedback_parts.append(f"Region count mismatch. Expected 4, got {len(region_names)} ({region_names})")

    # 4. Check Edge Count
    # There are 12 countries in the standard seed. Each should have 1 edge.
    if edge_count == 12:
        score += 20
        feedback_parts.append("Correct number of InRegion edges (12)")
    elif edge_count > 0:
        score += int(20 * (edge_count / 12))
        feedback_parts.append(f"Partial edge count: {edge_count}/12")
    else:
        feedback_parts.append("No InRegion edges created")

    # 5. Check Semantic Correctness
    # Verify a few known mappings
    correct_mappings = {
        "Italy": "European",
        "United States": "American",
        "Japan": "Asian",
        "Australia": "Oceanian",
        "Brazil": "American"
    }
    
    mapping_score = 0
    mapping_max = 30
    checks_passed = 0
    total_checks = len(correct_mappings)
    
    # Convert connections list to dict for lookup
    agent_map = {c['Country']: c['Region'] for c in connections if c.get('Country')}
    
    for country, expected_region in correct_mappings.items():
        if country in agent_map:
            if agent_map[country] == expected_region:
                checks_passed += 1
            else:
                feedback_parts.append(f"Wrong region for {country}: got {agent_map[country]}, expected {expected_region}")
        else:
            feedback_parts.append(f"No connection found for {country}")
    
    mapping_score = int((checks_passed / total_checks) * mapping_max)
    score += mapping_score
    
    if checks_passed == total_checks:
        feedback_parts.append("Sample connections verified correctly")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }