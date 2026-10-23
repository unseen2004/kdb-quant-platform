// ============================================================================
// feed.q - Synthetic GBM Market Microstructure, L3 LOB & Abuse Scenario Feed
// ============================================================================

\l src/common/schema.q
\l src/common/util.q

.util.setProc[`FEED];

\d .feed

syms:`BTCUSD`ETHUSD`SOLUSD`NVDA`AAPL;
basePrices:syms!68500f 3450f 185f 138f 228f;
currPrices:basePrices;
venues:`BINANCE`COINBASE`KRAKEN`LMAX;
traders:`TRDR_ALPHA`TRDR_BETA`TRDR_GAMMA`TRDR_DELTA`HFT_MM1`HFT_MM2;
seq:0j;
oidSeq:10000j;
tidSeq:50000j;

// Box-Muller standard normal random variable generator (vectorized)
rnorm:{[n]
    u1:1e-9 | n?1f;
    u2:n?1f;
    sqrt[-2f * log u1] * cos 2f * 3.141592653589793 * u2
    };

// Generate a batch of N realistic GBM trades & quotes
genTradesAndQuotes:{[n;t0]
    s:n?syms;
    dtNs:sums 1000000j + n?50000000j; // 1ms to 50ms inter-arrival
    ts:t0 + dtNs;
    shocks:0.0003 * rnorm n;
    // Update symbol prices using geometric drift + shock
    pxs:{[sym;shk] .feed.currPrices[sym]*:exp shk; 0.01*`int$100*.feed.currPrices[sym]}'[s;shocks];
    spreads:pxs * 0.0002 * 1 + n?3f;
    bids:0.01*`int$100*(pxs - 0.5*spreads);
    asks:0.01*`int$100*(pxs + 0.5*spreads);
    bsizes:0.1 * 1 + n?200f;
    asizes:0.1 * 1 + n?200f;
    sides:n?`B`S;
    tPrices:?[sides=`B; asks; bids];
    tSizes:0.05 * 1 + n?100f;
    exchs:n?venues;
    tIds:`$("TRD_",/:string .feed.tidSeq + 1 + til n);
    .feed.tidSeq+:n;

    qTbl:([] time:ts; sym:s; exchange:exchs; bid:bids; ask:asks; bsize:bsizes; asize:asizes);
    tTbl:([] time:ts; sym:s; exchange:exchs; price:tPrices; size:tSizes; side:sides; tradeId:tIds; cond:n#" ");
    `quote`trade!(qTbl; tTbl)
    };

// Generate realistic L3 Order Book Delta events (ADD, MOD, CAN, EXEC) for a symbol
genLobDeltas:{[s;n;t0]
    mid:.feed.currPrices s;
    tickSz:$[mid>1000f; 0.5f; 0.01f];
    dtNs:sums 500000j + n?10000000j;
    ts:t0 + dtNs;
    sides:n?`B`S;
    lvlOffsets:1 + n?5;
    pxs:?[sides=`B; mid - lvlOffsets * tickSz; mid + lvlOffsets * tickSz];
    szs:0.5 * 1 + n?20f;
    oids:`$("ORD_",/:string .feed.oidSeq + 1 + til n);
    .feed.oidSeq+:n;
    seqs:.feed.seq + 1 + til n;
    .feed.seq+:n;
    trdrs:n?traders;

    // Base ADD events
    adds:([] time:ts; sym:n#s; seqNum:seqs; orderId:oids; traderId:trdrs;
             action:n#`ADD; side:sides; price:pxs; size:szs);

    // Follow up a subset with CAN or EXEC events
    subIdx:where 0.35 > n?1f;
    if[0=count subIdx; :adds];
    followActs:(count subIdx)?`CAN`EXEC`MOD;
    followTs:(ts subIdx) + 5000000j + (count subIdx)?100000000j;
    followSeqs:.feed.seq + 1 + til count subIdx;
    .feed.seq+:count subIdx;
    followSizes:?[followActs=`EXEC; 0.5 * szs subIdx; szs subIdx];

    follows:([] time:followTs; sym:(count subIdx)#s; seqNum:followSeqs;
                orderId:oids subIdx; traderId:trdrs subIdx;
                action:followActs; side:sides subIdx; price:pxs subIdx; size:followSizes);

    `time xasc adds,follows
    };

// Inject synthetic Market Abuse Scenarios (Spoofing, Layering, Wash Trade, Fat Finger)
injectAbuseScenarios:{[t0]
    mid:.feed.currPrices`BTCUSD;

    // 1. Spoofing by `SPOOF_BOT_99: huge 45 BTC bid ADD followed 120ms later by CAN
    spoofOid:`$"ORD_SPOOF_",string .feed.oidSeq+:1;
    spoofDeltas:([]
        time:(t0 + 0D00:00:00.010; t0 + 0D00:00:00.050; t0 + 0D00:00:00.130);
        sym:3#`BTCUSD;
        seqNum:.feed.seq + 1 2 3;
        orderId:(spoofOid; `$"ORD_FILL_",string .feed.oidSeq+:1; spoofOid);
        traderId:3#`SPOOF_BOT_99;
        action:`ADD`EXEC`CAN;
        side:`B`S`B;
        price:(mid - 1.0f; mid + 0.5f; mid - 1.0f);
        size:(45f; 2.5f; 45f)
        );
    .feed.seq+:3;

    // 2. Layering by `LAYER_HFT_07: 5 distinct ask levels added and rapidly canceled
    layerLvls:1 2 3 4 5f;
    layerOids:`$("ORD_LAY_",/:string .feed.oidSeq + til 5);
    .feed.oidSeq+:5;
    layerAdds:([]
        time:t0 + 0D00:00:01 + 1000000j * til 5;
        sym:5#`BTCUSD;
        seqNum:.feed.seq + 1 + til 5;
        orderId:layerOids;
        traderId:5#`LAYER_HFT_07;
        action:5#`ADD;
        side:5#`S;
        price:mid + layerLvls * 2f;
        size:5#8f
        );
    .feed.seq+:5;
    layerCans:update time:time + 0D00:00:00.250, seqNum:.feed.seq + 1 + til 5, action:5#`CAN from layerAdds;
    .feed.seq+:5;

    // 3. Wash Trade by `WASH_ACCT_42: simultaneous Buy & Sell EXEC at exact same price/size
    washDeltas:([]
        time:(t0 + 0D00:00:02.000; t0 + 0D00:00:02.005);
        sym:2#`ETHUSD;
        seqNum:.feed.seq + 1 2;
        orderId:`$("ORD_WASH_",/:string .feed.oidSeq + 1 2);
        traderId:2#`WASH_ACCT_42;
        action:2#`EXEC;
        side:`B`S;
        price:2#.feed.currPrices`ETHUSD;
        size:2#18.5f
        );
    .feed.oidSeq+:2;
    .feed.seq+:2;

    // 4. Fat-Finger trade on BTCUSD (1.4% off-market spike)
    ffTrade:([]
        time:enlist t0 + 0D00:00:03.000;
        sym:enlist `BTCUSD;
        exchange:enlist `BINANCE;
        price:enlist mid * 1.014;
        size:enlist 12.0f;
        side:enlist `B;
        tradeId:enlist `TRD_FATFINGER_01;
        cond:enlist "F"
        );

    `lobDelta`trade!(`time xasc spoofDeltas,layerAdds,layerCans,washDeltas; ffTrade)
    };

// Generate Parent Orders & Child Executions aligned with generated market trades/quotes
genParentAndChildOrders:{[trades;quotes]
    pSyms:`BTCUSD`ETHUSD`SOLUSD`NVDA`AAPL;
    nP:count pSyms;
    tMin:first trades`time;
    tMax:last trades`time;
    span:`long$(tMax - tMin);
    starts:tMin + `long$0.1 * span;
    ends:tMin + `long$0.85 * span;

    arrPxs:{[q;s;ts] exec first 0.5*bid+ask from q where sym=s, time>=ts}[quotes;;starts] each pSyms;
    pIds:`$("PO_",/:string 1001 + til nP);
    sides:`B`S`B`B`S;
    algos:`VWAP`TWAP`IS`POV`VWAP;
    qtys:15f 120f 800f 2500f 1800f;

    parents:([]
        time:nP#starts;
        parentId:`u#pIds;
        clientId:`CITADEL`MILLENNIUM`TWO_SIGMA`JANE_STREET`JUMP;
        sym:`g#pSyms;
        side:sides;
        algo:algos;
        totalQty:qtys;
        arrivalPrice:arrPxs;
        startTime:nP#starts;
        endTime:nP#ends;
        limitPrice:arrPxs * ?[sides=`B; 1.005f; 0.995f]
        );

    // Slice each parent order into 8 child executions across venues
    makeChildren:{[pRow;quotes]
        k:8;
        cTimes:pRow[`startTime] + ((`long$pRow[`endTime] - pRow[`startTime]) div k) * til k;
        s:pRow`sym;
        qSlice:aj[`sym`time; ([] sym:k#s; time:cTimes); `sym`time xasc select sym, time, bid, ask from quotes];
        liqFlags:k?`MAKER`TAKER;
        dir:$[pRow[`side]=`B; 1f; -1f];
        midPx:0.5 * (qSlice`bid) + qSlice`ask;
        halfSp:0.5 * (qSlice`ask) - qSlice`bid;
        // Maker fills capture half spread; Taker fills cross half spread + slight impact
        fillPxs:midPx + dir * halfSp * ?[liqFlags=`TAKER; 1.15f; -0.4f];
        cQtys:(k#pRow[`totalQty] % k);
        ([] time:cTimes;
            execId:`$(("EX_",string[pRow`parentId],"_"),/:string 1 + til k);
            parentId:k#pRow`parentId;
            sym:k#s;
            venue:k?venues;
            side:k#pRow`side;
            fillPrice:fillPxs;
            fillQty:cQtys;
            liquidityFlag:liqFlags;
            feeBps:?[liqFlags=`MAKER; 1.0f; 3.5f])
        }[;quotes] each parents;

    `parentOrder`childExecution!(parents; `time xasc raze makeChildren)
    };

// Populate all global tables in-process (for standalone analytics, tests, or benchmarks)
populateSampleDataset:{[numTrades;numDeltasPerSym]
    t0:.z.p - 0D00:10:00;
    tq:genTradesAndQuotes[numTrades; t0];
    deltas:`time xasc raze genLobDeltas[;numDeltasPerSym;t0] each syms;
    abuse:injectAbuseScenarios[t0 + 0D00:02:00];
    allTrades:`time xasc (tq`trade), abuse`trade;
    allQuotes:`time xasc tq`quote;
    allDeltas:`time xasc deltas, abuse`lobDelta;
    orders:genParentAndChildOrders[allTrades; allQuotes];

    `trade set update `g#sym from allTrades;
    `quote set update `g#sym from allQuotes;
    `lobDelta set update `g#sym from allDeltas;
    `parentOrder set orders`parentOrder;
    `childExecution set update `g#parentId from orders`childExecution;

    `trades`quotes`lobDeltas`parentOrders`childExecutions!(
        count trade; count quote; count lobDelta; count parentOrder; count childExecution)
    };

\d .

// If launched with `-live 1`, connect to Tickerplant and stream ticks on timer
liveMode:.util.getOpt[`live;0i];
tpHostPort:.util.getOpt[`tp;`localhost:5010];

if[liveMode;
    h:.util.registerConn[`TP;`$":",string tpHostPort];
    .z.ts:{
        h:.util.connect`TP;
        if[not null h;
            tq:.feed.genTradesAndQuotes[10;.z.p];
            d:.feed.genLobDeltas[first 1?.feed.syms;6;.z.p];
            (neg h)(`upd;`quote;value flip tq`quote);
            (neg h)(`upd;`trade;value flip tq`trade);
            (neg h)(`upd;`lobDelta;value flip d);
            ];
        };
    system "t 250";
    .util.info "Live feed streaming to TP (",string[tpHostPort],") every 250ms";
    ];
