# DeepSeek Harness — Cost Optimization Guide

This setup is configured to give you the highest possible performance while keeping operational costs near zero.

## 1. Zero-Cost Baseline
- **DeepSeek Harness Desktop App**: 100% Free to install and run.
- **Memory Plugin (EverOS + GBrain)**: 100% Free, open source, zero external npm dependencies.
- **Session Sanitizer Tool**: Included free, prevents session format corruption locally.

## 2. Model Tier Breakdown

| Model / Service | Role in Config | Cost Profile | How to Use |
| :--- | :--- | :--- | :--- |
| **DeepSeek Account (Direct)** | Default Primary Engine (`deepseek-flash`) | Extremely low (~$0.07 / 1M input tokens, ~$0.28 / 1M output tokens). High reasoning performance with 90%+ cache hit discount. | Sign in to DeepSeek inside the app UI on first launch. |
| **Ollama Cloud Pro** | Fallback #1, #2, #3 + Research Synthesis | Free tier available / pay-as-you-go. Fallbacks include DeepSeek V4.1 Flash, GLM 5.3 Flash, MiniMax M3.1 Flash, and Kimi K2.7 Code. | Set `OLLAMA_API_KEY` in environment variables or when prompted during `setup.ps1`. |
| **Self-Hosted Ollama (Local)** | Unlimited Local Fallback | 100% Free if you have a local GPU. | Change `baseURL` in `cordis.patch.yml` to `http://localhost:11434/v1`. |

## 3. Estimated Monthly Budget
- **Light / Moderate Developer Workflow**: **$0.50 – $3.00 / month** on direct DeepSeek API tokens.
- **Heavy Agent Swarms & Coding Loops**: **$5.00 – $15.00 / month**.
- Compared to standard commercial agents ($20–$40/mo per seat), this setup saves ~80–90% on API overhead through prompt caching and selective fallback routing.
