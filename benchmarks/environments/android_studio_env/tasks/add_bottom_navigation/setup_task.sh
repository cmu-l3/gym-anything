#!/bin/bash
set -e

echo "=== Setting up add_bottom_navigation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous task artifacts
rm -rf /tmp/task_result.json 2>/dev/null || true
rm -rf /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -rf /tmp/gradle_output.log 2>/dev/null || true

# 2. Prepare the base NavigationApp project
PROJECT_DIR="/home/ga/AndroidStudioProjects/NavigationApp"
echo "Creating base project at $PROJECT_DIR..."

rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/navapp"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/drawable"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# Create build.gradle.kts (Project level)
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
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
    }
}
rootProject.name = "NavigationApp"
include(":app")
EOF

# Create app/build.gradle.kts
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.navapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.navapp"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
    
    // TODO: Add Navigation dependencies here
}
EOF

# Create AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
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
        android:theme="@style/Theme.NavigationApp"
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

# Create MainActivity.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/navapp/MainActivity.kt" << 'EOF'
package com.example.navapp

import androidx.appcompat.app.AppCompatActivity
import android.os.Bundle

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // TODO: Setup Navigation Controller with BottomNavigationView
    }
}
EOF

# Create activity_main.xml
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <TextView
        android:id="@+id/textView"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Hello World!"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# Create strings.xml
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">NavigationApp</string>
    <string name="title_home">Home</string>
    <string name="title_dashboard">Dashboard</string>
    <string name="title_settings">Settings</string>
</resources>
EOF

# Create themes.xml
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <!-- Base application theme. -->
    <style name="Base.Theme.NavigationApp" parent="Theme.Material3.DayNight.NoActionBar">
        <!-- Customize your light theme here. -->
        <!-- <item name="colorPrimary">@color/my_light_primary</item> -->
    </style>

    <style name="Theme.NavigationApp" parent="Base.Theme.NavigationApp" />
</resources>
EOF

# Create dummy backup rules to satisfy manifest
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo '<full-backup-content />' > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"
echo '<data-extraction-rules />' > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# Try to copy gradle wrapper from an existing project or create dummy
# Note: In this environment, we rely on Android Studio to provide gradle or we assume system gradle
# We create a simple gradlew script that uses system gradle if available
cat > "$PROJECT_DIR/gradlew" << 'EOF'
#!/bin/bash
if command -v gradle &> /dev/null; then
    gradle "$@"
else
    echo "Gradle not found in path. Please run via Android Studio."
    exit 1
fi
EOF
chmod +x "$PROJECT_DIR/gradlew"

# 3. Open project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "NavigationApp" 180

# 4. Record start time
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="