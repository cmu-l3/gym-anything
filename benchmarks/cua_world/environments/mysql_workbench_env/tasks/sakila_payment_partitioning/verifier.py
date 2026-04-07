#!/usr/bin/env python3
"""
Verifier for sakila_payment_partitioning task.

Evaluates:
1. payment_archive table creation with RANGE partitioning.
2. Correct partition definitions (p2005, p2006, p_future).
3. Data migration integrity (row counts).
4. Data distribution (verifies partitioning actually works).
5. Stored procedure creation.
6. CSV export of partition stats.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_payment_partitioning(traj, env_info, task_info):
    """
    Verify the partitioning task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/partitioning_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract data
    table_exists = result.get('table_exists', 0) > 0
    partition_method = result.get('partition_method', '').upper()
    partition_names_str = result.get('partition_names', '')
    archive_row_count = int(result.get('archive_row_count', 0))
    initial_payment_count = int(result.get('initial_payment_count', 0))
    partition_dist_str = result.get('partition_distribution', '')
    proc_exists = result.get('proc_exists', 0) > 0
    csv_exists = result.get('csv_exists', False)
    csv_content_valid = result.get('csv_content_valid', False)
    csv_mtime = int(result.get('csv_mtime', 0))
    task_start = int(result.get('task_start', 0))

    # Criterion 1: Table Creation (10 pts)
    if table_exists:
        score += 10
        feedback_parts.append("Table `payment_archive` created (10/10)")
    else:
        feedback_parts.append("Table `payment_archive` NOT found (0/10)")

    # Criterion 2: Partition Method (10 pts)
    if 'RANGE' in partition_method:
        score += 10
        feedback_parts.append(f"Partition method matches RANGE (10/10)")
    else:
        feedback_parts.append(f"Incorrect partition method: {partition_method} (0/10)")

    # Criterion 3: Partition Structure (20 pts)
    # Expecting p2005, p2006, p_future
    p_names = [p.strip().lower() for p in partition_names_str.split(',') if p.strip()]
    expected = {'p2005', 'p2006', 'p_future'}
    # Check if expected names are present (allow for extra system partitions if any, though unlikely in MySQL)
    found_expected = expected.intersection(set(p_names))
    
    if len(found_expected) == 3:
        score += 20
        feedback_parts.append("All 3 expected partitions found (20/20)")
    elif len(found_expected) > 0:
        score += 10
        feedback_parts.append(f"Found {len(found_expected)}/3 expected partitions (10/20)")
    else:
        feedback_parts.append("No expected partitions found (0/20)")

    # Criterion 4: Data Migration (20 pts)
    # Allow 1% tolerance
    if initial_payment_count > 0:
        diff = abs(archive_row_count - initial_payment_count)
        tolerance = initial_payment_count * 0.01
        
        if diff <= tolerance:
            score += 20
            feedback_parts.append(f"Data migration successful: {archive_row_count} rows (20/20)")
        elif archive_row_count > 0:
            score += 5
            feedback_parts.append(f"Partial data migration: {archive_row_count}/{initial_payment_count} rows (5/20)")
        else:
            feedback_parts.append("No data migrated to archive table (0/20)")
    else:
        feedback_parts.append("Source table was empty, cannot verify migration (0/20)")

    # Criterion 5: Data Distribution (15 pts)
    # Check that rows are distributed (not all in one partition)
    # partition_dist_str is comma separated numbers, e.g. "2000,5000,100"
    try:
        dist_counts = [int(x) for x in partition_dist_str.split(',') if x.strip().isdigit()]
        non_zero_partitions = sum(1 for c in dist_counts if c > 0)
        
        if non_zero_partitions >= 2:
            score += 15
            feedback_parts.append("Data correctly distributed across partitions (15/15)")
        elif non_zero_partitions == 1:
            # If all data is in one partition, the range logic might be wrong (e.g. everything in p_future)
            # Or data only spans one year. Sakila data spans 2005 and 2006.
            # 2005 payments -> p2005
            # 2006 payments -> p2006
            # So we strictly expect at least 2 partitions to have data.
            feedback_parts.append("Data not distributed: All rows in one partition (0/15)")
        else:
            feedback_parts.append("No data in partitions (0/15)")
    except:
        feedback_parts.append("Could not verify partition distribution (0/15)")

    # Criterion 6: Stored Procedure (15 pts)
    if proc_exists:
        score += 15
        feedback_parts.append("Stored procedure `sp_partition_stats` exists (15/15)")
    else:
        feedback_parts.append("Stored procedure missing (0/15)")

    # Criterion 7: CSV Export (10 pts)
    if csv_exists and csv_mtime > task_start and csv_content_valid:
        score += 10
        feedback_parts.append("Valid CSV export found (10/10)")
    elif csv_exists:
        feedback_parts.append("CSV exists but content invalid or old (2/10)")
    else:
        feedback_parts.append("CSV export missing (0/10)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }