#!/usr/bin/env python3
"""
Verifier for cluster_partitioning task.

Criteria:
1. Schema: Clusters (hotels_europe, etc.) must exist (15 pts).
2. Schema: Hotels class must include these clusters (15 pts).
3. Data: Records must be moved to correct clusters (No invalid countries in region cluster) (15 pts per cluster = 45 pts).
4. Completeness: Total records in new clusters should match total count (meaning old default cluster is empty) (10 pts).
5. Report: File exists, created during task, and contains data (15 pts).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cluster_partitioning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    schema = result.get('schema_analysis', {})
    stats = result.get('partition_stats', {})
    
    # 1. Verify Clusters Exist (15 pts)
    all_clusters = schema.get('all_clusters', [])
    required_clusters = ['hotels_europe', 'hotels_americas', 'hotels_asiapacific']
    missing_clusters = [c for c in required_clusters if c not in all_clusters]
    
    if not missing_clusters:
        score += 15
        feedback_parts.append("All regional clusters created")
    else:
        feedback_parts.append(f"Missing clusters: {', '.join(missing_clusters)}")
        
    # 2. Verify Class Binding (15 pts)
    # Hotels class must use these clusters
    hotels_clusters = schema.get('hotels_clusters', [])
    unbound_clusters = [c for c in required_clusters if c not in hotels_clusters]
    
    if not unbound_clusters:
        score += 15
        feedback_parts.append("Hotels class configured with all regional clusters")
    elif len(unbound_clusters) < 3:
        score += 5
        feedback_parts.append(f"Hotels class partially configured (missing: {unbound_clusters})")
    else:
        feedback_parts.append("Hotels class not configured with new clusters")

    # 3. Verify Data Partitioning (45 pts total, 15 per region)
    # For each region:
    # - Total > 0 (data exists)
    # - Invalid == 0 (no misplaced countries)
    
    total_moved = 0
    
    regions = {
        "europe": stats.get('europe', {}),
        "americas": stats.get('americas', {}),
        "asiapacific": stats.get('asiapacific', {})
    }
    
    for name, stat in regions.items():
        count = stat.get('total', 0)
        invalid = stat.get('invalid', 0)
        total_moved += count
        
        if count > 0 and invalid == 0:
            score += 15
            feedback_parts.append(f"Cluster hotels_{name} Correct ({count} records)")
        elif count > 0:
            # Penalize for invalid records
            score += 5
            feedback_parts.append(f"Cluster hotels_{name} has {invalid} misplaced records")
        else:
            feedback_parts.append(f"Cluster hotels_{name} is empty")

    # 4. Completeness (10 pts)
    # Did we move everything?
    total_db_records = stats.get('total_records', 0)
    
    # If total_moved close to total_db_records (allowing for minor discrepancies during migration, though exact is expected)
    if total_db_records > 0 and total_moved >= total_db_records:
        score += 10
        feedback_parts.append("All records successfully partitioned")
    elif total_moved > 0:
        feedback_parts.append(f"Partial migration: {total_moved}/{total_db_records} moved")
    
    # 5. Report Verification (15 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    task_start = result.get('task_start', 0)
    
    if report_exists:
        if report_mtime > task_start:
            score += 15
            feedback_parts.append("Report file created")
        else:
            score += 5
            feedback_parts.append("Report file exists but timestamp predates task")
    else:
        feedback_parts.append("Report file missing")

    passed = (score >= 60) and (not missing_clusters) and (total_moved > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }