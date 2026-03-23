# CostClaw — OpenClaw Spend Monitor

**Version:** 1.0.0  
**Author:** Oscar (clawaibuilder.com)  
**License:** Free  
**Tagline:** Know what your AI agent costs. Before it costs you.

---

## What This Skill Does

CostClaw tracks your daily API spend per model, warns you when you're approaching your budget, and delivers a clean daily summary — directly to your Telegram or terminal.

No hidden fees. No subscriptions. Just visibility.

---

## Prerequisites

- OpenClaw installed and running
- `jq` installed (`apt install jq` or `brew install jq`)
- OpenClaw log files accessible at `~/.openclaw/logs/` (default location)
- Optional: Telegram bot token + chat_id for alerts

---

## Setup

1. Copy `scripts/check-spend.sh` to your workspace or anywhere executable:
   ```bash
   cp scripts/check-spend.sh ~/check-spend.sh
   chmod +x ~/check-spend.sh
   ```

2. Set your budget (default: $5/day). Edit the `DAILY_BUDGET` variable in `check-spend.sh`.

3. Optional — add your Telegram credentials for alerts:
   ```bash
   export TELEGRAM_TOKEN="your_bot_token"
   export TELEGRAM_CHAT_ID="your_chat_id"
   ```

4. Run manually:
   ```bash
   ./check-spend.sh
   ```

5. Schedule daily (via OpenClaw cron or crontab):
   ```
   # Run at 8am UTC daily
   0 8 * * * /root/check-spend.sh >> /tmp/costclaw.log 2>&1
   ```

---

## How It Works

CostClaw reads your OpenClaw session logs and parses token usage + model metadata. It calculates estimated cost using standard model pricing, then:

- Shows spend **per model** for today
- Shows **total daily spend**
- Compares against your `DAILY_BUDGET`
- Fires an alert if you're **over 80% of budget**
- Sends a Telegram message if credentials are set

---

## Model Pricing Reference (as of March 2026)

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|---|---|---|
| claude-sonnet-4-6 | $3.00 | $15.00 |
| claude-opus-4 | $15.00 | $75.00 |
| gpt-4o | $2.50 | $10.00 |
| gpt-4o-mini | $0.15 | $0.60 |
| gemini-1.5-pro | $1.25 | $5.00 |

Update the pricing array in `check-spend.sh` to match current rates.

---

## Output Example

```
=== CostClaw Daily Report — 2026-03-23 ===
claude-sonnet-4-6    Input: 142,000 tok  Output: 18,500 tok  Cost: $0.70
gpt-4o-mini          Input:  28,000 tok  Output:  4,200 tok  Cost: $0.007
─────────────────────────────────────────
TOTAL TODAY: $0.71
DAILY BUDGET: $5.00
STATUS: ✅ 14% used — all good
```

---

## Alert Thresholds

| Threshold | Action |
|---|---|
| < 80% of budget | ✅ Green — no alert |
| 80–99% of budget | ⚠️ Warning — Telegram alert sent |
| ≥ 100% of budget | 🚨 Over budget — Telegram alert sent |

---

## Need Help Setting This Up?

👉 **[clawaibuilder.com](https://clawaibuilder.com)** — We set up OpenClaw agents for you. Done-for-you setup, configured overnight.

---

## Changelog

- **1.0.0** — Initial release. Daily spend tracking, per-model breakdown, Telegram alerts.
