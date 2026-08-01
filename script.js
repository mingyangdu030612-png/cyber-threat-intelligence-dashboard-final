// API Gateway endpoint created by Terraform (see `api_endpoint` output in main.tf)
const API_URL = "https://1680czogh3.execute-api.us-east-1.amazonaws.com/news";

const refreshBtn = document.getElementById("refreshBtn");
const refreshIcon = document.getElementById("refreshIcon");
const statusLine = document.getElementById("statusLine");
const loadingState = document.getElementById("loadingState");
const errorState = document.getElementById("errorState");
const errorMessage = document.getElementById("errorMessage");
const newsGrid = document.getElementById("newsGrid");

function setLoading(isLoading) {
  refreshBtn.disabled = isLoading;
  refreshIcon.classList.toggle("spin", isLoading);
  loadingState.hidden = !isLoading;
  if (isLoading) {
    errorState.hidden = true;
    newsGrid.innerHTML = "";
    statusLine.hidden = true;
  }
}

function showError(message) {
  errorState.hidden = false;
  errorMessage.textContent = message;
}

function formatDate(value) {
  if (!value) {
    return "Unknown date";
  }
  const parsed = new Date(value);
  if (isNaN(parsed.getTime())) {
    return value;
  }
  return parsed.toLocaleString("en-GB", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false
  });
}

function dedupeByTitle(articles) {
  if (!Array.isArray(articles)) {
    return articles;
  }
  const seenTitles = new Set();
  return articles.filter((article) => {
    const title = article.title || "";
    if (seenTitles.has(title)) {
      return false;
    }
    seenTitles.add(title);
    return true;
  });
}

function renderArticles(articles) {
  newsGrid.innerHTML = "";

  if (!Array.isArray(articles) || articles.length === 0) {
    newsGrid.innerHTML = '<p class="empty-state">No news articles available right now.</p>';
    return;
  }

  articles.forEach((article) => {
    const title = article.title || "Untitled article";
    const source = article.source || "Unknown source";
    const publishedAt = formatDate(article.publishedAt);
    const url = article.url;

    const card = document.createElement("article");
    card.className = "news-card";

    card.innerHTML = `
      <h2 class="news-card-title"></h2>
      <div class="news-card-meta">
        <span class="news-source"></span>
        <span class="news-date"></span>
      </div>
    `;

    card.querySelector(".news-card-title").textContent = title;
    card.querySelector(".news-source").textContent = source;
    card.querySelector(".news-date").textContent = publishedAt;

    if (url) {
      const link = document.createElement("a");
      link.className = "news-card-link";
      link.href = url;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.textContent = "Read More →";
      card.appendChild(link);
    }

    newsGrid.appendChild(card);
  });

  statusLine.hidden = false;
  statusLine.textContent = `Showing ${articles.length} article${articles.length === 1 ? "" : "s"} • Last updated ${new Date().toLocaleTimeString()}`;
}

async function loadNews() {
  setLoading(true);

  try {
    const response = await fetch(API_URL, { method: "GET" });
    const contentType = response.headers.get("content-type") || "";

    if (!contentType.includes("application/json")) {
      throw new Error(`Unexpected response type from API (status ${response.status}).`);
    }

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.message || `API returned status ${response.status}.`);
    }

    setLoading(false);
    renderArticles(dedupeByTitle(data.articles));
  } catch (err) {
    setLoading(false);
    if (err instanceof TypeError) {
      showError("Could not reach the API. Check your network connection or the API Gateway URL/CORS settings.");
    } else {
      showError(err.message || "An unexpected error occurred while loading news.");
    }
  }
}

refreshBtn.addEventListener("click", loadNews);
document.addEventListener("DOMContentLoaded", loadNews);
