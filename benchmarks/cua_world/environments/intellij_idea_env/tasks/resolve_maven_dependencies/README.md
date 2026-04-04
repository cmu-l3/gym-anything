# Task: resolve_maven_dependencies

## Overview

Dependency management is one of the most common and error-prone aspects of Java development. Real Maven projects accumulate dependency problems over time: test libraries leaking into production classpaths, the same library declared multiple times with conflicting versions, and unused dependencies bloating the build. This task requires the developer to use IntelliJ's Maven integration to systematically find and fix all three classes of problem.

**Domain**: Maven dependency management / Build hygiene
**Top occupations**: Software Developers (ONET importance 90), Computer Programmers (99), Computer Systems Engineers (92)

## Goal

Fix all three Maven dependency issues in the `data-processor` project's `pom.xml` so it follows best practices, while ensuring the project still compiles and all tests pass.

## Starting State

- IntelliJ IDEA is open with the `data-processor` Maven project loaded
- The project compiles and tests pass, but pom.xml has 3 dependency problems:
  1. `junit` is declared with `scope=compile` instead of `scope=test`
  2. `joda-time` is declared twice — versions 2.9.2 and 2.10.13
  3. `commons-codec` is declared but never imported in any source file
- The project source files (`TextRecord.java`, `RecordProcessor.java`) use only `joda-time` and standard Java

## Agent Workflow

1. Open `pom.xml` in IntelliJ and inspect the dependencies section
2. Open the Maven tool window (View > Tool Windows > Maven) to see the dependency tree
3. Identify the three problems (wrong scope, duplicate entry, unused dependency)
4. Fix each problem in pom.xml:
   - Change junit scope from `compile` to `test`
   - Remove the duplicate joda-time entry (keep version 2.10.13)
   - Remove the commons-codec dependency entirely
5. Click "Reload All Maven Projects" in the Maven tool window
6. Run `mvn test` or use IntelliJ's test runner to verify all tests still pass

## Success Criteria (100 points)

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| junit has scope=test | 30 pts | pom.xml content check |
| joda-time has exactly one entry (no duplicate) | 25 pts | pom.xml content check |
| commons-codec not in pom.xml | 20 pts | pom.xml content check |
| Project builds and all tests pass | 25 pts | mvn test exit code + surefire report |

**Pass threshold**: ≥70 points

## Verification Strategy

- `export_result.sh` copies pom.xml and runs `mvn test`
- `verifier.py` parses pom.xml content using regex and checks test results
- Do-nothing: pom.xml unchanged → all 3 dependency checks fail → score=0

## Schema / Data Reference

The `pom.xml` dependencies section should end up with:
```xml
<dependency>
    <groupId>junit</groupId>
    <artifactId>junit</artifactId>
    <version>4.12</version>
    <scope>test</scope>         <!-- fixed from compile -->
</dependency>
<dependency>
    <groupId>joda-time</groupId>
    <artifactId>joda-time</artifactId>
    <version>2.10.13</version>  <!-- one entry only -->
</dependency>
<!-- commons-codec removed entirely -->
```
