#!/bin/bash -l
set -euo pipefail

# Set PATH for cron
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

# Credit Header
# Crafted by @chieb_sol vibecoding with @grok
# Script to measure Bitcoin block propagation delays and send a Telegram summary - v2 with corrections to error handling, block delays and average calcs
# Designed for Bitcoin Knots on Umbrel (Docker)
# Outputs Propagation.log (CSV), Propagation.json (JSON), Debug.log (text)
# Sends a preformatted Telegram message with summary, highlights, and stats
# Dependencies: jq, curl, bc, awk, get_miner.sh
# Recommended NUM_BLOCKS: Minimum 5, Maximum 100 for optimal analysis
# Despite log checks, it's advisable to manually create the logs directory before attempting to run the code:  mkdir ~/logs/block_delay.
# If the code fails to run, most likely the logs directory is missing!
# Ensure that file is executable: chmod +x ~/block_delay.sh (+ do the same for get_miner.sh)
# test: ./get_block.sh <block number> i.e. ./block.sh 5
# test: ./get_miner.sh <block number> i.e. ./get_miner.sh 895802 (or some recent block validated by your node)
# after testing apply block_delay.sh as a cronjob. Recommend 50 blocks for overnight analysis run in the morning, and 100 blocks for full day run in late evening


# Ensure log directory exists before anything else
LOG_DIR="$HOME/logs/block_delay"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
ERROR_LOG="$LOG_DIR/error.log"


# Configuration
NUM_BLOCKS=${NUM_BLOCKS:-5}
TELEGRAM_CHAT_ID="your_chat_id"
TELEGRAM_BOT_TOKEN="your_bot_token"
ATTACH_PROPAGATION_LOG="NO"  # Attach Propagation log in CSV format to telegram (YES/NO)
ATTACH_PROPAGATION_JSON="NO" # Attach Propagation log in JOSON format to telegram (YES/NO
ATTACH_DEBUG_LOG="NO"        # Attach Debug log to telegram (YES/NO)
RECYCLE_LOGS_HOURS=336
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

check_dependencies() {
  for cmd in jq curl bc awk docker; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "[$TIMESTAMP] Error: $cmd is required but not found." >>"$ERROR_LOG"
      send_telegram_message "Error: $cmd not found at $TIMESTAMP!" "$ERROR_LOG"
      exit 1
    fi
  done
}

escape_md() {
  local input="$1"
  echo "$input" | sed 's/[][(){}#+=|!_.*^~`>\\-]/\\&/g' | \
    sed 's/[<]/\\&/g' | \
    sed 's/[[:space:]]\+/ /g' | \
    sed 's/[≤≥]/\\&/g' | \
    sed 's/\.\.\./\\.../g'
}

send_telegram_message() {
  local message="$1"
  local error_log="$2"
  local retries=3
  local attempt=1

  if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "[$TIMESTAMP] Error: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is empty" >>"$error_log"
    return 1
  fi

  if [ ${#message} -gt 4096 ]; then
    echo "[$TIMESTAMP] Error: Message length (${#message} chars) exceeds Telegram's 4096-char limit" >>"$error_log"
    return 1
  fi

  echo "[$TIMESTAMP] Preparing to send Telegram message (length: ${#message} chars)" >>"$error_log"
  echo "[$TIMESTAMP] Message content:" >>"$error_log"
  echo "$message" >>"$error_log"

  while [ $attempt -le $retries ]; do
    echo "[$TIMESTAMP] Sending Telegram message (attempt $attempt) at $(date -u)" >>"$error_log"
    local response=$(curl -s -w "\n%{http_code}" -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID" \
      -d parse_mode="MarkdownV2" \
      -d text="$message" 2>>"$error_log")
    local http_code=$(echo "$response" | tail -n 1)
    local response_body=$(echo "$response" | sed '$d')
    local curl_exit_code=$?

    echo "[$TIMESTAMP] curl exit code: $curl_exit_code, HTTP code: $http_code" >>"$error_log"
    echo "[$TIMESTAMP] curl response body: $response_body" >>"$error_log"

    if [ $curl_exit_code -eq 0 ] && [ "$http_code" -eq 200 ]; then
      echo "[$TIMESTAMP] Telegram message sent successfully" >>"$error_log"
      return 0
    else
      echo "[$TIMESTAMP] Failed to send Telegram message (attempt $attempt)" >>"$error_log"
      attempt=$((attempt + 1))
      sleep 2
    fi
  done

  echo "[$TIMESTAMP] Failed to send Telegram message after $retries attempts" >>"$error_log"
  return 1
}

send_telegram_document() {
  local file="$1"
  local error_log="$2"
  echo "[$TIMESTAMP] Sending Telegram document: $file at $(date -u)" >>"$error_log"
  curl -s -F document=@"$file" \
    "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument?chat_id=$TELEGRAM_CHAT_ID" >>"$error_log" 2>&1
  local curl_exit_code=$?
  echo "[$TIMESTAMP] curl exit code for sendDocument: $curl_exit_code" >>"$error_log"
  if [ $curl_exit_code -ne 0 ]; then
    echo "[$TIMESTAMP] Failed to send Telegram document $file at $(date -u)" >>"$error_log"
  fi
}

recycle_logs() {
  local log_dir="$1"
  local error_log="$2"
  local current_time=$(date +%s)
  local hours_since_reset last_reset

  recycle_log() {
    local log_file="$1"
    local reset_file="$2"
    local recycle_hours="$3"
    if [ "$recycle_hours" -gt 0 ]; then
      if [ ! -f "$reset_file" ]; then
        echo "$current_time" > "$reset_file"
        echo "[$TIMESTAMP] Created reset file $reset_file with timestamp $current_time" >>"$error_log"
      fi
      last_reset=$(cat "$reset_file" 2>/dev/null || echo 0)
      if ! [[ "$last_reset" =~ ^[0-9]+$ ]]; then
        last_reset=0
        echo "[$TIMESTAMP] Warning: Invalid last_reset in $reset_file, setting to 0" >>"$error_log"
      fi
      hours_since_reset=$(( (current_time - last_reset) / 3600 ))
      if [ "$hours_since_reset" -ge "$recycle_hours" ]; then
        if [ -f "$log_file" ]; then
          : > "$log_file"
          chmod 644 "$log_file"
          echo "[$TIMESTAMP] Recycled $log_file (age: $hours_since_reset hours)" >>"$error_log"
        fi
        echo "$current_time" > "$reset_file"
      fi
    fi
  }

  if ! [[ "$RECYCLE_LOGS_HOURS" =~ ^[0-9]+$ ]]; then
    echo "[$TIMESTAMP] Warning: Invalid RECYCLE_LOGS_HOURS ($RECYCLE_LOGS_HOURS). Using 336 hours." >>"$error_log"
    RECYCLE_LOGS_HOURS=336
  fi

  recycle_log "$log_dir/Propagation.log" "$log_dir/propagation_reset.txt" "$RECYCLE_LOGS_HOURS"
  recycle_log "$log_dir/Propagation.json" "$log_dir/propagation_json_reset.txt" "$RECYCLE_LOGS_HOURS"
  recycle_log "$log_dir/Debug.log" "$log_dir/debug_reset.txt" "$RECYCLE_LOGS_HOURS"
}

# Ensure log directory exists
check_dependencies
rm -f "$LOG_DIR/Propagation.log" "$LOG_DIR/Propagation.json" "$LOG_DIR/Debug.log"

CURRENT_BLOCK=$(docker exec bitcoin-knots_bitcoind_1 bitcoin-cli getblockcount 2>>"$ERROR_LOG")
if [ -z "$CURRENT_BLOCK" ]; then
  echo "[$TIMESTAMP] Error: Failed to get block height. Is bitcoind running?" >>"$ERROR_LOG"
  send_telegram_message "Error: Failed to get block height at $TIMESTAMP!" "$ERROR_LOG"
  exit 1
fi
TIP_BLOCK=$(curl -s https://mempool.space/api/blocks/tip/height 2>>"$ERROR_LOG")
if [ -n "$TIP_BLOCK" ] && [ "$CURRENT_BLOCK" -lt "$TIP_BLOCK" ]; then
  echo "[$TIMESTAMP] Error: Node not synced (local: $CURRENT_BLOCK, network: $TIP_BLOCK)" >>"$ERROR_LOG"
  send_telegram_message "Error: Node not synced at $TIMESTAMP!" "$ERROR_LOG"
  exit 1
fi

MINER_SCRIPT="$HOME/get_miner.sh"
if [ ! -x "$MINER_SCRIPT" ]; then
  echo "[$TIMESTAMP] Error: $MINER_SCRIPT not found or not executable." >>"$ERROR_LOG"
  send_telegram_message "Error: $MINER_SCRIPT not found at $TIMESTAMP!" "$ERROR_LOG"
  exit 1
fi

if [ $# -eq 1 ]; then
  NUM_BLOCKS=$1
  if ! [[ "$NUM_BLOCKS" =~ ^[0-9]+$ ]] || [ "$NUM_BLOCKS" -lt 1 ]; then
    echo "[$TIMESTAMP] Error: NUM_BLOCKS must be a positive integer." >>"$ERROR_LOG"
    send_telegram_message "Error: Invalid NUM_BLOCKS ($NUM_BLOCKS) at $TIMESTAMP!" "$ERROR_LOG"
    exit 1
  fi
fi

END_BLOCK=$CURRENT_BLOCK
START_BLOCK=$((END_BLOCK - NUM_BLOCKS + 1))
echo "[$TIMESTAMP] Capturing blocks $START_BLOCK to $END_BLOCK..." >>"$ERROR_LOG"

TEMP_LOG=$(mktemp)
docker logs bitcoin-knots_bitcoind_1 > "$TEMP_LOG" 2>>"$ERROR_LOG"

cat << EOF > "$LOG_DIR/Propagation.log"
### Propagation.log Start ###
# Generated: $TIMESTAMP
# Block Range: $START_BLOCK to $END_BLOCK
# Description: Block propagation data with precomputed delays and miner name
# AI Instructions:
# - Output this table verbatim as-is, with no analysis, calculations, or modifications.
# - Parse as a space-delimited table with exactly 9 columns.
# - Columns: block (integer), mined_time (ISO 8601 or N/A), external_mined_time (ISO 8601 or N/A), header_time (ISO 8601 or N/A), validation_time (ISO 8601 or N/A), mined_to_header_delay_(s) (integer seconds or N/A), mined_to_validation_delay_(s) (integer seconds or N/A), compact_flag (Yes/No), miner_name (string or Unknown).
# - Use mined_to_header_delay_(s) and mined_to_validation_delay_(s) directly as provided; do NOT recalculate delays.
# - Treat N/A as a string for non-timestamp columns.
# - miner_name may contain underscores (e.g., Mining_Squared) for CSV compatibility.
# - Example row: 892561 2025-04-15T15:43:03Z 2025-04-15T15:43:03Z 2025-04-15T15:43:42Z 2025-04-15T15:43:43Z 39 40 Yes AntPool
block mined_time external_mined_time header_time validation_time mined_to_header_delay_(s) mined_to_validation_delay_(s) compact_flag miner_name
EOF
chmod 644 "$LOG_DIR/Propagation.log"

cat << EOF > "$LOG_DIR/Propagation.json"
{
  "metadata": {
    "generated": "$TIMESTAMP",
    "block_range": "$START_BLOCK to $END_BLOCK",
    "description": "Block propagation data with precomputed delays and miner name",
    "ai_instructions": [
      "Parse as JSON array of objects under 'blocks' key.",
      "Each object contains: block (integer), mined_time (ISO 8601 or 'N/A'), external_mined_time (ISO 8601 or 'N/A'), header_time (ISO 8601 or 'N/A'), validation_time (ISO 8601 or 'N/A'), mined_to_header_delay_s (integer or 'N/A'), mined_to_validation_delay_s (integer or 'N/A'), compact_flag ('Yes'/'No'), miner_name (string or 'Unknown').",
      "Use mined_to_header_delay_s and mined_to_validation_delay_s directly; do NOT recalculate delays.",
      "Treat 'N/A' as a string for non-timestamp fields.",
      "Example object: {'block': 892561, 'mined_time': '2025-04-15T15:43:03Z', 'external_mined_time': '2025-04-15T15:43:03Z', 'header_time': '2025-04-15T15:43:42Z', 'validation_time': '2025-04-15T15:43:43Z', 'mined_to_header_delay_s': 39, 'mined_to_validation_delay_s': 40, 'compact_flag': 'Yes', 'miner_name': 'AntPool'}"
    ]
  },
  "blocks": []
}
EOF
chmod 644 "$LOG_DIR/Propagation.json"

cat << EOF > "$LOG_DIR/Debug.log"
### Debug.log Start ###
# Generated: $TIMESTAMP
# Block Range: $START_BLOCK to $END_BLOCK
# Description: Debug messages for missing data or errors, including miner name extraction
# AI Instructions:
# - Do not parse; treat as freeform text for reference only.
EOF
chmod 644 "$LOG_DIR/Debug.log"

for block in $(seq $START_BLOCK $END_BLOCK); do
    HEADER_LINE=$(grep "Saw new\( cmpctblock\)\? header.*height=$block" "$TEMP_LOG" | tail -1)
    if [ -n "$HEADER_LINE" ]; then
        BLOCK_HASH=$(echo "$HEADER_LINE" | grep -o "hash=[0-9a-f]\{64\}" | cut -d'=' -f2)
        HEADER_TIME=$(echo "$HEADER_LINE" | awk '{print $1}' | cut -d'.' -f1)
    else
        BLOCK_HASH=""
        HEADER_TIME="N/A"
        echo "[$TIMESTAMP] Block $block: No 'Saw new header' found in logs" >>"$ERROR_LOG"
        echo "Block $block: No 'Saw new header' found in logs" >> "$LOG_DIR/Debug.log"
    fi

    VALIDATION_LINE=$(grep "UpdateTip.*height=$block" "$TEMP_LOG" | tail -1)
    if [ -n "$VALIDATION_LINE" ]; then
        VALIDATION_TIME=$(echo "$VALIDATION_LINE" | awk '{print $1}' | cut -d'.' -f1)
        MINED_TIME=$(echo "$VALIDATION_LINE" | grep -o "date='[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z'" | cut -d"'" -f2)
        if [ -z "$MINED_TIME" ]; then
            MINED_TIME="N/A"
            echo "[$TIMESTAMP] Block $block: Found 'UpdateTip' but no 'date=' field in: $VALIDATION_LINE" >>"$ERROR_LOG"
            echo "Block $block: No 'date=' field in UpdateTip" >> "$LOG_DIR/Debug.log"
        fi
    else
        VALIDATION_TIME="N/A"
        MINED_TIME="N/A"
        echo "[$TIMESTAMP] Block $block: No 'UpdateTip' found in logs" >>"$ERROR_LOG"
        echo "Block $block: No 'UpdateTip' found in logs" >> "$LOG_DIR/Debug.log"
    fi

    if [[ "$HEADER_TIME" != "N/A" && "$HEADER_TIME" != *Z ]]; then
        HEADER_TIME="${HEADER_TIME}Z"
    fi
    if [[ "$VALIDATION_TIME" != "N/A" && "$VALIDATION_TIME" != *Z ]]; then
        VALIDATION_TIME="${VALIDATION_TIME}Z"
    fi

    EXTERNAL_MINED_TIME="N/A"
    EXTERNAL_EPOCH=""
    for attempt in {1..3}; do
        EXTERNAL_EPOCH=$(curl -s "https://blockchain.info/block-height/$block?format=json" | jq -r '.blocks[0].time' 2>>"$ERROR_LOG")
        if [ -n "$EXTERNAL_EPOCH" ] && [[ "$EXTERNAL_EPOCH" =~ ^[0-9]+$ ]]; then
            break
        fi
        echo "Block $block: Attempt $attempt failed to fetch external mined time" >> "$LOG_DIR/Debug.log"
        sleep 2
    done
    if [ -n "$EXTERNAL_EPOCH" ] && [[ "$EXTERNAL_EPOCH" =~ ^[0-9]+$ ]]; then
        EXTERNAL_MINED_TIME=$(date -u -d "@$EXTERNAL_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>>"$ERROR_LOG")
        if [ "$MINED_TIME" != "$EXTERNAL_MINED_TIME" ] && [ "$MINED_TIME" != "N/A" ]; then
            echo "Block $block: Mined time mismatch. Local: $MINED_TIME, External: $EXTERNAL_MINED_TIME" >> "$LOG_DIR/Debug.log"
        fi
    else
        echo "Block $block: Failed to fetch external mined time after 3 attempts" >> "$LOG_DIR/Debug.log"
    fi
    sleep 2

    if [ -n "$BLOCK_HASH" ] && grep -q "Saw new cmpctblock header.*$BLOCK_HASH" "$TEMP_LOG"; then
        COMPACT_FLAG="Yes"
    else
        COMPACT_FLAG="No"
    fi

    if [ "$MINED_TIME" != "N/A" ] && [ "$HEADER_TIME" != "N/A" ]; then
        CLEAN_MINED_TIME="${MINED_TIME%%Z*}"
        CLEAN_HEADER_TIME="${HEADER_TIME%%Z*}"
        MINED_EPOCH=$(date -u -d "$CLEAN_MINED_TIME" +%s 2>>"$ERROR_LOG")
        HEADER_EPOCH=$(date -u -d "$CLEAN_HEADER_TIME" +%s 2>>"$ERROR_LOG")
        if [ -n "$MINED_EPOCH" ] && [ -n "$HEADER_EPOCH" ]; then
            MINED_TO_HEADER_DELAY=$((HEADER_EPOCH - MINED_EPOCH))
        else
            MINED_TO_HEADER_DELAY="N/A"
            echo "[$TIMESTAMP] Block $block: Failed to compute header delay. MINED_EPOCH=$MINED_EPOCH, HEADER_EPOCH=$HEADER_EPOCH" >>"$ERROR_LOG"
        fi
    else
        MINED_TO_HEADER_DELAY="N/A"
        echo "[$TIMESTAMP] Block $block: mined_to_header_delay_s is N/A (mined_time=$MINED_TIME, header_time=$HEADER_TIME)" >>"$ERROR_LOG"
    fi

    if [ "$MINED_TIME" != "N/A" ] && [ "$VALIDATION_TIME" != "N/A" ]; then
        CLEAN_MINED_TIME="${MINED_TIME%%Z*}"
        CLEAN_VALIDATION_TIME="${VALIDATION_TIME%%Z*}"
        MINED_EPOCH=$(date -u -d "$CLEAN_MINED_TIME" +%s 2>>"$ERROR_LOG")
        VALIDATION_EPOCH=$(date -u -d "$CLEAN_VALIDATION_TIME" +%s 2>>"$ERROR_LOG")
        if [ -n "$MINED_EPOCH" ] && [ -n "$VALIDATION_EPOCH" ]; then
            MINED_TO_VALIDATION_DELAY=$((VALIDATION_EPOCH - MINED_EPOCH))
        else
            MINED_TO_VALIDATION_DELAY="N/A"
            echo "[$TIMESTAMP] Block $block: Failed to compute validation delay. MINED_EPOCH=$MINED_EPOCH, VALIDATION_EPOCH=$VALIDATION_EPOCH" >>"$ERROR_LOG"
        fi
    else
        MINED_TO_VALIDATION_DELAY="N/A"
        echo "[$TIMESTAMP] Block $block: mined_to_validation_delay_s is N/A (mined_time=$MINED_TIME, validation_time=$VALIDATION_TIME)" >>"$ERROR_LOG"
    fi

    MINER_NAME="Unknown"
    MINER_OUTPUT=$("$MINER_SCRIPT" "$block" 2>> "$LOG_DIR/Debug.log")
    if [ $? -eq 0 ] && [ -n "$MINER_OUTPUT" ]; then
        MINER_NAME=$(echo "$MINER_OUTPUT" | grep "Miner/contact_info:" | cut -d':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[^a-zA-Z0-9._-]/_/g')
        if [ -z "$MINER_NAME" ]; then
            MINER_NAME="Unknown"
            echo "Block $block: get_miner.sh returned empty miner name" >> "$LOG_DIR/Debug.log"
        else
            MINER_NAME_CSV=$(echo "$MINER_NAME" | tr ' ' '_')
        fi
    else
        echo "Block $block: Failed to fetch miner name from get_miner.sh" >> "$LOG_DIR/Debug.log"
    fi

    echo "$block $MINED_TIME $EXTERNAL_MINED_TIME $HEADER_TIME $VALIDATION_TIME $MINED_TO_HEADER_DELAY $MINED_TO_VALIDATION_DELAY $COMPACT_FLAG $MINER_NAME_CSV" >> "$LOG_DIR/Propagation.log"

    JSON_OBJECT=$(jq -c -n \
        --arg block "$block" \
        --arg mined_time "$MINED_TIME" \
        --arg external_mined_time "$EXTERNAL_MINED_TIME" \
        --arg header_time "$HEADER_TIME" \
        --arg validation_time "$VALIDATION_TIME" \
        --arg mined_to_header_delay "$MINED_TO_HEADER_DELAY" \
        --arg mined_to_validation_delay "$MINED_TO_VALIDATION_DELAY" \
        --arg compact_flag "$COMPACT_FLAG" \
        --arg miner_name "$MINER_NAME" \
        '{block: ($block | tonumber), mined_time: $mined_time, external_mined_time: $external_mined_time, header_time: $header_time, validation_time: $validation_time, mined_to_header_delay_s: (if $mined_to_header_delay == "N/A" then $mined_to_header_delay else ($mined_to_header_delay | tonumber) end), mined_to_validation_delay_s: (if $mined_to_validation_delay == "N/A" then $mined_to_validation_delay else ($mined_to_validation_delay | tonumber) end), compact_flag: $compact_flag, miner_name: $miner_name}' 2>>"$ERROR_LOG")
    if [ $? -ne 0 ]; then
        echo "[$TIMESTAMP] Block $block: Failed to create JSON object" >>"$ERROR_LOG"
        continue
    fi

    TEMP_JSON=$(mktemp)
    jq --argjson new_block "$JSON_OBJECT" '.blocks += [$new_block]' "$LOG_DIR/Propagation.json" > "$TEMP_JSON" 2>>"$ERROR_LOG"
    if [ $? -ne 0 ]; then
        echo "[$TIMESTAMP] Block $block: Failed to append JSON object to Propagation.json" >>"$ERROR_LOG"
        rm -f "$TEMP_JSON"
        continue
    fi
    mv "$TEMP_JSON" "$LOG_DIR/Propagation.json"
    chmod 644 "$LOG_DIR/Propagation.json"
done

echo "[$TIMESTAMP] Propagation.json contents:" >>"$ERROR_LOG"
cat "$LOG_DIR/Propagation.json" >>"$ERROR_LOG"

echo "### Propagation.log End ###" >> "$LOG_DIR/Propagation.log"
echo "### Debug.log End ###" >> "$LOG_DIR/Debug.log"
rm -f "$TEMP_LOG"

if [ ! -s "$LOG_DIR/Propagation.json" ]; then
  echo "[$TIMESTAMP] Error: No JSON data captured for blocks $START_BLOCK to $END_BLOCK." >>"$ERROR_LOG"
  send_telegram_message "Error: No data captured for blocks $START_BLOCK\\-$END_BLOCK at $TIMESTAMP!" "$ERROR_LOG"
  exit 1
fi

echo "[$TIMESTAMP] Checking Propagation.json permissions before jq: $(ls -l $LOG_DIR/Propagation.json)" >>"$ERROR_LOG"
if [ ! -r "$LOG_DIR/Propagation.json" ]; then
  echo "[$TIMESTAMP] Error: Cannot read Propagation.json" >>"$ERROR_LOG"
  TOTAL_BLOCKS=0
else
  echo "[$TIMESTAMP] Propagation.json size: $(stat -f %z "$LOG_DIR/Propagation.json" 2>/dev/null || stat -c %s "$LOG_DIR/Propagation.json") bytes" >>"$ERROR_LOG"
  TOTAL_BLOCKS=$(jq '.blocks | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
  if [ -z "$TOTAL_BLOCKS" ] || ! [[ "$TOTAL_BLOCKS" =~ ^[0-9]+$ ]]; then
    echo "[$TIMESTAMP] Error: Failed to get TOTAL_BLOCKS, setting to 0" >>"$ERROR_LOG"
    TOTAL_BLOCKS=0
  fi
fi

if [ "$TOTAL_BLOCKS" -eq 0 ]; then
  echo "[$TIMESTAMP] Warning: No blocks in Propagation.json, proceeding with empty metrics." >>"$ERROR_LOG"
fi


# Calculate delay counts
HEADER_DELAY_COUNT=$(jq '[.blocks[].mined_to_header_delay_s | select(type == "number" and . >= 0)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
if [ -z "$HEADER_DELAY_COUNT" ] || ! [[ "$HEADER_DELAY_COUNT" =~ ^[0-9]+$ ]]; then
  echo "[$TIMESTAMP] Error: Failed to get HEADER_DELAY_COUNT, setting to 0" >>"$ERROR_LOG"
  HEADER_DELAY_COUNT=0
fi

VALIDATION_DELAY_COUNT=$(jq '[.blocks[].mined_to_validation_delay_s | select(type == "number" and . >= 0)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
if [ -z "$VALIDATION_DELAY_COUNT" ] || ! [[ "$VALIDATION_DELAY_COUNT" =~ ^[0-9]+$ ]]; then
  echo "[$TIMESTAMP] Error: Failed to get VALIDATION_DELAY_COUNT, setting to 0" >>"$ERROR_LOG"
  VALIDATION_DELAY_COUNT=0
fi

# Debug: Log raw sums and counts for header and validation delays
HEADER_DELAY_SUM=$(jq '[.blocks[].mined_to_header_delay_s | select(type == "number" and . >= 0)] | add // 0' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo "0")
VALIDATION_DELAY_SUM=$(jq '[.blocks[].mined_to_validation_delay_s | select(type == "number" and . >= 0)] | add // 0' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo "0")
echo "[$TIMESTAMP] Header Delay Sum: $HEADER_DELAY_SUM, Count: $HEADER_DELAY_COUNT" >>"$ERROR_LOG"
echo "[$TIMESTAMP] Validation Delay Sum: $VALIDATION_DELAY_SUM, Count: $VALIDATION_DELAY_COUNT" >>"$ERROR_LOG"

# Calculate average delays
if [ "$HEADER_DELAY_COUNT" -gt 0 ]; then
  AVG_HEADER_DELAY=$(jq '[.blocks[].mined_to_header_delay_s | select(type == "number" and . >= 0)] | add / length | . * 10.0 | round / 10.0' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo "N/A")
else
  AVG_HEADER_DELAY="N/A"
fi

if [ "$VALIDATION_DELAY_COUNT" -gt 0 ]; then
  AVG_VALIDATION_DELAY=$(jq '[.blocks[].mined_to_validation_delay_s | select(type == "number" and . >= 0)] | add / length | . * 10.0 | round / 10.0' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo "N/A")
else
  AVG_VALIDATION_DELAY="N/A"
fi

COMPACT_COUNT=$(jq '[.blocks[] | select(.compact_flag == "Yes")] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
if [ -z "$COMPACT_COUNT" ] || ! [[ "$COMPACT_COUNT" =~ ^[0-9]+$ ]]; then
  echo "[$TIMESTAMP] Error: Failed to get COMPACT_COUNT, setting to 0" >>"$ERROR_LOG"
  COMPACT_COUNT=0
fi

COMPACT_PERCENT=$(echo "scale=0; ($COMPACT_COUNT * 100) / $TOTAL_BLOCKS" | bc 2>>"$ERROR_LOG" || echo 0)
echo "[$TIMESTAMP] COMPACT_PERCENT: $COMPACT_PERCENT" >>"$ERROR_LOG"

# Miner distribution
MINER_DISTRIBUTION=$(jq -r '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . >= 0) | {name: .miner_name, delay: .mined_to_header_delay_s}] | group_by(.name) | map({name: .[0].name, count: length, min_delay: (map(.delay) | min)}) | sort_by(-.count, .min_delay) | .[:3] | .[] | "\(.count) \(.name)"' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG")
echo "[$TIMESTAMP] MINER_DISTRIBUTION='$MINER_DISTRIBUTION'" >>"$ERROR_LOG"

# Extract miner counts and names
MINER_1_LINE=$(echo "$MINER_DISTRIBUTION" | sed -n '1p')
MINER_1_COUNT=$(echo "$MINER_1_LINE" | awk '{print $1}' || echo "0")
MINER_1_NAME=$(echo "$MINER_1_LINE" | awk '{print $2}' || echo "Unknown")
MINER_2_LINE=$(echo "$MINER_DISTRIBUTION" | sed -n '2p')
MINER_2_COUNT=$(echo "$MINER_2_LINE" | awk '{print $1}' || echo "0")
MINER_2_NAME=$(echo "$MINER_2_LINE" | awk '{print $2}' || echo "None")
MINER_3_LINE=$(echo "$MINER_DISTRIBUTION" | sed -n '3p')
MINER_3_COUNT=$(echo "$MINER_3_LINE" | awk '{print $1}' || echo "0")
MINER_3_NAME=$(echo "$MINER_3_LINE" | awk '{print $2}' || echo "None")

# Validate miner counts
for var in MINER_1_COUNT MINER_2_COUNT MINER_3_COUNT; do
  eval "value=\$$var"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "[$TIMESTAMP] Error: $var is not a valid integer ($value), setting to 0" >>"$ERROR_LOG"
    eval "$var=0"
  fi
done

echo "[$TIMESTAMP] Miner counts: MINER_1_COUNT=$MINER_1_COUNT, MINER_2_COUNT=$MINER_2_COUNT, MINER_3_COUNT=$MINER_3_COUNT" >>"$ERROR_LOG"

# Calculate unique miners and others
UNIQUE_MINERS=$(jq -r '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . >= 0) | .miner_name] | unique | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
echo "[$TIMESTAMP] UNIQUE_MINERS=$UNIQUE_MINERS" >>"$ERROR_LOG"
if ! [[ "$UNIQUE_MINERS" =~ ^[0-9]+$ ]]; then
  echo "[$TIMESTAMP] Error: UNIQUE_MINERS is not a valid integer ($UNIQUE_MINERS), setting to 0" >>"$ERROR_LOG"
  UNIQUE_MINERS=0
fi
MINER_OTHERS=$((UNIQUE_MINERS - 3))
echo "[$TIMESTAMP] MINER_OTHERS (before validation)=$MINER_OTHERS" >>"$ERROR_LOG"
if ! [[ "$MINER_OTHERS" =~ ^[0-9]+$ ]] || [ "$MINER_OTHERS" -lt 0 ]; then
  echo "[$TIMESTAMP] Error: MINER_OTHERS is invalid or negative ($MINER_OTHERS), setting to 0" >>"$ERROR_LOG"
  MINER_OTHERS=0
fi

echo "[$TIMESTAMP] MINER_OTHERS (final)=$MINER_OTHERS" >>"$ERROR_LOG"

FASTEST_BLOCK=$(jq -r '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . >= 0) | {block: .block, delay: .mined_to_header_delay_s}] | min_by(.delay) | "\(.block) → \(.delay)s" // "None"' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo "None")

SLOWEST_BLOCK=$(jq -r '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . >= 0) | {block: .block, delay: .mined_to_header_delay_s}] | max_by(.delay) | "\(.block) → \(.delay)s" // "None"' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo "None")

NEGATIVE_BLOCK=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . < 0)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)

# Delay bucket calculations
DELAY_LT2=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . < 0)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_LE1=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . >= 0 and . <= 1)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_LE6=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . > 1 and . <= 6)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_LE10=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . > 6 and . <= 10)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_LE15=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . > 10 and . <= 15)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_LE20=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . > 15 and . <= 20)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_GE21=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . >= 21)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)

# Total count of blocks with non-negative delays
# Delay bucket calculations
DELAY_LT2=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . < 0)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_LE1=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . >= 0 and . <= 1)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_LE6=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . > 1 and . <= 6)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_LE10=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . > 6 and . <= 10)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_LE15=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . > 10 and . <= 15)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_LE20=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . > 15 and . <= 20)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)
DELAY_GE21=$(jq '[.blocks[] | select(.mined_to_header_delay_s | type == "number" and . >= 21)] | length' "$LOG_DIR/Propagation.json" 2>>"$ERROR_LOG" || echo 0)

# Debug: Log delay bucket values
echo "[$TIMESTAMP] Delay bucket values: LT2=$DELAY_LT2, LE1=$DELAY_LE1, LE6=$DELAY_LE6, LE10=$DELAY_LE10, LE15=$DELAY_LE15, LE20=$DELAY_LE20, GE21=$DELAY_GE21" >>"$ERROR_LOG"

# Validate each delay variable is an integer
for var in DELAY_LT2 DELAY_LE1 DELAY_LE6 DELAY_LE10 DELAY_LE15 DELAY_LE20 DELAY_GE21; do
  eval "value=\$$var"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "[$TIMESTAMP] Validation: $var was not a valid integer ($value), set to 0" >>"$ERROR_LOG"
    eval "$var=0"
  fi
done

# Total count of blocks with non-negative delays
TOTAL_DELAY_COUNT=$((DELAY_LE1 + DELAY_LE6 + DELAY_LE10 + DELAY_LE15 + DELAY_LE20 + DELAY_GE21))
echo "[$TIMESTAMP] TOTAL_DELAY_COUNT=$TOTAL_DELAY_COUNT" >>"$ERROR_LOG"

# Calculate excluded blocks
EXCLUDED_BLOCKS=$((TOTAL_BLOCKS - TOTAL_DELAY_COUNT))
echo "[$TIMESTAMP] EXCLUDED_BLOCKS=$EXCLUDED_BLOCKS" >>"$ERROR_LOG"

# Ensure TOTAL_DELAY_COUNT is an integer before test
if ! [[ "$TOTAL_DELAY_COUNT" =~ ^[0-9]+$ ]]; then
  echo "[$TIMESTAMP] Error: TOTAL_DELAY_COUNT is not a valid integer ($TOTAL_DELAY_COUNT), setting to 0" >>"$ERROR_LOG"
  TOTAL_DELAY_COUNT=0
fi

if [ "$TOTAL_DELAY_COUNT" -eq 0 ]; then
  PCT_LT2=0
  PCT_LE1=0
  PCT_LE6=0
  PCT_LE10=0
  PCT_LE15=0
  PCT_LE20=0
  PCT_GE21=0
else
  PCT_LT2=0  # Negative delays excluded
  PCT_LE1=$(echo "scale=0; ($DELAY_LE1 * 100) / $TOTAL_DELAY_COUNT" | bc -l 2>>"$ERROR_LOG" | awk '{printf "%d", $1}' || echo 0)
  PCT_LE6=$(echo "scale=0; ($DELAY_LE6 * 100) / $TOTAL_DELAY_COUNT" | bc -l 2>>"$ERROR_LOG" | awk '{printf "%d", $1}' || echo 0)
  PCT_LE10=$(echo "scale=0; ($DELAY_LE10 * 100) / $TOTAL_DELAY_COUNT" | bc -l 2>>"$ERROR_LOG" | awk '{printf "%d", $1}' || echo 0)
  PCT_LE15=$(echo "scale=0; ($DELAY_LE15 * 100) / $TOTAL_DELAY_COUNT" | bc -l 2>>"$ERROR_LOG" | awk '{printf "%d", $1}' || echo 0)
  PCT_LE20=$(echo "scale=0; ($DELAY_LE20 * 100) / $TOTAL_DELAY_COUNT" | bc -l 2>>"$ERROR_LOG" | awk '{printf "%d", $1}' || echo 0)
  PCT_GE21=$(echo "scale=0; ($DELAY_GE21 * 100) / $TOTAL_DELAY_COUNT" | bc -l 2>>"$ERROR_LOG" | awk '{printf "%d", $1}' || echo 0)
fi


echo "[$TIMESTAMP] Delay counts: LT2=$DELAY_LT2, LE1=$DELAY_LE1, LE6=$DELAY_LE6, LE10=$DELAY_LE10, LE15=$DELAY_LE15, LE20=$DELAY_LE20, GE21=$DELAY_GE21, Excluded=$EXCLUDED_BLOCKS" >>"$ERROR_LOG"

# Telegram summary message
TIME_NOW=$(date -u +"%H:%M:%S UTC")
DATE_NOW=$(date -u +"%a %b %d %Y")
BLOCK_RANGE_ESC=$(escape_md "Blocks: $START_BLOCK-$END_BLOCK")
MINER_1_ESC=$(escape_md "$MINER_1_NAME")
MINER_2_ESC=$(escape_md "$MINER_2_NAME")
MINER_3_ESC=$(escape_md "$MINER_3_NAME")
NON_COMPACT_COUNT=$((TOTAL_BLOCKS - COMPACT_COUNT))

MINER_3_LINE=""
if [ "$MINER_3_COUNT" -gt 0 ]; then
  MINER_3_LINE="🏗 Top Miner 3: $MINER_3_ESC"
fi

SUMMARY_MESSAGE=$(cat <<EOF
📦 *Block Summary*
$BLOCK_RANGE_ESC
\`\`\`
#️⃣ Blocks Analysed:  $TOTAL_BLOCKS
⏱ Avg Header Delay: ${AVG_HEADER_DELAY:-N/A}s
🧮 Avg Validation:  ${AVG_VALIDATION_DELAY:-N/A}s
🧩 Compact Blocks:  $COMPACT_COUNT
🏗 Top Miner 1: ${MINER_1_ESC:-Unknown}
🏗 Top Miner 2: ${MINER_2_ESC:-None}
$MINER_3_LINE
──────────────
🚀 Fastest Block:   ${FASTEST_BLOCK:-None}
🐌 Slowest Block:   ${SLOWEST_BLOCK:-None}
🛑 Excluded Blocks: ${EXCLUDED_BLOCKS:-0}
──────────────
🛠️ Compact Block Stats
✅ Compact:         $COMPACT_COUNT
❌ Non-Compact:     $NON_COMPACT_COUNT
──────────────
⏳ Block Delay
🚀 ≤1s:            ${DELAY_LE1:-0}
⏳ 2-6s:           ${DELAY_LE6:-0}
🏃 7-10s:          ${DELAY_LE10:-0}
🚶 11-15s:         ${DELAY_LE15:-0}
🐢 16-20s:         ${DELAY_LE20:-0}
🐌 ≥21s:           ${DELAY_GE21:-0}
\`\`\`
🕒 Time: $TIME_NOW
📅 Date: $DATE_NOW
EOF
)

echo "[$TIMESTAMP] About to call send_telegram_message" >>"$ERROR_LOG"
if send_telegram_message "$SUMMARY_MESSAGE" "$ERROR_LOG"; then
  TELEGRAM_STATUS="Telegram message sent successfully."
else
  TELEGRAM_STATUS="Failed to send Telegram message. Check $ERROR_LOG for details."
fi

# Attach logs to Telegram if enabled
if [ "$ATTACH_PROPAGATION_LOG" = "YES" ] && [ -f "$LOG_DIR/Propagation.log" ]; then
  send_telegram_document "$LOG_DIR/Propagation.log" "$ERROR_LOG"
fi
if [ "$ATTACH_PROPAGATION_JSON" = "YES" ] && [ -f "$LOG_DIR/Propagation.json" ]; then
  send_telegram_document "$LOG_DIR/Propagation.json" "$ERROR_LOG"
fi
if [ "$ATTACH_DEBUG_LOG" = "YES" ] && [ -f "$LOG_DIR/Debug.log" ]; then
  send_telegram_document "$LOG_DIR/Debug.log" "$ERROR_LOG"
fi

cat << EOF >>"$ERROR_LOG"
[$TIMESTAMP] Data extraction complete for blocks $START_BLOCK to $END_BLOCK.
[$TIMESTAMP] Logs written to $LOG_DIR
[$TIMESTAMP] $TELEGRAM_STATUS
EOF

recycle_logs "$LOG_DIR" "$ERROR_LOG"

