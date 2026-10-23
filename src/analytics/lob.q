// ============================================================================
// lob.q - L3-to-L2 Limit Order Book Reconstruction, Microstructure & Slippage
// ============================================================================

\d .lob

// Active L3 order book state keyed by orderId
activeOrders:([orderId:`u#`symbol$()]
    time:`timestamp$();
    sym:`g#`symbol$();
    traderId:`symbol$();
    side:`symbol$();
    price:`float$();
    size:`float$()
    );

// Apply a single L3 delta dictionary to an activeOrders state table (usable with scan \ )
stepDelta:{[state;ev]
    act:ev`action;
    oid:ev`orderId;
    if[act=`ADD;
        :state upsert (oid;ev`time;ev`sym;ev`traderId;ev`side;ev`price;ev`size)];
    if[act=`MOD;
        if[oid in key[state]`orderId;
            state[oid;`time`price`size]:(ev`time;ev`price;ev`size)];
        :state];
    if[act=`CAN;
        :![state;enlist (=;`orderId;enlist oid);0b;`symbol$()]];
    if[act=`EXEC;
        if[oid in key[state]`orderId;
            rem:state[oid;`size] - ev`size;
            $[rem<=1e-9;
                state:![state;enlist (=;`orderId;enlist oid);0b;`symbol$()];
                state[oid;`time`size]:(ev`time;rem)]];
        :state];
    state
    };

// Apply batch of L3 delta rows to global .lob.activeOrders
processDeltas:{[deltas]
    .lob.activeOrders::stepDelta/[.lob.activeOrders; deltas];
    };

// Extract Top-N L2 price levels from an L3 state table for a given symbol
extractL2FromState:{[state;s;depth]
    sub:0!select from state where sym=s, size>1e-9;
    bids:`price xdesc select size:sum size by price from sub where side=`B;
    asks:`price xasc  select size:sum size by price from sub where side=`S;
    bp:depth#(exec price from bids),depth#0n;
    bs:depth#(exec size  from bids),depth#0f;
    ap:depth#(exec price from asks),depth#0n;
    as:depth#(exec size  from asks),depth#0f;
    b1:first bp; a1:first ap;
    bs1:first bs; as1:first as;
    mid:0.5 * b1 + a1;
    spBps:$[mid>0f; 10000f * (a1 - b1) % mid; 0n];
    tot1:bs1 + as1;
    imb:$[tot1>0f; (bs1 - as1) % tot1; 0f];
    micro:$[tot1>0f; ((bs1 * a1) + (as1 * b1)) % tot1; mid];
    `time`sym`bidPrices`bidSizes`askPrices`askSizes`mid`spreadBps`imbalance`microprice!(
        .z.p;s;bp;bs;ap;as;mid;spBps;imb;micro)
    };

// Reconstruct exact L2 order book at arbitrary historical timestamp `ts` from `lobDelta` table
reconstructAt:{[deltaTbl;s;ts;depth]
    evs:select from deltaTbl where sym=s, time<=ts;
    emptyState:0#.lob.activeOrders;
    finalState:stepDelta/[emptyState; evs];
    snap:extractL2FromState[finalState;s;depth];
    @[snap;`time;:;ts]
    };

// Replay a time-series of snapshots at every delta event using scan (\)
replayTrajectory:{[deltaTbl;s;depth]
    evs:select from deltaTbl where sym=s;
    if[0=count evs; :.schema.lobSnapshot];
    emptyState:0#.lob.activeOrders;
    states:1 _ stepDelta\[emptyState; evs];
    snaps:{[st;tm;s;d] @[extractL2FromState[st;s;d];`time;:;tm]}'[states; evs`time; count[evs]#s; count[evs]#depth];
    snaps
    };

// Vectorized Order Book Walk: estimate VWAP fill price & slippage (bps) for sweeping `qty`
// side = `B sweeps the Ask side; side = `S sweeps the Bid side
estimateSlippage:{[snap;side;qty]
    pxs:$[side=`B; snap`askPrices; snap`bidPrices];
    szs:$[side=`B; snap`askSizes;  snap`bidSizes];
    valid:where (not null pxs) & szs > 0f;
    pxs:pxs valid;
    szs:szs valid;
    if[0=count pxs;
        :`side`requestedQty`filledQty`vwapFillPrice`midPrice`slippageBps`levelsSwept!(side;qty;0f;0n;snap`mid;0n;0j)];
    cumSz:sums szs;
    prevCum:0f, -1 _ cumSz;
    taken:0f | (qty - prevCum) & szs;
    activeLvls:where taken > 0f;
    filled:sum taken;
    vwapPx:$[filled>0f; (sum taken * pxs) % filled; 0n];
    mid:snap`mid;
    dir:$[side=`B; 1f; -1f];
    slipBps:$[(filled>0f) & mid>0f; dir * 10000f * (vwapPx - mid) % mid; 0n];
    `side`requestedQty`filledQty`vwapFillPrice`midPrice`slippageBps`levelsSwept!(
        side;qty;filled;vwapPx;mid;slipBps;count activeLvls)
    };

// Multi-level Exponentially Weighted Order Book Imbalance (weights: exp(-0.5 * i))
multiLevelImbalance:{[snap]
    w:exp -0.5 * til count snap`bidSizes;
    wb:sum w * snap`bidSizes;
    wa:sum w * snap`askSizes;
    $[(wb+wa)>0f; (wb - wa) % (wb + wa); 0f]
    };

\d .
