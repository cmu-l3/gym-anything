# Medication Schedule Update Task

**Difficulty**: 🟡 Medium  
**Skills**: Time arithmetic, formulas, conditional formatting, data updates  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~20

## Objective

Update a medication tracking spreadsheet by changing dosing frequencies, updating last dose times, calculating when next doses are due using formulas, and applying conditional formatting to highlight medications that need attention soon. This represents a critical real-world caregiving scenario where accurate medication timing is essential.

## Task Description

You are helping a caregiver manage their parent's medication schedule. The spreadsheet tracks 5 medications with different dosing frequencies. You need to:

1. **Update frequency:** Change Metformin's dosing frequency from 12 hours to 8 hours (doctor's orders)
2. **Update last dose:** Record that Aspirin was just taken at 8:00 AM this morning
3. **Calculate next doses:** Add formulas to calculate when each medication's next dose is due
4. **Visual highlighting:** Apply conditional formatting to highlight medications due within the next 2 hours in yellow

## Starting State

- Spreadsheet opens with medication data pre-filled
- Columns: Medication Name (A), Dosage (B), Frequency (hours) (C), Last Dose Time (D), Next Dose (E)
- "Next Dose" column is empty and needs formulas
- Current medications: Lisinopril, Metformin, Atorvastatin, Aspirin, Gabapentin

## Required Actions

1. **Update Metformin frequency:**
   - Locate Metformin in the medication list
   - Change its "Frequency (hours)" from 12 to 8

2. **Update Aspirin last dose:**
   - Find Aspirin in the list
   - Update "Last Dose Time" to 8:00 AM today

3. **Create Next Dose formulas:**
   - Click on cell E2 (first Next Dose cell)
   - Enter formula: `=D2+(C2/24)` 
     - D2 is Last Dose Time
     - C2 is Frequency in hours
     - Divide by 24 because Calc stores time as fractional days
   - Copy formula down to all medication rows (E2:E6)

4. **Apply conditional formatting:**
   - Select the Next Dose column range (E2:E6)
   - Go to Format → Conditional → Condition (or Format → Conditional Formatting)
   - Create rule: If Next Dose is within 2 hours from now, highlight yellow
   - Formula approach: `E2<(NOW()+(2/24))` or use built-in condition builder
   - Apply formatting

5. **Verify and save:**
   - Check that all Next Dose cells show calculated times
   - Verify medications due soon are highlighted
   - Save the file (Ctrl+S)

## Expected Results

- **Metformin frequency:** 8 hours (changed from 12)
- **Aspirin last dose:** 8:00 AM today
- **Next Dose column:** Contains formulas in all rows (E2:E6)
- **Formula structure:** Each cell adds frequency to last dose time
- **Conditional formatting:** Applied to Next Dose column, highlights urgent medications
- **No errors:** No #VALUE!, #REF!, or other formula errors

## Formula Tips

**Time arithmetic in Calc:**
- Times are stored as fractional days (0.5 = 12 hours, 1 = 24 hours)
- To add 8 hours: `=D2+(8/24)` or `=D2+8/24`
- To add variable hours from cell C2: `=D2+(C2/24)`

**Conditional formatting for urgency:**
- Condition: Cell value < NOW() + 2 hours
- Formula: `E2<NOW()+(2/24)`
- Or use built-in: "Cell value is less than" with formula `=NOW()+(2/24)`

## Verification Criteria

1. ✅ **Formulas Present**: Next Dose column contains formulas (not static values)
2. ✅ **Calculations Correct**: At least 80% of next dose times are mathematically accurate
3. ✅ **Frequency Updated**: Metformin shows 8 hours frequency
4. ✅ **Last Dose Updated**: Aspirin shows 8:00 AM timestamp for today
5. ✅ **Conditional Formatting**: Formatting rules applied to Next Dose column
6. ✅ **No Errors**: No formula errors present

**Pass Threshold**: 70% (requires functional formulas, data updates, and attempted formatting)

## Skills Tested

- Time/date arithmetic in spreadsheets
- Formula creation with cell references
- Copying formulas across rows
- Data updates and editing
- Conditional formatting navigation
- Rule-based visual highlighting
- Understanding fractional day time representation

## Real-World Context

This task simulates a common caregiving scenario where medication schedules must be managed precisely. Missing or delayed medications can have serious health consequences, so having an automated, visual system that highlights upcoming doses is critical. The spreadsheet approach is widely used by caregivers who can't afford specialized medication management software.

## Common Pitfalls

- Forgetting to divide frequency by 24 (will result in adding days instead of hours)
- Using static values instead of formulas (won't update automatically)
- Not copying formulas to all rows
- Conditional formatting rule using wrong comparison or time calculation
- Not using NOW() function for current time reference