// ============================================================================
// tp.q - High-Throughput Tickerplant with Binary Write-Ahead Logging & EOD
// ============================================================================

\l src/common/schema.q
\l src/common/util.q
\l src/tick/u.q

.util.setProc[`TP];
initTables[];

\d .u

ld:{[d]
    L::`$(":",tplogDir,"/",string[tplogPrefix],string d);
    if[not type key L; .[L;();:;()]];
    i::j::-11!(-2;L);
    if[0<=type i;
        .util.warn "Corrupt tail in TP log ",(string L)," - truncating to valid record ",string last i;
        i::j::last i];
    hopen L
    };

tick:{[dir;prefix]
    init[];
    if[not min(`time`sym~2#key flip value@)each t; '`timesym];
    @[;`sym;`g#]each t;
    d::.z.D;
    tplogDir::dir;
    tplogPrefix::prefix;
    l::ld d
    };

endofday:{
    end d;
    d+:1;
    if[l; hclose l; l::0];
    l::ld d;
    .util.info "Completed EOD rollover to date ",string d;
    };

ts:{[dt]
    if[d<dt;
        if[d<dt-1; system"t 0"; '"more than one day?"];
        endofday[]]
    };

// Batched mode (timer > 0) vs Zero-Latency Immediate mode (timer = 0)
if[system"t";
    .z.ts:{
        pub'[t;value each t];
        @[`.;t;@[;`sym;`g#]0#];
        i::j;
        ts .z.D};
    upd:{[t;x]
        ts"d"$a:.z.P;
        if[not -16=type first first x; a:"n"$a; x:$[0>type first x;a,x;(enlist(count first x)#a),x]];
        t insert x;
        if[l; l enlist (`upd;t;x); j+:1]}
    ];

if[not system"t";
    system"t 1000";
    .z.ts:{ts .z.D};
    upd:{[t;x]
        ts"d"$a:.z.P;
        if[not -16=type first first x;
            if[null first first x; x[0]:(count first x)#a];
            ];
        f:key flip value t;
        pub[t;$[0>type first x;enlist f!x;flip f!x]];
        if[l; l enlist (`upd;t;x); i+:1]}
    ];

\d .

// Startup configuration
port:.util.getOpt[`port;5010i];
logDir:string .util.getOpt[`logdir;`tplog];
system "p ",string port;
system "mkdir -p ",logDir;

.u.tick[logDir;`tp_];
.util.info "Tickerplant listening on port ",string[port],", logging to ",logDir;
