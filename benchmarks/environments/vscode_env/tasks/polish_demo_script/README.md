# Polish Demo Script Task

**Difficulty**: 🟡 Medium  
**Skills**: Code quality, refactoring, documentation, Python best practices  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Prepare a working Python data processing script for a professional demo by cleaning up development artifacts, improving readability, and adding documentation—without breaking functionality.

## Scenario

You're preparing for a demo tomorrow morning. You have a working Python script (`data_processor.py`) that transforms customer order data, but it was written hastily during late-night debugging. The code works but is unprofessional with:
- Commented-out debug code
- Poor variable names (`df2`, `temp_x`, `data_final_v3`)
- Debug print statements everywhere
- Hard-coded magic numbers
- No documentation

Your task is to make this code presentable while maintaining functionality.

## Required Changes

1. **Remove all debug artifacts:**
   - Delete commented-out code lines
   - Remove all `print()` statements containing "DEBUG"

2. **Rename variables meaningfully:**
   - `df2` → descriptive name (e.g., `completed_orders`)
   - `temp_x` → descriptive name (e.g., `discounts`)
   - `data_final_v3` → descriptive name (e.g., `recent_orders`)

3. **Extract magic numbers to module-level constants:**
   - Create constants for: 0.15, 0.10, 0.05, 1000, 500, 100, 30
   - Use descriptive ALL_CAPS names (e.g., `TIER1_DISCOUNT_RATE`, `RECENT_DAYS_THRESHOLD`)

4. **Add documentation:**
   - Add function docstring with Args and Returns sections
   - Add inline comments explaining discount tier logic

5. **Verify the script still works correctly**

## Verification

Checks:
1. No commented-out code or DEBUG prints remain
2. All poor variable names replaced
3. At least 7 module-level constants defined, no magic numbers in function
4. Docstring and inline comments added
5. Script executes successfully

**Pass Threshold**: 100% (all 5 criteria must pass)