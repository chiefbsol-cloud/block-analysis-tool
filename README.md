# block-analysis-tool
A tool for analysing Bitcoin block propagation delays and miner information. Overview of findings are sent to Telegram with detailed CSV and JSON available. Tested on Bitcoin Knots
The Block Analysis Tool is a Bash-based utility designed to analyze Bitcoin block propagation delays and extract miner information from block coinbase scripts. It is tailored for Bitcoin Knots running on Umbrel (Docker) but can be adapted for Bitcoin Core users. The tool generates detailed reports in CSV and JSON formats, logs debug information, and sends summaries via Telegram for real-time monitoring.
Features
Block Propagation Analysis (block_delay.sh):
Measures propagation delays (mined-to-header and mined-to-validation) for a specified range of Bitcoin blocks.

Outputs:
Propagation.log (CSV): Block data with timestamps, delays, compact block status, and miner names.

Propagation.json (JSON): Structured block data with metadata for programmatic use.

Debug.log (text): Debug messages for troubleshooting.

Sends a formatted Telegram summary with key metrics (e.g., average delays, compact block percentage, top miners).

Supports cronjob scheduling for automated analysis (recommended: 50 blocks overnight, 100 blocks daily).

Recycles logs after a configurable period (default: 336 hours).

Miner Identification (get_miner.sh):
Extracts miner names from block coinbase scripts using block height.

Supports known mining pools (e.g., AntPool, Foundry USA Pool, MARA Pool) and handles manual overrides for specific blocks.

Cleans and normalizes coinbase data to ensure accurate miner identification.

Prerequisites
System Requirements:
Linux environment with Bash.

Bitcoin Knots or Bitcoin Core node (Umbrel Docker setup recommended).

Docker (for Umbrel users) or native Bitcoin Core installation.

Internet access for external API calls (e.g., mempool.space, blockchain.info).

Dependencies:
jq: JSON processing.

curl: API requests.

bc: Floating-point calculations.

awk: Text processing.

xxd: Hex-to-ASCII conversion.

Install dependencies (Ubuntu/Debian example):

