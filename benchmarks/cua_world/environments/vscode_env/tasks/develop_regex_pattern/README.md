# Develop Regex Pattern Task

**Difficulty**: 🟡 Medium  
**Skills**: Regex development, pattern testing, text processing, documentation  
**Duration**: 480 seconds (8 minutes)  
**Steps**: ~50

## Objective

Develop and test a robust regex pattern that can parse log entries from an authentication service. The pattern must extract structured data (timestamp, log level, component, message) from semi-structured text logs.

## Scenario

You're working on a log aggregation pipeline for your company's authentication service. The service outputs logs in a semi-structured text format that needs to be parsed into structured data for analytics. Your task is to develop a robust regex pattern that can extract key information from these log lines, test it thoroughly against sample data, and document it for future maintainers.

## Expected Workflow

1. Open and analyze `sample_logs.txt` to understand the log format
2. Identify the pattern structure:
   - Timestamp: `[YYYY-MM-DD HH:MM:SS.mmm]`
   - Log level: `INFO`, `WARN`, `ERROR`, `DEBUG`
   - Component: `auth.login`, `auth.password`, etc.
   - Message: Text after the dash
3. Develop a regex pattern with 4 capturing groups
4. Test the pattern against all sample log lines
5. Save outputs to required files

## Required Output Files

1. **`pattern.txt`**: Your final regex pattern (single line)
2. **`test_results.txt`**: Evidence showing your pattern tested against sample logs
3. **`pattern_explanation.md`**: Documentation explaining the pattern

## Verification Criteria

- **Pattern validity** (20%): Regex compiles without errors
- **Correctness** (50%): Pattern correctly extracts data from all 8 sample logs
- **Testing evidence** (20%): Test results show validation was performed
- **Documentation** (10%): Pattern explanation is provided

**Pass Threshold**: 80%

## Sample Log Format
