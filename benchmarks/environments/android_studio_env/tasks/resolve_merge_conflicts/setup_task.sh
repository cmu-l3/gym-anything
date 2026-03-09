#!/bin/bash
set -e
echo "=== Setting up TaskMaster Merge Conflict ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Setup Project Structure
PROJECT_NAME="TaskMaster"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"

# Clean up any previous runs
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/taskmaster"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

echo "Generating project files..."

# Create build.gradle.kts (Project level)
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# Create settings.gradle.kts
cat > "$PROJECT_DIR/settings.gradle.kts" << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = java.net.URI("https://jitpack.io") }
    }
}
rootProject.name = "TaskMaster"
include(":app")
EOF

# Create app/build.gradle.kts (Base version)
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.taskmaster"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.example.taskmaster"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# Create initial layout
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout 
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <TextView
        android:id="@+id/title"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="TaskMaster Dashboard"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintStart_toStartOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# Create Manifest
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:label="TaskMaster"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

# Create MainActivity
cat > "$PROJECT_DIR/app/src/main/java/com/example/taskmaster/MainActivity.kt" << 'EOF'
package com.example.taskmaster
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# Copy Gradle wrapper from a template or system location if available, otherwise mock it
# Assuming the environment has a cached gradle wrapper or we can use the one from Android Studio installation
# For robustness, we'll try to use the one from the template if it exists
TEMPLATE_DIR="/workspace/data/templates/BaseProject"
if [ -d "$TEMPLATE_DIR/gradle" ]; then
    cp -r "$TEMPLATE_DIR/gradle" "$PROJECT_DIR/"
    cp "$TEMPLATE_DIR/gradlew" "$PROJECT_DIR/"
else
    # Fallback: create a dummy wrapper script that delegates to local gradle or just fails gracefully
    # Realistically, the env should have this. We will assume standard env.
    echo "WARNING: Gradle wrapper template not found. Build might be slower."
    cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradle "$PROJECT_DIR/" 2>/dev/null || true
    touch "$PROJECT_DIR/gradlew"
    chmod +x "$PROJECT_DIR/gradlew"
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 2. Setup Git History & Conflict
echo "Initializing Git repository..."
cd "$PROJECT_DIR"

# Git configuration needs to be run as 'ga' user
su - ga -c "
    cd $PROJECT_DIR
    git init
    git config user.email 'dev@taskmaster.com'
    git config user.name 'Developer'
    git add .
    git commit -m 'Initial commit'

    # --- Create Feature Branch ---
    git checkout -b feature/login-ui
"

# Apply Feature Changes (Login UI + Retrofit)
# We use sed/cat to modify files to simulate development

# Modify Layout (Feature)
sed -i '/<\/androidx.constraintlayout.widget.ConstraintLayout>/d' "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml"
cat >> "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
    <LinearLayout
        android:id="@+id/login_container"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        app:layout_constraintTop_toBottomOf="@+id/title">
        <EditText android:hint="Username" android:layout_width="match_parent" android:layout_height="wrap_content"/>
        <Button android:text="Login" android:layout_width="wrap_content" android:layout_height="wrap_content"/>
    </LinearLayout>

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# Modify Gradle (Feature)
sed -i '/}/d' "$PROJECT_DIR/app/build.gradle.kts"
echo '    implementation("com.squareup.retrofit2:retrofit:2.9.0")' >> "$PROJECT_DIR/app/build.gradle.kts"
echo '}' >> "$PROJECT_DIR/app/build.gradle.kts"

# Commit Feature
su - ga -c "
    cd $PROJECT_DIR
    git add .
    git commit -m 'Add login UI and Retrofit'
    
    # --- Switch to Main and Create Conflict ---
    git checkout master 2>/dev/null || git checkout main
"

# Apply Main Changes (Chart + MPAndroidChart) - SAME LOCATIONS to force conflict

# Modify Layout (Main)
sed -i '/<\/androidx.constraintlayout.widget.ConstraintLayout>/d' "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml"
cat >> "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
    <com.github.mikephil.charting.charts.LineChart
        android:id="@+id/dashboard_chart"
        android:layout_width="match_parent"
        android:layout_height="300dp"
        app:layout_constraintTop_toBottomOf="@+id/title" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# Modify Gradle (Main)
sed -i '/}/d' "$PROJECT_DIR/app/build.gradle.kts"
echo '    implementation("com.github.PhilJay:MPAndroidChart:v3.1.0")' >> "$PROJECT_DIR/app/build.gradle.kts"
echo '}' >> "$PROJECT_DIR/app/build.gradle.kts"

# Commit Main
su - ga -c "
    cd $PROJECT_DIR
    git add .
    git commit -m 'Add dashboard chart'
    
    # --- TRIGGER CONFLICT ---
    echo 'Attempting merge (expecting conflict)...'
    git merge feature/login-ui || true
"

echo "Conflict created. Git status:"
su - ga -c "cd $PROJECT_DIR && git status"

# 3. Launch Android Studio
setup_android_studio_project "$PROJECT_DIR" "TaskMaster" 120

# 4. Record Initial State
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="