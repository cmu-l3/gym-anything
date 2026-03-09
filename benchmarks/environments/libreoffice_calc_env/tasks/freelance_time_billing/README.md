# Freelance Time Billing Task

**Difficulty**: 🟢 Easy-Medium
**Skills**: Time calculations, formula composition, subtotals, business logic
**Duration**: 180 seconds
**Steps**: ~15

## Objective

Process a partially-completed freelance timesheet by calculating missing durations from start/end times, computing billable amounts, creating client subtotals, and calculating a grand total. This simulates preparing an invoice from messy time-tracking data.

## Task Description

A freelance web developer has started entering their work hours into a spreadsheet but hasn't finished the calculations. The agent must:

1. Calculate missing **Durations** from Start Time and End Time (in decimal hours)
2. Calculate missing **Billable Amounts** from Duration × Hourly Rate
3. Create **Subtotals** for each of three clients (Acme Corp, TechStart Inc, LocalBiz LLC)
4. Calculate the **Grand Total** of all billable work
5. Ensure all calculations use formulas (not hardcoded values)

## Starting State

The spreadsheet contains:
- Headers: Date, Client, Project, Start Time, End Time, Duration (hrs), Rate ($/hr), Amount ($)
- 9 work entries across 3 clients
- Some entries have Start/End times but no Duration calculated
- Some entries have Duration but no Amount calculated
- Placeholder rows for subtotals and grand total (empty)

## Expected Calculations

### Duration Formula
For entries with Start/End times: