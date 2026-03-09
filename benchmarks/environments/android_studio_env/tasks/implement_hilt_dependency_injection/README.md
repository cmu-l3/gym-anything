# Task: Implement Hilt Dependency Injection

## Overview
Refactor the ExpenseTrackerApp to use Dagger Hilt for dependency injection, eliminating manual dependency construction scattered across three Activities.

## Current Problem
Each of the three Activities (MainActivity, AddExpenseActivity, SettingsActivity) creates its own instances:
```kotlin
private val currencyService = CurrencyService.getInstance()
private val repository = ExpenseRepository(applicationContext, currencyService)
private val notificationService = NotificationService(applicationContext)
private val settingsManager = SettingsManager(applicationContext)
```
This means three separate `CurrencyService` singletons exist, state is not shared, and the code is untestable.

## Required Changes

### 1. app/build.gradle.kts
- Add `com.google.dagger.hilt.android` to the plugins block
- Add `kapt` plugin
- Add Hilt dependencies: `hilt-android`, `hilt-compiler` (kapt)

### 2. ExpenseApp.kt
- Add `@HiltAndroidApp` annotation to the Application class

### 3. Create di/AppModule.kt
- Annotate with `@Module` and `@InstallIn(SingletonComponent::class)`
- Add `@Provides @Singleton` for CurrencyService
- Add `@Provides @Singleton` for ExpenseRepository
- Add `@Provides @Singleton` for NotificationService
- Add `@Provides @Singleton` for SettingsManager

### 4. Activities (MainActivity, AddExpenseActivity, SettingsActivity)
- Add `@AndroidEntryPoint` annotation to each Activity
- Replace manual construction with `@Inject lateinit var` fields

## Scoring
- Hilt plugin + dependency in build.gradle.kts: 15 pts
- @HiltAndroidApp on Application: 15 pts
- @Module class with @Provides methods: 20 pts
- @AndroidEntryPoint on Activities: 15 pts
- @Inject fields replace manual construction: 20 pts
- Project compiles: 15 pts

Pass threshold: 70/100
