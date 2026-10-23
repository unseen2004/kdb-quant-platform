// ============================================================================
// util.q - Logging, IPC Connection Pool, Profiling & Vectorized Quant Helpers
// ============================================================================

\d .util

// Structured logger with ISO-8601 timestamp and process tag
procName:`unknown;
setProc:{[name] procName::name;};

logMsg:{[level;msg]
    ts:string .z.p;
    out:ts," [",string[procName],"] [",string[level],"] ",$[10h=type msg;msg;-3!msg];
    $[`ERROR=level; -2 out; -1 out];
    };

info:logMsg[`INFO;];
warn:logMsg[`WARN;];
err:logMsg[`ERROR;];

// Parse command-line options with defaults: .util.getOpt[`port;5010i]
getOpt:{[k;default]
    opts:.Q.opt .z.x;
    $[(k in key opts) & count opts k;
        (type default)$first opts k;
        default]
    };

// Safe IPC connection open with timeout and retry state
conns:([name:`symbol$()] hostPort:`symbol$(); handle:`int$(); lastAttempt:`timestamp$());

registerConn:{[name;hp]
    `.util.conns upsert (name;hp;0Ni;0Np);
    connect name
    };

connect:{[name]
    row:.util.conns name;
    if[not null row`handle; :row`handle];
    hp:row`hostPort;
    h:@[hopen;(hp;2000);0Ni];
    `.util.conns upsert (name;hp;h;.z.p);
    $[null h;
        .util.warn "Failed to connect to ",string[name]," (",string[hp],")";
        .util.info "Connected to ",string[name]," on handle ",string h];
    h
    };

// Handle disconnect callback helper
onDisconnect:{[w]
    disconnected:exec name from .util.conns where handle=w;
    if[count disconnected;
        .util.warn "Disconnected from: ",", " sv string disconnected;
        update handle:0Ni from `.util.conns where handle=w];
    };

// Vectorized basis points calculation: (p2 - p1) / p1 * 10000
// Side-aware: if side=`B, paying more than benchmark is negative/costly
bpsDiff:{[px;bench;side]
    dir:?[side=`B; 1f; -1f];
    dir * 10000f * (px - bench) % bench
    };

// Exponential Moving Average (vectorized via scan)
ema:{[alpha;x]
    ema[alpha;x]:first[x]{(x*1-y)+z*y}\[alpha;x]
    };
ema:{[alpha;x] ({(z*1-x)+y*x}[alpha])\ [first x; 1_x] };

// Rolling Z-Score over window n
zscore:{[n;x]
    mu:n mavg x;
    sd:n mdev x;
    ?[sd>0f; (x - mu) % sd; 0f]
    };

// Microsecond timer / memory profiler for any q expression or function application
profile:{[label;fn;args]
    t0:.z.p;
    m0:.Q.w[]`used;
    res:fn . args;
    dt:(`long$.z.p - t0) div 1000; // microseconds (long)
    dm:(.Q.w[]`used) - m0;
    `label`timeUs`memDeltaBytes`result!(label;dt;dm;res)
    };

\d .
