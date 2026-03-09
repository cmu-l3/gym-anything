# VSCode Security Audit Task (`security_audit_scan@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Code analysis, security knowledge, regex search, documentation  
**Duration**: 300 seconds  
**Steps**: ~80

## Objective

Conduct a comprehensive security audit of a web application codebase before open-source release. Identify vulnerabilities across multiple categories, document findings in a structured report, and create a prioritized remediation plan.

## Scenario

You've been rapidly prototyping a personal web application (Express.js + React) and now want to open-source it. During development, you took shortcuts—hardcoded API keys, used quick string concatenation for SQL queries, and didn't sanitize user inputs. Before making the repository public, you must conduct a security audit.

## Expected Workflow

1. **Search for vulnerabilities** using VSCode's search (Ctrl+Shift+F):
   - Hardcoded secrets (API_KEY, SECRET, PASSWORD patterns)
   - Weak cryptography (MD5, SHA1 usage)
   - SQL injection (string concatenation in queries)
   - XSS vulnerabilities (innerHTML, dangerouslySetInnerHTML)
   - Command injection (eval, exec with user input)

2. **Create security audit report** (`SECURITY_AUDIT.md` in workspace root):
   - Document findings by category
   - Include file locations and line numbers
   - Assign severity levels (Critical/High/Medium/Low)
   - Minimum 8 specific vulnerabilities documented

3. **Create remediation plan** (`SECURITY_TODO.md` in workspace root):
   - Prioritized list of fixes
   - Severity classifications

## Verification

Checks for:
1. SECURITY_AUDIT.md exists in workspace root
2. Report contains "Hardcoded Credentials" section with 2+ findings
3. Report contains "Weak Cryptography" section with 1+ finding
4. Report contains "SQL Injection" section with 2+ findings
5. Report contains "XSS" section with 1+ finding
6. At least 8 total vulnerabilities documented
7. SECURITY_TODO.md exists
8. Findings include severity levels

**Pass Threshold**: 65% (5/8 criteria)