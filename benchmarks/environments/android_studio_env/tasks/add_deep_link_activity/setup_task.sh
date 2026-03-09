#!/bin/bash
set -e
echo "=== Setting up Add Deep Link Activity task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/ShopEasyApp"

# 1. Clean up any previous task artifacts
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/gradle_build_output.log 2>/dev/null || true

# 2. Create project directory structure
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/shopeasy"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/drawable"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-hdpi"
mkdir -p "$PROJECT_DIR/app/src/test/java/com/example/shopeasy"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 3. Create Project Files

# --- settings.gradle.kts ---
cat > "$PROJECT_DIR/settings.gradle.kts" << 'SETTINGSEOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolution {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "ShopEasy"
include(":app")
SETTINGSEOF

# --- build.gradle.kts (Project) ---
cat > "$PROJECT_DIR/build.gradle.kts" << 'BUILDEOF'
// Top-level build file
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
BUILDEOF

# --- build.gradle.kts (App) ---
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'APPBUILDEOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.shopeasy"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.shopeasy"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
}
APPBUILDEOF

# --- AndroidManifest.xml (Initial State) ---
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'MANIFESTEOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.ShopEasy"
        tools:targetApi="34">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity
            android:name=".ProductListActivity"
            android:exported="false"
            android:label="@string/title_product_list" />

    </application>

</manifest>
MANIFESTEOF

# Record initial manifest for comparison
cp "$PROJECT_DIR/app/src/main/AndroidManifest.xml" /tmp/original_manifest.xml

# --- MainActivity.kt ---
cat > "$PROJECT_DIR/app/src/main/java/com/example/shopeasy/MainActivity.kt" << 'MAINEOF'
package com.example.shopeasy

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<Button>(R.id.btn_browse).setOnClickListener {
            startActivity(Intent(this, ProductListActivity::class.java))
        }
    }
}
MAINEOF

# --- ProductListActivity.kt ---
cat > "$PROJECT_DIR/app/src/main/java/com/example/shopeasy/ProductListActivity.kt" << 'PRODEOF'
package com.example.shopeasy

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class ProductListActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_product_list)
    }
}
PRODEOF

# --- Layouts & Resources ---
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'LAYOUT1EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:gravity="center"
    android:orientation="vertical">
    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="Welcome to ShopEasy" />
    <Button android:id="@+id/btn_browse" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="Browse" />
</LinearLayout>
LAYOUT1EOF

cat > "$PROJECT_DIR/app/src/main/res/layout/activity_product_list.xml" << 'LAYOUT2EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content" android:text="Products" />
</LinearLayout>
LAYOUT2EOF

cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'STRINGSEOF'
<resources>
    <string name="app_name">ShopEasy</string>
    <string name="title_product_list">Products</string>
</resources>
STRINGSEOF

cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'THEMESEOF'
<resources>
    <style name="Theme.ShopEasy" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">#6200EE</item>
    </style>
</resources>
THEMESEOF

# --- Gradle Wrapper & Properties ---
cat > "$PROJECT_DIR/gradle.properties" << 'PROPEOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
PROPEOF

cat > "$PROJECT_DIR/local.properties" << 'LOCALEOF'
sdk.dir=/opt/android-sdk
LOCALEOF

cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'WRAPEOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
WRAPEOF

# Download wrapper jar
curl -sL "https://raw.githubusercontent.com/gradle/gradle/v8.5.0/gradle/wrapper/gradle-wrapper.jar" \
    -o "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null || true

# Create gradlew
cat > "$PROJECT_DIR/gradlew" << 'GRADLEWEOF'
#!/bin/sh
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
exec "$JAVA_HOME/bin/java" -classpath "$0/../gradle/wrapper/gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain "$@"
GRADLEWEOF
chmod +x "$PROJECT_DIR/gradlew"

# 4. Set Permissions
chown -R ga:ga "$PROJECT_DIR"

# 5. Open Project in Android Studio
echo "Opening project in Android Studio..."
setup_android_studio_project "$PROJECT_DIR" "ShopEasy" 120

# 6. Take Initial Screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="