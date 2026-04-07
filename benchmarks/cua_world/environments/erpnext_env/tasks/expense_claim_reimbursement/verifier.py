"""
Verifier for expense_claim_reimbursement task.

Task: Process a $1,250 travel reimbursement for Marco Silva.
      Agent must create an Expense Claim with 4 line items and a matching Payment Entry.

Scoring (100 pts total, pass >= 60):
  C1 [25 pts] — A new Expense Claim is submitted for Marco Silva.
  C2 [25 pts] — The total claimed amount on the Expense Claim is ~$1,250.
  C3 [15 pts] — The Expense Claim contains at least 4 line items.
  C4 [20 pts] — A new Payment Entry is submitted for Marco Silva.
  C5 [15 pts] — The paid amount on the Payment Entry is ~$1,250.

Anti-Gaming Checks:
  - Baseline tracking guarantees only records created *during the task* are evaluated.
  - Verifier strictly filters out pre-existing data, detecting "do-nothing" behavior.
"""

import json

EXPECTED_TOTAL = 1250.0
TOLERANCE = 10.0


def verify_expense_claim_reimbursement(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/expense_claim_reimbursement_result.json"
    )
    local_tmp = "/tmp/_ecr_result_local.json"

    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0,
            "feedback": f"Result file missing — export script may not have run: {e}"
        }

    try:
        with open(local_tmp) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0,
            "feedback": f"Could not parse result JSON: {e}"
        }

    expense_claims = data.get("expense_claims", [])
    payment_entries = data.get("payment_entries", [])

    score = 0
    feedback_parts = []

    # --- C1: Expense Claim submitted ---
    c1_pass = len(expense_claims) > 0
    if c1_pass:
        score += 25
        feedback_parts.append("C1 PASS: Expense Claim submitted for Marco Silva (+25)")
    else:
        feedback_parts.append("C1 FAIL: No new submitted Expense Claim found for Marco Silva")

    # --- C2: Total claimed amount ~ $1,250 ---
    c2_pass = any(abs(ec.get("total_claimed_amount", 0) - EXPECTED_TOTAL) <= TOLERANCE for ec in expense_claims)
    if c2_pass:
        score += 25
        feedback_parts.append(f"C2 PASS: Expense Claim total is correct (~${EXPECTED_TOTAL}) (+25)")
    else:
        if expense_claims:
            amounts = [ec.get("total_claimed_amount") for ec in expense_claims]
            feedback_parts.append(f"C2 FAIL: Expense Claim amounts incorrect (Expected ~${EXPECTED_TOTAL}, got {amounts})")
        else:
            feedback_parts.append("C2 SKIP: No Expense Claim to check amount")

    # --- C3: Contains >= 4 line items ---
    c3_pass = any(ec.get("expense_count", 0) >= 4 for ec in expense_claims)
    if c3_pass:
        score += 15
        feedback_parts.append("C3 PASS: Expense Claim contains >= 4 line items (+15)")
    else:
        if expense_claims:
            counts = [ec.get("expense_count") for ec in expense_claims]
            feedback_parts.append(f"C3 FAIL: Expense Claim line items insufficient (Expected >= 4, got {counts})")
        else:
            feedback_parts.append("C3 SKIP: No Expense Claim to check line items")

    # --- C4: Payment Entry submitted ---
    # Payment type doesn't strictly have to be 'Pay' if it's an outbound Employee payment, but it generally defaults to it.
    c4_pass = len(payment_entries) > 0
    if c4_pass:
        score += 20
        feedback_parts.append("C4 PASS: Payment Entry submitted for Marco Silva (+20)")
    else:
        feedback_parts.append("C4 FAIL: No new submitted Payment Entry found for Marco Silva")

    # --- C5: Payment amount ~ $1,250 ---
    c5_pass = any(abs(pe.get("paid_amount", 0) - EXPECTED_TOTAL) <= TOLERANCE for pe in payment_entries)
    if c5_pass:
        score += 15
        feedback_parts.append(f"C5 PASS: Payment amount is correct (~${EXPECTED_TOTAL}) (+15)")
    else:
        if payment_entries:
            amounts = [pe.get("paid_amount") for pe in payment_entries]
            feedback_parts.append(f"C5 FAIL: Payment Entry amounts incorrect (Expected ~${EXPECTED_TOTAL}, got {amounts})")
        else:
            feedback_parts.append("C5 SKIP: No Payment Entry to check amount")

    # Evaluated out of 100 points
    passed = score >= 60

    if not passed and score == 0:
        feedback_parts.append("AGENT DID NOTHING OR FAILED TO SUBMIT DOCS: Score is 0.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "expense_claims_found": len(expense_claims),
            "payment_entries_found": len(payment_entries)
        }
    }