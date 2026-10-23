#!/usr/bin/env python3
"""
binance_ws_feed.py - Live Binance WebSocket L1/L2 Feedhandler for kdb+ Tickerplant
Supports PyKX (modern KX interface) with graceful dry-run / stdout mode.
"""

import argparse
import asyncio
import json
import time
from datetime import datetime, timezone

try:
    import websockets
except ImportError:
    websockets = None

try:
    import pykx as kx
except ImportError:
    kx = None


SYMBOLS = ["btcusdt", "ethusdt", "solusdt"]
SYM_MAP = {
    "BTCUSDT": "BTCUSD",
    "ETHUSDT": "ETHUSD",
    "SOLUSDT": "SOLUSD",
}


class KdbTickerplantPublisher:
    """Publishes normalized trade and bookTicker events to kdb+ Tickerplant via IPC."""

    def __init__(self, host: str = "localhost", port: int = 5010, dry_run: bool = False):
        self.host = host
        self.port = port
        self.dry_run = dry_run
        self.q_conn = None

        if not dry_run and kx is not None:
            self.q_conn = kx.SyncQConnection(host=host, port=port)
            print(f"[FEED-PY] Connected to kdb+ Tickerplant at {host}:{port} via PyKX")
        else:
            mode = "DRY-RUN" if dry_run else "STDOUT (PyKX not installed)"
            print(f"[FEED-PY] Running in {mode} mode")

    def publish_trade(self, sym: str, price: float, size: float, side: str, trade_id: str) -> None:
        if self.q_conn is not None:
            self.q_conn(
                ".u.upd",
                kx.SymbolAtom("trade"),
                [
                    kx.TimestampAtom.now(),
                    kx.SymbolAtom(sym),
                    kx.SymbolAtom("BINANCE"),
                    kx.FloatAtom(price),
                    kx.FloatAtom(size),
                    kx.SymbolAtom(side),
                    kx.SymbolAtom(trade_id),
                    kx.CharAtom(" "),
                ],
            )
        else:
            ts = datetime.now(timezone.utc).isoformat()
            print(f"[TRADE] {ts} | {sym:6s} | {side} | px={price:10.2f} | sz={size:8.4f} | id={trade_id}")

    def publish_quote(self, sym: str, bid: float, ask: float, bsize: float, asize: float) -> None:
        if self.q_conn is not None:
            self.q_conn(
                ".u.upd",
                kx.SymbolAtom("quote"),
                [
                    kx.TimestampAtom.now(),
                    kx.SymbolAtom(sym),
                    kx.SymbolAtom("BINANCE"),
                    kx.FloatAtom(bid),
                    kx.FloatAtom(ask),
                    kx.FloatAtom(bsize),
                    kx.FloatAtom(asize),
                ],
            )
        else:
            ts = datetime.now(timezone.utc).isoformat()
            print(f"[QUOTE] {ts} | {sym:6s} | bid={bid:10.2f} ({bsize:.3f}) | ask={ask:10.2f} ({asize:.3f})")


async def stream_binance(publisher: KdbTickerplantPublisher, max_events: int = 0) -> None:
    if websockets is None:
        raise RuntimeError("Install `websockets` package (`pip install websockets pykx`) to stream live Binance data.")

    streams = "/".join([f"{s}@trade/{s}@bookTicker" for s in SYMBOLS])
    url = f"wss://stream.binance.com:9443/stream?streams={streams}"
    print(f"[FEED-PY] Subscribing to {url}")

    count = 0
    async with websockets.connect(url, ping_interval=20) as ws:
        async for raw_msg in ws:
            envelope = json.loads(raw_msg)
            stream = envelope.get("stream", "")
            data = envelope.get("data", {})
            raw_sym = data.get("s", "")
            sym = SYM_MAP.get(raw_sym, raw_sym)

            if stream.endswith("@trade"):
                price = float(data["p"])
                size = float(data["q"])
                # m=True means buyer is market maker -> seller is aggressor (`S)
                side = "S" if data.get("m", False) else "B"
                trade_id = f"BN_{data['t']}"
                publisher.publish_trade(sym, price, size, side, trade_id)
            elif stream.endswith("@bookTicker"):
                bid = float(data["b"])
                bsize = float(data["B"])
                ask = float(data["a"])
                asize = float(data["A"])
                publisher.publish_quote(sym, bid, ask, bsize, asize)

            count += 1
            if 0 < max_events <= count:
                print(f"[FEED-PY] Reached max_events={max_events}, shutting down cleanly.")
                break


def main() -> None:
    parser = argparse.ArgumentParser(description="Binance WebSocket Feedhandler for kdb+ Tickerplant")
    parser.add_argument("--tp-host", default="localhost", help="kdb+ Tickerplant host")
    parser.add_argument("--tp-port", type=int, default=5010, help="kdb+ Tickerplant port")
    parser.add_argument("--dry-run", action="store_true", help="Print normalized ticks without connecting to kdb+")
    parser.add_argument("--max-events", type=int, default=0, help="Stop after N events (0 = infinite)")
    args = parser.parse_args()

    pub = KdbTickerplantPublisher(host=args.tp_host, port=args.tp_port, dry_run=args.dry_run)
    asyncio.run(stream_binance(pub, max_events=args.max_events))


if __name__ == "__main__":
    main()
