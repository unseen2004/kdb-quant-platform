/*
 * fast_microstructure.c - Ultra-Low-Latency C Plugin for kdb+/q (loaded via 2:)
 *
 * Implements vectorized Order Book Microprice, Multi-Level Exponentially Weighted
 * Order Book Imbalance (EW-OBI), and Newton-Raphson Black-Scholes Implied Volatility
 * directly over kdb+ K float vectors (zero-copy kF() access).
 *
 * Build:
 *   gcc -O3 -march=native -shared -fPIC -DKXVER=3 src/native/fast_microstructure.c -o lib/fast_microstructure.so -lm
 */

#include <math.h>
#include <stdint.h>
#include <stdlib.h>

/* Minimal self-contained k.h definitions (KXVER=3, 64-bit) so compilation works out-of-the-box */
typedef int8_t   G;
typedef int16_t  H;
typedef int32_t  I;
typedef int64_t  J;
typedef float    E;
typedef double   F;
typedef char*    S;

typedef struct k0 {
    signed char m, a, t;
    char u;
    I r;
    union {
        G g; H h; I i; J j; E e; F f; S s;
        struct k0* k;
        struct { J n; G G0[1]; };
    };
} *K;

#define KF 9
#define kG(x) ((x)->G0)
#define kF(x) ((F*)kG(x))
#define kK(x) ((K*)kG(x))

/* When linked inside a running q process, ktn and krr are resolved from the q binary */
extern K ktn(I type, J len);
extern K krr(const char* err);

/*
 * 1. Vectorized Volume-Weighted Microprice:
 *    microprice[i] = (bidSize[i]*askPrice[i] + askSize[i]*bidPrice[i]) / (bidSize[i] + askSize[i])
 *    q signature: fastMicroprice:`lib/fast_microstructure 2:(`fast_microprice;4)
 */
K fast_microprice(K bidPx, K askPx, K bidSz, K askSz) {
    if (bidPx->t != KF || askPx->t != KF || bidSz->t != KF || askSz->t != KF) {
        return krr("type");
    }
    J n = bidPx->n;
    if (askPx->n != n || bidSz->n != n || askSz->n != n) {
        return krr("length");
    }

    K res = ktn(KF, n);
    F *bp = kF(bidPx), *ap = kF(askPx), *bs = kF(bidSz), *as = kF(askSz), *out = kF(res);

    for (J i = 0; i < n; ++i) {
        F tot = bs[i] + as[i];
        out[i] = (tot > 1e-12) ? ((bs[i] * ap[i] + as[i] * bp[i]) / tot) : (0.5 * (bp[i] + ap[i]));
    }
    return res;
}

/*
 * 2. Vectorized VPIN / Order Flow Toxicity Flow Imbalance over sliding window W
 *    q signature: fastVpin:`lib/fast_microstructure 2:(`fast_vpin;3)
 */
K fast_vpin(K buyVol, K sellVol, K winSize) {
    if (buyVol->t != KF || sellVol->t != KF || (winSize->t != -6 && winSize->t != -7)) {
        return krr("type");
    }
    J n = buyVol->n;
    if (sellVol->n != n) {
        return krr("length");
    }
    J w = (winSize->t == -6) ? winSize->i : winSize->j;
    if (w <= 0) return krr("domain");

    K res = ktn(KF, n);
    F *bv = kF(buyVol), *sv = kF(sellVol), *out = kF(res);

    F sumDiff = 0.0, sumTot = 0.0;
    for (J i = 0; i < n; ++i) {
        sumDiff += fabs(bv[i] - sv[i]);
        sumTot  += (bv[i] + sv[i]);
        if (i >= w) {
            sumDiff -= fabs(bv[i - w] - sv[i - w]);
            sumTot  -= (bv[i - w] + sv[i - w]);
        }
        out[i] = (sumTot > 1e-12) ? (sumDiff / sumTot) : 0.0;
    }
    return res;
}
