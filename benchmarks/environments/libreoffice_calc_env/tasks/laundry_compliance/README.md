# Shared Laundry Compliance Monitor Task

**Difficulty**: 🟡 Medium  
**Skills**: Data aggregation, formulas, conditional formatting, sorting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze shared apartment laundry booking data to identify residents who repeatedly violate facility policies (no-shows, overtime usage, slot hogging). Create a compliance summary with calculated metrics, apply conditional formatting to highlight violators, and generate recommendations for property management action.

## Real-World Context

You are a property manager for a 50-unit apartment building with shared laundry facilities. The smart laundry booking system exported a month of data showing resident booking and actual usage patterns. Multiple neighbors have complained about:
- Residents booking slots but never showing up
- People running laundry 30+ minutes past their allotted time
- Same person booking 3+ consecutive time slots (monopolizing machines)

Your job: Identify the repeat offenders objectively so you can send fair warning notices.

## Starting State

- LibreOffice Calc opens with `laundry_bookings.ods` containing 30 days of raw booking data
- Columns: Date, TimeSlot, ResidentID, ResidentName, BookingStatus, ActualUse, MinutesUsed, SlotDuration
- ~70 booking records across 10 residents
- Data contains violations: no-shows, overtime, multi-slot days

## Task Description

The agent must:
1. Examine the raw booking data in the "Bookings" sheet
2. Create a new sheet named "Compliance Summary"
3. Calculate per-resident metrics:
   - Total bookings
   - Completed uses
   - No-shows (BookingStatus="Booked" AND ActualUse="No")
   - No-show rate (percentage)
   - Average minutes used
   - Overtime violations (MinutesUsed > 100, when slot is 90 min + 10 min grace)
   - Days with 3+ consecutive slots booked
4. Calculate a composite violation score: (NoShowRate * 0.5) + (OvertimeRate * 0.3) + (MultiSlotDays * 5)
5. Apply conditional formatting to highlight violators
6. Sort by violation score (descending)
7. Add recommendations ("Warning: Excessive no-shows", "Monitor: Frequent overtime", "Acceptable usage")
8. Save the file

## Expected Results

**Compliance Summary Sheet** should contain:
- Columns: ResidentName, TotalBookings, CompletedUses, NoShows, NoShowRate, AvgMinutesUsed, OvertimeViolations, MultiSlotDays, ViolationScore, Notes
- Correct aggregation formulas (COUNTIF, SUMIF, etc.)
- Calculated no-show rates as percentages
- Violation scores calculated from weighted formula
- Conditional formatting on violation columns
- Sorted by ViolationScore (highest violators first)
- Recommendation notes for each resident

## Example Expected Data

| ResidentName | TotalBookings | NoShows | NoShowRate | ViolationScore | Notes |
|--------------|---------------|---------|------------|----------------|-------|
| Bob Martinez | 10            | 4       | 40.0%      | 20.0           | Warning: Excessive no-shows |
| Alice Chen   | 8             | 2       | 25.0%      | 22.5           | Warning: Multiple violations |
| Dana Kim     | 6             | 0       | 0.0%       | 0.0            | Acceptable usage |

## Verification Criteria

1. ✅ **Summary Sheet Exists**: "Compliance Summary" sheet created (15 pts)
2. ✅ **Required Columns Present**: All key columns exist (10 pts)
3. ✅ **Aggregation Accurate**: TotalBookings correctly counted for test resident (20 pts)
4. ✅ **No-Show Rate Calculated**: Percentage formula works correctly (20 pts)
5. ✅ **Violation Score Present**: Composite score calculated (15 pts)
6. ✅ **Conditional Formatting Applied**: Violation columns highlighted (10 pts)
7. ✅ **Sorted by Severity**: Highest violation score at top (10 pts)

**Pass Threshold**: 70% (requires correct calculations and basic formatting)

## Skills Tested

- Multi-sheet workbook navigation
- COUNTIF/SUMIF aggregation formulas
- Percentage calculations
- Nested IF statements
- Conditional formatting rules
- Data sorting
- Policy translation into metrics
- Real-world data analysis

## Tips

- Use COUNTIF to count bookings per resident: `=COUNTIF(Bookings.D:D, A2)`
- No-show rate: `=(NoShows / TotalBookings) * 100`
- Use AVERAGEIF for average minutes by resident
- Apply conditional formatting: Format → Conditional → Condition
- Sort by column: Data → Sort → Select ViolationScore column
- Test your formulas on one resident first, then copy down

## Building Policy

Apartment policy states:
- **No-show threshold**: >25% no-show rate triggers warning
- **Overtime threshold**: >3 overtime violations in a month
- **Slot hogging**: Booking 3+ consecutive slots on the same day more than twice
- **Violation score >15**: Requires management review

## Realistic Complications

- Some residents cancelled legitimately (BookingStatus="Cancelled") - these are NOT no-shows
- ActualUse can be "Yes", "No", or "Partial" (partial counts as completed use)
- Some MinutesUsed values may be missing for no-shows
- Resident names appear multiple times in raw data (need aggregation)