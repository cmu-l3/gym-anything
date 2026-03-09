# Jenkins Script Console System Audit (`script_console_audit@1`)

## Overview

This task evaluates the agent's ability to use the Jenkins Script Console — a powerful Groovy execution environment built into Jenkins — to perform a system audit. The agent must navigate to the Script Console, write and execute a Groovy script that collects system information, installed plugins, and configured jobs, then write the results to a file inside the Jenkins server.

## Rationale

**Why this task is valuable:**
- Tests knowledge of Jenkins administrative tooling beyond job creation
- Requires writing functional Groovy code that interacts with the Jenkins API
- Evaluates navigation through the "Manage Jenkins" administrative interface
- Exercises a real operational workflow used for compliance and troubleshooting
- Combines UI navigation, code authoring, and system introspection skills

**Real-world Context:** A Software Quality Assurance Analyst at a mid-sized company has been asked to perform a quarterly compliance audit of the Jenkins CI/CD instance. The security team needs a machine-readable report of the Jenkins version, all installed plugins (with versions), and a complete inventory of configured jobs. The Script Console is the fastest way to gather this information programmatically without installing additional plugins.

## Task Description

**Goal:** Use the Jenkins Script Console to execute a Groovy script that generates a system audit report and saves it to `/var/jenkins_home/audit_report.txt` inside the Jenkins server.

**Starting State:** Jenkins is running with several pre-configured CI/CD jobs. Firefox is open and showing the Jenkins dashboard. The agent is not logged in.

**Login Credentials:**
- Username: `admin`
- Password: `Admin123!`

**The audit report file (`/var/jenkins_home/audit_report.txt`) must contain ALL of the following sections:**

1. **Jenkins Version** — The exact Jenkins server version string (e.g., `Jenkins Version: 2.xxx.x`)
2. **JVM Information** — The Java version the server is running on
3. **Installed Plugins** — A listing of ALL installed plugins, each with its short name and version number (e.g., `git:5.2.1`)
4. **Configured Jobs** — A listing of ALL jobs/items configured in Jenkins, including each job's name

The report must be written by the Groovy script to the file path `/var/jenkins_home/audit_report.txt` on the Jenkins server. The script should also print the report content to the Script Console output for visual confirmation.

**Expected Actions:**
1. Log into Jenkins with the provided credentials
2. Navigate to **Manage Jenkins** → **Script Console**
3. Write a Groovy script that collects the required audit information using the Jenkins internal API
4. Execute the script in the Script Console
5. Verify the output appears correctly in the console result area

**Final State:** The file `/var/jenkins_home/audit_report.txt` exists inside the Jenkins container and contains all four required sections with accurate data.

## Verification Strategy

### Primary Verification: File Content Analysis

The export script retrieves the audit report file from inside the Jenkins Docker container and analyzes its content against known ground truth:

1. **File Existence**: Confirm `/var/jenkins_home/audit_report.txt` exists and is non-empty
2. **Jenkins Version Match**: Extract version from the file and cross-check against actual server version
3. **JVM Information Present**: Verify the file contains a Java version string
4. **Plugin Coverage**: Compare plugins listed in the file against the full installed plugin list
5. **Job Coverage**: Verify that all pre-existing jobs appear in the report
6. **Timestamp Check**: Confirm the file was created/modified after the task start time

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| File Exists & Non-empty | 10 | `/var/jenkins_home/audit_report.txt` exists with content |
| Jenkins Version Present | 15 | File contains the correct Jenkins version string |
| JVM Info Present | 10 | File contains Java/JVM version information |
| Plugin Listing Present | 20 | File contains plugin entries with name:version format |
| Plugin Coverage ≥ 80% | 15 | At least 80% of installed plugins are listed |
| Plugin Versions Accurate | 10 | Sampled plugin versions match actual installed versions |
| All Jobs Listed | 15 | All 3 setup jobs appear in the job inventory section |
| File Substantive (>20 lines) | 5 | Report is substantive, not a stub |
| **Total** | **100** | |

Pass Threshold: 70 points