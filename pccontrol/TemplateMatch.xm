#import "TemplateMatch.h"
#import <Accelerate/Accelerate.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#include <math.h>

// Convert a CGImage to a grayscale float buffer. Caller must free.
static float* cgImageToGrayscaleFloat(CGImageRef img, size_t *outWidth, size_t *outHeight) {
    size_t w = CGImageGetWidth(img);
    size_t h = CGImageGetHeight(img);
    *outWidth = w;
    *outHeight = h;

    size_t bytesPerRow = w * 4;
    unsigned char *rgba = (unsigned char *)malloc(bytesPerRow * h);
    if (!rgba) return NULL;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgba, w, h, 8, bytesPerRow, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) {
        free(rgba);
        return NULL;
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    CGContextRelease(ctx);

    float *gray = (float *)malloc(w * h * sizeof(float));
    if (!gray) {
        free(rgba);
        return NULL;
    }

    for (size_t i = 0; i < w * h; i++) {
        gray[i] = 0.299f * rgba[i * 4] + 0.587f * rgba[i * 4 + 1] + 0.114f * rgba[i * 4 + 2];
    }
    free(rgba);
    return gray;
}

static float* loadImageToGrayscaleFloat(NSString *path, size_t *outWidth, size_t *outHeight) {
    UIImage *ui = [UIImage imageWithContentsOfFile:path];
    if (!ui || !ui.CGImage) return NULL;
    return cgImageToGrayscaleFloat(ui.CGImage, outWidth, outHeight);
}

static float* resizeFloat(const float *src, size_t srcW, size_t srcH, size_t dstW, size_t dstH) {
    float *dst = (float *)malloc(dstW * dstH * sizeof(float));
    if (!dst) return NULL;

    vImage_Buffer srcBuf = { (void*)src, srcH, srcW, srcW * sizeof(float) };
    vImage_Buffer dstBuf = { dst, dstH, dstW, dstW * sizeof(float) };
    vImage_Error error = vImageScale_PlanarF(&srcBuf, &dstBuf, NULL, kvImageEdgeExtend);
    if (error != kvImageNoError) {
        free(dst);
        return NULL;
    }
    return dst;
}

static BOOL buildIntegralImages(const float *img, size_t w, size_t h, double **outSum, double **outSqSum) {
    size_t stride = w + 1;
    size_t rows = h + 1;
    double *sum = (double *)calloc(stride * rows, sizeof(double));
    double *sqSum = (double *)calloc(stride * rows, sizeof(double));
    if (!sum || !sqSum) {
        if (sum) free(sum);
        if (sqSum) free(sqSum);
        return NO;
    }

    for (size_t y = 1; y <= h; y++) {
        double rowSum = 0.0;
        double rowSqSum = 0.0;
        for (size_t x = 1; x <= w; x++) {
            double value = img[(y - 1) * w + (x - 1)];
            rowSum += value;
            rowSqSum += value * value;
            size_t idx = y * stride + x;
            sum[idx] = sum[(y - 1) * stride + x] + rowSum;
            sqSum[idx] = sqSum[(y - 1) * stride + x] + rowSqSum;
        }
    }

    *outSum = sum;
    *outSqSum = sqSum;
    return YES;
}

static inline double integralRectSum(const double *integral, size_t imgW, size_t x, size_t y, size_t w, size_t h) {
    size_t stride = imgW + 1;
    size_t x2 = x + w;
    size_t y2 = y + h;
    return integral[y2 * stride + x2] - integral[y * stride + x2] - integral[y2 * stride + x] + integral[y * stride + x];
}

static float* centeredTemplate(const float *tmpl, size_t tw, size_t th, float *outNorm) {
    size_t n = tw * th;
    float *tmplCentered = (float *)malloc(n * sizeof(float));
    if (!tmplCentered) return NULL;
    memcpy(tmplCentered, tmpl, n * sizeof(float));

    float tmplMean = 0.0f;
    vDSP_meanv(tmplCentered, 1, &tmplMean, n);
    float negTmplMean = -tmplMean;
    vDSP_vsadd(tmplCentered, 1, &negTmplMean, tmplCentered, 1, n);

    float tmplNorm = 0.0f;
    vDSP_svesq(tmplCentered, 1, &tmplNorm, n);
    *outNorm = tmplNorm;
    return tmplCentered;
}

static float nccScoreFast(const float *img, size_t imgW,
                          const double *integral, const double *sqIntegral,
                          const float *tmplCentered, float tmplNorm,
                          size_t tw, size_t th, size_t x, size_t y) {
    size_t n = tw * th;
    double patchSum = integralRectSum(integral, imgW, x, y, tw, th);
    double patchSqSum = integralRectSum(sqIntegral, imgW, x, y, tw, th);
    double patchNorm = patchSqSum - ((patchSum * patchSum) / (double)n);
    // patchNorm is a difference of two ~1e9 values, so a flat patch leaves a
    // rounding residue of ~1e-5 behind; an absolute epsilon lets that residue
    // through as a near-zero denominator and inflates the score past 1. Compare
    // against the patch's own magnitude instead.
    if (patchNorm <= 1e-6 * patchSqSum || tmplNorm <= 1e-6f) return 0.0f;

    double dotProduct = 0.0;
    for (size_t row = 0; row < th; row++) {
        float rowDot = 0.0f;
        vDSP_dotpr(img + (y + row) * imgW + x, 1,
                   tmplCentered + row * tw, 1,
                   &rowDot, tw);
        dotProduct += rowDot;
    }

    double denom = sqrt(patchNorm * (double)tmplNorm);
    if (denom < 1e-6) return 0.0f;
    float score = (float)(dotProduct / denom);
    return MAX(-1.0f, MIN(1.0f, score));
}

#define ZX_COARSE_CANDIDATES 4

// Collect the best few distinct coarse hits. The coarse level is too blunt to
// commit to a single peak, and two hits closer together than minDist are the
// same find reported twice -- in which case the better of the two is kept, so a
// hit is never represented by a neighbour that scored lower than it.
static void zxAddCandidate(float *scores, size_t *xs, size_t *ys, int *count,
                           float score, size_t x, size_t y, size_t minDist) {
    size_t minDistSq = minDist * minDist;
    int worst = 0;
    for (int k = 0; k < *count; k++) {
        long dx = (long)x - (long)xs[k];
        long dy = (long)y - (long)ys[k];
        if ((size_t)(dx * dx + dy * dy) < minDistSq) {
            if (score > scores[k]) {
                scores[k] = score;
                xs[k] = x;
                ys[k] = y;
            }
            return;
        }
        if (scores[k] < scores[worst]) worst = k;
    }
    if (*count < ZX_COARSE_CANDIDATES) {
        scores[*count] = score;
        xs[*count] = x;
        ys[*count] = y;
        (*count)++;
    } else if (score > scores[worst]) {
        scores[worst] = score;
        xs[worst] = x;
        ys[worst] = y;
    }
}

@interface TemplateMatch() {
    int _maxTryTimes;
    float _acceptableValue;
    float _scaleRation;
}
@end

@implementation TemplateMatch

- (instancetype)init {
    self = [super init];
    _maxTryTimes = 4;
    _acceptableValue = 0.8f;
    _scaleRation = 0.8f;
    return self;
}

- (void)setAcceptableValue:(float)av { _acceptableValue = av; }
- (void)setMaxTryTimes:(int)mtt     { _maxTryTimes = MAX(0, MIN(mtt, 8)); }
- (void)setScaleRation:(float)sr    { _scaleRation = (sr > 0.05f && sr < 1.0f) ? sr : 0.8f; }

- (CGRect)templateMatchWithCGImage:(CGImageRef)img templatePath:(NSString*)templatePath error:(NSError**)err {
    CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
    size_t imgW = 0, imgH = 0;
    float *imgGray = cgImageToGrayscaleFloat(img, &imgW, &imgH);
    if (!imgGray) {
        *err = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                userInfo:@{NSLocalizedDescriptionKey:@"-1;;image_match: failed to convert screenshot to grayscale\r\n"}];
        return CGRectZero;
    }

    size_t tmplW = 0, tmplH = 0;
    float *tmplGray = loadImageToGrayscaleFloat(templatePath, &tmplW, &tmplH);
    if (!tmplGray) {
        free(imgGray);
        *err = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:
                    @"-1;;image_match: failed to load template: %@\r\n", templatePath]}];
        return CGRectZero;
    }

    double *integral = NULL;
    double *sqIntegral = NULL;
    if (!buildIntegralImages(imgGray, imgW, imgH, &integral, &sqIntegral)) {
        free(imgGray);
        free(tmplGray);
        *err = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                userInfo:@{NSLocalizedDescriptionKey:@"-1;;image_match: failed to allocate integral image buffers\r\n"}];
        return CGRectZero;
    }

    // Coarse level. Scanning the full-resolution correlation surface on a stride
    // of min(tw,th)/8 steps straight over the match: a template with fine detail
    // only scores near the threshold within about two pixels, so a 8-20px stride
    // reports a perfect, pixel-for-pixel on-screen match as "not found" (measured
    // 0.56 for a match scoring 1.00). Downsampling the screen and the template
    // first broadens that peak, so an exhaustive search of the small level lands
    // within a couple of pixels of the match for 1/F^4 of the full-res cost.
    int pyramid = (int)MAX((size_t)1, MIN((size_t)4, MIN(tmplW, tmplH) / 8));
    size_t coarseW = 0, coarseH = 0;
    float *coarseGray = NULL;
    double *coarseIntegral = NULL;
    double *coarseSqIntegral = NULL;
    if (pyramid > 1) {
        coarseW = imgW / pyramid;
        coarseH = imgH / pyramid;
        if (coarseW >= 8 && coarseH >= 8) {
            coarseGray = resizeFloat(imgGray, imgW, imgH, coarseW, coarseH);
            if (coarseGray && !buildIntegralImages(coarseGray, coarseW, coarseH,
                                                   &coarseIntegral, &coarseSqIntegral)) {
                free(coarseGray);
                coarseGray = NULL;
            }
        } else {
            coarseW = 0;
            coarseH = 0;
        }
        if (!coarseGray) pyramid = 1;
    }

    CGRect best = CGRectZero;
    float bestScore = -1.0f;

    NSMutableArray *scales = [NSMutableArray array];
    [scales addObject:@(1.0f)];
    for (int i = 0; i < _maxTryTimes; i++) {
        [scales addObject:@(powf(2.0f - _scaleRation, i + 1))];
        [scales addObject:@(powf(_scaleRation, i + 1))];
    }

    for (NSNumber *scaleNum in scales) {
        float scale = scaleNum.floatValue;
        size_t tw = (size_t)llround((double)tmplW * scale);
        size_t th = (size_t)llround((double)tmplH * scale);
        if (tw < 2 || th < 2 || tw >= imgW || th >= imgH) continue;

        float *tmplScaled = NULL;
        if (fabsf(scale - 1.0f) < 0.0001f) {
            tmplScaled = tmplGray;
        } else {
            tmplScaled = resizeFloat(tmplGray, tmplW, tmplH, tw, th);
            if (!tmplScaled) continue;
        }

        float tmplNorm = 0.0f;
        float *tmplCentered = centeredTemplate(tmplScaled, tw, th, &tmplNorm);
        if (tmplCentered && tmplNorm > 1e-6f) {
            float candScores[ZX_COARSE_CANDIDATES];
            size_t candXs[ZX_COARSE_CANDIDATES];
            size_t candYs[ZX_COARSE_CANDIDATES];
            int candCount = 0;
            size_t pad = 0;

            if (coarseGray) {
                size_t ctw = MAX((size_t)2, (size_t)llround((double)tw / (double)pyramid));
                size_t cth = MAX((size_t)2, (size_t)llround((double)th / (double)pyramid));
                if (ctw < coarseW && cth < coarseH) {
                    float *coarseTmpl = resizeFloat(tmplScaled, tw, th, ctw, cth);
                    float coarseNorm = 0.0f;
                    float *coarseCentered = coarseTmpl ? centeredTemplate(coarseTmpl, ctw, cth, &coarseNorm) : NULL;
                    if (coarseCentered && coarseNorm > 1e-6f) {
                        size_t minDist = MAX((size_t)2, MIN(ctw, cth) / 2);
                        for (size_t y = 0; y + cth <= coarseH; y++) {
                            for (size_t x = 0; x + ctw <= coarseW; x++) {
                                float score = nccScoreFast(coarseGray, coarseW, coarseIntegral,
                                                           coarseSqIntegral, coarseCentered, coarseNorm,
                                                           ctw, cth, x, y);
                                zxAddCandidate(candScores, candXs, candYs, &candCount, score,
                                               x * (size_t)pyramid, y * (size_t)pyramid, minDist);
                            }
                        }
                        pad = (size_t)pyramid * 2 + 2;
                    }
                    if (coarseCentered) free(coarseCentered);
                    free(coarseTmpl);
                }
            }

            if (candCount == 0) {
                // No usable coarse level -- tiny template, or the downsample or
                // its integral images could not be allocated. Fall back to the
                // strided scan, whose stride of min(tw,th)/8 is small enough for
                // these templates that the peak survives it.
                size_t step = MAX((size_t)1, MIN(tw, th) / 8);
                float coarseScore = -1.0f;
                for (size_t y = 0; y + th <= imgH; y += step) {
                    for (size_t x = 0; x + tw <= imgW; x += step) {
                        float score = nccScoreFast(imgGray, imgW, integral, sqIntegral,
                                                   tmplCentered, tmplNorm, tw, th, x, y);
                        if (score > coarseScore) {
                            coarseScore = score;
                            candXs[0] = x;
                            candYs[0] = y;
                        }
                    }
                }
                candScores[0] = coarseScore;
                candCount = 1;
                pad = MAX((size_t)4, step);
            }

            // Rescore every candidate at step 1. This always runs: it is what
            // actually measures the match, so gating it on the coarse score --
            // as the previous revision did -- threw away matches whose coarse
            // hit happened to land next to the peak instead of on it.
            float scaleScore = -1.0f;
            size_t hitX = 0;
            size_t hitY = 0;
            for (int c = 0; c < candCount; c++) {
                size_t rx = (candXs[c] > pad) ? candXs[c] - pad : 0;
                size_t ry = (candYs[c] > pad) ? candYs[c] - pad : 0;
                size_t rxMax = MIN(candXs[c] + pad, imgW - tw);
                size_t ryMax = MIN(candYs[c] + pad, imgH - th);
                for (size_t y = ry; y <= ryMax; y++) {
                    for (size_t x = rx; x <= rxMax; x++) {
                        float score = nccScoreFast(imgGray, imgW, integral, sqIntegral,
                                                   tmplCentered, tmplNorm, tw, th, x, y);
                        if (score > scaleScore) {
                            scaleScore = score;
                            hitX = x;
                            hitY = y;
                        }
                    }
                }
            }
            if (scaleScore > bestScore) {
                bestScore = scaleScore;
                best = CGRectMake(hitX, hitY, tw, th);
            }
        }

        free(tmplCentered);
        if (tmplScaled != tmplGray) free(tmplScaled);

        if (bestScore >= _acceptableValue) break;
    }

    free(coarseIntegral);
    free(coarseSqIntegral);
    free(coarseGray);
    free(integral);
    free(sqIntegral);
    free(imgGray);
    free(tmplGray);

    CFTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - startedAt;
    if (bestScore >= _acceptableValue) {
        NSLog(@"com.zjx.springboard: image_match success. x:%.0f y:%.0f w:%.0f h:%.0f score:%.3f elapsed:%.3fs",
              best.origin.x, best.origin.y, best.size.width, best.size.height, bestScore, elapsed);
        return best;
    }

    NSLog(@"com.zjx.springboard: image_match failed. best score: %.3f elapsed:%.3fs", bestScore, elapsed);
    *err = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:
                @"-1;;image_match: no match found (best score: %.3f, required: %.3f)\r\n",
                bestScore, _acceptableValue]}];
    return CGRectZero;
}

@end
