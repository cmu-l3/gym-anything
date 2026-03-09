package com.example.cryptotracker.ui

import android.os.Bundle
import android.view.View
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.example.cryptotracker.R
import com.example.cryptotracker.model.CoinData

/**
 * Main screen displaying cryptocurrency prices.
 *
 * CURRENT STATE: Uses hardcoded static data — no network calls.
 *
 * REQUIRED CHANGES:
 * 1. Add Retrofit + OkHttp + Gson/Moshi dependencies to build.gradle.kts
 * 2. Create a network API interface (e.g., CoinGeckoApi) with @HTTP_GET endpoints
 * 3. Create response DTOs with @JSON_field for JSON deserialization
 * 4. Build an ApiClient singleton with OkHttp and logging interceptor
 * 5. Replace hardcoded data with live network fetch
 * 6. Add loading state (show/hide ProgressBar) during fetch
 * 7. Handle errors: network failure, HTTP errors, empty response
 * 8. Show user-facing error message (Snackbar or Toast) on failure
 * 9. Implement pull-to-refresh (SwipeRefreshLayout already in layout)
 */
class CryptoListActivity : AppCompatActivity() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var progressBar: ProgressBar
    private lateinit var tvError: TextView
    private lateinit var swipeRefresh: SwipeRefreshLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_crypto_list)

        recyclerView = findViewById(R.id.rv_coins)
        progressBar = findViewById(R.id.progress_bar)
        tvError = findViewById(R.id.tv_error)
        swipeRefresh = findViewById(R.id.swipe_refresh)

        recyclerView.layoutManager = LinearLayoutManager(this)

        swipeRefresh.setOnRefreshListener {
            loadCoinData()
        }

        loadCoinData()
    }

    private fun loadCoinData() {
        // TODO: Replace this hardcoded data with Retrofit API call
        // Expected endpoint: GET https://api.coingecko.com/api/v3/coins/markets
        //   ?vs_currency=usd&order=market_cap_desc&per_page=20&page=1
        //
        // Error handling must cover at minimum:
        //   - no internet / network unavailable errors
        //   - server HTTP error responses (4xx, 5xx)
        //   - malformed or unexpected JSON response
        //   - connection timeout errors

        tvError.visibility = View.GONE

        val hardcodedCoins = listOf(
            CoinData("bitcoin", "Bitcoin", "BTC", 67234.50, 2.14, 1325000000000L, 32500000000.0, 19700000.0),
            CoinData("ethereum", "Ethereum", "ETH", 3521.80, -0.87, 423000000000L, 18200000000.0, 120200000.0),
            CoinData("binancecoin", "BNB", "BNB", 584.20, 1.23, 85600000000L, 2100000000.0, 146500000.0),
            CoinData("solana", "Solana", "SOL", 178.40, 5.67, 82000000000L, 4800000000.0, 456000000.0),
            CoinData("cardano", "Cardano", "ADA", 0.621, -1.54, 22100000000L, 890000000.0, 35600000000.0),
            CoinData("avalanche-2", "Avalanche", "AVAX", 38.92, 3.21, 15900000000L, 720000000.0, 408000000.0),
            CoinData("polkadot", "Polkadot", "DOT", 8.76, -0.43, 12100000000L, 450000000.0, 1380000000.0),
            CoinData("chainlink", "Chainlink", "LINK", 18.34, 4.89, 10900000000L, 580000000.0, 587100000.0)
        )

        swipeRefresh.isRefreshing = false
        recyclerView.adapter = CoinAdapter(hardcodedCoins)
    }
}
