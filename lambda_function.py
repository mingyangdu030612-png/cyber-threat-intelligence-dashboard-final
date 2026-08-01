import hashlib
import json
import urllib.error
import urllib.parse
import urllib.request

import boto3
from botocore.exceptions import ClientError

NEWS_TABLE_NAME = "cti-news-table"

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
}


def respond(status_code, body_dict):
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": json.dumps(body_dict)
    }


def save_articles_to_dynamodb(articles):
    table = boto3.resource("dynamodb", region_name="us-east-1").Table(NEWS_TABLE_NAME)

    for article in articles:
        url = article.get("url")
        if not url:
            continue

        news_id = hashlib.sha256(url.encode("utf-8")).hexdigest()

        try:
            table.put_item(
                Item={
                    "news_id": news_id,
                    "title": article.get("title"),
                    "source": article.get("source"),
                    "publishedAt": article.get("publishedAt"),
                    "url": url
                },
                ConditionExpression="attribute_not_exists(news_id)"
            )
        except ClientError:
            # Conditional check failure means the item already exists (duplicate
            # news); other client errors are also swallowed so history-saving
            # issues never break the news response.
            continue


def lambda_handler(event, context):
    try:
        client = boto3.client(
            "secretsmanager",
            region_name="us-east-1"
        )

        secret = client.get_secret_value(
            SecretId="news-api-key"
        )

        secret_data = json.loads(secret["SecretString"])
        api_key = secret_data["api_key"]

        parameters = urllib.parse.urlencode({
            "q": "cybersecurity OR ransomware OR malware OR CVE OR phishing",
            "language": "en",
            "pageSize": 5,
            "sortBy": "publishedAt",
            "apiKey": api_key
        })

        url = "https://newsapi.org/v2/everything?" + parameters

        with urllib.request.urlopen(url, timeout=10) as response:
            news_data = json.loads(response.read().decode("utf-8"))

        articles = []

        for article in news_data.get("articles", []):
            articles.append({
                "title": article.get("title"),
                "source": article.get("source", {}).get("name"),
                "publishedAt": article.get("publishedAt"),
                "url": article.get("url")
            })

        save_articles_to_dynamodb(articles)

        return respond(200, {
            "message": "Cybersecurity news retrieved successfully",
            "articles": articles
        })

    except urllib.error.URLError:
        return respond(502, {
            "message": "Failed to reach NewsAPI",
            "articles": []
        })

    except Exception:
        return respond(500, {
            "message": "Internal server error while fetching news",
            "articles": []
        })
