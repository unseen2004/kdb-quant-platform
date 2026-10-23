// ============================================================================
// rte.q - Real-Time Analytics & CEP Engine (VWAP/OHLCV, Live LOB, Surveillance)
// ============================================================================

\l src/common/schema.q
\l src/common/util.q
\l src/analytics/lob.q
\l src/analytics/tca.q
\l src/analytics/surveillance.q

.util.setProc[`RTE];
initTables[];

// Connected WebSocket clients for live UI streaming
wsClients:`int$();

.z.wo:{[h]
    wsClients,:h;
    .util.info "WebSocket client connected on handle ",string h;
    };

.z.wc:{[h]
    wsClients::wsClients except h;
    .util.info "WebSocket client disconnected on handle ",string h;
    };

.z.ws:{[msg]
    req:@[.j.k;msg;(`cmd`sym!("snapshot";"BTCUSD"))];
    s:`$req["sym"];
    snap:getDashboardPayload[s];
    (neg .z.w) .j.j snap;
    };

// Build comprehensive JSON-ready dictionary for WebSocket dashboard
getDashboardPayload:{[s]
    l2:.lob.extractL2FromState[.lob.activeOrders;s;5];
    recentBars:-20#select from metrics1m where sym=s;
    recentAlerts:-15#select from surveillanceAlert;
    slipBuy:.lob.estimateSlippage[l2;`B;25f];
    slipSell:.lob.estimateSlippage[l2;`S;25f];
    `type`timestamp`sym`lob`slippageBuy25`slippageSell25`bars`alerts!(
        `dashboard_update;
        string .z.p;
        s;
        l2;
        slipBuy;
        slipSell;
        recentBars;
        recentAlerts)
    };

// Broadcast live update to all WebSocket subscribers
broadcastWS:{[s]
    if[count wsClients;
        payload:.j.j getDashboardPayload[s];
        {(neg x) y}[;payload] each wsClients;
        ];
    };

// Real-time update handler invoked by Tickerplant
upd:{[t;x]
    // Ensure x is a table
    if[not 98h=type x;
        f:cols value t;
        x:$[0>type first x; enlist f!x; flip f!x]];

    t insert x;

    if[t=`trade;
        // Update 1-minute OHLCV + VWAP/TWAP bars
        bars:0!select
            open:first price,
            high:max price,
            low:min price,
            close:last price,
            volume:sum size,
            vwap:size wavg price,
            twap:avg price,
            tradeCount:count i
            by time:0D00:01:00 xbar time, sym from trade;
        `metrics1m set `sym`time xasc bars;
        newAlerts:.surv.detectMomentumIgnition[-100#trade], .surv.detectFatFinger[-100#trade];
        if[count newAlerts; `surveillanceAlert insert newAlerts];
        ];

    if[t=`lobDelta;
        .lob.processDeltas x;
        syms:distinct x`sym;
        {`lobSnapshot insert .lob.extractL2FromState[.lob.activeOrders;x;5]} each syms;
        newAlerts:.surv.detectSpoofing[-200#lobDelta], .surv.detectLayering[-200#lobDelta], .surv.detectWashTrading[-200#lobDelta];
        if[count newAlerts; `surveillanceAlert insert newAlerts];
        broadcastWS first syms;
        ];
    };

\d .u
end:{[dt]
    .util.info "RTE EOD rollover for date ",string dt;
    @[`.;tables`.;0#];
    .Q.gc[];
    };
\d .

port:.util.getOpt[`port;5013i];
tpHostPort:.util.getOpt[`tp;`localhost:5010];
system "p ",string port;

connectTP:{[]
    h:.util.registerConn[`TP;`$":",string tpHostPort];
    if[not null h;
        res:h"(.u.sub[`;`];`.u `i`L)";
        (.[;();:;].) each first res;
        ];
    };

connectTP[];
.util.info "RTE & WebSocket server listening on port ",string port;
