# Annotate for Stakeholder Task

**Difficulty**: 🟡 Medium  
**Skills**: Code documentation, technical communication, business logic understanding  
**Duration**: 480 seconds (8 minutes)  
**Steps**: ~100

## Objective

Add business-focused inline comments to a pricing calculation function so a non-technical product manager can verify that the implementation matches agreed-upon business rules.

## Scenario

Your PM needs to verify subscription pricing logic for a compliance audit but gets overwhelmed by technical code. She needs simple comments explaining:
- Enterprise customers get 20% discount
- Annual billing gets additional 15% discount
- Price never goes below $99/month minimum

## Expected Workflow

1. Review the `calculate_subscription_price` function in `src/pricing.py`
2. Identify the business logic sections (enterprise discount, annual discount, minimum price)
3. Add clear, non-technical comments explaining each business rule
4. Ensure comments use business language (not technical jargon)
5. Save the file (Ctrl+S)

## Verification

Checks for:
1. At least 4 meaningful comments added (>10 chars each)
2. Comments explain 2+ key business rules (20% enterprise, 15% annual, $99 minimum)
3. Comments use business-friendly language
4. Python syntax remains valid
5. Function logic unchanged

**Pass Threshold**: 85% (comments explain 2+ rules with sufficient detail)