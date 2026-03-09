# Task: Implement Retrofit with Error Handling

## Overview
Replace hardcoded cryptocurrency data in CryptoTrackerApp with real Retrofit networking against the CoinGecko public API.

## Current Problem
```kotlin
// CryptoListActivity.kt — hardcoded data, no real API calls
private fun loadCoinData() {
    val coins = listOf(
        CoinData("bitcoin", "Bitcoin", "BTC", 43250.00, 2.5, 850000000000.0),
        CoinData("ethereum", "Ethereum", "ETH", 2280.00, -1.2, 270000000000.0),
        ...
    )
    coinAdapter.updateCoins(coins)
}
```

## Required Changes

### 1. app/build.gradle.kts
```kotlin
implementation("com.squareup.retrofit2:retrofit:2.9.0")
implementation("com.squareup.retrofit2:converter-gson:2.9.0")
implementation("com.squareup.okhttp3:okhttp:4.12.0")
implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
```

### 2. AndroidManifest.xml
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### 3. network/CoinGeckoApi.kt
```kotlin
interface CoinGeckoApi {
    @GET("coins/markets")
    suspend fun getCoins(
        @Query("vs_currency") currency: String = "usd",
        @Query("order") order: String = "market_cap_desc",
        @Query("per_page") perPage: Int = 20
    ): List<CoinResponse>
}
```

### 4. network/CoinResponse.kt (DTO)
```kotlin
data class CoinResponse(
    @SerializedName("id") val id: String,
    @SerializedName("symbol") val symbol: String,
    @SerializedName("name") val name: String,
    @SerializedName("current_price") val currentPrice: Double,
    @SerializedName("price_change_percentage_24h") val priceChange24h: Double?,
    @SerializedName("market_cap") val marketCap: Double
)
```

### 5. network/ApiClient.kt
OkHttpClient + HttpLoggingInterceptor + 15s connect/read/write timeouts + Retrofit singleton.

### 6. CryptoListActivity.kt — replace loadCoinData()
```kotlin
lifecycleScope.launch {
    try {
        val coins = ApiClient.api.getCoins()
        val data = coins.map { CoinData(it.id, it.name, it.symbol.uppercase(), it.currentPrice, it.priceChange24h ?: 0.0, it.marketCap) }
        coinAdapter.updateCoins(data)
    } catch (e: UnknownHostException) {
        Toast.makeText(this@CryptoListActivity, "No internet connection", Toast.LENGTH_LONG).show()
    } catch (e: HttpException) {
        Toast.makeText(this@CryptoListActivity, "API error: ${e.code()}", Toast.LENGTH_LONG).show()
    } catch (e: SocketTimeoutException) {
        Toast.makeText(this@CryptoListActivity, "Connection timed out", Toast.LENGTH_LONG).show()
    }
}
```

## Scoring
- Retrofit + OkHttp deps in build.gradle.kts: 15 pts
- INTERNET permission in AndroidManifest.xml: 10 pts
- @GET interface with @SerializedName DTO: 20 pts
- ApiClient / OkHttpClient singleton: 15 pts
- Error handling (at least 2 exception types): 15 pts
- Hardcoded data removed from Activity: 10 pts
- Project compiles: 15 pts

Pass threshold: 70/100
