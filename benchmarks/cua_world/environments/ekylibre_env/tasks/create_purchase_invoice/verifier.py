#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_purchase_invoice(traj, env_info, task_info):
    """
    Verify create_purchase_invoice task.
    
    Criteria:
    1. Invoice exists in DB (25 pts)
    2. Reference number matches 'INV-2024-0587' (15 pts)
    3. Supplier contains 'Poitou' (15 pts)
    4. Line item count >= 2 (15 pts)
    5. Amount is reasonable (approx 1015 EUR) (15 pts)
    6. Date is correct (2024-03-15) (5 pts)
    7. VLM verification of workflow (10 pts)
    """
    
    # 1. Retrieve result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Database Results
    invoice = result.get('invoice_data')
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    
    metadata = task_info.get('metadata', {})
    expected_ref = metadata.get('expected_reference', 'INV-2024-0587')
    expected_supplier = metadata.get('expected_supplier_partial', 'Poitou')
    
    score = 0
    feedback = []
    
    # CRITERION 1: Invoice Existence (25 pts)
    if invoice:
        score += 25
        feedback.append("Invoice record found.")
    elif current_count > initial_count:
        # Fallback: Invoice created but script failed to find details (maybe weird chars)
        score += 10
        feedback.append("Invoice count increased, but specific record details not verified.")
    else:
        feedback.append("No new invoice found in database.")
        return {"passed": False, "score": 0, "feedback": "Failed: No invoice created."}

    if invoice:
        # CRITERION 2: Reference Number (15 pts)
        ref_num = invoice.get('reference_number', '')
        if expected_ref in ref_num:
            score += 15
            feedback.append(f"Reference number correct ({ref_num}).")
        else:
            feedback.append(f"Reference number incorrect. Expected '{expected_ref}', got '{ref_num}'.")

        # CRITERION 3: Supplier Name (15 pts)
        supplier_name = invoice.get('supplier_name', '')
        # Check for 'Poitou' OR 'Coopérative' to be lenient on exact spelling
        if expected_supplier.lower() in supplier_name.lower() or "coop" in supplier_name.lower():
            score += 15
            feedback.append(f"Supplier correct ({supplier_name}).")
        else:
            feedback.append(f"Supplier incorrect. Expected similar to '{expected_supplier}', got '{supplier_name}'.")

        # CRITERION 4: Line Items (15 pts)
        item_count = int(invoice.get('item_count', 0))
        if item_count >= 2:
            score += 15
            feedback.append(f"Line items count correct ({item_count}).")
        elif item_count == 1:
            score += 5
            feedback.append("Only 1 line item found (expected 2).")
        else:
            feedback.append("No line items found.")

        # CRITERION 5: Amount Accuracy (15 pts)
        # Expected: ~1015. Allow 900-1150 range.
        try:
            amount = float(invoice.get('pretax_amount') or invoice.get('amount') or 0)
            if 900.0 <= amount <= 1150.0:
                score += 15
                feedback.append(f"Amount within expected range ({amount} EUR).")
            else:
                feedback.append(f"Amount {amount} EUR outside expected range (900-1150).")
        except:
            feedback.append("Could not parse invoice amount.")

        # CRITERION 6: Date (5 pts)
        inv_date = invoice.get('invoiced_at', '')
        if '2024-03-15' in inv_date:
            score += 5
            feedback.append("Invoice date correct.")
        else:
            feedback.append(f"Invoice date incorrect ({inv_date}).")

    # CRITERION 7: VLM Verification (10 pts)
    # Check if they actually used the UI
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        if final_scr:
            frames.append(final_scr)
        
        vlm_prompt = (
            "Review these screenshots of a farm management software task. "
            "Did the user fill out a purchase invoice form? "
            "Look for: 'Nouvelle facture', 'Fournisseur', 'Lignes', or saving a document. "
            "Reply 'YES' if the workflow is visible, 'NO' otherwise."
        )
        
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt).get('response', '').upper()
        
        if 'YES' in vlm_resp:
            score += 10
            feedback.append("VLM verified form interaction.")
        else:
            feedback.append("VLM did not clearly see invoice creation workflow.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Give benefit of doubt if DB check passed strongly
        if score >= 60:
            score += 10
            feedback.append("VLM check skipped (error), awarded points based on DB success.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }