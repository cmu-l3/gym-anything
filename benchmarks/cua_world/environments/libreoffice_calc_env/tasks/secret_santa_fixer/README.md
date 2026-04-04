# Secret Santa Assignment Fixer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data validation, constraint satisfaction, relationship mapping, data cleaning  
**Duration**: 240 seconds  
**Steps**: ~25

## Objective

Fix a partially-completed Secret Santa gift exchange spreadsheet that contains constraint violations and data inconsistencies. The agent must identify and correct rule violations (self-assignments, spouse pairings), complete missing assignments, standardize budgets, and ensure the exchange forms a proper gift-giving cycle.

## Task Description

The agent must:
1. Open the provided Secret Santa spreadsheet with existing violations
2. Identify people assigned to themselves (self-assignment violations)
3. Identify married couples assigned to each other (spouse pairing violations)
4. Fix all constraint violations by reassigning to valid recipients
5. Complete any missing "Gives To" assignments
6. Standardize budget entries to consistent numeric values
7. Ensure every person gives to exactly one person and receives from exactly one person
8. Save the corrected file

## Starting State

The spreadsheet contains 4 columns:
- **Column A (Name)**: Participant name
- **Column B (Spouse)**: Spouse name (if married, empty if single)
- **Column C (Gives To)**: Who this person should give a gift to
- **Column D (Budget)**: Suggested gift budget (inconsistent formats)

**Intentional Problems:**
- 2 self-assignments (person assigned to themselves)
- 1-2 spouse pairings (married couples assigned to each other)
- 1-2 missing assignments (empty "Gives To" cells)
- Inconsistent budget formats ("$25", "25 dollars", "twenty-five", etc.)

## Expected Results

After fixing:
- **No self-assignments**: Every person gives to someone different
- **No spouse pairings**: Married couples don't give to each other
- **Complete assignments**: Every "Gives To" cell is filled
- **Valid cycle**: Assignments form a single connected cycle
- **Standardized budgets**: All budgets are numeric ($15-50 range)
- **Balanced coverage**: Everyone gives to 1 and receives from 1

## Verification Criteria

1. ✅ **No Self-Assignments**: No person assigned to themselves (0 violations)
2. ✅ **No Spouse Pairings**: No married couples assigned to each other (0 violations)
3. ✅ **Complete Assignments**: Every participant has a "Gives To" entry
4. ✅ **Valid Cycle**: Assignments form a single complete cycle including all participants
5. ✅ **Budget Standardized**: All budgets are numeric and within $15-50 range
6. ✅ **Balanced Coverage**: Each person gives to exactly 1 and receives from exactly 1

**Pass Threshold**: 80% (5/6 criteria must pass)

## Skills Tested

- Constraint satisfaction and rule enforcement
- Data validation across related columns
- Relationship mapping (directional graphs)
- Data cleaning and standardization
- Completeness checking
- Logical problem solving with real-world constraints

## Real-World Context

You're helping organize a family Secret Santa exchange. Your aunt started the spreadsheet but made several mistakes. People are getting anxious because the gathering is in 3 days and they need to know who to shop for. You must fix all the violations quickly and correctly.

## Tips

- Check each row to identify self-assignments (Name = Gives To)
- Use the Spouse column to identify married couples
- Ensure no one appears twice as a recipient
- Budget should be a clear number (e.g., 25 or $25, not "twenty-five")
- Test your solution: follow the chain of giving to verify it forms one complete cycle