// Implementation of the GT7 Tone Mapping operator.
//
// Adapted as a HLSL shader by aletschfirn, 2025.
// at https://github.com/aletschfirn/gt7tonemapper
//
// Adapted as a Unity shader by Rune Skovbo Johansen, 2026.

// MIT License
//
// Copyright (c) 2025 Polyphony Digital Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

Shader "Tone Mapping/GT7"
{
	Properties
	{
		_MainTex ("Identity LUT", 2D) = "white" {}
		mapping ("Mapping (0=ICTCP, 1=JZAZBZ)", Integer) = 0
		dynamic_range ("Dynamic Range (0=SDR, 1=HDR)", Integer) = 0
		exposure ("Exposure", Range(0.1, 10.0)) = 1.0
		blendRatio ("Blend Ratio", Range(0.1, 1.0)) = 0.6
		fadeStart ("Fade Start", Range(0.1, 2.0)) = 0.98
		fadeEnd ("Fade End", Range(0.1, 2.0)) = 1.16
		hdr_luminance ("HDR Luminance", Range(250.0, 10000.0)) = 1000.0
		JZAZBZ_EXPONENT_SCALE_FACTOR ("JZAZBZ exponent scale factor", Range(0.1, 10.0)) = 1.7
	}

	SubShader
	{
		Cull Off
		ZWrite Off
		ZTest Always

		Pass
		{
			HLSLPROGRAM
			#pragma vertex Vert
			#pragma fragment Frag

			#include "UnityCG.cginc"

			sampler2D _MainTex;

			struct appdata {
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f {
				float4 position : SV_POSITION;
				float2 uv : TEXCOORD0;
			};

			v2f Vert(appdata v)
			{
				v2f o;
				o.position = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}

			// -----------------------------------------------------------------------------
			// Mode options.
			// -----------------------------------------------------------------------------
			int mapping; // 0=ICTCP, 1=JZAZBZ
			int dynamic_range; // 0=SDR, 1=HDR
			float exposure;
			float blendRatio;
			float fadeStart;
			float fadeEnd;
			float hdr_luminance;
			float JZAZBZ_EXPONENT_SCALE_FACTOR;

			// -----------------------------------------------------------------------------
			// Defines the SDR reference white level used in our tone mapping (typically 250 nits).
			// -----------------------------------------------------------------------------
			#define GRAN_TURISMO_SDR_PAPER_WHITE 250.0f // cd/m^2

			// -----------------------------------------------------------------------------
			// Gran Turismo luminance-scale conversion helpers.
			// In Gran Turismo, 1.0f in the linear frame-buffer space corresponds to
			// REFERENCE_LUMINANCE cd/m^2 of physical luminance (typically 100 cd/m^2).
			// -----------------------------------------------------------------------------
			#define REFERENCE_LUMINANCE 100.0f // cd/m^2 <-> 1.0f

			float frameBufferValueToPhysicalValue(float fbValue)
			{
				// Converts linear frame-buffer value to physical luminance (cd/m^2)
				// where 1.0 corresponds to REFERENCE_LUMINANCE (e.g., 100 cd/m^2).
				return fbValue * REFERENCE_LUMINANCE;
			}

			float physicalValueToFrameBufferValue(float physical)
			{
				// Converts physical luminance (cd/m^2) to a linear frame-buffer value,
				// where 1.0 corresponds to REFERENCE_LUMINANCE (e.g., 100 cd/m^2).
				return physical / REFERENCE_LUMINANCE;
			}

			// -----------------------------------------------------------------------------
			// Utility functions.
			// -----------------------------------------------------------------------------
			float smoothStep(float x, float edge0, float edge1)
			{
				float t = (x - edge0) / (edge1 - edge0);

				if (x < edge0)
				{
					return 0.0f;
				}
				if (x > edge1)
				{
					return 1.0f;
				}

				return t * t * (3.0f - 2.0f * t);
			}

			float chromaCurve(float x, float a, float b)
			{
				return 1.0f - smoothStep(x, a, b);
			}

			// -----------------------------------------------------------------------------
			// GT7 Tone Mapping class.
			// -----------------------------------------------------------------------------
			struct GT7ToneMapping {
				float sdrCorrectionFactor_;

				float framebufferLuminanceTarget_;
				float framebufferLuminanceTargetUcs_; // Target luminance in UCS space
				float peakIntensity_;
				float alpha_;
				float midPoint_;
				float linearSection_;
				float toeStrength_;
				float kA_, kB_, kC_;

				float blendRatio_;
				float fadeStart_;
				float fadeEnd_;

			};

			// -----------------------------------------------------------------------------
			// "GT Tone Mapping" curve with convergent shoulder.
			// -----------------------------------------------------------------------------
			struct GTToneMappingCurveV2 {
				float peakIntensity_;
				float alpha_;
				float midPoint_;
				float linearSection_;
				float toeStrength_;
				float kA_, kB_, kC_;
			};

			void initializeCurve(inout GT7ToneMapping toneMapper, float monitorIntensity, float alpha, float grayPoint, float linearSection, float toeStrength)
			{
				// Added to avoid compile error:
				toneMapper.framebufferLuminanceTargetUcs_ = 0;
				toneMapper.blendRatio_ = 0;
				toneMapper.fadeStart_ = 0;
				toneMapper.fadeEnd_ = 0;

				toneMapper.peakIntensity_ = monitorIntensity;
				toneMapper.alpha_ = alpha;
				toneMapper.midPoint_ = grayPoint;
				toneMapper.linearSection_ = linearSection;
				toneMapper.toeStrength_ = toeStrength;
				// Pre-compute constants for the shoulder region.
				float k = (toneMapper.linearSection_ - 1.0f) / (toneMapper.alpha_ - 1.0f);
				toneMapper.kA_ = toneMapper.peakIntensity_ * toneMapper.linearSection_ + toneMapper.peakIntensity_ * k;
				toneMapper.kB_ = -toneMapper.peakIntensity_ * k * exp(toneMapper.linearSection_ / k);
				toneMapper.kC_ = -1.0f / (k * toneMapper.peakIntensity_);
			}

			float evaluateCurve(in GT7ToneMapping toneMapper, float x)
			{
				if (x < 0.0f)
				{
					return 0.0f;
				};
				float weightLinear = smoothStep(x, 0.0f, toneMapper.midPoint_);
				float weightToe = 1.0f - weightLinear;
				// Shoulder mapping for highlights.
				float shoulder = toneMapper.kA_ + toneMapper.kB_ * exp(x * toneMapper.kC_);
				if (x < toneMapper.linearSection_ * toneMapper.peakIntensity_)
				{
					float toeMapped = toneMapper.midPoint_ * pow(x / toneMapper.midPoint_, toneMapper.toeStrength_);
					return weightToe * toeMapped + weightLinear * x;
				}
				else
				{
					return shoulder;
				}
			}

			// -----------------------------------------------------------------------------
			// EOTF / inverse-EOTF for ST-2084 (PQ).
			// Note: Introduce exponentScaleFactor to allow scaling of the exponent in the EOTF for Jzazbz.
			// -----------------------------------------------------------------------------
			float eotfSt2084(float n, float exponentScaleFactor = 1.0f)
			{
				if (n < 0.0f)
				{
					n = 0.0f;
				}
				if (n > 1.0f)
				{
					n = 1.0f;
				}

				// Base functions from SMPTE ST 2084:2014
				// Converts from normalized PQ (0-1) to absolute luminance in cd/m^2 (linear light)
				// Assumes float input; does not handle integer encoding (Annex)
				// Assumes full-range signal (0-1)
				const float m1 = 0.1593017578125f;                // (2610 / 4096) / 4
				const float m2 = 78.84375f * exponentScaleFactor; // (2523 / 4096) * 128
				const float c1 = 0.8359375f;                      // 3424 / 4096
				const float c2 = 18.8515625f;                     // (2413 / 4096) * 32
				const float c3 = 18.6875f;                        // (2392 / 4096) * 32
				const float pqC = 10000.0f;                        // Maximum luminance supported by PQ (cd/m^2)

				// Does not handle signal range from 2084 - assumes full range (0-1)
				float np = pow(n, 1.0f / m2);
				float l = np - c1;

				if (l < 0.0f)
				{
					l = 0.0f;
				}

				l = l / (c2 - c3 * np);
				l = pow(l, 1.0f / m1);

				// Convert absolute luminance (cd/m^2) into the frame-buffer linear scale.
				return physicalValueToFrameBufferValue(l * pqC);
			}

			float inverseEotfSt2084(float v, float exponentScaleFactor = 1.0f)
			{
				const float m1 = 0.1593017578125f;
				const float m2 = 78.84375f * exponentScaleFactor;
				const float c1 = 0.8359375f;
				const float c2 = 18.8515625f;
				const float c3 = 18.6875f;
				const float pqC = 10000.0f;

				// Convert the frame-buffer linear scale into absolute luminance (cd/m^2).
				float physical = frameBufferValueToPhysicalValue(v);
				float y = physical / pqC; // Normalize for the ST-2084 curve

				float ym = pow(y, m1);
				return exp2(m2 * (log2(c1 + c2 * ym) - log2(1.0f + c3 * ym)));
			}

			// -----------------------------------------------------------------------------
			// ICtCp conversion.
			// Reference: ITU-T T.302 (https://www.itu.int/rec/T-REC-T.302/en)
			// -----------------------------------------------------------------------------
			void rgbToICtCp(const float3 rgb, out float3 ictCp) // Input: linear Rec.2020
			{
				float l = (rgb[0] * 1688.0f + rgb[1] * 2146.0f + rgb[2] * 262.0f) / 4096.0f;
				float m = (rgb[0] * 683.0f + rgb[1] * 2951.0f + rgb[2] * 462.0f) / 4096.0f;
				float s = (rgb[0] * 99.0f + rgb[1] * 309.0f + rgb[2] * 3688.0f) / 4096.0f;

				float lPQ = inverseEotfSt2084(l);
				float mPQ = inverseEotfSt2084(m);
				float sPQ = inverseEotfSt2084(s);

				ictCp[0] = (2048.0f * lPQ + 2048.0f * mPQ) / 4096.0f;
				ictCp[1] = (6610.0f * lPQ - 13613.0f * mPQ + 7003.0f * sPQ) / 4096.0f;
				ictCp[2] = (17933.0f * lPQ - 17390.0f * mPQ - 543.0f * sPQ) / 4096.0f;
			}

			void iCtCpToRgb(const float3 ictCp, out float3 rgb) // Output: linear Rec.2020
			{
				float l = ictCp[0] + 0.00860904f * ictCp[1] + 0.11103f * ictCp[2];
				float m = ictCp[0] - 0.00860904f * ictCp[1] - 0.11103f * ictCp[2];
				float s = ictCp[0] + 0.560031f * ictCp[1] - 0.320627f * ictCp[2];

				float lLin = eotfSt2084(l);
				float mLin = eotfSt2084(m);
				float sLin = eotfSt2084(s);

				rgb[0] = max(3.43661f * lLin - 2.50645f * mLin + 0.0698454f * sLin, 0.0f);
				rgb[1] = max(-0.79133f * lLin + 1.9836f * mLin - 0.192271f * sLin, 0.0f);
				rgb[2] = max(-0.0259499f * lLin - 0.0989137f * mLin + 1.12486f * sLin, 0.0f);
			}

			// -----------------------------------------------------------------------------
			// Jzazbz conversion.
			// Reference:
			// Muhammad Safdar, Guihua Cui, Youn Jin Kim, and Ming Ronnier Luo,
			// "Perceptually uniform color space for image signals including high dynamic
			// range and wide gamut," Opt. Express 25, 15131-15151 (2017)
			// Note: Coefficients adjusted for linear Rec.2020
			// -----------------------------------------------------------------------------
			void rgbToJzazbz(const float3 rgb, out float3 jab) // Input: linear Rec.2020
			{
				float l = rgb[0] * 0.530004f + rgb[1] * 0.355704f + rgb[2] * 0.086090f;
				float m = rgb[0] * 0.289388f + rgb[1] * 0.525395f + rgb[2] * 0.157481f;
				float s = rgb[0] * 0.091098f + rgb[1] * 0.147588f + rgb[2] * 0.734234f;

				float lPQ = inverseEotfSt2084(l, JZAZBZ_EXPONENT_SCALE_FACTOR);
				float mPQ = inverseEotfSt2084(m, JZAZBZ_EXPONENT_SCALE_FACTOR);
				float sPQ = inverseEotfSt2084(s, JZAZBZ_EXPONENT_SCALE_FACTOR);

				float iz = 0.5f * lPQ + 0.5f * mPQ;

				jab[0] = (0.44f * iz) / (1.0f - 0.56f * iz) - 1.6295499532821566e-11f;
				jab[1] = 3.524000f * lPQ - 4.066708f * mPQ + 0.542708f * sPQ;
				jab[2] = 0.199076f * lPQ + 1.096799f * mPQ - 1.295875f * sPQ;
			}

			void jzazbzToRgb(const float3 jab, out float3 rgb) // Output: linear Rec.2020
			{
				float jz = jab[0] + 1.6295499532821566e-11f;
				float iz = jz / (0.44f + 0.56f * jz);
				float a = jab[1];
				float b = jab[2];

				float l = iz + a * 0.1386050432715393 + b * 0.05804731615611869;
				float m = iz + a * -0.1386050432715393 + b * -0.05804731615611869;
				float s = iz + a * -0.09601924202631895 + b * -0.8118918960560390;

				float lLin = eotfSt2084(l, JZAZBZ_EXPONENT_SCALE_FACTOR);
				float mLin = eotfSt2084(m, JZAZBZ_EXPONENT_SCALE_FACTOR);
				float sLin = eotfSt2084(s, JZAZBZ_EXPONENT_SCALE_FACTOR);

				rgb[0] = lLin * 2.990669f + mLin * -2.049742f + sLin * 0.088977f;
				rgb[1] = lLin * -1.634525f + mLin * 3.145627f + sLin * -0.483037f;
				rgb[2] = lLin * -0.042505f + mLin * -0.377983f + sLin * 1.448019f;
			}

			// -----------------------------------------------------------------------------
			// Unified color space (UCS): ICtCp or Jzazbz.
			// -----------------------------------------------------------------------------
			void rgbToUcs(const float3 rgb, out float3 ucs)
			{
				if (mapping == 0)
					rgbToICtCp(rgb, ucs);
				else
					rgbToJzazbz(rgb, ucs);
			}

			void ucsToRgb(const float3 ucs, out float3 rgb)
			{
				if (mapping == 0)
					iCtCpToRgb(ucs, rgb);
				else
					jzazbzToRgb(ucs, rgb);
			}

			// Initializes the tone mapping curve and related parameters based on the target display luminance.
			// This method should not be called directly. Use initializeAsHDR() orinitializeAsSDR() instead.
			void initializeParameters(inout GT7ToneMapping toneMapper, float physicalTargetLuminance)
			{
				toneMapper.framebufferLuminanceTarget_ = physicalValueToFrameBufferValue(physicalTargetLuminance);
				// Initialize the curve (slightly different parameters from GT Sport).
				initializeCurve(toneMapper, toneMapper.framebufferLuminanceTarget_,
					0.25f, 0.538f, 0.444f, 1.280f);
				// Default parameters.
				toneMapper.blendRatio_ = blendRatio;
				toneMapper.fadeStart_ = fadeStart;
				toneMapper.fadeEnd_ = fadeEnd;
				float3 ucs;
				float3 rgb = float3(toneMapper.framebufferLuminanceTarget_, toneMapper.framebufferLuminanceTarget_, toneMapper.framebufferLuminanceTarget_);
				rgbToUcs(rgb, ucs);
				toneMapper.framebufferLuminanceTargetUcs_ = ucs[0]; // Use the first UCS component (I or Jz) as luminance
			}

			// Initialize for HDR (High Dynamic Range) display.
			// Input: target display peak luminance in nits (range: 250 to 10,000)
			// Note: The lower limit is 250 because the parameters forGTToneMappingCurveV2
			//       were determined based on an SDR paper white assumption of 250 nits(GRAN_TURISMO_SDR_PAPER_WHITE).
			void initializeAsHDR(inout GT7ToneMapping toneMapper, float physicalTargetLuminance)
			{
				toneMapper.sdrCorrectionFactor_ = 1.0f;
				initializeParameters(toneMapper, physicalTargetLuminance);
			}

			// Initialize for SDR (Standard Dynamic Range) display.
			void initializeAsSDR(inout GT7ToneMapping toneMapper)
			{
				// Regarding SDR output:
				// First, in GT (Gran Turismo), it is assumed that a maximum value of 10 in SDR output
				// corresponds to GRAN_TURISMO_SDR_PAPER_WHITE (typically 250 nits).
				// Therefore, tone mapping for SDR output is performed based onGRAN_TURISMO_SDR_PAPER_WHITE.
				// However, in the sRGB standard, 1.0f corresponds to 100 nits,
				// so we need to "undo" the tone-mapped values accordingly.
				// To match the sRGB range, the tone-mapped values are scaled using sdrCorrectionFactor_.
				//
				// * These adjustments ensure that the visual appearance (in terms ofbrightness)
				//   stays generally consistent across both HDR and SDR outputs for thesame rendered content.
				toneMapper.sdrCorrectionFactor_ = 1.0f / physicalValueToFrameBufferValue(GRAN_TURISMO_SDR_PAPER_WHITE);
				initializeParameters(toneMapper, GRAN_TURISMO_SDR_PAPER_WHITE);
			}

			// Input:  linear Rec.2020 RGB (frame buffer values)
			// Output: tone-mapped RGB (frame buffer values);
			//         - in SDR mode: mapped to [0, 1], ready for sRGB OETF
			//         - in HDR mode: mapped to [0, framebufferLuminanceTarget_], readyfor PQ inverse-EOTF
			// Note: framebufferLuminanceTarget_ represents the display's target peakluminance converted to a frame buffer value.
			//       The returned values are suitable for applying the appropriate OETFto generate final output signal.
			void applyToneMapping(inout GT7ToneMapping toneMapper, const float3 rgb, out float3 outColor)
			{
				// Convert to UCS to separate luminance and chroma.
				float3 ucs;
				rgbToUcs(rgb, ucs);
				// Per-channel tone mapping ("skewed" color).
				float3 skewedRgb = float3(evaluateCurve(toneMapper, rgb[0]), evaluateCurve(toneMapper, rgb[1]), evaluateCurve(toneMapper, rgb[2]));
				float3 skewedUcs;
				rgbToUcs(skewedRgb, skewedUcs);
				float chromaScale =
				chromaCurve(ucs[0] / toneMapper.framebufferLuminanceTargetUcs_, toneMapper.fadeStart_, toneMapper.fadeEnd_);
				const float3 scaledUcs = float3(ucs[0], ucs[1] * chromaScale, ucs[2] * chromaScale);
				// Convert back to RGB.
				float3 scaledRgb;
				ucsToRgb(scaledUcs, scaledRgb);
				// Final blend between per-channel and UCS-scaled results.
				for (int i = 0; i < 3; ++i)
				{
					float blended = (1.0f - toneMapper.blendRatio_) * skewedRgb[i] + toneMapper.blendRatio_ * scaledRgb[i];
					// When using SDR, apply the correction factor.
					// When using HDR, sdrCorrectionFactor_ is 1.0f, so it has noeffect.
					outColor[i] = toneMapper.sdrCorrectionFactor_ * min(blended, toneMapper.framebufferLuminanceTarget_);
				}
			}

			float3 ApplyTransform(float3 inputColor)
			{
				GT7ToneMapping toneMapper;

				if (dynamic_range == 0)
			        initializeAsSDR(toneMapper);
			    else
			        initializeAsHDR(toneMapper, hdr_luminance);

			    float3 outColor;
			    applyToneMapping(toneMapper, inputColor, outColor);
				return outColor;
			}

			float4 Frag(v2f i) : SV_Target
			{
				float3 color = tex2D(_MainTex, i.uv).rgb;
				color = ApplyTransform(color);
				return float4(color, 1.0);
			}
			ENDHLSL
		}
	}
}
