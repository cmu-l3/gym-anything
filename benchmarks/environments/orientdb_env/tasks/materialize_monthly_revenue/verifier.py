#!/usr/bin/env python3
"""
Verifier for materialize_monthly_revenue task.

Verification Logic:
1. Schema Check: Verify 'MonthlyStats' class exists with correct properties (Year, Month, TotalRevenue, OrderCount).
2. Index Check: Verify UNIQUE index exists on (Year, Month).
3. Data Accuracy: Re-calculate the aggregation from the raw 'Orders' data (ground truth) and compare with the agent's 'MonthlyStats' records.
"""

import json
import tempfile
import os
import logging
from datetime import datetime
from collections import defaultdict
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_materialize_monthly_revenue(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
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

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []
    
    schema = result.get("schema", {})
    monthly_stats = result.get("monthly_stats", [])
    source_data = result.get("source_data", []) # Only contains 'paid' orders as filtered by export script
    
    # ------------------------------------------------------------------
    # 1. Schema Verification (40 points)
    # ------------------------------------------------------------------
    classes = {c["name"]: c for c in schema.get("classes", [])}
    
    if "MonthlyStats" not in classes:
        return {"passed": False, "score": 0, "feedback": "Class 'MonthlyStats' not found."}
    
    score += 10
    feedback.append("Class 'MonthlyStats' created.")
    
    target_cls = classes["MonthlyStats"]
    props = {p["name"]: p["type"] for p in target_cls.get("properties", [])}
    
    # Check properties
    required_props = {
        "Year": ["INTEGER", "LONG", "SHORT"],
        "Month": ["INTEGER", "LONG", "SHORT"],
        "TotalRevenue": ["DOUBLE", "FLOAT", "DECIMAL"],
        "OrderCount": ["INTEGER", "LONG", "SHORT"]
    }
    
    props_ok = True
    for name, allowed_types in required_props.items():
        if name not in props:
            feedback.append(f"Missing property: {name}")
            props_ok = False
        elif props[name].upper() not in allowed_types:
            feedback.append(f"Property {name} has wrong type: {props[name]} (expected {allowed_types})")
            props_ok = False
            
    if props_ok:
        score += 15
        feedback.append("Properties defined correctly.")
        
    # Check Index (UNIQUE on Year, Month)
    indexes = target_cls.get("indexes", [])
    index_found = False
    for idx in indexes:
        fields = idx.get("fields", [])
        idx_type = idx.get("type", "").upper()
        if "Year" in fields and "Month" in fields and idx_type == "UNIQUE":
            index_found = True
            break
            
    if index_found:
        score += 15
        feedback.append("Unique composite index on (Year, Month) found.")
    else:
        feedback.append("Missing UNIQUE index on (Year, Month).")

    # ------------------------------------------------------------------
    # 2. Data Calculation (Ground Truth)
    # ------------------------------------------------------------------
    # Calculate expected stats from source data
    # Source data from export is already filtered by Status='paid', but let's be safe
    # Actually export script ran: SELECT Date, Price, Status FROM Orders WHERE Status='paid'
    
    ground_truth = defaultdict(lambda: {"revenue": 0.0, "count": 0})
    
    for row in source_data:
        # Date format in OrientDB default is yyyy-MM-dd HH:mm:ss or similar
        # But we inserted as yyyy-MM-dd. Python generator used yyyy-MM-dd.
        # OrientDB REST often returns date as string.
        date_str = row.get("Date", "")
        price = float(row.get("Price", 0))
        status = row.get("Status", "").lower()
        
        # Verify status (double check)
        if status != "paid":
            continue
            
        try:
            # Parse date - handle potential timestamp format
            if "T" in date_str:
                dt = datetime.strptime(date_str.split("T")[0], "%Y-%m-%d")
            else:
                dt = datetime.strptime(date_str.split(" ")[0], "%Y-%m-%d")
                
            key = (dt.year, dt.month)
            ground_truth[key]["revenue"] += price
            ground_truth[key]["count"] += 1
        except Exception as e:
            # If date parsing fails, skip (shouldn't happen with our setup)
            continue
            
    # ------------------------------------------------------------------
    # 3. Data Verification (60 points)
    # ------------------------------------------------------------------
    if not monthly_stats:
        feedback.append("MonthlyStats class is empty (no data inserted).")
    else:
        # Build map of agent's results
        agent_data = {}
        for row in monthly_stats:
            y = row.get("Year")
            m = row.get("Month")
            if y is not None and m is not None:
                agent_data[(int(y), int(m))] = {
                    "revenue": float(row.get("TotalRevenue", 0)),
                    "count": int(row.get("OrderCount", 0))
                }
        
        # Compare
        match_count = 0
        total_months = len(ground_truth)
        
        if total_months == 0:
            # Edge case: no paid orders generated?
            feedback.append("Warning: No ground truth data found (setup issue?).")
            # If agent also has empty, give pass
            if not agent_data:
                score += 60
        else:
            correct_records = 0
            for key, truth in ground_truth.items():
                if key not in agent_data:
                    feedback.append(f"Missing record for {key[0]}-{key[1]:02d}")
                    continue
                
                agent = agent_data[key]
                
                # Check Count
                count_ok = agent["count"] == truth["count"]
                
                # Check Revenue (float tolerance)
                rev_ok = math.isclose(agent["revenue"], truth["revenue"], abs_tol=0.1)
                
                if count_ok and rev_ok:
                    correct_records += 1
                else:
                    feedback.append(f"Mismatch for {key[0]}-{key[1]:02d}: "
                                    f"Expected (cnt={truth['count']}, rev={truth['revenue']:.2f}), "
                                    f"Got (cnt={agent['count']}, rev={agent['revenue']:.2f})")
            
            # Scoring logic for data
            # 20 pts for populated non-empty
            # 40 pts for accuracy proportional
            score += 20
            
            accuracy_ratio = correct_records / total_months
            score += int(40 * accuracy_ratio)
            feedback.append(f"Data accuracy: {correct_records}/{total_months} months correct.")

    return {
        "passed": score >= 85,
        "score": score,
        "feedback": " ".join(feedback)
    }