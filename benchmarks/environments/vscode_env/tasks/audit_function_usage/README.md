# Audit Function Usage Task

**Difficulty**: 🟡 Medium  
**Skills**: Code navigation, Find All References, documentation, refactoring preparation  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Audit all usages of the `calculate_discount()` function across a codebase before refactoring it. Use VSCode's "Find All References" feature to locate all call sites and document them in a refactoring plan.

## Scenario

You're working on an e-commerce application and need to refactor the `calculate_discount(price, customer_type)` function to add a third parameter for promotional codes. Before making changes, you must audit all existing usages to understand the impact.

## Expected Workflow

1. Navigate to `pricing/calculator.py`
2. Locate the `calculate_discount` function definition
3. Use "Find All References" (Right-click → Find All References, or Shift+F12)
4. Review all usage locations in the References panel
5. Create `/home/ga/workspace/ecommerce_app/REFACTOR_PLAN.md`
6. Document each usage location with:
   - File path
   - Line number or function/class context
   - Brief description
7. Add a refactoring marker comment above the function definition
8. Save all changes

## Verification

Checks for:
1. `REFACTOR_PLAN.md` exists and has substantial content (>200 bytes)
2. Documentation mentions at least 4 usage locations (checkout.py, cart.py, discount_api.py, test_pricing.py)
3. Contains line numbers or location references
4. Mentions `calculate_discount` multiple times
5. Refactoring comment added to `calculator.py` above function definition
6. Comment mentions refactoring context (plan/audit/usage/parameter)

**Pass Threshold**: 5.5/6.0 points (91%)