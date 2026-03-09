#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aws_ha_architecture_migration(traj, env_info, task_info):
    """
    Verifies the AWS HA Architecture Migration task.
    Checks for:
    1. Diagram modification and PDF export.
    2. Significant increase in complexity (shape/edge counts).
    3. Presence of required HA components (ALB, ASG, CloudFront, Multi-AZ, etc.).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    file_modified = result.get("file_modified", False)
    pdf_exists = result.get("pdf_exists", False)
    analysis = result.get("analysis", {})
    
    shape_count = analysis.get("total_shapes", 0)
    edge_count = analysis.get("total_edges", 0)
    
    # Components detected by text analysis
    has_az_b = analysis.get("has_az_b", False)
    has_alb = analysis.get("has_alb", False)
    has_asg = analysis.get("has_asg", False)
    has_cloudfront = analysis.get("has_cloudfront", False)
    has_nat = analysis.get("has_nat", False)
    has_redis = analysis.get("has_redis", False)
    has_multiaz_rds = analysis.get("has_multiaz_rds", False)

    # 3. Scoring Logic (Max 100)
    score = 0
    feedback = []

    # Basics (15 pts)
    if file_modified:
        score += 5
        feedback.append("File modified (+5)")
    else:
        feedback.append("File not modified (0)")

    if pdf_exists:
        score += 10
        feedback.append("PDF export found (+10)")
    else:
        feedback.append("PDF export missing (0)")

    # Structural Complexity (20 pts)
    # Starter diagram had ~10 shapes and ~3 edges.
    # Expecting significant increase (e.g. >18 shapes, >10 edges)
    if shape_count >= 18:
        score += 10
        feedback.append(f"Shape count good ({shape_count}) (+10)")
    elif shape_count >= 14:
        score += 5
        feedback.append(f"Shape count partial ({shape_count}) (+5)")
    else:
        feedback.append(f"Shape count low ({shape_count}) (0)")

    if edge_count >= 10:
        score += 10
        feedback.append(f"Edge count good ({edge_count}) (+10)")
    else:
        feedback.append(f"Edge count low ({edge_count}) (0)")

    # HA Components (65 pts)
    components = [
        (has_az_b, "Second Availability Zone (AZ-b)", 15),
        (has_alb, "Application Load Balancer", 10),
        (has_asg, "Auto Scaling Group", 10),
        (has_cloudfront, "CloudFront Distribution", 10),
        (has_nat, "NAT Gateway", 5),
        (has_redis, "Redis/ElastiCache", 5),
        (has_multiaz_rds, "Multi-AZ RDS", 10)
    ]

    for detected, name, pts in components:
        if detected:
            score += pts
            feedback.append(f"{name} detected (+{pts})")
        else:
            feedback.append(f"{name} missing (0)")

    # 4. Final Verdict
    # Threshold 60/100
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }