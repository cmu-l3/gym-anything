#!/usr/bin/env python3
"""
Verifier for azure_iot_telemetry_pipeline task.

Scoring:
- Files Exist (10 pts)
- Azure Shapes Used (25 pts): Checks for mxgraph.azure style tags
- Key Components Found (20 pts): IoT Hub, Stream Analytics, Cosmos, Storage, Power BI
- Ingestion Flow (15 pts): Edge exists from Hub to Stream Analytics
- Split Topology (20 pts): Stream Analytics has >1 outgoing edge (Hot/Cold split)
- Visualization End (10 pts): Power BI present
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_azure_iot_telemetry_pipeline(traj, env_info, task_info):
    """Verify Azure IoT architecture diagram."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result from container
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
    
    # 1. Files Check (10 pts)
    if result.get("file_exists") and result.get("png_exists"):
        score += 10
        feedback.append("Files saved successfully")
    elif result.get("file_exists"):
        score += 5
        feedback.append("Drawio file saved, but PNG missing")
    else:
        feedback.append("No output files found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    analysis = result.get("analysis", {})
    
    # 2. Azure Library Usage (25 pts)
    # A real diagram should have at least 3-4 distinct Azure shapes.
    # The XML analysis counts shapes with 'azure' in the style.
    azure_count = analysis.get("azure_shapes_count", 0)
    if azure_count >= 4:
        score += 25
        feedback.append(f"Good use of Azure shape library ({azure_count} shapes)")
    elif azure_count >= 1:
        score += 10
        feedback.append(f"Limited use of Azure shape library ({azure_count} shapes)")
    else:
        feedback.append("No official Azure shapes detected (did you use generic rectangles?)")

    # 3. Components Check (20 pts)
    comps = analysis.get("components_found", {})
    found_count = sum(1 for v in comps.values() if v)
    if found_count >= 4:
        score += 20
        feedback.append("All key architecture components identified")
    elif found_count >= 2:
        score += 10
        feedback.append(f"Some components missing (Found {found_count}/5)")
    else:
        feedback.append("Most components missing")
        missing = [k for k,v in comps.items() if not v]
        feedback.append(f"Missing: {', '.join(missing)}")

    # 4. Ingestion Flow (15 pts)
    # Checks for edge from Hub -> Stream Analytics
    if analysis.get("has_ingestion_flow"):
        score += 15
        feedback.append("Ingestion flow (Hub -> Analytics) correct")
    else:
        feedback.append("Missing connection from IoT Hub to Stream Analytics")

    # 5. Split Topology (20 pts)
    # Checks if Stream Analytics has > 1 outgoing connection (Bifurcation)
    out_degree = analysis.get("stream_analytics_out_degree", 0)
    if out_degree >= 2:
        score += 20
        feedback.append("Hot/Cold path split verified")
    elif out_degree == 1:
        score += 5
        feedback.append("Stream Analytics only has 1 output (Missing Hot or Cold path)")
    else:
        feedback.append("Stream Analytics has no outputs")

    # 6. Visualization (10 pts)
    if comps.get("power_bi"):
        score += 10
        feedback.append("Power BI visualization included")

    # Pass Threshold
    # Needs 60 points.
    # Essential: Files (10) + Some Azure Shapes (10) + Components (10) + Basic Flow (15) + Some Split (5) = 50 (Fail)
    # Needs at least correct library usage or correct full topology to pass.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }