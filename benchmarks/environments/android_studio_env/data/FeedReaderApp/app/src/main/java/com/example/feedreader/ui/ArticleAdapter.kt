package com.example.feedreader.ui

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.example.feedreader.R
import com.example.feedreader.model.Article

class ArticleAdapter(
    private val articles: List<Article>,
    private val onArticleClick: (Article) -> Unit
) : RecyclerView.Adapter<ArticleAdapter.ArticleViewHolder>() {

    class ArticleViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val tvTitle: TextView = view.findViewById(R.id.tv_article_title)
        val tvSummary: TextView = view.findViewById(R.id.tv_article_summary)
        val tvAuthor: TextView = view.findViewById(R.id.tv_article_author)
        val tvCategory: TextView = view.findViewById(R.id.tv_article_category)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ArticleViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_article, parent, false)
        return ArticleViewHolder(view)
    }

    override fun onBindViewHolder(holder: ArticleViewHolder, position: Int) {
        val article = articles[position]
        holder.tvTitle.text = article.title
        holder.tvSummary.text = article.summary
        holder.tvAuthor.text = "By ${article.author}"
        holder.tvCategory.text = article.category.uppercase()
        holder.itemView.setOnClickListener { onArticleClick(article) }
    }

    override fun getItemCount() = articles.size
}
