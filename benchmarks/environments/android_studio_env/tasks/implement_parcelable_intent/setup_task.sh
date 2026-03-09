#!/bin/bash
set -e

echo "=== Setting up implement_parcelable_intent task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Directories
PROJECT_NAME="InventoryManager"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="app/src/main/java/com/example/inventory"

# 1. Clean up previous artifacts
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Create Project Structure
# We'll base this on a standard template or create files manually if needed.
# Since we need specific broken code, we'll generate the project files.
# We assume a base project template exists or we construct a minimal one.
# For robustness, we will create a minimal valid project structure here.

mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/inventory/model"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 3. Write build.gradle.kts (Project Level)
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

# 4. Write settings.gradle.kts
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
rootProject.name = "InventoryManager"
include(":app")
EOF

# 5. Write app/build.gradle.kts (MISSING THE PLUGIN)
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // TODO: Something missing here for Parcelize support?
}

android {
    namespace = "com.example.inventory"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.inventory"
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
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# 6. Write Item.kt (NOT PARCELABLE - The Core Problem)
cat > "$PROJECT_DIR/$PACKAGE_DIR/model/Item.kt" << 'EOF'
package com.example.inventory.model

// This class needs to be passed between Activities via Intent
data class Item(
    val id: String,
    val name: String,
    val quantity: Int,
    val price: Double,
    val description: String,
    val isInStock: Boolean
)
EOF

# 7. Write DetailActivity.kt (Target activity)
cat > "$PROJECT_DIR/$PACKAGE_DIR/DetailActivity.kt" << 'EOF'
package com.example.inventory

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class DetailActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Intent to load layout would go here
    }
}
EOF

# 8. Write MainActivity.kt (HAS COMPILATION ERROR)
cat > "$PROJECT_DIR/$PACKAGE_DIR/MainActivity.kt" << 'EOF'
package com.example.inventory

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.example.inventory.model.Item

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Simulating an item fetched from a database
        val item = Item(
            id = "101",
            name = "Super Widget",
            quantity = 5,
            price = 19.99,
            description = "High quality widget",
            isInStock = true
        )

        val intent = Intent(this, DetailActivity::class.java)
        
        // ERROR: This line causes a compilation error because Item is not Parcelable/Serializable
        // and putExtra(String, Serializable/Parcelable) is expected.
        intent.putExtra("selected_item", item)
        
        startActivity(intent)
    }
}
EOF

# 9. Write AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="InventoryManager"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.AppCompat.Light.DarkActionBar"
        tools:targetApi="31">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <activity android:name=".DetailActivity" />
    </application>

</manifest>
EOF

# 10. Add Gradle Wrapper (Copy from system or generate)
# Assuming a standard location for wrapper files in the environment, or we use the 'gradle' command to generate them.
# If not available, we can rely on the IDE to fix it, but better to have it.
# We will copy from a known source if possible, otherwise we write minimal properties.
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Create dummy gradlew scripts to avoid IDE errors if it checks immediately
touch "$PROJECT_DIR/gradlew"
chmod +x "$PROJECT_DIR/gradlew"

# 11. Copy standard res files (minimal needed)
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">InventoryManager</string>
</resources>
EOF
cat > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?><data-extraction-rules><cloud-backup><include domain="root" /></cloud-backup><device-transfer><include domain="root" /></device-transfer></data-extraction-rules>
EOF
cat > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?><full-backup-content><include domain="root" /></full-backup-content>
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 12. Open Project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "InventoryManager" 120

# 13. Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="