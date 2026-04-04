#!/bin/bash
set -e
echo "=== Setting up implement_encrypted_shared_preferences task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define project paths
PROJECT_NAME="SecureNotes"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="$PROJECT_DIR/app/src/main/java/com/example/securenotes/data"
TEST_DIR="$PROJECT_DIR/app/src/test/java/com/example/securenotes"

# Clean up any existing project
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PACKAGE_DIR"
mkdir -p "$TEST_DIR"

# ------------------------------------------------------------------
# 1. Create Project Files
# ------------------------------------------------------------------

# settings.gradle.kts
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
rootProject.name = "SecureNotes"
include(":app")
EOF

# build.gradle.kts (Project level)
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
// Top-level build file
plugins {
    id("com.android.application") version "8.1.0" apply false
    id("org.jetbrains.kotlin.android") version "1.8.10" apply false
}
EOF

# app/build.gradle.kts (App level - MISSING SECURITY DEPENDENCY)
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.securenotes"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.securenotes"
        minSdk = 23 // Required for Jetpack Security
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
    implementation("androidx.core:core-ktx:1.9.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.9.0")
    
    // Unit testing
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito:mockito-core:5.3.1")
    testImplementation("org.robolectric:robolectric:4.10.3")
}
EOF

# TokenManager.kt (INSECURE IMPLEMENTATION)
cat > "$PACKAGE_DIR/TokenManager.kt" << 'EOF'
package com.example.securenotes.data

import android.content.Context
import android.content.SharedPreferences

class TokenManager(context: Context) {

    // TODO: Migrate to EncryptedSharedPreferences
    private val sharedPreferences: SharedPreferences = context.getSharedPreferences(
        "app_prefs", // Current insecure filename
        Context.MODE_PRIVATE
    )

    companion object {
        private const val KEY_AUTH_TOKEN = "auth_token"
    }

    fun saveToken(token: String) {
        sharedPreferences.edit().putString(KEY_AUTH_TOKEN, token).apply()
    }

    fun getToken(): String? {
        return sharedPreferences.getString(KEY_AUTH_TOKEN, null)
    }

    fun clearToken() {
        sharedPreferences.edit().remove(KEY_AUTH_TOKEN).apply()
    }
}
EOF

# TokenManagerTest.kt (Unit Test)
cat > "$TEST_DIR/TokenManagerTest.kt" << 'EOF'
package com.example.securenotes

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.example.securenotes.data.TokenManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest=Config.NONE)
class TokenManagerTest {

    private lateinit var context: Context
    private lateinit var tokenManager: TokenManager

    @Before
    fun setup() {
        context = ApplicationProvider.getApplicationContext()
        tokenManager = TokenManager(context)
    }

    @Test
    fun testSaveAndGetToken() {
        val testToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        tokenManager.saveToken(testToken)
        
        val retrievedToken = tokenManager.getToken()
        assertEquals(testToken, retrievedToken)
    }

    @Test
    fun testClearToken() {
        val testToken = "secret-token"
        tokenManager.saveToken(testToken)
        tokenManager.clearToken()
        
        assertNull(tokenManager.getToken())
    }
}
EOF

# Create AndroidManifest.xml
mkdir -p "$PROJECT_DIR/app/src/main"
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="SecureNotes"
        android:theme="@style/Theme.SecureNotes">
    </application>
</manifest>
EOF

# Create dummy resource files to prevent build errors
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources>
    <style name="Theme.SecureNotes" parent="Theme.MaterialComponents.DayNight.DarkActionBar" />
</resources>
EOF
cat > "$PROJECT_DIR/app/src/main/res/values/colors.xml" << 'EOF'
<resources>
    <color name="purple_200">#FFBB86FC</color>
    <color name="purple_500">#FF6200EE</color>
</resources>
EOF
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"

# Copy gradle wrapper from system or generate it
# Assuming environment has a way to bootstrap gradle, otherwise use the one in /opt
if [ -d "/opt/android-studio/plugins/android/lib/templates/gradle/wrapper" ]; then
    mkdir -p "$PROJECT_DIR/gradle/wrapper"
    cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/* "$PROJECT_DIR/gradle/wrapper/"
fi
# Ensure gradlew exists
if [ ! -f "$PROJECT_DIR/gradlew" ]; then
    # Create a basic gradlew script if missing (fallback)
    echo '#!/bin/bash' > "$PROJECT_DIR/gradlew"
    echo 'gradle "$@"' >> "$PROJECT_DIR/gradlew" 
fi
chmod +x "$PROJECT_DIR/gradlew"

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# ------------------------------------------------------------------
# 2. Open Project in Android Studio
# ------------------------------------------------------------------
setup_android_studio_project "$PROJECT_DIR" "SecureNotes" 180

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="