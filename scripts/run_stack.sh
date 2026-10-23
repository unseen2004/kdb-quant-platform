#!/usr/bin/env bash
# ============================================================================
# run_stack.sh - Launch Full kdb+ Tick Plant, RTE, HDB, Gateway & Feedhandler
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

Q_BIN="${Q_BIN:-q}"
if ! command -v "$Q_BIN" >/dev/null 2>&1; then
  echo "[ERROR] kdb+/q binary ('$Q_BIN') not found in PATH."
  echo "        Install kdb+ Personal/On-Demand from https://kx.com/ or set Q_BIN=/path/to/q"
  exit 1
fi

mkdir -p logs tplog hdb pids

echo "[1/5] Starting Tickerplant (TP) on port 5010..."
nohup "$Q_BIN" src/tick/tp.q -port 5010 -logdir tplog > logs/tp.log 2>&1 &
echo $! > pids/tp.pid
sleep 0.5

echo "[2/5] Starting Historical Database (HDB) on port 5012..."
nohup "$Q_BIN" src/tick/hdb.q -port 5012 -hdbdir hdb > logs/hdb.log 2>&1 &
echo $! > pids/hdb.pid
sleep 0.5

echo "[3/5] Starting Real-Time Database (RDB) on port 5011..."
nohup "$Q_BIN" src/tick/rdb.q -port 5011 -tp localhost:5010 -hdb localhost:5012 -hdbdir hdb > logs/rdb.log 2>&1 &
echo $! > pids/rdb.pid
sleep 0.5

echo "[4/5] Starting Real-Time Engine & CEP Surveillance (RTE) on port 5013..."
nohup "$Q_BIN" src/tick/rte.q -port 5013 -tp localhost:5010 > logs/rte.log 2>&1 &
echo $! > pids/rte.pid
sleep 0.5

echo "[5/5] Starting Non-Blocking Query Gateway (GW) on port 5014 & Live Feed..."
nohup "$Q_BIN" src/tick/gw.q -port 5014 -rdb localhost:5011 -hdb localhost:5012 -rte localhost:5013 > logs/gw.log 2>&1 &
echo $! > pids/gw.pid

nohup "$Q_BIN" src/tick/feed.q -live 1 -tp localhost:5010 > logs/feed.log 2>&1 &
echo $! > pids/feed.pid

echo ""
echo "===================================================================="
echo "kdb+ Quant Platform is RUNNING"
echo "  Tickerplant (TP) : localhost:5010"
echo "  Real-Time DB     : localhost:5011"
echo "  Historical DB    : localhost:5012"
echo "  Real-Time Engine : localhost:5013 (WebSocket UI enabled)"
echo "  Query Gateway    : localhost:5014"
echo "  Dashboard UI     : open dashboard/index.html in browser"
echo "===================================================================="
