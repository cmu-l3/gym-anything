#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_transformer_architecture(traj, env_info, task_info):
    """
    Verifies the Transformer Architecture Diagram task.
    
    Scoring Criteria:
    1. File Saved & Modified: 10 pts
    2. Core Components (Attention, FF, Linear, Softmax, Embedding): 30 pts
    3. Residual Connections ("Add & Norm" blocks): 20 pts
    4. Decoder Specifics ("Masked"): 15 pts
    5. Stacks & Repetition ("Nx" labels): 10 pts
    6. Diagram Complexity (Edges/Cross-Connection): 5 pts
    7. PNG Export: 10 pts
    
    Total: 100 pts
    Pass: 60 pts
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
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

    # 2. Parse Analysis Data
    analysis = result.get("analysis", {})
    counts = analysis.get("counts", {})
    
    score = 0
    feedback = []
    
    # --- Criterion 1: File Saved (10 pts) ---
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
    else:
        feedback.append("Draw.io file was not saved or not modified.")
        
    # --- Criterion 2: Core Components (30 pts) ---
    # We expect: Multi-Head Attention, Feed Forward, Linear, Softmax, Embedding
    core_items = ["Multi-Head Attention", "Feed Forward", "Linear", "Softmax", "Embedding"]
    found_core = 0
    missing_core = []
    
    for item in core_items:
        if counts.get(item, 0) > 0:
            found_core += 1
        else:
            missing_core.append(item)
            
    # Scale score: 5 items * 6 pts each = 30
    score += found_core * 6
    if missing_core:
        feedback.append(f"Missing core components: {', '.join(missing_core)}.")
    else:
        feedback.append("All core components found.")
        
    # --- Criterion 3: Residual Connections (Add & Norm) (20 pts) ---
    # The spec requires Add & Norm after every sublayer.
    # Encoder: 2 sublayers * Nx. Decoder: 3 sublayers * Nx.
    # We verify if "Add & Norm" appears at least 5 times total (minimum for a single unrolled pass or representative blocks).
    add_norm_count = counts.get("Add & Norm", 0)
    if add_norm_count >= 5:
        score += 20
        feedback.append(f"Residual connections verified (found {add_norm_count} 'Add & Norm' blocks).")
    elif add_norm_count > 0:
        score += 10
        feedback.append(f"Partial residual connections found ({add_norm_count} blocks, expected >= 5).")
    else:
        feedback.append("No 'Add & Norm' blocks found. Residual connections missing.")
        
    # --- Criterion 4: Decoder Specifics (Masked Attention) (15 pts) ---
    if counts.get("Masked", 0) > 0:
        score += 15
        feedback.append("Decoder 'Masked' attention found.")
    else:
        feedback.append("Missing 'Masked' attention component specific to Decoder.")
        
    # --- Criterion 5: Stacks & Repetition (10 pts) ---
    if counts.get("Nx", 0) > 0:
        score += 10
        feedback.append("Stack repetition label 'Nx' found.")
    else:
        feedback.append("Missing 'Nx' label to indicate stack repetition.")
        
    # --- Criterion 6: Connectivity (5 pts) ---
    # We check if there are a reasonable number of edges.
    # A transformer diagram is complex. Should have at least 10 edges.
    edge_count = analysis.get("edge_count", 0)
    if edge_count >= 10:
        score += 5
    else:
        feedback.append(f"Diagram appears too simple (only {edge_count} edges found).")

    # --- Criterion 7: PNG Export (10 pts) ---
    if result.get("png_exists") and result.get("png_size", 0) > 2000:
        score += 10
    else:
        feedback.append("PNG export missing or invalid.")

    # 3. Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }