# Edge Case Investigation Task (`investigate_edge_case_behavior@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Debugging, hypothesis testing, documentation, root cause analysis  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Investigate and document a bizarre edge case bug in a pricing utility function. The function `calculate_discount()` fails for negative discounts, excessive discounts (>100%), and string inputs. Your goal is to understand WHY these failures occur and document your findings systematically.

## Background Story

A customer reported seeing **negative prices** on the checkout page. The QA team traced the issue to `calculate_discount()` in `utils/pricing.py`. Your task is to investigate the root cause and prepare a detailed report for the team lead.

## Expected Workflow

### 1. Reproduce the Issue
- Open integrated terminal (Ctrl+\`)
- Run the test suite: `python test_pricing.py`
- Observe which tests fail and how

### 2. Add Debugging Instrumentation
- Open `utils/pricing.py`
- Add `print()` statements to trace:
  - Input values and their types
  - Intermediate calculations
  - Return values
- Run tests again to see debug output

### 3. Add Explanatory Comments
- Add comments explaining:
  - What the original code was trying to do
  - Why it fails for edge cases
  - What assumptions are violated
  - What's missing (validation, bounds checking, etc.)

### 4. Create Analysis Document
- Create a new file: `edge_case_analysis.md` in workspace root
- Document your findings with these sections:
  - **Problem Description**: What's happening?
  - **Observed Behaviors**: For each edge case, what did you observe?
  - **Root Cause Analysis**: WHY does it fail? (type issues, validation, bounds)
  - **Proposed Solutions**: How should it be fixed?

### 5. Save Everything
- Save all modified files (Ctrl+S or Ctrl+Shift+S for all)

## Verification Criteria

The verifier checks:
1. ✅ **Documentation file exists** (`edge_case_analysis.md`) with substantial content (>200 chars)
2. ✅ **Structured analysis** with sections for problem, observations, root cause, solutions
3. ✅ **Code comments added** to `pricing.py` (significant increase from original ~10 lines)
4. ✅ **Print statements added** to trace execution (at least 2-3 strategic locations)
5. ✅ **Technical understanding** shown through keywords (validation, type, bounds, coercion, etc.)
6. ✅ **Multiple edge cases discussed** (negative, excessive, string inputs, boundaries)
7. ✅ **Code remains syntactically valid** (no syntax errors introduced)

**Pass Threshold**: 70/100 points

## Edge Cases to Investigate

- **Negative discount** (`-10%`): Why does it produce a price higher than original?
- **Excessive discount** (`150%`): Why does it produce a negative price?
- **String inputs**: Why do they sometimes "work" instead of raising errors?
- **Zero edge cases**: Do they behave correctly?

## Files Provided

- `utils/pricing.py` - The buggy implementation
- `test_pricing.py` - Test suite demonstrating failures
- `README.md` - Task instructions and context

## Tips

- **Don't fix the bugs yet** - just investigate and document
- Use print statements strategically at decision points
- Test your hypotheses by running the test suite multiple times
- Think about what the code *assumes* vs. what inputs it *receives*
- Consider Python's type coercion behavior
- Document clearly - imagine explaining to a junior developer

## Example Investigation Approach
