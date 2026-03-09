package com.example.cryptotracker.ui

import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.example.cryptotracker.R
import com.example.cryptotracker.model.CoinData

class CoinAdapter(private val coins: List<CoinData>) :
    RecyclerView.Adapter<CoinAdapter.CoinViewHolder>() {

    class CoinViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val tvName: TextView = view.findViewById(R.id.tv_coin_name)
        val tvSymbol: TextView = view.findViewById(R.id.tv_coin_symbol)
        val tvPrice: TextView = view.findViewById(R.id.tv_coin_price)
        val tvChange: TextView = view.findViewById(R.id.tv_price_change)
        val tvMarketCap: TextView = view.findViewById(R.id.tv_market_cap)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): CoinViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_coin, parent, false)
        return CoinViewHolder(view)
    }

    override fun onBindViewHolder(holder: CoinViewHolder, position: Int) {
        val coin = coins[position]
        holder.tvName.text = coin.name
        holder.tvSymbol.text = coin.symbol.uppercase()
        holder.tvPrice.text = coin.formattedPrice()
        holder.tvMarketCap.text = "MCap: ${coin.formattedMarketCap()}"

        val changeText = "${if (coin.isPriceUp) "+" else ""}${String.format("%.2f", coin.priceChangePercent24h)}%"
        holder.tvChange.text = changeText
        holder.tvChange.setTextColor(if (coin.isPriceUp) Color.parseColor("#4CAF50") else Color.parseColor("#F44336"))
    }

    override fun getItemCount() = coins.size
}
