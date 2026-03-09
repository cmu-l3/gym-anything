# Eclipse IDE Environment - Evidence Documentation

## Environment Status: Fully Functional (Updated after audit fixes)

### What Works
1. **Eclipse IDE Installation** - Successfully installed from eclipse.org (eclipse-java-2024-12)
2. **Java 17 (OpenJDK)** - Installed and configured as default
3. **Maven 3.6.3** - Installed and functional
4. **Desktop Environment** - GNOME desktop with proper display
5. **VNC/SSH Access** - Environment is accessible
6. **Project Import** - Projects are automatically imported during task setup
7. **Build System** - Maven builds work correctly
8. **Verification** - Export script and verifier work correctly

### Audit Issues Fixed (2026-02-01)

#### Audit #1 Fixes

| Issue | Severity | Fix Applied |
|-------|----------|-------------|
| Task start state mismatch (projects not imported) | CRITICAL | Task descriptions now explicitly require agents to import projects as the first step. This is intentional - importing a project is part of the task. |
| Adversarial vulnerability in create_maven_project | CRITICAL | Sample data (gs-maven, gs-maven-broken) is deleted during setup_task.sh to prevent copying |
| Ambiguous run_and_debug description | MEDIUM | Now specifies exact line number (line 10) for breakpoint |
| XML namespace bugs in verifiers | LOW | Fixed to use full namespace prefix `{http://maven.apache.org/POM/4.0.0}` for element lookup |

#### Audit #2 Fixes

| Issue | Severity | Fix Applied |
|-------|----------|-------------|
| Export scripts still run `mvn compile` | CRITICAL | Removed `mvn compile` from create_maven_project/export_result.sh and refactor_rename_class/export_result.sh. Verifiers now only check existing class files produced by agent's actions. |
| Exception type mismatch in add_junit_tests | CRITICAL | Fixed task description: divide() throws `ArithmeticException` (not IllegalArgumentException). Also updated to mention all Calculator methods (add, subtract, multiply, divide, power, factorial). |
| Hardcoded paths in create_maven_project | HIGH | Task description now explicitly specifies the expected package and class structure: `src/main/java/hello/HelloWorld.java` and `src/main/java/hello/Greeter.java` |
| VLM-dependent verification in run_and_debug | MEDIUM | Verifier initially used 60% file-based evidence and 40% VLM. (Further improved in Audit #4 to 70%/30%) |

#### Audit #3 Fixes

| Issue | Severity | Fix Applied |
|-------|----------|-------------|
| Pre-compilation in run_and_debug task | CRITICAL | Removed `mvn compile` from run_and_debug/setup_task.sh. Agent must now trigger the build themselves through Eclipse. |
| Export script runs tests in add_junit_tests | HIGH | Removed `mvn test` from add_junit_tests/export_result.sh. Export script now only collects evidence from existing surefire reports (if agent ran tests). |
| Verifier accepts loose matches in add_junit_tests | HIGH | Tightened regex patterns to require actual method calls (e.g., `calc.add(...)`) rather than just substring matches like `'add(' in content`. |
| Test class name not specified | MEDIUM | Updated add_junit_tests task description to explicitly require `CalculatorTest.java` at `src/test/java/com/example/calculator/`. |
| Hints in source code comments | MEDIUM | Removed hint comments from: gs-maven-broken/pom.xml (removed "Missing joda-time" comment), OldClassName.java and Main.java (replaced hint Javadocs with neutral descriptions). |
| Ambiguous breakpoint line specification | MEDIUM | Updated run_and_debug description to reference the code content ("the line containing 'System.out.println(greeter.sayHello())'") rather than just line number. Also added explicit build step. |

#### Audit #4 Fixes

| Issue | Severity | Fix Applied |
|-------|----------|-------------|
| run_and_debug VLM dependency (40%) | HIGH | Rebalanced verification weights: now 70% file-based (25+25+10+10) and 30% VLM. File-based evidence alone can now yield 70 points, exceeding pass threshold. |
| Potential race condition in create_maven_project | MEDIUM | Added anti-cheating check in verifier to detect if sample data wasn't properly deleted. Setup script already deletes at start. |
| add_junit_tests regex permissiveness | LOW | Removed `re.DOTALL` flag and tightened patterns to require explicit method signatures or method calls with arguments. |

#### Audit #5 Fixes

| Issue | Severity | Fix Applied |
|-------|----------|-------------|
| Empty test methods could pass | HIGH | Verifier now checks for actual assertions (`assert*()` calls) and Calculator instance creation. Empty test methods only get partial credit (5 pts vs 10 pts), and only if assertions exist elsewhere in the file. |
| Sample data not deleted in fix_build_errors | LOW | Added anti-cheating measure to delete `/workspace/data/gs-maven` during setup, preventing agents from copying the working project instead of fixing the broken one. |

### Task Description Pattern

All tasks now follow this pattern:
1. **State where files are located** (e.g., "Project files are at ~/eclipse-workspace/...")
2. **First step is always "Import the Maven project"** - this is part of the task
3. **Subsequent steps describe the actual work**
4. **Clear success criteria**

This approach:
- Accurately describes the initial state (empty Eclipse workspace with files in filesystem)
- Tests the agent's ability to perform IDE operations from scratch
- Avoids fragile GUI automation in setup scripts

### Interactive Testing Evidence

#### Task: fix_build_errors
**Objective:** Add missing joda-time dependency to pom.xml and fix build errors.

#### Screenshots

1. **01_eclipse_started.png** - Eclipse IDE launched with empty workspace
   - Package Explorer visible on left
   - Main editor area in center
   - Problems/Javadoc tabs at bottom

2. **02_import_maven_project.png** - Import dialog with "Existing Maven Projects" selected

3. **03_project_found.png** - Maven project found at workspace location
   - Root Directory: `/home/ga/eclipse-workspace/gs-maven-broken`
   - Project detected: `org.springframework:gs-maven-broken:0.1.0.jar`

4. **04_project_imported_with_errors.png** - Project imported showing 3 build errors
   - Errors due to missing joda-time dependency
   - `org.joda.time.LocalTime` cannot be resolved

5. **05_pom_editor_open.png** - pom.xml file open in editor

6. **06_final_state.png** - Final state after fix applied

### Fix Applied

The joda-time dependency was added to pom.xml:
```xml
<dependency>
    <groupId>joda-time</groupId>
    <artifactId>joda-time</artifactId>
    <version>2.12.5</version>
</dependency>
```

### Build Verification

Maven build completed successfully:
```
[INFO] BUILD SUCCESS
[INFO] Compiling 2 source files to /home/ga/eclipse-workspace/gs-maven-broken/target/classes
```

Compiled class files verified:
```
/home/ga/eclipse-workspace/gs-maven-broken/target/classes/hello/
├── Greeter.class (369 bytes)
└── HelloWorld.class (1322 bytes)
```

### Export Script Output
```json
{
    "pom_exists": true,
    "has_jodatime_dependency": true,
    "build_success": true,
    "pom_content": "... (pom.xml with joda-time dependency) ...",
    "timestamp": "2026-02-02T03:02:11+00:00"
}
```

### Verification Result
```
Passed: True
Score: 100
Feedback: pom.xml exists | joda-time dependency added (version 2.12.5) | Build successful (HelloWorld.class verified)
```

### Installation Log (pre_start hook)
```
=== Installing Eclipse IDE ===
Downloading Eclipse IDE...
Extracting Eclipse IDE...
Eclipse IDE installed at /opt/eclipse
openjdk version "17.0.x"
Apache Maven 3.6.3
Pre-warming Maven local repository...
=== Eclipse IDE installation complete ===
```

### Setup Log (post_start hook)
```
=== Setting up Eclipse IDE ===
Launching Eclipse IDE...
Waiting for Eclipse IDE to start...
Eclipse window detected after 5s
Eclipse window maximized
=== Eclipse IDE setup complete ===
```

### Known Issues and Solutions

1. **Menu Click Registration** - During testing, direct menu clicks via xdotool sometimes didn't register properly.
   - **Solution:** Use keyboard shortcuts (Alt+F for File menu, Ctrl+Shift+R for Open Resource, etc.)

2. **Project Import** - Projects in workspace folder need to be explicitly imported.
   - **Solution:** setup_task.sh creates Eclipse metadata files (.project, .classpath, .settings/)

3. **Eclipse Errors Stale** - Eclipse's Problems view may show stale errors even after Maven build succeeds.
   - **Solution:** Run Project > Clean or Maven > Update Project to refresh Eclipse's view

### Verification Criteria Met

| Criterion | Points | Status |
|-----------|--------|--------|
| pom.xml exists | 10 | PASS |
| joda-time dependency added | 40 | PASS |
| Build successful (HelloWorld.class verified) | 50 | PASS |
| **Total** | **100** | **PASS** |

### Files Created

- `benchmarks/environments/eclipse_env/env.json` - Environment configuration
- `benchmarks/environments/eclipse_env/scripts/install_eclipse.sh` - Installation script
- `benchmarks/environments/eclipse_env/scripts/setup_eclipse.sh` - Setup script
- `benchmarks/environments/eclipse_env/scripts/task_utils.sh` - Shared utilities
- `benchmarks/environments/eclipse_env/tasks/fix_build_errors/` - Complete task with verifier
- `benchmarks/environments/eclipse_env/data/gs-maven-broken/` - Test project with missing dependency
- `benchmarks/environments/eclipse_env/utils/eclipse_verification_utils.py` - VLM verification utilities

---

## New Hard/Very Hard Tasks (Added 2026-02-28)

Five new production-grade tasks were created to replace the original simple starter tasks. These target senior software engineers working on realistic professional scenarios.

### Task Design Principles Applied

- **Real professional workflows** from diverse industries (security, architecture, HR, quality engineering)
- **Discovery required** — agents must identify what's broken/missing before fixing it
- **Multi-file edits** — no single-file solutions; changes must be coherent across the codebase
- **Build verification** — all tasks require `mvn clean test` to pass after changes
- **Anti-gaming guards** — build points gated on actual changes, initial baselines recorded at setup

### New Tasks Summary

| Task | Occupation | Industry | Difficulty | Pass Threshold |
|------|-----------|----------|------------|----------------|
| `security_vulnerability_remediation` | Security Engineer | Financial Services / API | Very Hard | 70/100 |
| `multi_module_project_refactor` | Software Architect | E-Commerce | Hard | 65/100 |
| `concurrent_inventory_bugfix` | Senior Backend Engineer | Retail / Logistics | Very Hard | 65/100 |
| `java8_to_java17_migration` | Platform Engineer | HR / Enterprise | Hard | 65/100 |
| `jacoco_coverage_enforcement` | Quality Engineer | FinTech | Hard | 70/100 |

### Task 1: security_vulnerability_remediation

**Data Project:** `benchmarks/environments/eclipse_env/data/secure-api/`

A REST API backend with three intentional security vulnerabilities embedded in the source:
- SQL injection via `Statement` + string concatenation in `UserRepository` (3 vulnerable methods)
- Hardcoded database password `"Sup3rS3cr3tP@ssw0rd"` in `DatabaseConfig`
- Path traversal in `FileService` (no canonical path validation)

**Scoring (100 pts, pass ≥ 70):**
- Security audit report created: 10 pts
- SQL injection fixed (PreparedStatement + setString, no concatenation): 25 pts
- Hardcoded credentials removed (System.getenv, no literal password): 20 pts
- Path traversal fixed (getCanonicalPath + base dir check): 20 pts
- Security regression test added: 15 pts
- Build passes (only if fixes applied): 10 pts

**Anti-gaming:** Build credit requires at least one security fix applied first (prevents do-nothing build score).

**Do-nothing test result:** score=0, passed=False ✓

---

### Task 2: multi_module_project_refactor

**Data Project:** `benchmarks/environments/eclipse_env/data/ecommerce-monolith/`

A single-module Maven e-commerce application that must be split into a proper multi-module Maven project with separate modules for `core` (models), `repository`, and `service`, connected via a parent POM and cross-module dependencies.

**Scoring (100 pts, pass ≥ 65):**
- Parent POM with modules declared: 20 pts
- Module structure created (≥3 modules): 20 pts
- Cross-module dependencies declared: 20 pts
- Source files moved to correct modules: 15 pts
- Build compiles successfully: 15 pts
- Tests pass: 10 pts

**Do-nothing test result:** score=0, passed=False ✓

---

### Task 3: concurrent_inventory_bugfix

**Data Project:** `benchmarks/environments/eclipse_env/data/inventory-service/`

A thread-unsafe inventory service with four concurrent bugs: plain `int` counters without synchronization, raw `HashMap` for shared state, check-then-act race conditions in `InventoryManager`, and unsynchronized `ReservationService`.

**Scoring (100 pts, pass ≥ 65):**
- AtomicInteger/locks used for counters: 20 pts
- ConcurrentHashMap used for shared maps: 20 pts
- Atomic check-and-update for reservations: 20 pts
- Concurrent test added: 20 pts
- Build passes: 20 pts

**Gate:** If no `java.util.concurrent` usage detected → score=0 immediately.

**Do-nothing test result:** score=0, passed=False ✓

---

### Task 4: java8_to_java17_migration

**Data Project:** `benchmarks/environments/eclipse_env/data/legacy-hr-system/`

A legacy HR system written in Java 8 style with `java.util.Date/Calendar`, raw types (unparameterized `List`, `Map`), and `StringBuffer`. The agent must migrate to Java 17 idioms: `java.time` API, proper generics, `StringBuilder`, and update `pom.xml` target to Java 17.

**Scoring (100 pts, pass ≥ 65):**
- Date/Calendar removed (25 pts, partial at 12 pts if ≥50% removed)
- java.time API used (20 pts): LocalDate ≥3 (+10), Period (+5), DateTimeFormatter (+5)
- Raw types replaced with generics (20 pts, partial at 10 pts)
- StringBuffer → StringBuilder (15 pts, partial at 7 pts)
- pom.xml targets Java 17 (10 pts)
- Build passes (only if migration applied, 10 pts)

**Bugs fixed during testing:**
- `export_result.sh`: `grep -c pattern file || echo "0"` produced malformed JSON `0\n0` → replaced with `grep -q ... && POM_SOURCE_17=1` pattern
- Source file Javadoc comments contained exact grep keywords (`LocalDate.now()`, `Map<Integer`, `List<Employee`) causing 30 pts false positive in do-nothing state → Neutralized comments to remove exact solution API names

**Do-nothing test result:** score=0, passed=False ✓

---

### Task 5: jacoco_coverage_enforcement

**Data Project:** `benchmarks/environments/eclipse_env/data/transaction-service/`

A financial transaction service with no tests and no JaCoCo coverage configuration. The agent must write comprehensive unit tests using JUnit 5 + Mockito, configure the JaCoCo Maven plugin, and achieve ≥70% line coverage.

**Scoring (100 pts, pass ≥ 70):**
- JaCoCo plugin declared in pom.xml (15 pts, partial at 7 pts)
- ≥3 new test files created (15 pts, tiered partial)
- Mockito usage (20 pts, tiered partial)
- JaCoCo HTML report generated after build (20 pts)
- Line coverage ≥70% (30 pts, partial at 15 pts if within 15%)

**Bug fixed during testing:**
- `export_result.sh`: `grep -c "jacoco" pom.xml || echo "0"` produced malformed JSON → removed the `|| echo "0"` suffix (grep -c outputs "0" cleanly; `[ -z ]` guard added for missing file case)

**Do-nothing test result:** score=0, passed=False ✓

---

### Phase 4 Do-Nothing Test Results

All 5 tasks confirmed score=0, passed=False via live VM testing:

| Task | Score | Passed | Status |
|------|-------|--------|--------|
| security_vulnerability_remediation | 0 | False | PASS ✓ |
| multi_module_project_refactor | 0 | False | PASS ✓ |
| concurrent_inventory_bugfix | 0 | False | PASS ✓ |
| java8_to_java17_migration | 0 | False | PASS ✓ |
| jacoco_coverage_enforcement | 0 | False | PASS ✓ |

Evidence JSON files:
- `security_vulnerability_remediation_evidence.json`
- `multi_module_project_refactor_evidence.json`
- `concurrent_inventory_bugfix_evidence.json`
- `java8_to_java17_migration_evidence.json`
- `jacoco_coverage_enforcement_evidence.json`
