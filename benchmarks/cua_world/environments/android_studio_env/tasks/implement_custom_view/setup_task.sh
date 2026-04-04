#!/bin/bash
set -e
echo "=== Setting up implement_custom_view task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="LogisticsDashboard"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="com/example/logisticsdashboard"
PACKAGE_NAME="com.example.logisticsdashboard"

# Clean up previous runs
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json

# Create project directory structure
mkdir -p "$PROJECT_DIR/app/src/main/java/$PACKAGE_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# ------------------------------------------------------------------
# Generate Project Files (Simulating a fresh Empty Activity project)
# ------------------------------------------------------------------

# settings.gradle.kts
cat > "$PROJECT_DIR/settings.gradle.kts" <<EOF
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
rootProject.name = "$PROJECT_NAME"
include(":app")
EOF

# build.gradle.kts (Project)
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# app/build.gradle.kts
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "$PACKAGE_NAME"
    compileSdk = 34

    defaultConfig {
        applicationId = "$PACKAGE_NAME"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.LogisticsDashboard"
        tools:targetApi="31">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF

# MainActivity.kt
cat > "$PROJECT_DIR/app/src/main/java/$PACKAGE_DIR/MainActivity.kt" <<EOF
package $PACKAGE_NAME

import androidx.appcompat.app.AppCompatActivity
import android.os.Bundle

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# res/layout/activity_main.xml
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Logistics Dashboard"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# res/values/strings.xml
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" <<EOF
<resources>
    <string name="app_name">Logistics Dashboard</string>
</resources>
EOF

# res/values/themes.xml
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" <<EOF
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.LogisticsDashboard" parent="Theme.Material3.DayNight.NoActionBar">
        <!-- Customize your light theme here. -->
    </style>
    <style name="Theme.LogisticsDashboard" parent="Base.Theme.LogisticsDashboard" />
</resources>
EOF

# res/values/colors.xml
cat > "$PROJECT_DIR/app/src/main/res/values/colors.xml" <<EOF
<resources>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
    <color name="teal_200">#FF03DAC5</color>
</resources>
EOF

# res/xml dummies (to satisfy manifest)
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"

# Copy Gradle Wrapper from a source if available, else try to generate or use system gradle
# In this environment, we usually have a cached wrapper or system gradle.
# Let's assume we can use the 'gradle' command to init wrapper if needed,
# or better, copy from a known location in /opt/android-studio if it exists.
# For robustness, we'll try to use the system gradle to generate the wrapper.
if command -v gradle >/dev/null 2>&1; then
    cd "$PROJECT_DIR"
    gradle wrapper --gradle-version 8.2 >/dev/null 2>&1 || true
fi
# Ensure gradlew exists and is executable
if [ ! -f "$PROJECT_DIR/gradlew" ]; then
    # Fallback: create a dummy gradlew that calls system gradle
    echo '#!/bin/bash' > "$PROJECT_DIR/gradlew"
    echo 'gradle "$@"' >> "$PROJECT_DIR/gradlew"
fi
chmod +x "$PROJECT_DIR/gradlew"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# ------------------------------------------------------------------
# Launch Android Studio
# ------------------------------------------------------------------
setup_android_studio_project "$PROJECT_DIR" "$PROJECT_NAME" 180

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="