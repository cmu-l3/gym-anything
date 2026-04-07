#!/usr/bin/env python3
"""
Verifier for Review Radiology Exams task (`review_radiology_exams@1`).

Verification Strategy:
1. Infrastructure Check (20%): VistA running, YDBGui accessible.
2. Trajectory/Screenshot VLM Analysis (80%):
   - Confirm agent navigated to ^RA(71) (Procedures)
   - Confirm agent navigated to ^RA(75.1) (Orders)
   - Confirm data content (procedure names) matches ground truth context.

"""

import json
import os
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_review_radiology_exams(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Review Radiology Exams task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Infrastructure Checks (20 points)
    vista_status = result.get('vista_container_status', 'unknown')
    ydbgui_accessible = result.get('ydbgui_accessible', False)
    
    if vista_status == 'running':
        score += 10
        feedback_parts.append("✅ VistA container running")
    else:
        feedback_parts.append("❌ VistA container not running")

    if ydbgui_accessible:
        score += 10
        feedback_parts.append("✅ YDBGui accessible")
    else:
        feedback_parts.append("❌ YDBGui not accessible")

    # 3. Ground Truth Context (for VLM prompt)
    gt = result.get('ground_truth', {})
    sample_procs = gt.get('sample_procedures', '')
    sample_orders = gt.get('sample_orders', '')
    
    # 4. VLM Verification (80 points)
    # We use the final screenshot and optionally trajectory frames
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        
        # We construct a prompt that asks the VLM to look for specific visual evidence
        prompt = f"""
        Analyze this screenshot of the VistA/YottaDB web interface (YDBGui).
        The user is supposed to be reviewing RADIOLOGY data.

        Look for the following specific indicators:
        1. **Procedures Global**: The text "^RA(71)" or "RAD/NUC MED PROCEDURES" or "71".
        2. **Orders Global**: The text "^RA(75.1)" or "RAD/NUC MED ORDERS" or "75.1".
        3. **Procedure Names**: Look for medical imaging terms like "CHEST", "SKULL", "CT", "MRI", "X-RAY". 
           (Known examples in DB: {sample_procs})
        4. **Tree Navigation**: A hierarchical tree view showing "RA" expanded.
        
        Respond in JSON format:
        {{
            "procedures_global_visible": boolean,
            "orders_global_visible": boolean,
            "procedure_names_visible": boolean,
            "procedure_names_text": "list names seen",
            "is_dashboard_only": boolean,
            "confidence": "high|medium|low"
        }}
        """
        
        try:
            vlm_response = query_vlm(prompt=prompt, image=final_screenshot)
            
            # Simple parsing if VLM returns string (handles potential markdown wrapping)
            if isinstance(vlm_response, str):
                # Try to extract JSON if wrapped in code blocks
                if "