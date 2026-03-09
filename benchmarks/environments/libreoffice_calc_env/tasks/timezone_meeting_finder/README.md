# Global Team Meeting Scheduler Task

**Difficulty**: 🟡 Medium  
**Skills**: Time formulas, timezone conversion, conditional logic, data analysis  
**Duration**: 240 seconds (4 minutes)  
**Steps**: ~15

## Objective

Coordinate meeting times across multiple timezones by converting team member availability to UTC and identifying overlapping windows. This task simulates the real-world challenge of scheduling meetings for globally distributed teams.

## Task Description

You are coordinating a recurring 2-hour meeting for a global book club with 5 members in different timezones. Each member has submitted their weekly availability in their local time, and you need to find a time that works for everyone.

**Team Members:**
- **Alex** (New York, UTC-5): 9:00 AM - 5:00 PM local time
- **Priya** (London, UTC+0): 8:00 AM - 4:00 PM local time  
- **Kenji** (Tokyo, UTC+9): 10:00 AM - 6:00 PM local time
- **Sophie** (Sydney, UTC+11): 9:00 AM - 5:00 PM local time
- **Carlos** (Los Angeles, UTC-8): 10:00 AM - 6:00 PM local time

## Required Actions

1. **Convert local times to UTC**:
   - Create formulas in "UTC Start" and "UTC End" columns
   - Apply timezone offset to each person's local times
   - Handle time wraparound (e.g., Tokyo 10 AM → 1 AM UTC)

2. **Identify overlapping availability**:
   - Create analysis showing which UTC hours all members are available
   - Use conditional logic (AND/OR formulas) to check overlap
   - Find at least one 2-hour contiguous window

3. **Document the meeting time**:
   - Write the recommended UTC time range in a summary cell
   - Ensure the window accommodates all 5 participants

## Expected Results

- **UTC Conversion**: Formulas calculate correct UTC times for all team members
- **Overlap Analysis**: Logic identifies common available hours
- **Meeting Window**: Valid 2+ hour window documented (likely around 16:00-18:00 UTC or similar)

## Success Criteria

1. ✅ **UTC Conversions Present**: All 5 team members have Start/End UTC columns with formulas
2. ✅ **Conversion Accuracy**: At least 80% of conversions are mathematically correct (±15min tolerance)
3. ✅ **Overlap Logic Exists**: Formula checking availability across all participants detected
4. ✅ **Valid Window Identified**: At least one 2-hour contiguous block found

**Pass Threshold**: 70% (requires functional UTC conversion and overlap detection)

## Skills Tested

- Time/date formulas (TIME, HOUR, MOD functions)
- Timezone mathematics (offset calculations)
- Conditional logic (IF, AND, OR)
- Cell references (absolute and relative)
- Logical problem solving (constraint satisfaction)

## Tips

- Use `=MOD(LocalTime + (Offset/24), 1)` for UTC conversion with wraparound
- Remember: Negative offsets (NYC -5) mean adding 5 hours to get UTC
- Positive offsets (Tokyo +9) mean subtracting 9 hours to get UTC
- Use TIME() function to work with hours: `=TIME(9, 0, 0)` creates 9:00 AM
- AND() function checks multiple conditions: `=AND(A1>10, A1<20)`
- Format cells as Time for proper display (Format → Cells → Time)

## Real-World Context

This task mirrors the frustration of coordinating across timezones—a universal problem in remote work, international friendships, and global collaboration. One timezone math error can mean sending awkward "sorry, that time doesn't actually work" emails to the whole group.