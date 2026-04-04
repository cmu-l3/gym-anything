# Investigate Customer Bug Task

**Difficulty**: 🟡 Medium  
**Skills**: Bug investigation, code analysis, documentation, problem-solving  
**Duration**: 480 seconds (8 minutes)  
**Steps**: ~100

## Objective

Investigate a customer-reported bug where date-range exports show incorrect revenue totals. Reproduce the issue, identify the root cause in the codebase, and document your findings with a clear comment for the engineering team.

## Scenario

Customer "TechCorp Inc" reports that when they export Q1 2024 sales data (January 1 - March 31), the total shown is $45,230, but their accounting system shows $52,150. You need to find why the export is missing transactions.

## Expected Workflow

1. **Read support ticket** (`support_ticket_2847.txt`) - understand the issue
2. **Examine sample data** (`customer_data_sample.csv`) - see what data looks like
3. **Navigate codebase** - use Ctrl+Shift+F (Find in Files) or explore `src/` directory
4. **Identify bug location** - find date filtering logic in `src/date_utils.py`
5. **Analyze the bug** - spot the off-by-one error in date comparison
6. **Document findings** - add TODO/FIXME comment explaining the root cause

## Bug Description

The bug is in `src/date_utils.py` in the `filter_by_date_range` function. The comparison uses `<` instead of `<=` for the end date, making it exclusive instead of inclusive. This causes transactions on the last day of the range (e.g., March 31) to be excluded.

## Verification

Checks for:
1. ✅ Correct file modified (`src/date_utils.py`)
2. ✅ Comment added near buggy line (within ±5 lines of the comparison)
3. ✅ Comment has marker (TODO, FIXME, BUG, or XXX)
4. ✅ Comment mentions it's a bug/error/problem
5. ✅ Comment explains technical issue (end date exclusivity, off-by-one)
6. ✅ Comment describes impact (missing transactions, wrong totals)

**Pass Threshold**: 85% (3.4/4 criteria with partial credit)

## Real-World Relevance

This task mirrors actual developer workflows:
- 📧 Customer escalations from support teams
- 🐛 Vague bug reports from non-technical users  
- 🔍 Code archaeology in unfamiliar parts of codebase
- 📝 Documentation before fixing to share knowledge
- ⏰ Time pressure of production issues