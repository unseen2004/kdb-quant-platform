// ============================================================================
// u.q - Pub/Sub Management for Tickerplant & Chained Real-Time Engines
// ============================================================================

\d .u

init:{
    w::t!(count t::tables`.)#();
    };

// Remove handle from subscription dictionary
del:{w[x]_:w[x;;0]?y};

// Clean up on client disconnect
.z.pc:{del[;x]each t;};

// Select slice of table by subscribed symbols (` for all)
sel:{$[`~y;x;select from x where sym in y]};

// Publish table data to all subscribed handles asynchronously
pub:{[t;x]
    {[t;x;w]
        if[count x:sel[x] w 1;
            (neg first w)(`upd;t;x)]
    }[t;x] each w t
    };

// Add subscriber for table x and symbol list y
add:{
    $[(count w x)>i:w[x;;0]?z:.z.w;
        .[`.u.w;(x;i;1);union;y];
        w[x],:enlist(z;y)];
    (x;$[99=type v:value x;sel[v]y;@[0#v;`sym;`g#]])
    };

// Subscribe entry point: .u.sub[`trade;`BTCUSD`ETHUSD] or .u.sub[`;`]
sub:{
    if[x~`; :sub[;y]each t];
    if[not x in t; 'x];
    del[x].z.w;
    add[x;y]
    };

// Broadcast End-of-Day rollover signal to all unique subscribers
end:{
    (neg union/[w[;;0]])@\:(`.u.end;x)
    };

\d .
