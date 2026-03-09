#!/bin/bash
set -e

echo "=== Setting up Extract Interface task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Define paths
PROJECT_DIR="/home/ga/eclipse-workspace/ServiceApp"
SRC_DIR="$PROJECT_DIR/src/main/java/com/serviceapp"

# Clean up any previous attempt
rm -rf "$PROJECT_DIR"
mkdir -p "$SRC_DIR/model"
mkdir -p "$SRC_DIR/service"
mkdir -p "$SRC_DIR/controller"
mkdir -p "$PROJECT_DIR/bin"

# ------------------------------------------------------------------
# 1. Create Java Source Files
# ------------------------------------------------------------------

# User.java (Model)
cat > "$SRC_DIR/model/User.java" << 'JAVAEOF'
package com.serviceapp.model;
import java.util.Objects;
public class User {
    private int id;
    private String name;
    private String email;
    private boolean active;
    public User() { this.active = true; }
    public User(int id, String name, String email) {
        this.id = id; this.name = name; this.email = email; this.active = true;
    }
    public User(int id, String name, String email, boolean active) {
        this.id = id; this.name = name; this.email = email; this.active = active;
    }
    public int getId() { return id; }
    public void setId(int id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public boolean isActive() { return active; }
    public void setActive(boolean active) { this.active = active; }
    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        User user = (User) o;
        return id == user.id && active == user.active &&
               Objects.equals(name, user.name) && Objects.equals(email, user.email);
    }
    @Override
    public int hashCode() { return Objects.hash(id, name, email, active); }
    @Override
    public String toString() {
        return "User{id=" + id + ", name='" + name + "', email='" + email + "'}";
    }
}
JAVAEOF

# UserService.java (Target for refactoring)
cat > "$SRC_DIR/service/UserService.java" << 'JAVAEOF'
package com.serviceapp.service;

import com.serviceapp.model.User;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

public class UserService {

    private final Map<Integer, User> userStore;
    private final AtomicInteger idSequence;

    public UserService() {
        this.userStore = new HashMap<>();
        this.idSequence = new AtomicInteger(1);
        seedInitialData();
    }

    public User findById(int id) {
        User original = userStore.get(id);
        if (original == null) return null;
        return new User(original.getId(), original.getName(), original.getEmail(), original.isActive());
    }

    public List<User> findAll() {
        return userStore.values().stream()
                .map(u -> new User(u.getId(), u.getName(), u.getEmail(), u.isActive()))
                .collect(Collectors.toList());
    }

    public void save(User user) {
        if (user == null) throw new IllegalArgumentException("User must not be null");
        if (user.getId() <= 0) user.setId(idSequence.getAndIncrement());
        userStore.put(user.getId(), new User(user.getId(), user.getName(), user.getEmail(), user.isActive()));
    }

    public void delete(int id) {
        userStore.remove(id);
    }

    public boolean exists(int id) {
        return userStore.containsKey(id);
    }

    private void seedInitialData() {
        save(new User(0, "Alice Johnson", "alice@example.com"));
        save(new User(0, "Bob Williams", "bob@example.com"));
    }
}
JAVAEOF

# UserController.java (Dependent class)
cat > "$SRC_DIR/controller/UserController.java" << 'JAVAEOF'
package com.serviceapp.controller;

import com.serviceapp.model.User;
import com.serviceapp.service.UserService;
import java.util.List;

public class UserController {

    // Dependency on concrete class - needs to be updated to interface
    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    public String getUserDetails(int id) {
        User user = userService.findById(id);
        return (user != null) ? user.toString() : "User not found";
    }

    public List<User> getAllUsers() {
        return userService.findAll();
    }

    public void registerUser(String name, String email) {
        userService.save(new User(0, name, email));
    }
}
JAVAEOF

# Main.java (Entry point)
cat > "$SRC_DIR/Main.java" << 'JAVAEOF'
package com.serviceapp;
import com.serviceapp.controller.UserController;
import com.serviceapp.service.UserService;

public class Main {
    public static void main(String[] args) {
        UserService service = new UserService();
        UserController controller = new UserController(service);
        System.out.println("Users: " + controller.getAllUsers());
    }
}
JAVAEOF

# ------------------------------------------------------------------
# 2. Configure Eclipse Project
# ------------------------------------------------------------------

# .project
cat > "$PROJECT_DIR/.project" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>ServiceApp</name>
    <comment></comment>
    <projects></projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments></arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
    </natures>
</projectDescription>
XMLEOF

# .classpath
cat > "$PROJECT_DIR/.classpath" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src/main/java"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17">
        <attributes>
            <attribute name="module" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="output" path="bin"/>
</classpath>
XMLEOF

# JDT Settings (Java 17)
mkdir -p "$PROJECT_DIR/.settings"
cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'PREFS'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.inlineJsrBytecode=enabled
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.problem.assertIdentifier=error
org.eclipse.jdt.core.compiler.problem.enablePreviewFeatures=disabled
org.eclipse.jdt.core.compiler.problem.enumIdentifier=error
org.eclipse.jdt.core.compiler.release=enabled
org.eclipse.jdt.core.compiler.source=17
PREFS

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# ------------------------------------------------------------------
# 3. Initial State Validation
# ------------------------------------------------------------------

# Verify it compiles initially
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
$JAVA_HOME/bin/javac -d "$PROJECT_DIR/bin" $(find "$SRC_DIR" -name "*.java")

# Record initial file hashes (to detect changes later)
sha256sum "$SRC_DIR/service/UserService.java" > /tmp/initial_hashes.txt
sha256sum "$SRC_DIR/controller/UserController.java" >> /tmp/initial_hashes.txt

# ------------------------------------------------------------------
# 4. GUI Setup
# ------------------------------------------------------------------

# Ensure Eclipse is running
if ! pgrep -f "eclipse" > /dev/null; then
    echo "Starting Eclipse..."
    su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "eclipse"; then
            break
        fi
        sleep 1
    done
fi

# Focus and maximize
DISPLAY=:1 wmctrl -r "Eclipse" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Eclipse" 2>/dev/null || true

# Refresh workspace (F5) to ensure project is detected
sleep 5
DISPLAY=:1 xdotool key F5
sleep 2

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="