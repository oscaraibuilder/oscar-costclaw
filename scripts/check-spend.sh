#!/bin/bash
# ============================================================
# CostClaw — OpenClaw Spend Monitor
# Version: 1.0.0 | clawaibuilder.com
# Tracks daily API spend per model, alerts on budget
# ============================================================

set -euo pipefail

# ── CONFIG ──────────────────────────────────────────────────
DAILY_BUDGET="${DAILY_BUDGET:-5.00}"
ALERT_THRESHOLD="0.80"          # Alert at 80% of budget
OPENCLAW_LOG_DIR="${OPENCLAW_LOG_DIR:-$HOME/.openclaw/logs}"
SPEND_LOG="${SPEND_LOG:-/tmp/costclaw-spend.json}"
TODAY=$(date -u +%Y-%m-%d)

# Telegram (optional) — set via env vars or hardcode below
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# ── MODEL PRICING (per 1M tokens) ───────────────────────────
# Format: "model_name:input_price:output_price"
declare -A MODEL_INPUT_PRICE
declare -A MODEL_OUTPUT_PRICE

MODEL_INPUT_PRICE["claude-sonnet-4-6"]="3.00"
MODEL_OUTPUT_PRICE["claude-sonnet-4-6"]="15.00"
MODEL_INPUT_PRICE["claude-sonnet-4-5"]="3.00"
MODEL_OUTPUT_PRICE["claude-sonnet-4-5"]="15.00"
MODEL_INPUT_PRICE["claude-opus-4"]="15.00"
MODEL_OUTPUT_PRICE["claude-opus-4"]="75.00"
MODEL_INPUT_PRICE["claude-haiku-3-5"]="0.80"
MODEL_OUTPUT_PRICE["claude-haiku-3-5"]="4.00"
MODEL_INPUT_PRICE["gpt-4o"]="2.50"
MODEL_OUTPUT_PRICE["gpt-4o"]="10.00"
MODEL_INPUT_PRICE["gpt-4o-mini"]="0.15"
MODEL_OUTPUT_PRICE["gpt-4o-mini"]="0.60"
MODEL_INPUT_PRICE["gpt-4.1"]="2.00"
MODEL_OUTPUT_PRICE["gpt-4.1"]="8.00"
MODEL_INPUT_PRICE["gemini-1.5-pro"]="1.25"
MODEL_OUTPUT_PRICE["gemini-1.5-pro"]="5.00"
MODEL_INPUT_PRICE["gemini-2.0-flash"]="0.10"
MODEL_OUTPUT_PRICE["gemini-2.0-flash"]="0.40"

# ── FUNCTIONS ────────────────────────────────────────────────

send_telegram() {
  local message="$1"
  if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -H "Content-Type: application/json" \
      -d "{\"chat_id\":\"${TELEGRAM_CHAT_ID}\",\"text\":\"${message}\",\"parse_mode\":\"Markdown\"}" \
      > /dev/null 2>&1 || true
  fi
}

bc_calc() {
  echo "scale=6; $1" | bc -l 2>/dev/null || echo "0"
}

# ── PARSE LOGS ───────────────────────────────────────────────
# Looks for JSON log lines with token usage data
# OpenClaw logs usage as: {"model":"...","usage":{"input_tokens":N,"output_tokens":N}}
# Adjust grep patterns to match your actual log format

declare -A TOTAL_INPUT
declare -A TOTAL_OUTPUT

if [[ ! -d "$OPENCLAW_LOG_DIR" ]]; then
  echo "⚠️  Log directory not found: $OPENCLAW_LOG_DIR"
  echo "   Set OPENCLAW_LOG_DIR env var or check your OpenClaw install."
  echo ""
fi

# Parse today's logs
LOG_FILES=$(find "$OPENCLAW_LOG_DIR" -name "*.log" -newer /tmp -type f 2>/dev/null || \
            find "$OPENCLAW_LOG_DIR" -name "*${TODAY}*.log" -type f 2>/dev/null || \
            ls "$OPENCLAW_LOG_DIR"/*.log 2>/dev/null || echo "")

if [[ -n "$LOG_FILES" ]]; then
  while IFS= read -r logfile; do
    [[ -z "$logfile" ]] && continue
    # Extract token usage lines (adjust pattern for your log format)
    grep -o '"model":"[^"]*","usage":{"input_tokens":[0-9]*,"output_tokens":[0-9]*}' "$logfile" 2>/dev/null | \
    while IFS= read -r line; do
      model=$(echo "$line" | grep -o '"model":"[^"]*"' | cut -d'"' -f4)
      input=$(echo "$line" | grep -o '"input_tokens":[0-9]*' | cut -d':' -f2)
      output=$(echo "$line" | grep -o '"output_tokens":[0-9]*' | cut -d':' -f2)
      echo "${model}:${input}:${output}"
    done
  done <<< "$LOG_FILES" | sort | awk -F: '{
    input[$1] += $2
    output[$1] += $3
  } END {
    for (m in input) print m ":" input[m] ":" output[m]
  }' > "$SPEND_LOG.tmp" 2>/dev/null || true
fi

# ── CALCULATE COSTS ──────────────────────────────────────────
echo ""
echo "=== CostClaw Daily Report — ${TODAY} ==="
echo ""

TOTAL_COST="0"
REPORT_LINES=""
HAS_DATA=false

if [[ -f "$SPEND_LOG.tmp" && -s "$SPEND_LOG.tmp" ]]; then
  while IFS=: read -r model input output; do
    [[ -z "$model" ]] && continue
    HAS_DATA=true
    
    in_price="${MODEL_INPUT_PRICE[$model]:-0.50}"
    out_price="${MODEL_OUTPUT_PRICE[$model]:-2.00}"
    
    # Cost = (tokens / 1,000,000) * price_per_million
    in_cost=$(bc_calc "${input} * ${in_price} / 1000000")
    out_cost=$(bc_calc "${output} * ${out_price} / 1000000")
    model_cost=$(bc_calc "${in_cost} + ${out_cost}")
    
    TOTAL_COST=$(bc_calc "${TOTAL_COST} + ${model_cost}")
    
    # Format nicely
    in_fmt=$(printf "%'d" "$input" 2>/dev/null || echo "$input")
    out_fmt=$(printf "%'d" "$output" 2>/dev/null || echo "$output")
    
    line=$(printf "%-28s Input: %10s tok  Output: %8s tok  Cost: \$%.4f\n" \
      "$model" "$in_fmt" "$out_fmt" "$model_cost")
    echo "$line"
    REPORT_LINES="${REPORT_LINES}\n${line}"
  done < "$SPEND_LOG.tmp"
  rm -f "$SPEND_LOG.tmp"
else
  echo "  No token usage data found for today."
  echo "  (Logs searched: $OPENCLAW_LOG_DIR)"
  echo ""
  echo "  💡 Tip: Make sure OpenClaw is logging token usage."
  echo "  Check: ls -la $OPENCLAW_LOG_DIR"
fi

# ── SUMMARY ──────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────────────"
printf "TOTAL TODAY:    \$%.4f\n" "$TOTAL_COST"
printf "DAILY BUDGET:   \$%.2f\n" "$DAILY_BUDGET"

# Calculate percentage
PCT=$(bc_calc "${TOTAL_COST} / ${DAILY_BUDGET} * 100" | cut -d'.' -f1)
PCT=${PCT:-0}

THRESHOLD_AMOUNT=$(bc_calc "${DAILY_BUDGET} * ${ALERT_THRESHOLD}")
OVER_BUDGET=$(bc_calc "${TOTAL_COST} >= ${DAILY_BUDGET}" | tr -d ' ')

if (( PCT >= 100 )); then
  STATUS="🚨 OVER BUDGET (${PCT}% used)"
  ALERT=true
elif (( PCT >= 80 )); then
  STATUS="⚠️  WARNING: ${PCT}% of budget used"
  ALERT=true
else
  STATUS="✅ ${PCT}% used — all good"
  ALERT=false
fi

echo "STATUS:         ${STATUS}"
echo "─────────────────────────────────────────────────────"
echo ""

# ── TELEGRAM ALERT ───────────────────────────────────────────
if [[ "$ALERT" == "true" ]]; then
  TELE_MSG="🦞 *CostClaw Alert* — ${TODAY}

💸 Spend: \$${TOTAL_COST} / \$${DAILY_BUDGET}
📊 Status: ${STATUS}

Check your OpenClaw agent — you're burning through budget."
  send_telegram "$TELE_MSG"
fi

# Daily summary to Telegram (optional — uncomment to enable)
# SUMMARY_MSG="🦞 *CostClaw Daily Summary* — ${TODAY}
# Total: \$${TOTAL_COST} | Budget: \$${DAILY_BUDGET}
# ${STATUS}"
# send_telegram "$SUMMARY_MSG"

# ── SAVE HISTORY ─────────────────────────────────────────────
HISTORY_FILE="/tmp/costclaw-history.log"
echo "${TODAY}|${TOTAL_COST}|${DAILY_BUDGET}|${PCT}%" >> "$HISTORY_FILE" 2>/dev/null || true

echo "💡 To enable Telegram alerts: export TELEGRAM_TOKEN=xxx TELEGRAM_CHAT_ID=yyy"
echo "💡 To change budget: export DAILY_BUDGET=10.00"
echo "📖 Docs + setup help: https://clawaibuilder.com"
echo ""
