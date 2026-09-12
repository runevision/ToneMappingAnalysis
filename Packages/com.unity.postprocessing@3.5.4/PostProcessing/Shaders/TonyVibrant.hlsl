/*
* Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef __TONY_VIBRANT__
#define __TONY_VIBRANT__

int GetMinIndex(float3 v)
{
    bool xy = v.x < v.y;
    bool yz = v.y < v.z;
    bool zx = v.z < v.x;
    return (yz && !xy) + 2 * (zx && !yz);
}

int GetMaxIndex(float3 v)
{
    bool xy = v.x < v.y;
    bool yz = v.y < v.z;
    bool zx = v.z < v.x;
    return (!yz && xy) + 2 * (!zx && yz);
}

float SlowDown(float v, float scale, float slow)
{
    return log(v / scale * slow + 1) / slow * scale;
}

float3 Remap(float3 x, float fromMin, float fromMax, float toMin, float toMax)
{
    fromMin = min(fromMin, fromMax - 0.0001);
    return (x - fromMin) / (fromMax - fromMin) * (toMax - toMin) + toMin;
}

// curve: x: inverseWhitePoint, y: x0, z: x1
float3 TonyVibrantTonemap(float3 x, float3 curve, float4 toeSegmentA, float2 toeSegmentB, float4 midSegmentA, float2 midSegmentB, float4 shoSegmentA, float2 shoSegmentB, float whitening)
{
    // Color boost removes less saturation from less saturated colors.
    const float colorBoost  =  0.5; // 0 - 1

    // Color shifting shifts colors towards cyan, magenta, and yellow.
    const float shiftAmount =  0.6; // 0 - 1 (param)
    const float shiftStart  = -5.0; // -10 - 10
    const float shiftEnd    =  7.0; // -10 - 10

    // Desaturation makes brighter colors more white.
    const float desatStart  =  0.3; // 0 - 10
    const float desatEnd    =  4.8; // 0 - 10
    // Bias affects which colors get desaturated at which brightness.
    const float desatBias   =  0.0; // 0 - 3 (param)

    // Slow down how fast the shoulder reaches 1.
    // (The builtin shoulder-length has little effect beyond a point.)
    const float slowDown    =  0.1; // 0.001 - 1

    float3 normX = x * curve.x;

    // Per channel mapping.
    float3 mappedCh;
    mappedCh.x = EvalCustomCurve(SlowDown(normX.x, curve.x, slowDown), curve, toeSegmentA, toeSegmentB, midSegmentA, midSegmentB, shoSegmentA, shoSegmentB);
    mappedCh.y = EvalCustomCurve(SlowDown(normX.y, curve.x, slowDown), curve, toeSegmentA, toeSegmentB, midSegmentA, midSegmentB, shoSegmentA, shoSegmentB);
    mappedCh.z = EvalCustomCurve(SlowDown(normX.z, curve.x, slowDown), curve, toeSegmentA, toeSegmentB, midSegmentA, midSegmentB, shoSegmentA, shoSegmentB);

    // Find minimum and maximum values.
    int minIndex = GetMinIndex(x);
    int maxIndex = GetMaxIndex(x);
    float xMin = x[minIndex];
    float xMax = x[maxIndex];
    float mappedMin = mappedCh[minIndex];
    float mappedMax = mappedCh[maxIndex];
    float logVal = log(xMax);

    // HUE PRESERVING REMAP
    // Hue preserving mapping based on mapping old min-max range to new one.
    float3 mapped = Remap(x, xMin, xMax, mappedMin, mappedMax);

    // HUE SHIFTING AT HIGHER BRIGHTNESS LEVELS
    // Apply lerp from hue preserving to hue shifted per-channel mapping.
    float discolorLerp = shiftAmount * smoothstep(shiftStart, shiftEnd, logVal);
    mapped = lerp(mapped, mappedCh, discolorLerp);

    // BOOST SATURATION A LITTLE (WHILE NOT CAUSING LUMINANCE INVERSION)
    // Hue preserving mapping based on mapping old max to new one.
    // This preserves maximal saturated, but doesn't work on its own.
    float3 mappedScaled = x * mappedMax / xMax;
    // Allow less contribution from the boost at higher brightness levels.
    float boostLerp = colorBoost * sqrt(mappedMin) / pow(1 + xMin, 2);
    mapped = lerp(mapped, mappedScaled, boostLerp);

    // Optional color bias to make whitening happen sooner for brighter colors.
    float bias = (0.333 * x.r + 0.555 * x.g + 0.111 * x.b) / xMax - 0.5;
    bias *= desatBias;

    // DESATURATE AT HIGHER BRIGHTNESS LEVELS
    // Apply lerp from color to max channel (grayscale, close to white).
    float desatLerp = smoothstep(desatStart, desatEnd, logVal + bias);
    mapped = lerp(mapped, mappedMax, desatLerp);

    return mapped;
}

#endif // __TONY_VIBRANT__
