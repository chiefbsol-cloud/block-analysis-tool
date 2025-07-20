#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH


# Crafted by @chieb_sol vibecoding with @grok, @chatgpt, and @cursorAI - July 20th 2025
# This v3 accompanies the block_delayv3.sh core code
# Script to extract miner names from Bitcoin block coinbase scripts
# Designed for Bitcoin Knots (v28.1-4) on Umbrel (Docker); outputs miner name for a given block height
# BITCOIN CORE USERS:
# - Umbrel: Replace 'bitcoin-knots_app_1' with your Bitcoin Core container name (e.g., 'bitcoin_bitcoind_1'). Run 'docker ps' to find it.
# - Native: Replace 'docker exec bitcoin-knots_app_1 bitcoin-cli' with 'bitcoin-cli' (e.g., 'bitcoin-cli -datadir=/data/bitcoin -rpcport=9332 getblockhash').
#   Ensure bitcoind is running ('systemctl status bitcoind') and ~/.bitcoin/bitcoin.conf has rpcuser/rpcpassword.
# Test your setup: Run 'bitcoin-cli -datadir=/data/bitcoin -rpcport=9332 getblockcount' to verify node access before executing.
# Dependencies: jq, xxd
# Changes: Removed sudo from Docker commands for cron compatibility, added error logging, kept overrides for 894924 (Mining Squared), fixed /Mining-Dutch/, added /2cDw/ for Foundry USA Pool, manual overrides for Carbon Negative and Mining Squared, removed debug output
# It's advisable to create the logs directory before attempting to run the code:  mkdir ~/logs/block_delay. If the code fails to run, most likely the logs directory is missing!

# Error log for cron compatibility
LOG_DIR="$HOME/logs/block_delay"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
ERROR_LOG="$LOG_DIR/error.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
#ERROR_LOG="$HOME/logs/block_delay/error.log"

# Function to fetch the block hash from the Bitcoin node using the block height
get_block_hash() {
  local block_height=$1
  # BITCOIN CORE USERS: Replace 'bitcoin-knots_app_1' with your container name or use 'bitcoin-cli -datadir=/data/bitcoin -rpcport=9332 getblockhash'.
  # Example: Umbrel Core: 'docker exec bitcoin_bitcoind_1 bitcoin-cli -datadir=/data/bitcoin -rpcport=9332 getblockhash "$block_height"'
  #          Native: 'bitcoin-cli -datadir=/data/bitcoin -rpcport=9332 getblockhash "$block_height"'
  local block_hash=$(docker exec bitcoin-knots_app_1 bitcoin-cli -datadir=/data/bitcoin -rpcport=9332 getblockhash "$block_height" 2>>"$ERROR_LOG")

  if [ "$block_hash" == "null" ] || [ -z "$block_hash" ]; then
    echo "[$TIMESTAMP] Error: Block hash not found for block height $block_height." >>"$ERROR_LOG"
    echo "Error: Block hash not found for block height $block_height."
    exit 1
  fi

  echo "$block_hash"
}

# Function to fetch miner info (coinbase script)
get_miner_info() {
  local block_hash=$1
  # BITCOIN CORE USERS: Replace 'bitcoin-knots_app_1' with your container name or use 'bitcoin-cli -datadir=/data/bitcoin -rpcport=9332 getblock'.
  # Example: Umbrel Core: 'docker exec bitcoin_bitcoind_1 bitcoin-cli -datadir=/data/bitcoin -rpcport=9332 getblock "$block_hash" 2'
  #          Native: 'bitcoin-cli -datadir=/data/bitcoin -rpcport=9332 getblock "$block_hash" 2'
  local raw_block=$(docker exec bitcoin-knots_app_1 bitcoin-cli -datadir=/data/bitcoin -rpcport=9332 getblock "$block_hash" 2 2>>"$ERROR_LOG")

  # Extract the coinbase (first) transaction's script
  local coinbase_script=$(echo "$raw_block" | jq -r '.tx[0].vin[0].coinbase' 2>>"$ERROR_LOG")

  if [ "$coinbase_script" == "null" ]; then
    echo "[$TIMESTAMP] Error: Coinbase script not found for block hash $block_hash." >>"$ERROR_LOG"
    echo "Error: Coinbase script not found."
    exit 1
  fi

  echo "$coinbase_script"
}

# Fetch miner info and clean it
get_clean_miner_info() {
  local raw_miner_info=$1
  local block_height=$2

  # Decode the coinbase script (hex to ASCII), handle null bytes
  local miner_info=$(echo "$raw_miner_info" | xxd -r -p | tr -d '\0' 2>>"$ERROR_LOG")

  # Remove non-printable characters, keep alphanumeric, spaces, and symbols (., /, - for tags like /Mining-Dutch/)
  local clean_miner_info=$(echo "$miner_info" | tr -cd '[:alnum:][:space:]./-')

  # Normalize whitespace and remove common prefixes like "Mined by"
  clean_miner_info=$(echo "$clean_miner_info" | sed 's/Mined by //g' | tr -s '[:space:]')

  # List of known mining pool names (expanded)
  local known_pools="Foundry USA Pool|AntPool|F2Pool|ViaBTC|Poolin|Binance Pool|BTC.com|SlushPool|MaraPool|Luxor|SigmaPool|SpiderPool|SBICrypto.com Pool|Secpool|WhitePool|Braiins Pool|BitFuFuPool|Carbon Negative|Mining Squared|Mining-Dutch"

  # Extract the pool name using case-insensitive grep, matching pool names or their prefixes/legacy names/tags
  local extracted_pool=$(echo "$clean_miner_info" | grep -i -oE "($known_pools|binance|slush|BitFuFu|MARA|MARA Made in USA|/BTC.com/|btccom|carbon negative|hz|mining squared|bsquared network|/bsquared/|bsquared|/2cDw/|/Mining-Dutch/)" | head -n 1)

  if [ -n "$extracted_pool" ]; then
    # Normalize the extracted pool name
    case "$extracted_pool" in
      binance)
        clean_miner_info="Binance Pool"
        ;;
      slush)
        clean_miner_info="Braiins Pool"
        ;;
      bitfufu)
        clean_miner_info="BitFuFuPool"
        ;;
      MARA|"MARA Made in USA")
        clean_miner_info="MARA Pool"
        ;;
      btc.com|/BTC.com/|BTCcom)
        clean_miner_info="BTC.com"
        ;;
      "carbon negative"|hz)
        clean_miner_info="Carbon Negative"
        ;;
      "mining squared"|"bsquared network"|"/bsquared/"|bsquared)
        clean_miner_info="Mining Squared"
        ;;
      "/2cDw/")
        clean_miner_info="Foundry USA Pool"
        ;;
      "/Mining-Dutch/")
        clean_miner_info="Mining-Dutch"
        ;;
      *)
        clean_miner_info="$extracted_pool"
        ;;
    esac
  else
    # Manual override for known blocks (temporary until coinbase patterns are confirmed)
    case "$block_height" in
      894703|894591|894918)
        clean_miner_info="Carbon Negative"
        ;;
      894628|894924)
        clean_miner_info="Mining Squared"
        ;;
      *)
        # Fallback: tokenize cleaned string into words, filter out garbage
        fallback_candidate=$(echo "$clean_miner_info" | tr '\n' ' ' | grep -oE '[[:alnum:]./-]{4,30}' | grep -vE '^[[:digit:]]+$' | head -n 1)

        # Final validation: must contain alphabetic characters, not be garbage, and not include long metadata
        if [ -z "$fallback_candidate" ] || [ ${#fallback_candidate} -lt 6 ] || ! echo "$fallback_candidate" | grep -qE '[[:alpha:]]{3,}' || echo "$fallback_candidate" | grep -qE '[[:alnum:]]{6,}' ; then
          clean_miner_info="Unknown"
        else
          clean_miner_info="$fallback_candidate"
        fi
        ;;
    esac
  fi

  # Ensure no trailing newlines or stray output
  echo -n "$clean_miner_info"
}

# Main script
if [ -z "$1" ]; then
  echo "Usage: $0 <block_height>"
  exit 1
fi

block_height=$1
echo "[$TIMESTAMP] Fetching block for height $block_height..." >>"$ERROR_LOG"

# Fetch the block hash
block_hash=$(get_block_hash "$block_height")
echo "[$TIMESTAMP] Block hash: $block_hash" >>"$ERROR_LOG"

# Fetch the coinbase script
coinbase_script=$(get_miner_info "$block_hash")
echo "[$TIMESTAMP] Coinbase Script (Raw): $coinbase_script" >>"$ERROR_LOG"

# Clean the miner info, passing block height for manual overrides
clean_miner_info=$(get_clean_miner_info "$coinbase_script" "$block_height")
echo "[$TIMESTAMP] Miner/contact_info: $clean_miner_info" >>"$ERROR_LOG"
echo "Miner/contact_info: $clean_miner_info"

