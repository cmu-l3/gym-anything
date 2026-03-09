#!/bin/bash
set -e

echo "=== Setting up Add Room Database task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AndroidStudioProjects/TaskTracker"
mkdir -p "$PROJECT_DIR"

# Clean up any previous attempt
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# ==============================
# Generate Project Files
# ==============================

# 1. Project-level build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << 'BUILDEOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
BUILDEOF

# 2. settings.gradle.kts
cat > "$PROJECT_DIR/settings.gradle.kts" << 'SETTINGSEOF'
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
rootProject.name = "TaskTracker"
include(":app")
SETTINGSEOF

# 3. gradle.properties
cat > "$PROJECT_DIR/gradle.properties" << 'PROPSEOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
PROPSEOF

# 4. local.properties
cat > "$PROJECT_DIR/local.properties" << 'LOCALEOF'
sdk.dir=/opt/android-sdk
LOCALEOF

# 5. Gradle Wrapper
mkdir -p "$PROJECT_DIR/gradle/wrapper"
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'WRAPPEREOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
WRAPPEREOF

# Create gradlew script
cat > "$PROJECT_DIR/gradlew" << 'GRADLEW_EOF'
#!/bin/sh
APP_HOME=$( cd "${APP_HOME:-$(dirname "$0")}" > /dev/null && pwd -P ) || exit
if [ -n "$JAVA_HOME" ] ; then
    if [ -x "$JAVA_HOME/jre/sh/java" ] ; then
        JAVACMD="$JAVA_HOME/jre/sh/java"
    else
        JAVACMD="$JAVA_HOME/bin/java"
    fi
else
    JAVACMD="java"
fi
CLASSPATH=$APP_HOME/gradle/wrapper/gradle-wrapper.jar
DEFAULT_JVM_OPTS='"-Xmx64m" "-Xms64m"'
exec "$JAVACMD" $DEFAULT_JVM_OPTS $JAVA_OPTS $GRADLE_OPTS "-Dorg.gradle.appname=Gradle" -classpath "$CLASSPATH" org.gradle.wrapper.GradleWrapperMain "$@"
GRADLEW_EOF
chmod +x "$PROJECT_DIR/gradlew"

# Download wrapper jar
if [ ! -f "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" ]; then
    wget -q "https://raw.githubusercontent.com/gradle/gradle/v8.4.0/gradle/wrapper/gradle-wrapper.jar" \
        -O "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" || true
fi

# 6. App Module
mkdir -p "$PROJECT_DIR/app"

# App build.gradle.kts
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'APPBUILDEOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.tasktracker"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.tasktracker"
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
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
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
}
APPBUILDEOF

# Proguard
touch "$PROJECT_DIR/app/proguard-rules.pro"

# Source structure
SRC_DIR="$PROJECT_DIR/app/src/main/java/com/example/tasktracker"
mkdir -p "$SRC_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"

# AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'MANIFESTEOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <application
        android:allowBackup="true"
        android:label="TaskTracker"
        android:theme="@style/Theme.TaskTracker"
        tools:targetApi="31">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
MANIFESTEOF

# MainActivity.kt
cat > "$SRC_DIR/MainActivity.kt" << 'MAINEOF'
package com.example.tasktracker

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
MAINEOF

# Layout
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'LAYOUTEOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Task Tracker"
        xmlns:app="http://schemas.android.com/apk/res-auto"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />
</androidx.constraintlayout.widget.ConstraintLayout>
LAYOUTEOF

# Themes
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'THEMESEOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.TaskTracker" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">#6200EE</item>
    </style>
</resources>
THEMESEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# ==============================
# Initial State Recording
# ==============================
# Count existing Kotlin files
find "$SRC_DIR" -name "*.kt" | wc -l > /tmp/initial_kt_count.txt
# Record build.gradle hashes
md5sum "$PROJECT_DIR/app/build.gradle.kts" > /tmp/initial_app_build_hash.txt
md5sum "$PROJECT_DIR/build.gradle.kts" > /tmp/initial_project_build_hash.txt

# ==============================
# Open in Android Studio
# ==============================
echo "Opening project in Android Studio..."
setup_android_studio_project "$PROJECT_DIR" "TaskTracker" 120

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="