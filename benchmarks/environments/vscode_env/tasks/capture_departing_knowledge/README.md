# Capture Departing Knowledge Task

**Difficulty**: 🟡 Medium  
**Skills**: Documentation, Code Comments, Knowledge Transfer, Markdown  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Document critical system knowledge from a departing engineer by enriching code with inline documentation and creating a comprehensive guide document. This simulates a real-world scenario where tribal knowledge must be captured before an employee leaves.

## Scenario

Your senior backend engineer, Maya, is leaving in one week. She's the only person who understands the payment processing pipeline. You have a knowledge transfer transcript and need to embed her expertise into the codebase so it's not lost.

## Expected Workflow

1. Read `knowledge_transfer.md` to understand Maya's insights
2. Open `payment_processor.py` 
3. Add Python docstrings to functions (at least 5)
4. Add inline comments explaining WHY decisions were made (at least 8)
5. Add WARNING comments for known edge cases (at least 2)
6. Add TODO comments for identified technical debt (at least 1)
7. Create `PAYMENT_SYSTEM_GUIDE.md` with:
   - Common gotchas/known issues section
   - References to related files (webhook_handler.py, refund_logic.py, fraud_checker.py)
   - External resource links
   - Contact/troubleshooting information
8. Save all files

## Verification

Checks for:
1. **Inline Documentation (40%)**: Docstrings, explanatory comments, warnings, TODOs
2. **Guide Document (35%)**: Structure, gotchas section, file references, external links, contact info
3. **Documentation Quality (25%)**: Proper formatting, WHY vs WHAT comments, cross-references, readability

**Pass Threshold**: 70% (70/100 points)