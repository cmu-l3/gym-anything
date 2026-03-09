# Register a Supplier Credit Note (`register_supplier_credit_note@1`)

## Overview
This task requires the agent to record a **supplier credit note** (purchase refund) in Ekylibre. The agent must verify or create a supplier, enter the credit note details including a specific reference number, and record the returned items to adjust the accounts payable balance correctly.

## Rationale
**Why this task is valuable:**
- **Exception Handling**: Tests the ability to handle "negative" financial flows (refunds/returns), which are less common but critical for accurate bookkeeping.
- **Workflow Variation**: Credit notes often have slightly different UI flows or validation rules compared to standard invoices.
- **Financial Accuracy**: Ensures the agent understands the difference between a debt (invoice) and a credit (credit note) in a farm management context.
- **Entity Management**: Requires handling supplier entities on the fly.

**Real-world Context:** A farmer at GAEC JOULIN returned unused fencing materials (wooden posts and wire) to their local supplier "AgriMat 17" after completing a pasture enclosure. The supplier has issued a credit note (Avoir) for €150.00. The farmer needs to record this document to reduce the amount owed to the supplier and correct the VAT records.

## Task Description

**Goal:** Record a supplier credit note (Avoir fournisseur) from "AgriMat 17" for a total pretax amount of €150.00.

**Starting State:**
- Ekylibre is open in Firefox.
- User is logged in as Administrator.
- The Dashboard or Purchases list is visible.

**Expected Actions:**
1. Navigate to the **Purchases** (Trade / Achats) section.
2. Initiate the creation of a **Credit Note** (Avoir) or a Purchase with a negative type/refund status.
3. Enter the header details:
   - **Supplier**: `AgriMat 17` (Create this supplier if they do not exist).
   - **Reference Number**: `AV-2025-004`.
   - **Date**: `2024-11-15`.
4. Add line items to match the credit amount:
   - **Description/Product**: `Matériel de clôture` (Fencing material) or similar.
   - **Quantity**: `1`.
   - **Unit Price (Pretax)**: `150.00`.
   - *Alternatively, multiple lines summing to €150.00 pretax are acceptable.*
5. Save and confirm the document.

**Final State:**
- A valid purchase credit note with reference `AV-2025-004` exists in the system.
- The document is linked to supplier `AgriMat 17`.
- The total pretax amount is €150.00.

## Verification Strategy

### Primary Verification: Database Query
The verifier queries the Ekylibre PostgreSQL database (`purchases` table) to confirm the existence of the credit note. It checks for the reference number and ensures the record type or amount reflects a credit note.

### Anti-Gaming Checks
1. **Timestamp Validation**: The record's `created_at` must be after the task start time.
2. **Do-Nothing Detection**: The count of purchase documents must increase.
3. **Value Precision**: The amount must be exactly 150.00.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Credit Note Exists | 40 | A purchase record with ref `AV-2025-004` is found. |
| Correct Type | 20 | The record is identified as a Credit Note (not a standard Invoice). |
| Correct Supplier | 20 | Linked to supplier "AgriMat 17". |
| Correct Amount | 20 | Pretax amount matches €150.00. |
| **Total** | **100** | |