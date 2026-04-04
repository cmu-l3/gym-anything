#!/usr/bin/env python3
"""
Verifier for aws_saas_architecture task.

Scoring (100 points total):
- File exists and modified after task start: 10 pts
- 15+ shapes drawn: 15 pts                    (partial: 8+ = 6 pts)
- 8+ connection edges: 10 pts                 (partial: 4+ = 4 pts)
- 8+ AWS service types identified: 25 pts     (partial: 5+ = 12 pts, 3+ = 5 pts)
- 2+ diagram pages (Architecture + Data Flow): 15 pts
- Security group zones present (dashed regions): 10 pts
- PNG exported and valid: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

CORE_AWS_COMPONENTS = {
    "vpc": "VPC",
    "subnet": "Subnet",
    "ec2": "EC2 instance",
    "rds": "RDS database",
    "alb": "Application Load Balancer",
    "cloudfront": "CloudFront",
    "s3": "S3 bucket",
    "igw": "Internet Gateway",
}

FULL_AWS_COMPONENTS = list(CORE_AWS_COMPONENTS.keys()) + [
    "elasticache", "route53", "nat", "asg", "waf", "acm"
]


def verify_aws_saas_architecture(traj, env_info, task_info):
    """Verify AWS SaaS architecture diagram creation."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    min_shapes = metadata.get('min_shapes', 15)
    min_edges = metadata.get('min_edges', 8)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    subscores = {}

    # --- Criterion 1: File exists and modified (10 pts) ---
    if not result.get('file_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "aws_architecture.drawio not found. Nothing was saved.",
            "subscores": {}
        }

    if result.get('file_modified_after_start'):
        score += 10
        subscores["file_saved"] = True
        feedback.append("Architecture file saved")
    else:
        subscores["file_saved"] = False
        feedback.append("WARN: File not modified after task start")

    if result.get('file_size', 0) < 800:
        return {
            "passed": False,
            "score": score,
            "feedback": f"File too small ({result.get('file_size',0)} bytes) — no diagram content",
            "subscores": subscores
        }

    # --- Criterion 2: Shape count (15 pts full, 6 pts partial) ---
    num_shapes = result.get('num_shapes', 0)
    subscores["num_shapes"] = num_shapes
    if num_shapes >= min_shapes:
        score += 15
        feedback.append(f"Shapes: {num_shapes} (≥{min_shapes} required)")
    elif num_shapes >= 8:
        score += 6
        feedback.append(f"Shapes: {num_shapes} (partial, need ≥{min_shapes})")
    elif num_shapes >= 4:
        score += 2
        feedback.append(f"Shapes: {num_shapes} (insufficient)")
    else:
        feedback.append(f"Shapes: only {num_shapes}")

    # --- Criterion 3: Edge count (10 pts full, 4 pts partial) ---
    num_edges = result.get('num_edges', 0)
    subscores["num_edges"] = num_edges
    if num_edges >= min_edges:
        score += 10
        feedback.append(f"Connections: {num_edges} edges")
    elif num_edges >= 4:
        score += 4
        feedback.append(f"Connections: {num_edges} (partial)")
    else:
        feedback.append(f"Connections: only {num_edges}")

    # --- Criterion 4: AWS components identified (25 pts full, 12/5 pts partial) ---
    aws_found = result.get('aws_components_found', 0)
    aws_list = result.get('aws_list', '')
    subscores["aws_components"] = aws_found

    # Check core components specifically
    core_found = sum(1 for c in CORE_AWS_COMPONENTS if c in aws_list)

    if aws_found >= 8:
        score += 25
        feedback.append(f"AWS components: {aws_found} service types identified (comprehensive)")
    elif aws_found >= 5:
        score += 12
        feedback.append(f"AWS components: {aws_found} service types (missing some required services)")
    elif aws_found >= 3:
        score += 5
        feedback.append(f"AWS components: only {aws_found} service types")
    else:
        feedback.append(f"AWS components: very few ({aws_found}); use the AWS shape library")

    # Check for core services
    missing_core = [CORE_AWS_COMPONENTS[c] for c in CORE_AWS_COMPONENTS if c not in aws_list]
    if missing_core:
        feedback.append(f"Missing core: {', '.join(missing_core[:4])}")

    # --- Criterion 5: Multiple pages (15 pts) ---
    num_pages = result.get('num_pages', 0)
    subscores["num_pages"] = num_pages
    if num_pages >= 2:
        score += 15
        feedback.append(f"Pages: {num_pages} (Architecture + Data Flow)")
    else:
        feedback.append(f"Pages: {num_pages} (need ≥2: Architecture Overview + Data Flow)")

    # --- Criterion 6: Security zones (10 pts) ---
    if result.get('has_security_zones'):
        score += 10
        subscores["security_zones"] = True
        feedback.append("Security group zones: dashed boundaries present")
    else:
        subscores["security_zones"] = False
        feedback.append("Security group zones: missing (show SG boundaries as dashed rectangles)")

    # --- Criterion 7: PNG exported (15 pts) ---
    png_valid = result.get('png_valid', False)
    png_size = result.get('png_size', 0)
    subscores["png_exported"] = result.get('png_exists', False) and png_valid
    if png_valid and png_size >= 5000:
        score += 15
        feedback.append(f"PNG exported: {png_size} bytes")
    elif result.get('png_exists') and png_size >= 500:
        score += 7
        feedback.append(f"PNG present but small: {png_size} bytes")
    else:
        feedback.append("PNG not exported (need ~/Desktop/aws_architecture.png)")

    passed = score >= 60
    feedback.append(f"{'PASSED' if passed else 'FAILED'} (score={score}/100)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }
