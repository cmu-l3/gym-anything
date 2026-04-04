#!/bin/bash
set -e
echo "=== Setting up split_monolithic_file task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define project paths
PROJECT_NAME="CommandPatternApp"
PROJECT_DIR="/home/ga/eclipse-workspace/$PROJECT_NAME"
SRC_PKG_DIR="$PROJECT_DIR/src/com/example/commands"

# Clean up any previous task artifacts
rm -rf "$PROJECT_DIR"
rm -f /home/ga/refactored_output.txt
rm -f /tmp/expected_output.txt
rm -f /tmp/task_result.json

# Create project directory structure
mkdir -p "$SRC_PKG_DIR"
mkdir -p "$PROJECT_DIR/bin"
mkdir -p "$PROJECT_DIR/.settings"

# Create .project file for Eclipse
cat > "$PROJECT_DIR/.project" << 'PROJECTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>CommandPatternApp</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments>
            </arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
    </natures>
</projectDescription>
PROJECTEOF

# Create .classpath file
cat > "$PROJECT_DIR/.classpath" << 'CPEOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
CPEOF

# Create JDT settings (Java 17)
cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'SETTINGSEOF'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
SETTINGSEOF

# Create the monolithic CommandSystem.java file
cat > "$SRC_PKG_DIR/CommandSystem.java" << 'JAVAEOF'
package com.example.commands;

import java.util.ArrayList;
import java.util.List;
import java.util.Stack;

/**
 * Command Pattern Implementation.
 * 
 * TODO: Refactor this file! It contains too many types.
 * Use "Move Type to New File" to split them up.
 */

// ---- Command Interface ----

interface Command {
    void execute();
    String getDescription();
}

// ---- UndoableCommand Interface ----

interface UndoableCommand extends Command {
    void undo();
}

// ---- TextDocument (Receiver) ----

class TextDocument {
    private StringBuilder content;

    public TextDocument() {
        this.content = new StringBuilder();
    }

    public void insertText(int position, String text) {
        if (position < 0 || position > content.length()) {
            throw new IndexOutOfBoundsException("Position " + position + " invalid");
        }
        content.insert(position, text);
    }

    public String deleteText(int position, int length) {
        if (position < 0 || position + length > content.length()) {
            throw new IndexOutOfBoundsException("Delete range invalid");
        }
        String deleted = content.substring(position, position + length);
        content.delete(position, position + length);
        return deleted;
    }

    public String getContent() {
        return content.toString();
    }
}

// ---- InsertTextCommand ----

class InsertTextCommand implements UndoableCommand {
    private final TextDocument document;
    private final int position;
    private final String text;

    public InsertTextCommand(TextDocument document, int position, String text) {
        this.document = document;
        this.position = position;
        this.text = text;
    }

    @Override
    public void execute() {
        document.insertText(position, text);
    }

    @Override
    public void undo() {
        document.deleteText(position, text.length());
    }

    @Override
    public String getDescription() {
        return "Insert '" + text + "' at " + position;
    }
}

// ---- DeleteTextCommand ----

class DeleteTextCommand implements UndoableCommand {
    private final TextDocument document;
    private final int position;
    private final int length;
    private String deletedText;

    public DeleteTextCommand(TextDocument document, int position, int length) {
        this.document = document;
        this.position = position;
        this.length = length;
    }

    @Override
    public void execute() {
        deletedText = document.deleteText(position, length);
    }

    @Override
    public void undo() {
        document.insertText(position, deletedText);
    }

    @Override
    public String getDescription() {
        return "Delete " + length + " chars at " + position;
    }
}

// ---- MacroCommand ----

class MacroCommand implements Command {
    private final List<Command> commands;
    private final String name;

    public MacroCommand(String name) {
        this.name = name;
        this.commands = new ArrayList<>();
    }

    public void addCommand(Command command) {
        commands.add(command);
    }

    @Override
    public void execute() {
        System.out.println("Executing macro: " + name);
        for (Command command : commands) {
            command.execute();
        }
    }

    @Override
    public String getDescription() {
        return "Macro '" + name + "'";
    }
}

// ---- CommandInvoker ----

class CommandInvoker {
    private final Stack<UndoableCommand> history;

    public CommandInvoker() {
        this.history = new Stack<>();
    }

    public void executeCommand(Command command) {
        command.execute();
        if (command instanceof UndoableCommand) {
            history.push((UndoableCommand) command);
        }
    }

    public void undoLastCommand() {
        if (!history.isEmpty()) {
            UndoableCommand command = history.pop();
            command.undo();
        }
    }
    
    public int getHistorySize() {
        return history.size();
    }
}
JAVAEOF

# Create Main.java
cat > "$SRC_PKG_DIR/Main.java" << 'MAINEOF'
package com.example.commands;

public class Main {
    public static void main(String[] args) {
        System.out.println("--- Command Pattern Demo ---");
        TextDocument doc = new TextDocument();
        CommandInvoker invoker = new CommandInvoker();

        Command cmd1 = new InsertTextCommand(doc, 0, "Hello");
        invoker.executeCommand(cmd1);
        System.out.println("Doc: " + doc.getContent());

        Command cmd2 = new InsertTextCommand(doc, 5, " World");
        invoker.executeCommand(cmd2);
        System.out.println("Doc: " + doc.getContent());

        invoker.undoLastCommand();
        System.out.println("Undo: " + doc.getContent());
        
        MacroCommand macro = new MacroCommand("TestMacro");
        macro.addCommand(new InsertTextCommand(doc, 5, "!"));
        invoker.executeCommand(macro);
        System.out.println("Final: " + doc.getContent());
        System.out.println("--- Done ---");
    }
}
MAINEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Compile and capture EXPECTED output (ground truth)
echo "Generating ground truth output..."
cd "$PROJECT_DIR"
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 javac -d bin -sourcepath src src/com/example/commands/Main.java
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 java -cp bin com.example.commands.Main > /tmp/expected_output.txt 2>&1

echo "Expected output:"
cat /tmp/expected_output.txt

# Start Eclipse
if ! pgrep -f "eclipse" > /dev/null; then
    echo "Starting Eclipse..."
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace -nosplash > /tmp/eclipse_task.log 2>&1 &"
    sleep 5
fi

wait_for_eclipse 60

# Import project into Eclipse
echo "Importing project..."
su - ga -c "DISPLAY=:1 /opt/eclipse/eclipse -nosplash -data /home/ga/eclipse-workspace -application org.eclipse.ui.ide.workbench -import '$PROJECT_DIR' 2>/dev/null &" || true

sleep 10
focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab

# Open the Package Explorer view if not open (usually default, but good to ensure)
# Open CommandSystem.java
echo "Opening CommandSystem.java..."
# We can use eclipse command line to open a file, but simpler to just let agent find it.
# We'll just ensure window is ready.

take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="