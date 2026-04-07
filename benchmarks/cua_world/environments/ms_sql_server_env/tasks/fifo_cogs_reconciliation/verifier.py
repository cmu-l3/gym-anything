#!/usr/bin/env python3
"""
Verifier for FIFO COGS Reconciliation Task.

This script recalculates the FIFO allocation using Python (Ground Truth)
and compares it against the agent's SQL output.
"""

import json
import logging
import os
import tempfile
from decimal import Decimal

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fifo_allocation(traj, env_info, task_info):
    """
    Verify the FIFO allocation logic.
    
    1. Reconstruct Ground Truth Allocation from Supply and Demand data provided in the export.
    2. Compare Agent's Allocation to Ground Truth.
    3. Check constraints: Total Quantity, Cost Accuracy, Split Handling.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic Checks
    schema_exists = int(result.get('schema_exists', 0)) > 0
    table_exists = int(result.get('table_exists', 0)) > 0
    
    agent_allocs = result.get('agent_allocations', [])
    supply_data = result.get('supply_data', [])
    demand_data = result.get('demand_data', [])

    if not schema_exists or not table_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Schema 'Accounting' or Table 'FIFOAllocation' does not exist."
        }

    if not agent_allocs:
        return {
            "passed": False,
            "score": 10,
            "feedback": "Table exists but is empty. No allocations found."
        }

    # 2. Compute Ground Truth (Python Implementation of FIFO)
    # Sort Supply by Date then ID (Strict FIFO)
    # Note: Supply/Demand JSON comes ordered from SQL, but we enforce it here for safety.
    supply_queue = sorted(supply_data, key=lambda x: (x['BatchDate'], x['BatchID']))
    demand_queue = sorted(demand_data, key=lambda x: (x['OrderDate'], x['SalesOrderID'], x['SalesOrderDetailID']))

    ground_truth = [] # List of dicts matching agent output structure
    
    # We need mutable state for supply consumption
    current_supply_idx = 0
    
    # Track remaining qty in the current batch
    if supply_queue:
        current_batch_rem = supply_queue[0]['Quantity']
    else:
        current_batch_rem = 0

    total_demand_qty = 0
    
    for order in demand_queue:
        order_rem = order['OrderQty']
        total_demand_qty += order_rem
        sdid = order['SalesOrderDetailID']
        soid = order['SalesOrderID']
        
        while order_rem > 0:
            if current_supply_idx >= len(supply_queue):
                # Run out of supply - this shouldn't happen with proper seeding, 
                # but handled for robustness (allocating to 'None' or -1)
                ground_truth.append({
                    'SalesOrderID': soid,
                    'SalesOrderDetailID': sdid,
                    'BatchID': -1,
                    'QtyAllocated': order_rem,
                    'UnitCost': 0.0
                })
                break

            batch = supply_queue[current_supply_idx]
            batch_id = batch['BatchID']
            unit_cost = float(batch['UnitCost'])
            
            # Allocate
            alloc_qty = min(order_rem, current_batch_rem)
            
            ground_truth.append({
                'SalesOrderID': soid,
                'SalesOrderDetailID': sdid,
                'BatchID': batch_id,
                'QtyAllocated': alloc_qty,
                'UnitCost': unit_cost
            })
            
            order_rem -= alloc_qty
            current_batch_rem -= alloc_qty
            
            # If batch exhausted, move to next
            if current_batch_rem == 0:
                current_supply_idx += 1
                if current_supply_idx < len(supply_queue):
                    current_batch_rem = supply_queue[current_supply_idx]['Quantity']

    # 3. Compare Results
    score = 0
    feedback = []

    # A. Volume Check (15 pts)
    agent_total_qty = sum(a['QtyAllocated'] for a in agent_allocs)
    if agent_total_qty == total_demand_qty:
        score += 15
        feedback.append("Volume Check Passed: Total allocated quantity matches demand.")
    else:
        feedback.append(f"Volume Check Failed: Agent allocated {agent_total_qty}, expected {total_demand_qty}.")

    # B. Supply Integrity (15 pts)
    # Check if agent allocated more from a batch than existed
    agent_batch_sums = {}
    for a in agent_allocs:
        bid = a['BatchID']
        agent_batch_sums[bid] = agent_batch_sums.get(bid, 0) + a['QtyAllocated']
    
    integrity_pass = True
    for batch in supply_data:
        bid = batch['BatchID']
        limit = batch['Quantity']
        used = agent_batch_sums.get(bid, 0)
        if used > limit:
            integrity_pass = False
            feedback.append(f"Supply Integrity Failed: Batch {bid} over-allocated (Used {used} > Limit {limit}).")
    
    if integrity_pass:
        score += 15
        feedback.append("Supply Integrity Passed: No batch over-allocated.")

    # C. FIFO Logic & Split Handling (50 pts)
    # We compare the sets of allocations.
    # Key = (SalesOrderDetailID, BatchID) -> {Qty, Cost}
    
    gt_map = {(x['SalesOrderDetailID'], x['BatchID']): x for x in ground_truth}
    agent_map = {(x['SalesOrderDetailID'], x['BatchID']): x for x in agent_allocs}
    
    matches = 0
    splits_correct = 0
    splits_expected = 0
    
    # Calculate how many "Split" lines exist in GT
    # A split is a SalesOrderDetailID that appears more than once in GT
    gt_sdid_counts = {}
    for x in ground_truth:
        gt_sdid_counts[x['SalesOrderDetailID']] = gt_sdid_counts.get(x['SalesOrderDetailID'], 0) + 1
    
    split_sdids = [k for k,v in gt_sdid_counts.items() if v > 1]
    splits_expected = len(split_sdids)
    
    # Verify Agent Matches
    for key, gt_row in gt_map.items():
        if key in agent_map:
            agent_row = agent_map[key]
            # Check Qty
            if agent_row['QtyAllocated'] == gt_row['QtyAllocated']:
                # Check Cost (tolerance 0.01)
                if abs(float(agent_row['UnitCost']) - gt_row['UnitCost']) < 0.01:
                    matches += 1
    
    # Check split specifically
    split_matches = 0
    for sdid in split_sdids:
        # Get all agent rows for this sdid
        agent_rows = [a for a in agent_allocs if a['SalesOrderDetailID'] == sdid]
        gt_rows = [g for g in ground_truth if g['SalesOrderDetailID'] == sdid]
        
        # Sort by BatchID to compare
        agent_rows.sort(key=lambda x: x['BatchID'])
        gt_rows.sort(key=lambda x: x['BatchID'])
        
        if len(agent_rows) == len(gt_rows):
            # Compare contents
            match = True
            for i in range(len(gt_rows)):
                if (agent_rows[i]['BatchID'] != gt_rows[i]['BatchID'] or
                    agent_rows[i]['QtyAllocated'] != gt_rows[i]['QtyAllocated']):
                    match = False
                    break
            if match:
                split_matches += 1

    # Scoring Logic
    # 50 points total for logic
    # - 25 points for general row matching percentage
    # - 25 points for split handling
    
    total_gt_rows = len(ground_truth)
    if total_gt_rows > 0:
        match_pct = matches / total_gt_rows
        score += int(25 * match_pct)
        feedback.append(f"Allocation Accuracy: {matches}/{total_gt_rows} exact matches ({int(match_pct*100)}%).")
    
    if splits_expected > 0:
        split_pct = split_matches / splits_expected
        score += int(25 * split_pct)
        feedback.append(f"Split Handling: {split_matches}/{splits_expected} split orders handled correctly.")
    else:
        # If no splits generated by random data (unlikely with our seed), give full points if general accuracy is high
        if matches == total_gt_rows:
            score += 25

    # D. Schema/Table Bonus (Already checked existence, giving points)
    score += 10 # Schema creation points
    
    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback)
    }