// ============================================================================
// native.q - Dynamic C Shared Library Loader (2:) with Vectorized q Fallback
// ============================================================================

\d .native

soPath:`:lib/fast_microstructure;

// Pure vectorized q fallback implementations
qMicroprice:{[bp;ap;bs;as]
    tot:bs + as;
    ?[tot>1e-12; ((bs * ap) + (as * bp)) % tot; 0.5 * bp + ap]
    };

qVpin:{[bv;sv;w]
    diff:w msum abs bv - sv;
    tot:w msum bv + sv;
    ?[tot>1e-12; diff % tot; 0f]
    };

// Attempt to bind C shared object via `2:`; fallback to pure vectorized q
init:{[]
    loaded:@[{
        .native.microprice::.native.soPath 2:(`fast_microprice;4);
        .native.vpin::.native.soPath 2:(`fast_vpin;3);
        1b
        }; ::; 0b];
    if[not loaded;
        .native.microprice::.native.qMicroprice;
        .native.vpin::.native.qVpin;
        ];
    loaded
    };

isNativeLoaded:init[];

\d .
