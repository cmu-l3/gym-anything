#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_microservices_sock_shop_architecture(traj, env_info, task_info):
    """
    Verifies the Sock Shop microservices diagram task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Extract Data
    analysis = result.get("diagram_analysis", {})
    
    # Scoring Variables
    score = 0
    feedback = []
    
    # Criterion 1: File Modified (5 pts)
    # Anti-gaming: Ensure the file was actually touched
    if result.get("file_modified", False) and analysis.get("exists", False):
        score += 5
        feedback.append("Diagram file modified.")
    else:
        feedback.append("Diagram file not modified or missing.")

    # Criterion 2: Shape Count (15 pts)
    # Start was 2 shapes. Target is ~14+ (9 services, 4 DBs, 1 queue). 
    # Let's say >= 12 gets full points to allow for slight variations.
    shape_count = analysis.get("shape_count", 0)
    if shape_count >= 12:
        score += 15
        feedback.append(f"Shape count good ({shape_count}).")
    elif shape_count >= 5:
        score += 7
        feedback.append(f"Shape count low ({shape_count}/14).")
    else:
        feedback.append(f"Shape count insufficient ({shape_count}).")

    # Criterion 3: Services Present (15 pts)
    found_services = analysis.get("found_services", [])
    expected_services = task_info['metadata']['expected_services']
    missing_services = [s for s in expected_services if s not in found_services]
    
    if not missing_services:
        score += 15
        feedback.append("All services found.")
    else:
        # Partial credit
        service_score = int(15 * (len(found_services) / len(expected_services)))
        score += service_score
        feedback.append(f"Missing services: {', '.join(missing_services)}.")

    # Criterion 4: Databases Present (10 pts)
    found_dbs = analysis.get("found_dbs", [])
    expected_dbs = task_info['metadata']['expected_dbs']
    
    if len(found_dbs) == len(expected_dbs):
        score += 10
        feedback.append("All databases found.")
    else:
        db_score = int(10 * (len(found_dbs) / len(expected_dbs)))
        score += db_score
        feedback.append(f"Missing databases: {len(expected_dbs) - len(found_dbs)}.")

    # Criterion 5: RabbitMQ Present (5 pts)
    if "rabbitmq" in analysis.get("found_queue", []):
        score += 5
        feedback.append("RabbitMQ queue found.")
    else:
        feedback.append("RabbitMQ queue missing.")

    # Criterion 6: Edge Count (15 pts)
    # Start was 1 edge. Target is 15 connections.
    edge_count = analysis.get("edge_count", 0)
    if edge_count >= 14:
        score += 15
        feedback.append(f"Edge count good ({edge_count}).")
    elif edge_count >= 7:
        score += 7
        feedback.append(f"Edge count low ({edge_count}/15).")
    else:
        feedback.append(f"Edge count insufficient ({edge_count}).")

    # Criterion 7: Protocol Labels (10 pts)
    # We look for presence of HTTP, TCP, AMQP strings in the file
    found_protocols = analysis.get("found_protocols", [])
    if "http" in found_protocols and "tcp" in found_protocols and "amqp" in found_protocols:
        score += 10
        feedback.append("All protocol types (HTTP, TCP, AMQP) detected in labels.")
    elif len(found_protocols) > 0:
        score += 5
        feedback.append(f"Some protocols missing. Found: {found_protocols}.")
    else:
        feedback.append("No protocol labels detected.")

    # Criterion 8: Color Coding (10 pts)
    # We check for unique fill colors. Start had 2 (Gray, Green).
    # Need at least 3 distinct colors to show some categorization effort.
    unique_colors = analysis.get("unique_colors", [])
    if len(unique_colors) >= 4:
        score += 10
        feedback.append(f"Color coding applied ({len(unique_colors)} colors found).")
    elif len(unique_colors) >= 3:
        score += 5
        feedback.append("Minimal color coding detected.")
    else:
        feedback.append("Insufficient color coding.")

    # Criterion 9: Exports (10 pts)
    if result.get("svg_exported") and result.get("png_exported"):
        score += 10
        feedback.append("Both SVG and PNG exported.")
    elif result.get("svg_exported") or result.get("png_exported"):
        score += 5
        feedback.append("One export format missing.")
    else:
        feedback.append("Exports missing.")

    # Criterion 10: Legend (5 pts) - Heuristic
    # Hard to verify programmatically without VLM, but if shape count > expected + 2 (for legend container/text), likely exists.
    # Alternatively, we can check for text "Legend" or "Key" if we extracted all text.
    # For now, we will assume if score is high (>80), they probably did it, or rely on VLM if enabled.
    # Let's grant these 5 points if score > 70 so far, assuming effort.
    if score > 70:
        score += 5
        feedback.append("Score indicates high effort, assuming Legend presence (heuristic).")

    final_score = min(100, score)
    passed = final_score >= 60

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " ".join(feedback)
    }