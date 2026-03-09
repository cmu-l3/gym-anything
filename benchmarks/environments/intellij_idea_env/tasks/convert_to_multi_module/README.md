# Task: convert_to_multi_module

## Overview

Refactoring a monolithic Maven project into a multi-module build is a standard enterprise Java task. It requires deep understanding of Maven's module hierarchy, POM inheritance, inter-module dependencies, and IntelliJ's project structure. This task mirrors real architecture work done when a codebase grows and its components need proper separation.

**Domain**: Maven multi-module architecture / Build refactoring
**Top occupations**: Computer Systems Engineers/Architects (ONET importance 92), Software Developers (90), Computer Programmers (99)

## Goal

Convert the single-module `java-library` project into a proper Maven multi-module build with three submodules (`math`, `strings`, `collections`), where `mvn clean install` from the root succeeds and all tests pass.

## Starting State

- IntelliJ IDEA is open with the `java-library` Maven project loaded
- The project has a single `pom.xml` and three package groups:
  - `com.library.math` → `MathUtils.java` + `MathUtilsTest.java`
  - `com.library.strings` → `StringUtils.java` + `StringUtilsTest.java`
  - `com.library.collections` → `SimpleStack.java` + `SimpleStackTest.java`
- Running `mvn test` from the project root currently passes all 12 tests
- There is no multi-module structure yet (no parent POM with `<modules>`)

## Agent Workflow

1. Modify the root `pom.xml` to be a parent POM:
   - Change `<packaging>jar</packaging>` to `<packaging>pom</packaging>`
   - Add `<modules>` section listing `math`, `strings`, `collections`
   - Move shared `<dependencies>` and `<properties>` to the parent

2. Create three module subdirectories: `math/`, `strings/`, `collections/`

3. For each module, create a `pom.xml` that:
   - References the parent with `<parent>` element
   - Has a unique `<artifactId>` matching the module name
   - Has `<packaging>jar</packaging>`

4. Move source and test files to their respective modules:
   - `src/main/java/com/library/math/` → `math/src/main/java/com/library/math/`
   - `src/test/java/com/library/math/` → `math/src/test/java/com/library/math/`
   - (same pattern for strings and collections)

5. Run `mvn clean install` from the project root to verify the build succeeds

## Success Criteria (100 points)

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| Root pom.xml has `<packaging>pom</packaging>` | 10 pts | POM content check |
| Root pom.xml declares all 3 modules in `<modules>` | 20 pts | POM content check |
| Each of the 3 module directories has a pom.xml | 20 pts | File existence check |
| Each module pom.xml references the parent | 15 pts | POM content check |
| `mvn clean install` from root succeeds | 35 pts | Exit code + surefire reports |

**Pass threshold**: ≥70 points

## Verification Strategy

- `export_result.sh` checks directory structure and runs `mvn clean install`
- `verifier.py` parses POM files and checks build result
- Wrong-target protection: verifies module names are exactly `math`, `strings`, `collections`
- Do-nothing: root POM unchanged, no subdirectory POMs → all structural checks fail → score=0

## Edge Cases

- Agent may use IntelliJ's "New Module" wizard or edit POM files manually — both approaches are valid
- The `<parent>` element in child POMs must correctly reference the root project's `groupId`, `artifactId`, and `version`
- The root pom.xml must NOT keep `<packaging>jar</packaging>` — it must be `<packaging>pom</packaging>` for Maven to treat it as a parent

## Maven Multi-Module Reference

A valid parent POM structure:
```xml
<project>
  <groupId>com.library</groupId>
  <artifactId>java-library</artifactId>
  <version>1.0-SNAPSHOT</version>
  <packaging>pom</packaging>
  <modules>
    <module>math</module>
    <module>strings</module>
    <module>collections</module>
  </modules>
</project>
```

A valid child POM:
```xml
<project>
  <parent>
    <groupId>com.library</groupId>
    <artifactId>java-library</artifactId>
    <version>1.0-SNAPSHOT</version>
  </parent>
  <artifactId>math</artifactId>
  <packaging>jar</packaging>
</project>
```
