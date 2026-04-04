#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up User Guide Callout Styling Task ==="

# Create documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create the draft document using python-docx
# We use Python to ensure the file structure is valid but unstyled
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Title (Plain text, agent must leave as is or style as Title, but task focuses on headings/callouts)
doc.add_paragraph("Git Version Control: User Guide")
doc.add_paragraph("This guide covers the basics of using Git for version control in software development projects.")
doc.add_paragraph("")

# Section 1
doc.add_paragraph("Getting Started with Git")
doc.add_paragraph(
    "Git is a distributed version control system that allows you to track changes in source "
    "code during software development. It is designed for coordinating work among programmers, "
    "but it can be used to track changes in any set of files."
)
doc.add_paragraph(
    "[NOTE] Git stores data as a series of snapshots. Every time you commit, or save the state "
    "of your project, Git takes a picture of what all your files look like at that moment and "
    "stores a reference to that snapshot."
)

# Subsection 1.1
doc.add_paragraph("Installing Git")
doc.add_paragraph(
    "You can install Git on Linux via the package manager (apt, yum, etc.), on macOS via "
    "Xcode or Homebrew, and on Windows via the official installer."
)

# Subsection 1.2
doc.add_paragraph("Initial Configuration")
doc.add_paragraph(
    "Before you start, you need to configure your identity. This is important because every "
    "Git commit uses this information."
)
doc.add_paragraph("[CODE] git config --global user.name \"Your Name\"\ngit config --global user.email \"you@example.com\"")
doc.add_paragraph(
    "[TIP] You can use git config --global alias.<short> <command> to create shortcuts for "
    "common commands. For example, 'git config --global alias.co checkout' lets you type "
    "'git co' instead."
)

# Section 2
doc.add_paragraph("Working with Repositories")
doc.add_paragraph(
    "To start tracking a project in Git, you need to initialize a repository or clone an "
    "existing one."
)
doc.add_paragraph("[CODE] git clone https://github.com/user/repo.git")
doc.add_paragraph(
    "[NOTE] The staging area is a file, generally contained in your Git directory, that "
    "stores information about what will go into your next commit."
)
doc.add_paragraph(
    "[WARNING] If you lose your local .git directory, you lose the entire project history "
    "unless it has been pushed to a remote server. Treat this directory with care."
)

# Section 3
doc.add_paragraph("Branching and Merging")
doc.add_paragraph(
    "Branching means you diverge from the main line of development and continue to do work "
    "without messing with that main line."
)
doc.add_paragraph("[CODE] git checkout -b feature-branch")
doc.add_paragraph(
    "Once you have completed work on a branch, you can merge it back into your main branch."
)
doc.add_paragraph("[CODE] git merge feature-branch")
doc.add_paragraph(
    "[NOTE] Git does not explicitly track file movement. If you rename a file, Git infers "
    "that it was a rename based on content similarity."
)
doc.add_paragraph(
    "[TIP] Use git diff --cached to see what you have staged that is about to be committed, "
    "as opposed to git diff which shows unstaged changes."
)

# Subsection 3.1
doc.add_paragraph("Remote Repositories")
doc.add_paragraph(
    "Remote repositories are versions of your project that are hosted on the internet or "
    "network somewhere."
)
doc.add_paragraph("[CODE] git push origin main")
doc.add_paragraph(
    "[WARNING] Changing the commit history (using rebase or amend) on commits that have "
    "already been pushed to a shared remote repository can cause significant problems for "
    "other collaborators."
)

# Section 4
doc.add_paragraph("Best Practices")
doc.add_paragraph(
    "Commit often, perfect later. You can always squash commits before pushing."
)
doc.add_paragraph(
    "[NOTE] You can check the status of your files using the 'git status' command, which "
    "shows you which files are staged, unstaged, or untracked."
)
doc.add_paragraph(
    "[TIP] Pressing Tab will auto-complete command names and branch names in most shells."
)
doc.add_paragraph(
    "[WARNING] Hard resetting will discard all local changes in your working directory. "
    "Use 'git reset --hard' only if you are absolutely sure you want to lose that work."
)

doc.save("/home/ga/Documents/git_guide_draft.docx")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/git_guide_draft.docx

# Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/git_guide_draft.docx > /tmp/writer.log 2>&1 &"

# Wait for Writer to start
if ! wait_for_process "soffice" 20; then
    echo "ERROR: LibreOffice failed to start"
fi

# Wait for window
wait_for_window "git_guide_draft" 30 || wait_for_window "LibreOffice Writer" 30

# Maximize and focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="