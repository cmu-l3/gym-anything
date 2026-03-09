#!/bin/bash
set -e

echo "=== Setting up Enforce Copyright Headers task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Define paths
PROJECT_NAME="TechCorpApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="$PROJECT_DIR/app/src/main/java/com/example/techcorpapp"
RES_LAYOUT_DIR="$PROJECT_DIR/app/src/main/res/layout"
RES_VALUES_DIR="$PROJECT_DIR/app/src/main/res/values"

# Clean up previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 1. Create Project Structure
mkdir -p "$PACKAGE_DIR"
mkdir -p "$RES_LAYOUT_DIR"
mkdir -p "$RES_VALUES_DIR"

# 2. Create build.gradle.kts (Minimal valid build)
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
// Top-level build file
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.techcorpapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.techcorpapp"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
}
EOF

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
    }
}
rootProject.name = "TechCorpApp"
include(":app")
EOF

# 3. Create Source Files (Explicitly NO headers)

# MainActivity.kt
cat > "$PACKAGE_DIR/MainActivity.kt" << 'EOF'
package com.example.techcorpapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# Utils.kt
cat > "$PACKAGE_DIR/Utils.kt" << 'EOF'
package com.example.techcorpapp

object Utils {
    fun formatString(input: String): String {
        return input.trim().uppercase()
    }
}
EOF

# activity_main.xml
cat > "$RES_LAYOUT_DIR/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Welcome to TechCorp" />

</LinearLayout>
EOF

# colors.xml
cat > "$RES_VALUES_DIR/colors.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF

# 4. Set Ownership
chown -R ga:ga "/home/ga/AndroidStudioProjects"
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;

# 5. Open Project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "TechCorpApp" 120

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="