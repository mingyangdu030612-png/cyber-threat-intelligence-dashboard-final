# Cyber Threat Intelligence Dashboard

A serverless AWS application that aggregates the latest cybersecurity news and displays it through a lightweight static dashboard. Built as an AWS Academy Capstone project.

**Live API:** `https://1680czogh3.execute-api.us-east-1.amazonaws.com/news`

**Live UI (demo environment):** `http://cti-news-dashboard-698578465771.s3-website-us-east-1.amazonaws.com`

## Project Overview

This project fetches the latest cybersecurity-related news (ransomware, malware, CVEs, phishing, etc.) from [NewsAPI](https://newsapi.org) through a serverless backend on AWS, and presents it in a simple, professional dashboard UI.

The goal of this Capstone project is to demonstrate a working end-to-end serverless architecture on AWS — API Gateway, Lambda, Secrets Manager, and DynamoDB — deployed with Terraform, paired with a framework-free front end.

## Architecture

```
 Browser (dashboard hosted on Amazon S3 — Static Website Hosting)
        |
        |  GET /news  (fetch, CORS)
        v
 API Gateway (HTTP API v2)
        |
        |  AWS_PROXY integration
        v
 AWS Lambda (Python 3.12)
        |
        |-- Secrets Manager  --> retrieves NewsAPI key
        |-- NewsAPI (external HTTPS call)
        |-- DynamoDB            --> saves each article as history (dedup by URL hash)
        v
 JSON response (title, source, publishedAt, url)
```

The stack is fully serverless: there is no server to manage, and cost is incurred only per request.

## AWS Services

| Service | Role |
|---|---|
| **AWS Lambda** | Runs the Python backend logic: retrieves the NewsAPI key, calls NewsAPI, transforms the response, saves each article to DynamoDB, returns JSON. |
| **API Gateway (HTTP API v2)** | Public HTTPS entry point (`GET /news`). Handles CORS declaratively so the browser can call it directly. |
| **Secrets Manager** | Stores the NewsAPI key outside of source code and Terraform state. |
| **DynamoDB** | Lightweight history log (`cti-news-table`) of every article the Lambda has ever fetched. Each item's key is a SHA-256 hash of the article URL, so re-fetching the same article on a later refresh does not create a duplicate row. Write-only from the API's perspective — `GET /news` always returns the latest 5 articles from NewsAPI directly, never reads from DynamoDB. |
| **Amazon S3 (Static Website Hosting)** | Hosts the dashboard's static frontend (`index.html`, `style.css`, `script.js`) as the demo environment — replaces the earlier GitHub Pages / `localhost:8000` setup. The bucket allows public, read-only (`s3:GetObject`) access via a bucket policy; no server-side rendering or build step is involved. |
| **IAM (LabRole)** | The pre-provisioned AWS Academy Learner Lab role is reused for the Lambda execution role — no custom IAM roles/policies are created, per Learner Lab constraints. |

## Project Structure

```
./
├── main.tf                 # Terraform: all AWS resources
├── lambda_function.py      # Lambda source code
├── .terraform.lock.hcl     # Terraform provider version lock
├── index.html               # Root-level copy of the UI, uploaded to S3 by Terraform
├── style.css                # (identical to ui/style.css)
├── script.js                 # (identical to ui/script.js)
├── ui/
│   ├── index.html           # Dashboard markup (used for local development)
│   ├── style.css             # AWS-console-inspired styling
│   └── script.js              # Fetches the API, renders news cards
├── .gitignore
└── README.md
```

The UI exists in two identical locations on purpose: `ui/` is used for local development (see [How to Run the UI](#how-to-run-the-ui)), and the root-level copy is what Terraform uploads to the S3 demo bucket (see [Amazon S3 Static Website Hosting Deployment](#amazon-s3-static-website-hosting-deployment)). If you edit the UI, apply the same change to both copies.

Files such as `.terraform/`, `terraform.tfstate*`, and `lambda.zip` are generated locally by Terraform/the packaging step and are intentionally excluded from version control (see [Security Considerations](#security-considerations)).

## Prerequisites

- An **AWS Academy Learner Lab** session (or any AWS account with an equivalent IAM role) with active credentials.
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- A free [NewsAPI](https://newsapi.org) API key
- Python 3.12 (only needed if you modify `lambda_function.py`; no dependencies beyond `boto3`, which is preinstalled in the Lambda runtime)

## Deployment

1. **Configure AWS credentials** (Learner Lab credentials expire periodically — copy fresh ones into `~/.aws/credentials` under `[default]` when they expire).

2. **Create the Secrets Manager secret value** (Terraform only creates the secret container, not the value, so it is never stored in state):
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id news-api-key \
     --secret-string '{"api_key":"<YOUR_NEWSAPI_KEY>"}'
   ```

3. **Package the Lambda function:**
   ```powershell
   Compress-Archive -Path lambda_function.py -DestinationPath lambda.zip
   ```

4. **Deploy with Terraform:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```
   This provisions the backend (Lambda, API Gateway, Secrets Manager, DynamoDB) **and** uploads the frontend to the S3 demo bucket in one step. The API endpoint is printed as the `api_endpoint` output, and the dashboard URL is printed as the `website_url` output.

5. **Redeploying after a code change:** re-zip `lambda_function.py` and/or edit `index.html` / `style.css` / `script.js` at the repository root, then run `terraform apply` again — Terraform detects Lambda changes via `source_code_hash` and frontend file changes via each `aws_s3_object`'s `etag`.

## How to Run the UI

The UI is plain HTML/CSS/JS with no build step. Because it calls a remote API with `fetch()`, serve it over HTTP rather than opening the file directly:

```bash
cd ui
python -m http.server 8000
```

Then open `http://localhost:8000` in a browser. The dashboard loads news automatically and can be refreshed with the **Refresh News** button.

This `localhost` server is for local development only. The final demo environment is the Amazon S3 URL above, not `localhost` (see [Amazon S3 Static Website Hosting Deployment](#amazon-s3-static-website-hosting-deployment)).

If you deploy your own copy of the backend, update the `API_URL` constant at the top of `ui/script.js` **and** the root-level `script.js` (see [Amazon S3 Static Website Hosting Deployment](#amazon-s3-static-website-hosting-deployment)).

## Amazon S3 Static Website Hosting Deployment

The final demo environment is **Amazon S3 Static Website Hosting**, not `localhost` and not GitHub Pages. The repository root already contains `index.html`, `style.css`, and `script.js` (identical copies of the files in `ui/`), and `main.tf` manages the S3 bucket and uploads these three files as part of the normal `terraform apply` (see [Deployment](#deployment)):

- `aws_s3_bucket` — the demo bucket (`cti-news-dashboard-<AWS account ID>`, globally unique per account).
- `aws_s3_bucket_ownership_controls` (`BucketOwnerEnforced`) + `aws_s3_bucket_public_access_block` (all four block settings disabled) — required so the bucket policy below can actually grant public read access.
- `aws_s3_bucket_policy` — allows anonymous `s3:GetObject` on the bucket's objects only (no write/delete, no bucket-level permissions).
- `aws_s3_bucket_website_configuration` — serves `index.html` as both the index and error document.
- `aws_s3_object` (×3) — uploads `index.html`, `style.css`, `script.js`; Terraform re-uploads a file automatically when its content changes (tracked via `etag = filemd5(...)`).

After `terraform apply`, the dashboard is live at the URL printed in the `website_url` output, e.g.:
```
http://cti-news-dashboard-698578465771.s3-website-us-east-1.amazonaws.com
```

No IAM roles or policies are created for this — the bucket policy is a resource policy on the bucket itself, consistent with the Learner Lab constraint of reusing `LabRole` and not creating IAM entities (see [AWS Services](#aws-services)).

The `ui/` folder is unaffected and keeps working for local development exactly as described above.

## Security Considerations

- The NewsAPI key is stored in **AWS Secrets Manager** and is never hardcoded in source code, Terraform files, or state.
- The Lambda execution role reuses the **pre-provisioned `LabRole`** — no custom IAM roles or policies are created, consistent with AWS Academy Learner Lab restrictions.
- CORS is scoped to `GET`/`OPTIONS` only. `Access-Control-Allow-Origin: *` is used because the API only exposes public, read-only news data — there is no user data, authentication, or state-changing operation behind it.
- The S3 demo bucket's public-read policy grants `s3:GetObject` only (no listing, write, or delete), and only on the three static frontend files — appropriate since they contain no secrets or user data. `Block Public Access` is disabled only at the bucket level (not the account level), scoped to this bucket alone.
- `terraform.tfstate`, `.terraform/`, and `lambda.zip` are excluded from version control via `.gitignore`. State files can contain account IDs and resource ARNs and should never be committed.
- AWS credentials are never stored in this repository; they live only in the local `~/.aws/credentials` file, outside the project directory.

## Current Limitations

- **DynamoDB is write-only.** The dashboard always displays the latest 5 articles returned directly by NewsAPI; nothing is ever read back from `cti-news-table`. It exists purely as a history log for this Capstone project.
- **No automated tests** for the Lambda function or the front end.
- **No CI/CD pipeline** — deployment is manual (`terraform apply`), which is appropriate for a single-presenter Capstone demo but not for a team/production setting.
- **AWS Academy Learner Lab sessions expire periodically**, requiring credentials to be refreshed manually before running Terraform commands.
- **Single region, single environment** (`us-east-1`) — no staging/production separation.
- **The UI is duplicated** (`ui/` and repository root); the two copies must be kept in sync manually.
- **The S3 website endpoint is HTTP only** (no TLS/custom domain) — the S3 Static Website Hosting feature does not support HTTPS directly. This does not block the dashboard (fetching an HTTPS API from an HTTP page is not blocked as mixed content), but the URL itself is not `https://`. Adding CloudFront in front of the bucket would be the next step if an HTTPS demo URL is required.

## Future Improvements

- Add unit tests for `lambda_function.py` (mocking Secrets Manager, NewsAPI, and DynamoDB calls).
- Add a small script or page to browse the saved DynamoDB history, if a future assignment calls for it.
