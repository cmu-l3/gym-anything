# Task: setup_version_control

## Overview

Every professional Java developer must be able to initialize version control for a new project, establish proper ignore rules, make structured commits, and work on feature branches. This task tests the complete Git workflow inside IntelliJ's VCS integration — a core daily skill for software developers.

**Domain**: Version control / Git workflow
**Top occupations**: Software Developers (ONET importance 90), Computer Programmers (99), Software QA Analysts (99)

## Goal

Initialize Git for the `sort-algorithms` project, establish a clean repository with a .gitignore, make an initial commit, and deliver a MergeSort implementation on a feature branch with its own commit.

## Starting State

- IntelliJ IDEA is open with the `sort-algorithms` Maven project loaded
- The project has InsertionSort and SelectionSort implementations with passing tests
- There is **no .git directory** — the project has never been under version control
- No .gitignore file exists

## Agent Workflow

1. Use VCS > Enable Version Control Integration to initialize a Git repository
2. Create a `.gitignore` file at the project root that excludes:
   - `target/` (Maven build output)
   - `.idea/` (IntelliJ project files)
   - `*.iml` (IntelliJ module files)
   - `*.class` (compiled Java bytecode)
3. Stage all source files and commit with a message that includes "initial" or "Initial commit"
4. Create and switch to a new branch named `feature/add-merge-sort`
5. Implement a correct MergeSort in `src/main/java/com/sorts/MergeSort.java`
6. Write at least 3 JUnit 4 tests in `src/test/java/com/sorts/MergeSortTest.java`
7. Stage and commit these new files on the feature branch

## Success Criteria (100 points)

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| .git directory exists (VCS initialized) | 15 pts | Directory check |
| .gitignore exists with target/ exclusion | 15 pts | File content check |
| .gitignore excludes .idea/ and *.iml | 10 pts | File content check |
| Initial commit exists (at least 1 commit on main/master) | 15 pts | git log |
| feature/add-merge-sort branch exists | 15 pts | git branch |
| MergeSort.java exists and compiles | 15 pts | File + class check |
| MergeSortTest.java has ≥3 test methods | 15 pts | Source analysis |
| VLM: VCS panel or commit dialog visible | up to +10 pts | Trajectory |

**Pass threshold**: ≥70 points

## Verification Strategy

- `export_result.sh` checks filesystem state: .git/, .gitignore, git log, git branch
- `verifier.py` parses output of git commands run in the VM
- All checks are file-system based (no network required)

## Edge Cases

- IntelliJ may default to `master` or `main` as the initial branch name — both are accepted
- The agent may use IntelliJ's Commit dialog or the terminal — both paths are valid
- MergeSort.java must be in the correct package and compile with `mvn compile`
