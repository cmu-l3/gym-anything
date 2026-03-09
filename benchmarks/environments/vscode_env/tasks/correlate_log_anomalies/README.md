# Correlate Log Anomalies Task

**Difficulty**: 🟡 Medium  
**Skills**: Log analysis, multi-file search, pattern recognition, documentation  
**Duration**: 480 seconds  
**Steps**: ~100

## Objective

Investigate a performance incident by analyzing multiple log files and create a structured incident report documenting the root cause.

## Scenario

You are a backend engineer investigating a performance degradation incident. Yesterday, users reported that the checkout API was extremely slow (5-10 second response times instead of the usual 200-300ms) during the 14:00-15:00 time window.

## Expected Workflow

1. Open the log_analysis workspace in VSCode
2. Review the three log files in `/logs`:
   - `application.log` - Main application logs
   - `database.log` - Database query logs  
   - `requests.log` - HTTP request/response logs
3. Use Find in Files (Ctrl+Shift+F) to search for anomalies
4. Correlate events across the three log files around 14:23:XX timeframe
5. Use split editor view to compare logs side-by-side
6. Create incident report based on the template
7. Document findings with root cause, timeline, and evidence

## What Happened (Hidden Story)

The logs contain evidence that:
- A scheduled export job started at 14:23:15
- This exhausted the database connection pool
- API requests started timing out waiting for connections
- Response times spiked from ~250ms to 8000ms

## Verification

The verifier checks your incident report for:
1. ✅ File exists at correct location
2. ✅ Contains required sections (Root Cause, Timeline, Evidence)
3. ✅ Root cause mentions "connection pool"
4. ✅ Timeline has at least 3 timestamps
5. ✅ Evidence references at least 2 log files
6. ✅ Report is substantive (≥400 characters)

**Pass Threshold**: 80% (weighted score)