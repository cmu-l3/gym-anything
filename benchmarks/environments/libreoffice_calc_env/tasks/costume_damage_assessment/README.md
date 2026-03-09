# Community Theater Costume Damage Assessment Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-sheet navigation, conditional formulas, data reconciliation, priority triage  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Update a costume inventory spreadsheet by processing post-production damage reports, applying conditional logic to calculate repair urgency, and flagging items needing immediate attention before the next show. This simulates real-world inventory management where informal notes must be reconciled with structured databases under time pressure.

## Task Scenario

**Context**: It's Monday at Riverside Community Theater. "A Midsummer Night's Dream" closed yesterday, and rehearsals for "The Importance of Being Earnest" (Victorian period costumes) start Thursday. A handwritten damage log notes torn waistcoats, stained collars, missing buttons, and destroyed fairy wings.

You have one volunteer seamstress who can repair 3-4 items before Thursday. Your task:
1. Update master inventory with condition changes from damage reports
2. Calculate repair urgency (damage severity + costume type + production needs)
3. Flag top priority repairs
4. Identify costume gaps requiring rentals/purchases

## Starting State

- LibreOffice Calc opens with workbook containing two sheets:
  - **Master_Inventory**: 30+ costume items with ID, Type, Era, Size, Current_Condition, Last_Used
  - **Damage_Log**: 8 informal damage descriptions from the Midsummer production
- Most inventory items currently marked "Good" or "Excellent"
- Damage log uses informal language (e.g., "velvet jacket is toast")

## Required Actions

1. **Match damage reports to inventory**: Cross-reference informal descriptions to formal inventory entries
2. **Update conditions**: Change "Current_Condition" based on damage severity (use: Excellent, Good, Fair, Poor, Unusable)
3. **Create urgency formula**: Add "Repair_Urgency_Score" column with formula combining:
   - Damage severity: Poor=3pts, Fair=2pts, Good=1pt
   - Victorian/Edwardian era needed for Earnest: +2pts
   - High rental cost items: +1pt
4. **Flag priorities**: Add "Repair_Priority" column marking items with urgency ≥4 as "URGENT"
5. **Identify gaps**: Calculate shortage of usable Victorian/Edwardian costumes
6. **Sort by priority**: Order inventory by urgency score descending

## Success Criteria

1. ✅ **Conditions Updated**: At least 6 items have modified Current_Condition reflecting damage
2. ✅ **Urgency Formula Present**: Repair_Urgency_Score column exists with calculated values
3. ✅ **Logic Correct**: Spot-check shows urgency scores follow specified logic
4. ✅ **Priority Flags Applied**: URGENT flags or formatting applied to high-urgency items (2-6 items)
5. ✅ **Gap Analysis Complete**: Calculation showing Victorian/Edwardian costume shortage
6. ✅ **Sorted by Priority**: Inventory sorted with most urgent items at top

**Pass Threshold**: 60% (requires 4 out of 6 criteria)

## Skills Tested

- Multi-sheet workbook navigation
- Data reconciliation (matching informal to structured data)
- Conditional formula creation (IF, AND statements)
- Multi-criteria decision logic
- Text parsing and categorization
- Priority sorting and triage
- Gap analysis and inventory counting

## Tips

- Start by reading the Damage_Log sheet to understand what needs updating
- Use Find (Ctrl+F) to locate costume items by type or era
- IF formulas structure: `=IF(condition, value_if_true, value_if_false)`
- Multiple conditions: `=IF(AND(condition1, condition2), value, else_value)`
- Points can be added: `=(condition_points)+(era_points)+(cost_points)`
- Sort: Select data range → Data menu → Sort → Choose column
- COUNTIF can help with gap analysis: `=COUNTIF(range, criteria)`

## Expected Results Example

After completion, top rows might show:
- Victorian waistcoat (Poor condition, urgency=5) → URGENT
- Edwardian evening gown (Fair condition, urgency=4) → URGENT  
- Medieval tunic (Poor condition, urgency=3) → Medium
- Contemporary dress (Good condition, urgency=1) → Low

Summary should indicate: "Need 3 additional Victorian formal costumes"