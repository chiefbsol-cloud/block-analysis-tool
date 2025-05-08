# block-analysis-tool
A tool for analysing Bitcoin block propagation delays and miner information. Overview of findings are sent to Telegram with detailed CSV and JSON available. Tested on Bitcoin Knots
# Block Analysis Tool 📊

![GitHub License](https://img.shields.io/github/license/<your-username>/block-analysis-tool?color=blue)
![Language](https://img.shields.io/badge/language-Bash-green)
![Status](https://img.shields.io/badge/status-active-brightgreen)

A Bash-based utility for analyzing **Bitcoin block propagation delays** and extracting **miner information** from coinbase scripts. Tailored for **Bitcoin Knots** on Umbrel (Docker), it supports Bitcoin Core setups and provides detailed CSV/JSON reports, debug logs, and Telegram summaries for real-time monitoring.

---

## ✨ Features

### Block Propagation Analysis (`block_delay.sh`)
- ⏱ Measures mined-to-header and mined-to-validation delays for a range of Bitcoin blocks.
- 📄 Outputs:
  - **Propagation.log** (CSV): Block data with timestamps, delays, compact block status, and miner names.
  - **Propagation.json** (JSON): Structured data for programmatic use.
  - **Debug.log** (text): Troubleshooting messages.
- 📨 Sends Telegram summaries with metrics (e.g., average delays, compact block %, top miners).
- ⏰ Supports cronjob scheduling (e.g., 50 blocks overnight, 100 blocks daily).
- ♻️ Recycles logs after a configurable period (default: 336 hours).

### Miner Identification (`get_miner.sh`)
- 🕵️‍♂️ Extracts miner names from block coinbase scripts using block height.
- 🏊 Supports major mining pools (e.g., AntPool, Foundry USA Pool, MARA Pool) with manual overrides.
- 🧹 Cleans and normalizes coinbase data for accuracy.

---

## 🛠️ Prerequisites

| Requirement | Description |
|-------------|-------------|
| **System** | Linux with Bash, Bitcoin Knots/Core node (Umbrel Docker recommended), internet access. |
| **Dependencies** | `jq`, `curl`, `bc`, `awk`, `xxd` (Install: `sudo apt-get install jq curl bc gawk xxd`). |
| **Bitcoin Node** | Umbrel: Ensure `bitcoin-knots_bitcoind_1` container runs (`docker ps`). Native: `bitcoind` with `rpcuser`/`rpcpassword` in `~/.bitcoin/bitcoin.conf`. Test: `bitcoin-cli getblockcount`. |
| **Telegram Bot** (Optional) | Create a bot via [BotFather](https://t.me/BotFather) for `TELEGRAM_BOT_TOKEN`. Get `TELEGRAM_CHAT_ID` by messaging the bot. |

---

## 🚀 Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/<your-username>/block-analysis-tool.git
   cd block-analysis-tool

2. **Create Log Directory**:
 ```bash
mkdir -p ~/logs/block_delay
```

3. **Set File Permissions to Executable**:
```bash
Store block_delay.sh and get_miner.sh in root of Umbrel
chmod +x block_delay.sh
chmod +x get_miner.sh
