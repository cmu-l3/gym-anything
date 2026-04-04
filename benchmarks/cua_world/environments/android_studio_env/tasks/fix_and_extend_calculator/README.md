# Task: fix_and_extend_calculator

## Overview
The CalculatorApp has several bugs in edge case handling and needs feature enhancements. The agent must diagnose the bugs, fix them, and add requested features.

## Domain Context
Maintaining and extending an existing codebase — fixing bugs while adding features — is the most common professional software development workflow. This task tests the ability to understand existing code, diagnose issues, and make safe changes.

## Goal
1. Fix crash when pressing % with 0 or empty input
2. Fix crash when pressing +/- with empty input
3. Extend history display from 5 to 10 entries
4. Add memory indicator ("M" visible when memory is non-zero)
5. Project compiles

## Success Criteria
- onPercentPressed handles zero/empty input without crash
- onNegatePressed handles empty input without crash
- History shows last 10 entries (not 5)
- Memory indicator added to UI
- Project compiles
