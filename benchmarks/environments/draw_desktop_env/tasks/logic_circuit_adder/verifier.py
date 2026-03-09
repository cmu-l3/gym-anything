#!/usr/bin/env python3
"""
Verifier for logic_circuit_adder task.

Scoring Criteria (100 pts total):
1. File saved & modified after start (10 pts)
2. Multi-page diagram (>= 2 pages) (10 pts)
3. Block Diagram Content (Page 1):
   - FA blocks (FA0-3) found (15 pts)
   - Signal labels (A0-3, B0-3, etc) found (15 pts)
   - Connectivity (>= 15 edges) (10 pts)
4. Gate Schematic Content (Page 2):
   - Gate keywords/shapes (XOR, AND, OR) (15 pts)
   - Boolean equations annotated (10 pts)
5. Export:
   - PNG file exists (10 pts)
6. Structure:
   - Carry chain heuristic (edges > blocks) (5 pts)

Pass Threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_logic_circuit_adder(traj, env_info, task_info):
    """Verify the 4-bit adder circuit task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Read error: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    analysis = result.get('analysis', {})
    
    # 1. File Existence & Modification (10 pts)
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 10
        feedback.append("File saved successfully")
    elif result.get('file_exists'):
        # Exists but not modified? Likely pre-existing or touch error, but if analysis shows content, we trust analysis
        if analysis.get('num_pages', 0) > 0:
            score += 5
            feedback.append("File exists (timestamp check uncertain)")
        else:
            feedback.append("File exists but appears empty/unmodified")
    else:
        return {"passed": False, "score": 0, "feedback": "Main .drawio file not found"}

    # 2. Pages (10 pts)
    pages = analysis.get('num_pages', 0)
    if pages >= 2:
        score += 10
        feedback.append(f"Multi-page diagram found ({pages} pages)")
    elif pages == 1:
        score += 5
        feedback.append("Only 1 page found (expected 2)")
    else:
        feedback.append("No diagram pages found")

    # 3. Block Diagram Content (30 pts total)
    # Blocks (15)
    blocks = analysis.get('blocks_found', [])
    if len(blocks) >= 4:
        score += 15
        feedback.append("All 4 FA blocks found")
    elif len(blocks) >= 2:
        score += 8
        feedback.append(f"Partial blocks found: {', '.join(blocks)}")
    else:
        feedback.append("Missing FA blocks (need FA0-FA3)")

    # Signals (15)
    signals = analysis.get('signals_found', [])
    # We expect A0-A3, B0-B3, S0-S3, Cout (approx 13 labels)
    if len(signals) >= 8:
        score += 15
        feedback.append(f"Signal labels good ({len(signals)} found)")
    elif len(signals) >= 4:
        score += 7
        feedback.append(f"Some signal labels found ({len(signals)})")
    else:
        feedback.append("Missing signal labels")

    # 4. Connectivity (15 pts total)
    edges = analysis.get('num_edges', 0)
    # 4 blocks * ~3-4 connections each + gate internals ~ 20 edges
    if edges >= 15:
        score += 10
        feedback.append(f"Good connectivity ({edges} edges)")
    elif edges >= 5:
        score += 5
        feedback.append(f"Low connectivity ({edges} edges)")
    else:
        feedback.append("Diagram has few/no connections")

    # Carry chain heuristic (5 pts)
    # If we have 4 blocks and 15 edges, we assume some interconnectivity
    if len(blocks) >= 3 and edges >= 10:
        score += 5
        feedback.append("Implied carry chain structure")

    # 5. Gate Schematic (25 pts total)
    gates = analysis.get('gates_found', [])
    if len(gates) >= 2: # e.g. XOR and AND
        score += 15
        feedback.append(f"Logic gates found: {', '.join(gates)}")
    elif len(gates) == 1:
        score += 5
        feedback.append(f"Some gates found: {gates[0]}")
    else:
        feedback.append("No logic gate keywords (XOR/AND/OR) found")

    if analysis.get('has_equations'):
        score += 10
        feedback.append("Boolean equations annotated")
    else:
        feedback.append("Missing boolean equations")

    # 6. PNG Export (10 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 1000:
        score += 10
        feedback.append("PNG exported")
    else:
        feedback.append("PNG export missing or empty")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }