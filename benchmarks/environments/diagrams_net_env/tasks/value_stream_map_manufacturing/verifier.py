#!/usr/bin/env python3
import json
import os
import tempfile

def verify_value_stream_map_manufacturing(traj, env_info, task_info):
    """
    Verifies the Value Stream Map task based on the JSON exported from the container.
    """
    
    # 1. Setup - Get Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/final_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Verification Logic
    score = 0
    feedback = []

    # Criterion A: File Modification (Anti-Gaming)
    if result.get("file_exists") and result.get("file_modified"):
        score += 5
        feedback.append("File modified successfully.")
    else:
        feedback.append("File not found or not modified.")

    # Criterion B: Content - Current State Processes (15 pts)
    # The agent needed to add Welding II, Assembly I, Assembly II, Shipping
    if result.get("has_required_processes"):
        score += 15
        feedback.append("All required process steps found.")
    else:
        feedback.append("Missing some process steps (Welding II, Assembly I/II, or Shipping).")

    # Criterion C: Content - Data Values (15 pts)
    # Checked for presence of cycle times: 46, 62, 40
    if result.get("has_required_data"):
        score += 15
        feedback.append("Process data values (C/T) verified.")
    else:
        feedback.append("Missing or incorrect process data values.")

    # Criterion D: Lead Time Ladder Totals (10 pts)
    if result.get("has_totals"):
        score += 10
        feedback.append("Lead time ladder totals (23.5 days, 188s) verified.")
    else:
        feedback.append("Total Lead Time or Processing Time missing/incorrect.")

    # Criterion E: Complexity / Shape Count (5 pts)
    # Initial file has ~8 cells. Expecting > 50.
    if result.get("cell_count", 0) > 40:
        score += 5
        feedback.append("Diagram complexity looks good.")
    elif result.get("cell_count", 0) > 20:
        score += 2
        feedback.append("Diagram complexity low.")
    else:
        feedback.append("Diagram has very few shapes.")

    # Criterion F: Future State Page (10 pts)
    if result.get("page_count", 0) >= 2:
        score += 10
        feedback.append("Future State page created.")
    else:
        feedback.append("Missing second page for Future State.")

    # Criterion G: Future State Content (15 pts)
    # Checking for: Weld Cell, Assembly Cell, Supermarket, FIFO, Kaizen
    if result.get("has_future_state"):
        score += 15
        feedback.append("Future state elements (Cells, FIFO, Supermarket) found.")
    else:
        feedback.append("Missing key future state elements.")

    # Criterion H: PDF Export (5 pts)
    if result.get("pdf_exists"):
        score += 5
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    # Inventory Triangles / Info Flow (20 pts implied by logic/text presence)
    # We'll award remaining points based on general cell count and modification
    # as strict text matching for graphical triangles is hard.
    # If they did the work, cell count is high and modification is true.
    if result.get("cell_count", 0) > 60:
         score += 20
         feedback.append("Detailed diagram structure detected.")
    elif result.get("cell_count", 0) > 40:
         score += 10
         feedback.append("Moderate diagram structure detected.")

    # 3. Final Result
    passed = score >= 55
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }