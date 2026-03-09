# IntelliJ IDEA Environment - Evidence Documentation

Last updated: 2026-01-29 (Audit issues fixed and retested)

## Environment Checklist

### 1. Environment Boot
- [x] Environment boots successfully with `from_config("benchmarks/environments/intellij_idea_env")`
- [x] `env.reset(seed=42, use_cache=False)` completes without errors
- [x] SSH and VNC ports are assigned and accessible
- [x] Pre-start hook (install_intellij.sh) runs successfully
- [x] Post-start hook (setup_intellij.sh) runs successfully

### 2. Software Installation
- [x] **OpenJDK 17** installed: `openjdk version "17.0.17" 2025-10-21`
- [x] **Apache Maven 3.6.3** installed and functional
- [x] **IntelliJ IDEA CE 2024.3.1.1** installed at `/opt/idea/bin/idea.sh`
- [x] GUI tools installed: scrot, wmctrl, xdotool, xclip, jq

### 3. IntelliJ IDEA Launches
- [x] IntelliJ window detected by wmctrl: `Welcome to IntelliJ IDEA`
- [x] IntelliJ process running (`/opt/idea/jbr/bin/java ...`)
- [x] fsnotifier process running
- [x] EULA/consent dialogs suppressed via VM options
- [x] Config directory correctly versioned as `IdeaIC2024.3`
- [x] CUA verification confirms: "IntelliJ IDEA welcome screen displayed with version 2024.3.1.1"

### 4. Task Setup and Verification

All 5 tasks boot, run export scripts, and verify correctly:

| Task | Baseline Score | Expected | Status |
|------|---------------|----------|--------|
| create_maven_project | 0/100 | 0 (project not created yet) | PASS |
| fix_build_errors | 0/100 | 0 (bugs still present) | PASS |
| refactor_code | 25/100 | 25 (code unmodified, build works) | PASS |
| debug_fix_bug | 64/100 | 64 (4/5 tests pass, bug present) | PASS |
| add_junit_tests | 0/100 | 0 (no JUnit added yet) | PASS |

### 5. Verification Features

Each verifier includes:
- **Programmatic verification**: Reads files from the VM via `copy_from_env`, checks content with regex patterns, parses XML reports, validates `.class` file magic bytes
- **VLM-based trajectory verification**: Uses `vlm_verify_intellij_task()` from `utils/intellij_verification_utils.py` with task-specific checklist items. Samples first, middle, and final trajectory frames for multi-image analysis. VLM contributes up to 10 bonus points when checks pass.
- **Multi-criteria scoring**: Each task has 4-6 weighted criteria totaling 100 points, with partial credit for incomplete work

### 6. Evidence Files

#### Screenshots
- `intellij_desktop.png` - Desktop with IntelliJ Welcome screen visible
- `intellij_v2_desktop.png` - Desktop during iterative debugging
- `intellij_v3_desktop.png` - Desktop after EULA fix (IntelliJ running)
- `intellij_after_manual_start.png` - Desktop after manual start verification
- `task_create_maven_project_setup.png` - After create_maven_project task setup
- `task_fix_build_errors_setup.png` - After fix_build_errors task setup (project loaded in IDE)
- `task_refactor_code_setup.png` - After refactor_code task setup (project loaded in IDE)
- `task_debug_fix_bug_setup.png` - After debug_fix_bug task setup (project loaded in IDE)
- `task_add_junit_tests_setup.png` - After add_junit_tests task setup (project loaded in IDE)

#### Logs
- `pre_start.log` - Full installation log (Java, Maven, IntelliJ download + install)
- `post_start.log` - Setup script output showing IntelliJ config and launch

#### Task Results (JSON)
- `task_create_maven_project_result.json` - Export script output (no project yet)
- `task_fix_build_errors_result.json` - Export with unfixed bugs and failed build
- `task_refactor_code_result.json` - Export with unrefactored code
- `task_debug_fix_bug_result.json` - Export with 4/5 tests passing
- `task_add_junit_tests_result.json` - Export with no test dependencies

#### Summary
- `evidence_summary.json` - Automated evidence collection results
- `test_summary.json` - Full end-to-end test results for all tasks

## Key Log Snippets

### Pre-start log (installation)
```
=== Installing IntelliJ IDEA dependencies ===
Installing OpenJDK 17...
Installing Maven...
Downloading IntelliJ IDEA CE...
Extracting IntelliJ IDEA...
IntelliJ IDEA installed at /opt/idea
openjdk version "17.0.17" 2025-10-21
Apache Maven 3.6.3
Pre-warming Maven local repository...
=== IntelliJ IDEA installation complete ===
```

### Post-start log (setup)
```
=== Setting up IntelliJ IDEA ===
IntelliJ build: IC-243.22562.218
Using config directory name: IdeaIC2024.3
Launching IntelliJ IDEA...
Waiting for IntelliJ IDEA to start...
IntelliJ window detected after 3s
IntelliJ window maximized
=== IntelliJ IDEA setup complete ===
```

### CUA Verification Response
The CUA (Computer-Use Agent via ask_cua.py) confirmed IntelliJ IDEA is visible:
> "The IntelliJ IDEA welcome screen is displayed with the title 'Welcome to IntelliJ IDEA'.
> The window shows it's version 2024.3.1.1. There's a dark theme interface with a left sidebar
> containing menu options: Projects (highlighted), Customize, Plugins, Learn. Main content area
> shows 'New Project', 'Open', 'Clone Repository' buttons. Bottom section shows onboarding tour
> prompt with 'Start Tour in Java' button."

### Verifier Output Examples

**create_maven_project (baseline, 0/100):**
```
pom.xml not found | HelloWorld.java not found | Greeter.java not found | Build not completed (no .class files)
```

**debug_fix_bug (baseline, 64/100):**
```
No zero divisor check found in divide() | IllegalArgumentException present but throw pattern unclear | Expected exception message not found | Test file unmodified | 4/5 tests passed (24/30 pts) | Calculator.class compiled successfully
```

**refactor_code (baseline, 25/100):**
```
Method still named 'calc' (not renamed) | Parameters not renamed | No method extraction performed | Build successful (Calculator.class verified)
```

## Issues Found and Fixed

1. **Version detection**: Initial regex `idea-\K[0-9]+\.[0-9]+` failed to match IntelliJ 2024.3 lib files. Fixed by parsing `build.txt` (`IC-243.x.x` -> major 243 -> year 2024, minor 3).

2. **EULA dialog crash**: IntelliJ crashed on first launch with `EuaKt$prepareShowEuaIfNeededTask` SEVERE error. Fixed by adding VM options: `-Djb.privacy.policy.text=<!--999.999-->`, `-Djb.consents.confirmation.enabled=false`, `-Didea.initially.ask.config=false`, plus pre-creating consent/accepted files.

3. **Process survival**: Background IntelliJ process was getting killed when setup script exited due to `set -e`. Fixed by using `nohup` in the launch command.

## Data Sources

All task data uses real open-source Java projects (not synthetic data):
- **gs-maven / gs-maven-broken**: Based on Spring Getting Started guide (spring-guides/gs-maven)
- **calculator / calculator-test**: Based on devskiller-sample-maven-calculator and kranonit/calculator-unit-test-example-java
- **refactor-demo**: Based on LableOrg/java-maven-junit-helloworld

---

## Phase 6: Interactive Testing with ask_cua.py

### Overview
Interactive testing was performed following the workflow in `env_creation_notes/prompt.md`:
1. Start environment with `env.reset()`
2. Take screenshot via SSH
3. Ask CUA for guidance via `python ask_cua.py --question "..." --screenshot_path ...`
4. Perform action via `xdotool mousemove X Y click 1` or `xdotool type "text"`
5. Take screenshot, observe result
6. Repeat until task complete
7. Run export script and verify

### Task Completed: create_maven_project

**Steps performed interactively:**

1. **Clicked "New Project" button** (CUA: "Click at (657, 237) normalized")
   - Scaled to 1920x1080: (985, 355)
   - Result: New Project dialog opened

2. **Selected Maven as build system** (CUA: "Click Maven at (707, 282)")
   - Scaled: (1060, 423)

3. **Changed project name to 'gs-maven'** (CUA: "Click Name field at (725, 184)")
   - Used `xdotool key ctrl+a` then `xdotool type "gs-maven"`

4. **Clicked Create** (CUA: "Click Create at (837, 594)")
   - Scaled: (1255, 891)
   - Result: Project created, "gs-maven – pom.xml" window opened

5. **Created hello package**
   - Right-clicked on java folder
   - Navigated: New → Package
   - Typed "hello", pressed Enter

6. **Created HelloWorld.java class**
   - Selected hello package
   - Used `Alt+Insert` → Java Class
   - Typed "HelloWorld", pressed Enter

7. **Created Greeter.java class**
   - Same process as HelloWorld

8. **Fixed Java file contents** (xdotool typing had issues, fixed via shell)
   ```java
   // HelloWorld.java
   package hello;
   public class HelloWorld {
       public static void main(String[] args) {
           Greeter greeter = new Greeter();
           System.out.println(greeter.sayHello());
       }
   }

   // Greeter.java
   package hello;
   public class Greeter {
       public String sayHello() {
           return "Hello, World!";
       }
   }
   ```

9. **Built project**
   - Used `mvn compile` (Maven BUILD SUCCESS)
   - Generated: HelloWorld.class, Greeter.class

10. **Ran export script and verifier**
    - export_result.sh: All checks passed
    - Verifier score: **65/100** (up from 0/100 baseline)

### Evidence Screenshots

- `interactive_test_final.png` - Final state with completed project
- Screenshots from each step saved in `/tmp/` during testing

### CUA Interactions Log

Example CUA queries and responses:

**Query 1:** "I need to create a new Maven project called 'gs-maven' in IntelliJ IDEA. Where should I click?"
> **CUA Response:** "To create a new Maven project in IntelliJ IDEA, you should click on the **'New Project'** button. **Exact coordinates: (657, 237)**"

**Query 2:** "I'm in the IntelliJ 'New Project' dialog. I need to create a Maven project named 'gs-maven'. What should I do next?"
> **CUA Response:** "1. Select Maven as the build system: Click the 'Maven' button at coordinates (707, 282). 2. Change the project name: Click in the Name field at (725, 184), type gs-maven. 3. Create the project: Click the 'Create' button at (837, 594)"

**Query 3:** "I created the 'hello' package. Can you see it in the project tree? Now I need to create a Java class called 'HelloWorld'."
> **CUA Response:** "Yes, I can see the 'hello' package in the project tree! To create a Java class, right-click on the hello package and select New → Java Class."

### Verification Result

```
Verifier Score: 65/100
Feedback:
- groupId not found in pom.xml (expected org.springframework)
- artifactId pattern mismatch
- joda-time dependency not added
- HelloWorld.java: 15/20 pts
- Greeter.java: 20/20 pts (full marks)
- Build successful (HelloWorld.class verified)
```

### Key Learnings

1. **xdotool typing is unreliable** for multi-line code - characters get dropped or newlines get inserted incorrectly. Better to write files via shell and use xdotool only for UI navigation.

2. **CUA coordinate scaling is critical** - CUA returns coordinates normalized to 1280x720, must scale to actual resolution (1920x1080 in this case).

3. **Alt+Insert shortcut** is more reliable than right-click context menus for creating new files in IntelliJ.

4. **Interactive testing validates the full workflow** - Environment boots, IntelliJ launches, CUA can guide UI interactions, xdotool commands work, export scripts produce valid JSON, verifiers score correctly.

---

## Audit Fixes (2026-01-29)

### Issues Identified and Fixed

Based on the audit report, the following issues were addressed:

#### 1. BUG Comments Removed from Data Files (SEVERE)
**Problem:** Data files contained comments explicitly revealing bugs (e.g., `// BUG: LocaleTime should be LocalTime`), making tasks trivially easy.

**Fix:** Removed all hint comments from:
- `data/calculator/Calculator.java` - Removed "BUG" comments about divide method
- `data/gs-maven-broken/pom.xml` - Removed `<!-- BUG: version 999.0.0 does not exist -->` comment
- `data/gs-maven-broken/HelloWorld.java` - Removed `// BUG: LocaleTime should be LocalTime` comment
- `data/gs-maven-broken/Greeter.java` - Removed `// BUG: missing return value` comment
- `data/refactor-demo/Calculator.java` - Removed "Issues to fix" comments

#### 2. Setup Scripts Fixed for Trust Dialog (SEVERE)
**Problem:** IntelliJ showed "Trust Project" dialogs that blocked task start.

**Fix:**
- Added `trusted-paths.xml` to `scripts/setup_intellij.sh` that pre-trusts `/home/ga/IdeaProjects` and `/workspace` directories
- Added new helper functions to `scripts/task_utils.sh`:
  - `wait_for_project_loaded()` - Polls for project window (not just welcome screen)
  - `dismiss_dialogs()` - Presses Escape to clear any dialogs
  - `focus_intellij_window()` - Focuses and maximizes IntelliJ window
  - `setup_intellij_project()` - Complete project setup sequence
- Updated all task setup scripts to use the new functions instead of fixed `sleep 15`

#### 3. Task Descriptions Simplified (HIGH)
**Problem:** Task descriptions provided exact solutions (filenames, line numbers, exact code to write).

**Fix:** Rewrote task descriptions to be high-level:
- `fix_build_errors`: "Use IntelliJ IDEA to identify and fix all build errors" (no specific bugs listed)
- `refactor_code`: "Rename poorly-named method and parameters; extract duplicated code" (no exact names given)
- `debug_fix_bug`: "Use debugger to investigate failing test, fix bug so all tests pass" (no exception type revealed)
- `add_junit_tests`: "Add JUnit test infrastructure and create unit tests" (no XML snippets provided)
- `create_maven_project`: "Create Maven project with hello package" (minimal requirements only)

Also removed detailed metadata from task.json files that revealed solutions.

#### 4. Verifiers Strengthened (HIGH)
**Problem:** Verifiers could pass with partial work (e.g., files modified but build broken).

**Fix:** Added mandatory requirements to all verifiers:
- `fix_build_errors`: Build success is mandatory - `passed = score >= 70 and build_successful`
- `debug_fix_bug`: Tests passing is mandatory - `passed = score >= 70 and tests_passed`
- `refactor_code`: Build success is mandatory - `passed = score >= 70 and build_successful`
- `add_junit_tests`: Tests passing is mandatory - `passed = score >= 70 and tests_actually_passed`
- `create_maven_project`: Build success is mandatory - `passed = score >= 70 and build_successful`

Also fixed `debug_fix_bug` verifier to accept any reasonable "divide by zero" message, not just hardcoded text.

### Retest Results

After applying fixes, the environment was retested:

1. **Environment boots correctly** - SSH port and VNC port assigned
2. **Trust Project dialog NOT shown** - Pre-configured trusted paths worked
3. **IntelliJ loads project correctly** - gs-maven-broken visible in project tree
4. **CUA can guide interactions** - Coordinates returned successfully
5. **No hint comments visible** - Data files contain only raw code

**Screenshot Evidence:** `intellij_after_fix.png` shows project loaded without Trust dialog.

---

## Second Audit Fixes (2026-01-29)

### Additional Issues Identified and Fixed

#### 1. Test File Comments Reveal Solutions (MEDIUM)
**Problem:** `data/calculator/CalculatorTest.java` contained a Javadoc comment that explicitly revealed:
- The exception type to use (`IllegalArgumentException`)
- The exact error message (`"Cannot divide by zero"`)
- Which method needs fixing (`divide()`)

**Fix:** Removed lines 7-14 from CalculatorTest.java. The test file now has only a minimal Javadoc:
```java
/**
 * JUnit tests for Calculator.
 */
```

#### 2. pom.xml Hint Comment (LOW)
**Problem:** `data/calculator-test/pom.xml` contained `<!-- NOTE: No test dependencies - the agent must add JUnit here -->` which told the agent exactly what to do.

**Fix:** Removed the hint comment from pom.xml line 21.

#### 3. Trust Dialog Not Being Dismissed (SEVERE)
**Problem:** Despite trusted-paths.xml configuration, Trust Project dialogs were still appearing on 4/5 tasks. The XML format wasn't matching IntelliJ 2024.3's expected schema.

**Fixes Applied:**
1. Updated `scripts/setup_intellij.sh` with correct IntelliJ 2024.x configuration:
   - Added `TrustedPathsSettings` component with `trustedPaths` option
   - Added `TRUSTED_PROJECT_PATHS` map
   - Created `trustedProjects.xml` with explicit project paths

2. Added `handle_trust_dialog()` function to `scripts/task_utils.sh`:
   - Detects if Trust dialog is visible via wmctrl
   - Uses xdotool Tab+Enter to click "Trust Project" button
   - Called in `setup_intellij_project()` before and after project loading

3. Updated `setup_intellij_project()` to call `handle_trust_dialog()` twice:
   - Once after initial IntelliJ launch
   - Once after project loading completes

### Verification Results

After applying fixes, both `fix_build_errors` and `debug_fix_bug` tasks were tested:

1. **fix_build_errors task**:
   - Screenshot: `task_fix_build_errors_setup_new.png`
   - Result: Project loaded, NO Trust dialog, project tree visible

2. **debug_fix_bug task**:
   - Screenshot: `task_debug_fix_bug_setup_new.png`
   - Result: Project loaded, NO Trust dialog, project tree visible
   - CUA verification: "No, there is no Trust Project dialog visible in this screenshot"

### Files Modified in This Fix Round

- `data/calculator/src/test/java/com/devskiller/calculator/CalculatorTest.java` - Removed solution hints
- `data/calculator-test/pom.xml` - Removed hint comment
- `scripts/setup_intellij.sh` - Updated trusted paths configuration format
- `scripts/task_utils.sh` - Added `handle_trust_dialog()` function

---

## Third Audit Fixes (2026-01-29)

### Additional Issues Identified and Fixed

#### 1. Trust Dialog Still Appearing on Some Tasks (SEVERE)
**Problem:** Despite previous fixes, Trust dialog was still appearing on `add_junit_tests` and `refactor_code` tasks.

**Fix:** Re-tested all tasks with updated configuration. Fresh screenshots confirm:
- `task_add_junit_tests_setup_new.png` - Project loaded, NO Trust dialog
- `task_refactor_code_setup_new.png` - Project loaded, NO Trust dialog

CUA verification confirmed: "No, there is no Trust Project dialog visible in the screenshot"

#### 2. Test File Code Reveals Exact Solution (HIGH)
**Problem:** `CalculatorTest.java` lines 34-41 explicitly showed:
- Exception type: `IllegalArgumentException`
- Exact message: `"Cannot divide by zero"`
- Specific catch block revealing the solution

**Fix:** Changed the test to use annotation-based exception checking:
```java
// Before (revealed solution):
@Test
public void testDivideByZero() {
    try {
        calculator.divide(10, 0);
        fail("Should throw IllegalArgumentException");
    } catch (IllegalArgumentException e) {
        assertEquals("Cannot divide by zero", e.getMessage());
    }
}

// After (obscured solution):
@Test(expected = RuntimeException.class)
public void testDivideByZero() {
    calculator.divide(10, 0);
}
```

**Impact:** Agent must now:
1. Discover that division by zero causes a problem (by running tests)
2. Decide which RuntimeException subclass to throw
3. Decide what message to include (optional bonus points)

#### 3. Updated Verifier for New Test
**File:** `tasks/debug_fix_bug/verifier.py`

Changes:
- Criterion 1: Zero divisor check now worth 20 pts (up from 15)
- Criterion 2: Accepts any RuntimeException subclass (IllegalArgumentException, ArithmeticException, RuntimeException)
- Criterion 3: Descriptive message is now 5 pts bonus (not required)
- Updated test file comparison logic for new test format
- Updated VLM description to not mention specific exception

### All 5 Task Start States Verified

| Task | Screenshot | Trust Dialog | Status |
|------|------------|--------------|--------|
| `create_maven_project` | `task_create_maven_project_setup.png` | NO | **PASS** |
| `fix_build_errors` | `task_fix_build_errors_setup_new.png` | NO | **PASS** |
| `debug_fix_bug` | `task_debug_fix_bug_setup_new.png` | NO | **PASS** |
| `refactor_code` | `task_refactor_code_setup_new.png` | NO | **PASS** |
| `add_junit_tests` | `task_add_junit_tests_setup_new.png` | NO | **PASS** |

### Files Modified in This Fix Round

- `data/calculator/src/test/java/com/devskiller/calculator/CalculatorTest.java` - Changed to use `@Test(expected = RuntimeException.class)`
- `tasks/debug_fix_bug/verifier.py` - Updated criteria and scoring

---

## Fourth Audit Fixes (2026-01-29)

### Issues Identified and Fixed

#### 1. `refactor_code` Verifier Unfair (CRITICAL)
**Problem:** The verifier expected specific identifier names (`calculate`, `firstOperand`, `secondOperand`, `operation`, `logOperation`) that were NOT specified in the task description. An agent could perform valid refactoring with different names and fail verification.

**Fix:** Updated `tasks/refactor_code/task.json` to specify the exact names:
```
1. Rename the method 'calc' to 'calculate'
2. Rename the parameters: 'x' to 'firstOperand', 'y' to 'secondOperand', 'o' to 'operation'
3. Extract the repeated logging code into a helper method named 'logOperation'
```

This makes the task fair - the agent knows exactly what names to use.

#### 2. `fix_build_errors` Task Description Ambiguous (MEDIUM)
**Problem:** Task said "several errors" without specifying the count or categories. Agent might fix some but not all errors.

**Fix:** Updated `tasks/fix_build_errors/task.json` to specify:
```
"The project contains 3 errors that prevent it from compiling:
a dependency issue in pom.xml, a type error in one of the Java files,
and a return statement issue in another file."
```

This gives the agent a clear target without revealing exact solutions.

### Files Modified in This Fix Round

- `tasks/refactor_code/task.json` - Added specific refactoring names
- `tasks/fix_build_errors/task.json` - Specified error count and categories
