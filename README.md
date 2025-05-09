# block-analysis-tool
A tool for analysing Bitcoin block propagation delays and miner information. Overview of findings are sent to Telegram with detailed CSV and JSON available. Tested on Bitcoin Knots
# Block Analysis Tool 📊

![GitHub License](https://img.shields.io/github/license/<your-username>/block-analysis-tool?color=blue)
![Language](https://img.shields.io/badge/language-Bash-green)
![Status](https://img.shields.io/badge/status-active-brightgreen)

A Bash-based utility for analyzing **Bitcoin block propagation delays** and extracting **miner information** from coinbase scripts. Tailored for **Bitcoin Knots** on Umbrel (Docker), it supports Bitcoin Core setups and provides detailed CSV/JSON reports, debug logs, and Telegram summaries for real-time monitoring.

This script has been tested on a DIY Raspberry Pi 5 (8GB) running Umbrel, ensuring compatibility with lightweight Linux environments.

**Disclaimer**: Use this script at your own risk. The authors assume no liability for any issues arising from its use. Ensure you understand the script’s functionality and test it thoroughly before deployment.

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


## Telegram Setup

The script sends reports to a Telegram chat. Follow these steps to set up your Telegram bot and obtain the necessary credentials.

1. **Create a Telegram Bot**:
   - Open Telegram and message `@BotFather`.
   - Send `/start`, then `/newbot`.
   - Follow prompts to name your bot (e.g., `BitaxeMonitorBot`).
   - Copy the **Bot Token** (e.g., `123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZ`).

2. **Get Your Chat ID**:
   - Message your bot (e.g., `/start`).
   - Forward a message from your bot to `@GetIDsBot` or use an AI assistant with this prompt:
     ```
     I need help getting my Telegram Chat ID for a bot. I’ve created a bot with BotFather and sent it a message. How do I find the Chat ID?
     ```
   - The AI or `@GetIDsBot` will provide your **Chat ID** (e.g., `123456789`).

3. **Test Telegram Connectivity**:
   - Replace `YOUR_BOT_TOKEN` and `YOUR_CHAT_ID` in the command below and run it on your node:
     ```bash
     curl -s -X POST "https://api.telegram.org/botYOUR_BOT_TOKEN/sendMessage" -d chat_id="YOUR_CHAT_ID" -d text="Test from my node"
     ```
   - Check your Telegram chat for the test message. If it fails, verify your token, chat ID, and network connectivity.
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
chmod +x block_delay.sh
chmod +x get_miner.sh
```

4. **Grant Docker Permissions to the Umbrel User**:
```bash
Solution: Grant Docker Permissions to the umbrel User
To resolve this, add the umbrel user to the docker group, which allows non-root access to the Docker daemon.
Add umbrel to the docker Group:
Run the following command to add the umbrel user to the docker group:

sudo usermod -aG docker umbrel

-aG: Appends the docker group to the user’s groups without overwriting existing memberships.

Verify the user is in the docker group:

groups umbrel

You should see docker in the output (e.g., umbrel : umbrel docker).

Apply the Group Change:
For the group change to take effect, you need to log out and log back in via SSH:

exit
ssh umbrel@umbrel.local
```

5. **Configure Environment**:
```bash
Edit block_delay.sh:
NUM_BLOCKS: Blocks to analyze (default: 5, recommended: 5–100).

TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID: For notifications.

ATTACH_*_LOG: Set to YES to attach logs to Telegram.

RECYCLE_LOGS_HOURS: Log retention (default: 336 hours).

For Bitcoin Core Users (Untested), update both files:
Replace docker exec bitcoin-knots_bitcoind_1 bitcoin-cli with your container name or bitcoin-cli.
```
6. ** Test the Scripts **:
```bash
Test get_miner.sh
./get_miner.sh 895802

Output:
Miner/contact_info: AntPool

Test block_delay.sh
./block_delay.sh 5

Check ~/logs/block_delay for:
Propagation.log (CSV)
Propagation.json (JSON)
Debug.log (text)
error.log (errors)
```

7. ** Run as a Cronjob **:
```bash
crontab -e
Add cronjob Overnight (50 blocks, 6 AM):
0 6 * * * /path/to/block_delay.sh 50

Daily (100 blocks, 10 PM):
0 22 * * * /path/to/block_delay.sh
```

