#!/usr/bin/env python3
"""
Verifier for create_service_dependency_map task.

Evaluates the creation of interdependent microservice tiddlers and
a dashboard map using TiddlyWiki filter widgets.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_tiddler_content(raw_content):
    """Parse a .tid file content into fields and body."""
    fields = {}
    body = ""
    lines = raw_content.split('\n')
    in_body = False
    
    for line in lines:
        if in_body:
            body += line + "\n"
        elif line.strip() == "":
            in_body = True
        else:
            if ":" in line:
                key, val = line.split(":", 1)
                fields[key.strip().lower()] = val.strip()
                
    return fields, body.strip()

def verify_create_service_dependency_map(traj, env_info, task_info):
    """
    Verify the microservice tiddlers and dependency map using exported data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely copy result payload
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    tiddlers = result.get("tiddlers", {})
    task_start_time = result.get("task_start_time", 0)
    
    score = 0
    feedback_parts = []
    
    # Define expected services
    expected_services = [
        ("UserService", "Platform", "production", []),
        ("ProductCatalog", "Commerce", "production", []),
        ("InventoryService", "Commerce", "production", ["ProductCatalog"]),
        ("PaymentGateway", "Platform", "production", ["UserService"]),
        ("OrderService", "Commerce", "production", ["UserService", "ProductCatalog", "InventoryService", "PaymentGateway"]),
        ("NotificationService", "Platform", "beta", ["UserService", "OrderService"])
    ]
    
    services_correct = 0
    services_found = 0
    
    # ---------------------------------------------------------
    # Criteria 1: Microservice Tiddlers (Max 46 points total)
    # ---------------------------------------------------------
    for title, team, status, deps in expected_services:
        data = tiddlers.get(title, {})
        if not data.get("exists"):
            feedback_parts.append(f"Missing tiddler: {title}")
            continue
            
        services_found += 1
        fields, body = parse_tiddler_content(data.get("content", ""))
        
        # Calculate points for this service
        service_score = 0
        checks_passed = 0
        total_checks = 5 if not deps else 6
        
        if "microservice" in fields.get("tags", "").lower():
            checks_passed += 1
        if fields.get("team", "").lower() == team.lower():
            checks_passed += 1
        if fields.get("service-status", "").lower() == status.lower():
            checks_passed += 1
            
        actual_deps = fields.get("depends-on", "")
        if not deps:
            if not actual_deps.strip():
                checks_passed += 1
        else:
            deps_correct = all(d.lower() in actual_deps.lower() for d in deps)
            if deps_correct:
                checks_passed += 2  # Higher weight for complex dependencies
                
        if len(body) > 5:
            checks_passed += 1
            
        # Assign base points per service type
        base_points = 6 if not deps else (10 if title == "OrderService" else 8)
        awarded = int((checks_passed / total_checks) * base_points)
        score += awarded
        
        if checks_passed == total_checks:
            services_correct += 1
            feedback_parts.append(f"{title} is perfectly configured")
        else:
            feedback_parts.append(f"{title} partially correct ({checks_passed}/{total_checks})")

    # ---------------------------------------------------------
    # Criteria 2: Service Dependency Map Tiddler (Max 49 points)
    # ---------------------------------------------------------
    map_data = tiddlers.get("Service Dependency Map", {})
    if map_data.get("exists"):
        fields, body = parse_tiddler_content(map_data.get("content", ""))
        body_lower = body.lower()
        
        # Exists and tagged (5 pts)
        if "architecture" in fields.get("tags", "").lower():
            score += 5
            feedback_parts.append("Map tiddler exists with 'Architecture' tag")
        else:
            score += 3
            feedback_parts.append("Map tiddler exists but missing 'Architecture' tag")
            
        # Lists all services dynamically (12 pts)
        if re.search(r'\[tag\[microservice\]\]|tag:microservice', body_lower):
            if '<$list' in body_lower or '$list' in body_lower:
                score += 12
                feedback_parts.append("Map dynamically lists services via filter")
            else:
                score += 6
                feedback_parts.append("Map has service filter but missing list widget")
        else:
            feedback_parts.append("Map missing dynamic [tag[Microservice]] filter")

        # Shows reverse dependencies (15 pts)
        if re.search(r'field:depends-on|depends-on\[|backlinks|contains:depends-on|listed\[depends-on\]', body_lower):
            score += 15
            feedback_parts.append("Map correctly handles reverse dependencies")
        elif 'depends-on' in body_lower:
            score += 5
            feedback_parts.append("Map mentions depends-on but valid reverse filter syntax not detected")
        else:
            feedback_parts.append("Map missing reverse dependency logic")

        # Identifies leaf services (10 pts)
        if re.search(r'!has\[depends-on\]|depends-on\[\]', body_lower):
            score += 10
            feedback_parts.append("Map correctly isolates leaf services")
        elif 'leaf' in body_lower or 'independent' in body_lower:
            score += 3
            feedback_parts.append("Map has leaf section but filter syntax not detected")
            
        # Summary count (7 pts)
        if re.search(r'<\$count|count\[\]', body_lower):
            score += 7
            feedback_parts.append("Map includes dynamic count widget/filter")
        elif 'count' in body_lower:
            score += 2
            feedback_parts.append("Map mentions count but syntax not detected")
            
    else:
        feedback_parts.append("CRITICAL: 'Service Dependency Map' tiddler missing")

    # ---------------------------------------------------------
    # Criteria 3: Anti-gaming / Timestamps (Max 5 points)
    # ---------------------------------------------------------
    all_new = True
    for title, data in tiddlers.items():
        if data.get("exists"):
            if data.get("mtime", 0) < task_start_time:
                all_new = False
                break
                
    if all_new and services_found > 0:
        score += 5
        feedback_parts.append("All timestamps verified (created during task)")
    else:
        feedback_parts.append("Warning: Timestamp check failed")

    # ---------------------------------------------------------
    # Final Result Compilation
    # ---------------------------------------------------------
    # Pass condition: Score >= 60, at least 4 services correct, and Map exists
    passed = (
        score >= 60 and 
        services_correct >= 4 and 
        map_data.get("exists", False)
    )

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }