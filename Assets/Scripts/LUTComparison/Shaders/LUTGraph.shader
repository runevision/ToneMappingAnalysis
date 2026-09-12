/*
 * Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


Shader "Hidden/LUTGraph"
{
	Properties
	{
		_LUT ("LUT", 3D) = "" {}
	}

	SubShader
	{
		Lighting Off
		Blend SrcAlpha OneMinusSrcAlpha, One One
		Cull Off
		ZWrite Off
		ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#pragma shader_feature ShowWhite
			#pragma shader_feature ShowRGB
			#pragma shader_feature ShowCMY
			#pragma shader_feature ClipOutput

			#include "UnityCG.cginc"

			sampler3D _LUT;
			float _Multiplier;
			float2 _Lut3D_Params;

			sampler2D _GUIClipTexture;
			uniform float4x4 unity_GUIClipTextureMatrix;

			#define PI              3.14159265358979323846264338327950288;
			#define EPSILON         1.0e-4

			struct appdata {
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f {
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;
				float2 clipUV : TEXCOORD1;
			};

			v2f vert(appdata v)
			{
				v2f o;

				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;

				float3 eyePos = UnityObjectToViewPos(v.vertex);
				o.clipUV = mul(unity_GUIClipTextureMatrix, float4(eyePos.xy, 0, 1.0));

				return o;
			}

			struct ParamsLogC {
				float cut;
				float a, b, c, d, e, f;
			};

			static const ParamsLogC LogC =
			{
				0.011361, // cut
				5.555556, // a
				0.047996, // b
				0.244161, // c
				0.386036, // d
				5.301883, // e
				0.092819  // f
			};

			float LinearToLogC_Precise(float x)
			{
				if (x > LogC.cut)
					return LogC.c * log10(LogC.a * x + LogC.b) + LogC.d;

				return LogC.e * x + LogC.f;
			}

			float LogCToLinear_Precise(float x)
			{
				float o;
				if (x > LogC.e * LogC.cut + LogC.f)
					o = (pow(10.0, (x - LogC.d) / LogC.c) - LogC.b) / LogC.a;
				else
					o = (x - LogC.f) / LogC.e;
				return o;
			}

			float3 LinearToLogC(float3 x)
			{
				//#if USE_PRECISE_LOGC
				return float3(
					LinearToLogC_Precise(x.x),
					LinearToLogC_Precise(x.y),
					LinearToLogC_Precise(x.z)
				);
				//#else
				//return LogC.c * log10(LogC.a * x + LogC.b) + LogC.d;
				//#endif
			}

			// 3D LUT grading
			//
			//     scaleOffset = (1 / lut_size, lut_size - 1)
			//
			// The uvw coordinates (which are initially 0 - 1) are scaled with:
			//
			//     (lut_size - 1) * (1 / lut_size) + (1 / lut_size) * 0.5
			//
			// So sampling starts at 0.5 texels and ends at width - 0.5 texels.
			half3 ApplyLut3D(sampler3D tex, float3 uvw, float2 scaleOffset)
			{
				uvw.xyz = uvw.xyz * scaleOffset.yyy * scaleOffset.xxx + scaleOffset.xxx * 0.5;
				return tex3D(tex, uvw).rgb;
			}

			#define FLT_EPSILON     1.192092896e-07
			float3 PositivePow(float3 base, float3 power)
			{
				return pow(max(abs(base), float3(FLT_EPSILON, FLT_EPSILON, FLT_EPSILON)), power);
			}

			half3 LinearToSRGB(half3 c)
			{
				half3 sRGBLo = c * 12.92;
				half3 sRGBHi = (PositivePow(c, half3(1.0 / 2.4, 1.0 / 2.4, 1.0 / 2.4)) * 1.055) - 0.055;
				half3 sRGB = (c <= 0.0031308) ? sRGBLo : sRGBHi;
				return sRGB;
			}

			float3 GetDeltaVis(float delta)
			{
				float3 deltaVis;
				if (delta > 0)
					deltaVis = saturate(float3(1, 1 - delta, 1 - delta));
				else
					deltaVis = saturate(float3(1 + delta, 1 + delta, 1));
				return deltaVis * deltaVis;
			}

			float2 GetMinMax(float3 col)
			{
				return float2(
					min(min(col.r, col.g), col.b),
					max(max(col.r, col.g), col.b));
			}

			float GetMaxChannelChange(float3 orig, float3 mapped)
			{
				float2 origMinMax = GetMinMax(orig);
				float2 mappedMinMax = GetMinMax(mapped);
				float maxChangeColor = mappedMinMax.y / origMinMax.y;
				return origMinMax.y == 0 ? 0 : maxChangeColor - 1;
			}

			float GetSaturationChange(float3 orig, float3 mapped)
			{
				float2 origMinMax = GetMinMax(orig);
				float2 mappedMinMax = GetMinMax(mapped);
				float origSat = 1 - origMinMax.x / origMinMax.y;
				float mappedSat = 1 - mappedMinMax.x / mappedMinMax.y;
				float satChange = mappedSat - origSat;
				return origMinMax.y == 0 ? 0 : satChange;
			}

			float3 MapColor(float3 color)
			{
				color *= _Multiplier;
				float3 colorLutSpace = saturate(LinearToLogC(color));
				float3 mapped = ApplyLut3D(_LUT, colorLutSpace, _Lut3D_Params);
				if (ClipOutput)
					mapped = saturate(mapped);
				return mapped;
			}

			float3 RgbToHsv(float3 c)
			{
				float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
				float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
				float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
				float d = q.x - min(q.w, q.y);
				float e = EPSILON;
				return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
			}

			float3 HsvToRgb(float3 c)
			{
				float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
				float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
				return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
			}

			float MaxChannel(float3 col)
			{
				return max(col.r, max(col.g, col.b));
			}

			float MinChannel(float3 col)
			{
				return min(col.r, min(col.g, col.b));
			}

			float line_segment(float2 a, float2 b, float2 p)
			{
				a -= p;
				b -= p;
				float2 ba = b - a;
				float h = clamp(dot(-a, ba) / dot(ba, ba), 0.0, 1.0);
				return length(-a - h * ba);
			}

			float GetLineAlpha(float dist, float lineWidth)
			{
				return saturate(0.5 - dist + lineWidth * 0.5);
			}

			float3 DrawGraphRect(float3 color, float2 s, float2 q)
			{
				float dist = 1000000.0;
				dist = min(dist, line_segment(float2(0.0, 0.0), float2(0.0, s.y), q));
				dist = min(dist, line_segment(float2(0.0, s.y), float2(s.x, s.y), q));
				dist = min(dist, line_segment(float2(s.x, s.y), float2(s.x, 0.0), q));
				dist = min(dist, line_segment(float2(s.x, 0.0), float2(0.0, 0.0), q));
				return lerp(color, 0.2, GetLineAlpha(dist, 1));
			}

			float HLineDist(float2 s, float2 q, float h)
			{
				h *= s.y;
				return line_segment(float2(0, h), float2(s.x, h), q);
			}

			static const float exp2slope = 0.69314718;
			static const float linearPart = 1.0 / exp2slope;
			static const float maxEv = 6;

			float LinearPlusExpCurve(float input, float ev)
			{
				float x = lerp(-1 / exp2slope, ev, input);
				return x <= 0 ? (x * exp2slope + 1) : exp2(x);
			}

			float3 DrawLinearPlusExpGraphLines(float3 color, float2 s, float2 q, bool drawDiagonal)
			{
				float dist = 1000000.0;
				for (int i = 0; i < maxEv; i++)
				{
					float h = (i + linearPart) / (linearPart + maxEv);
					dist = min(dist, HLineDist(s, q, h));
				}
				if (drawDiagonal)
				{
					float v = linearPart / (linearPart + maxEv);
					dist = min(dist, line_segment(float2(0, 0), float2(s.x, v * s.y), q));
				}
				return lerp(color, 0.1, GetLineAlpha(dist, 1));
			}

			float3 DrawMaxChannelGraphLines(float3 color, float2 s, float2 q)
			{
				float dist = 1000000.0;
				for (int c = 1; c < 6; c++)
				{
					float h = (c / 6.0) * s;
					dist = min(dist, line_segment(float2(h, 0), float2(h, s.y), q));
				}
				dist = min(dist, line_segment(float2(0, 0), float2(s.x / 6, s.y), q));
				return lerp(color, 0.1, GetLineAlpha(dist, 1));
			}

			float3 DrawSatValGraph(float3 color, float3 testCol, float2 s, float2 q, float sat)
			{
				float3 displayCol = lerp(testCol, 1.0, 0.1);
				displayCol = lerp(0.0, displayCol, sat * sat * sat);
				testCol = lerp(1.0, testCol, sat);

				float dist = 1000000.0;

				// Draw saturation/value curve.
				int segments = 48;
				float2 pA = RgbToHsv(MapColor(testCol * 0.01)).yz * s;
				for (int c = 0; c < segments; c++)
				{
					float v = (c + 1) / float(segments);
					v = v * v * 32;
					float2 pB = RgbToHsv(MapColor(testCol * v)).yz * s;
					dist = min(dist, line_segment(pA, pB, q));
					pA = pB;
				}

				// Draw saturation/value markers.
				for (int c = -2; c < 6; c++)
				{
					float v = pow(2, c);
					float2 pA = RgbToHsv(testCol * v).yz * s;
					pA.x += 0.1 * s;
					float3 mapped = MapColor(testCol * v);
					float2 pB = RgbToHsv(mapped).yz * s;
					pA = pB + normalize(pA - pB) * s * 0.03;
					if (c == 0)
						pB = pA + (pB - pA) * 2;
					dist = min(dist, line_segment(pA, pB, q));
				}
				float l = GetLineAlpha(dist, 1);
				color += displayCol * l;

				return color;
			}

			float3 DrawSatGraph(float3 color, float3 testCol, float2 s, float2 q, float sat)
			{
				float3 displayCol = lerp(testCol, 1.0, 0.1);
				displayCol = lerp(0.0, displayCol, sat * sat * sat);
				testCol = lerp(1.0, testCol, sat);

				// Draw saturation curve.
				int segments = 48;
				float dist = 1000000.0;
				float3 hsv = RgbToHsv(MapColor(testCol * 0.01));
				float2 pA = float2(hsv.y, 0) * s;
				for (int c = 0; c < segments; c++)
				{
					float y = (c + 1) / float(segments);
					float v = LinearPlusExpCurve(y, maxEv);
					hsv = RgbToHsv(MapColor(testCol * v));
					float2 pB = float2(hsv.y, y) * s;
					dist = min(dist, line_segment(pA, pB, q));
					pA = pB;
				}
				float l = GetLineAlpha(dist, 1);
				color += displayCol * l;

				return color;
			}

			float3 DrawHueGraph(float3 color, float3 testCol, float2 s, float2 q)
			{
				float3 displayCol = lerp(testCol, 1.0, 0.1);

				// Draw hue curve.
				float hueXOffset = 0.02;
				int segments = 48;
				float dist = 1000000.0;
				float3 hsv = RgbToHsv(MapColor(testCol * 0.01));
				hsv.x = frac(hsv.x + hueXOffset);
				float2 pA = float2(hsv.x, 0) * s;
				for (int c = 0; c < segments; c++)
				{
					float y = (c + 1) / float(segments);
					float v = LinearPlusExpCurve(y, maxEv);
					hsv = RgbToHsv(MapColor(testCol * v));
					hsv.x = frac(hsv.x + hueXOffset);
					float2 pB = float2(hsv.x, y) * s;
					if (hsv.y > 0.001)
						dist = min(dist, line_segment(pA, pB, q));
					pA = pB;
				}
				float l = GetLineAlpha(dist, 1);
				color += displayCol * l;

				return color;
			}

			float3 DrawMaxChannelGraph(float3 color, float3 testCol, float2 s, float2 q, float m)
			{
				float3 displayCol = lerp(testCol, 1.0, 0.1) * m;

				// Draw max channel curve.
				int segments = 48;
				float dist = 1000000.0;
				float2 pA = float2(0, MaxChannel(MapColor(testCol * 0))) * s;
				for (int c = 0; c < segments; c++)
				{
					float y = (c + 1) / float(segments);
					y = y * y;
					float v = LinearPlusExpCurve(y, maxEv);
					float2 pB = float2(y, MaxChannel(MapColor(testCol * v))) * s;
					dist = min(dist, line_segment(pA, pB, q));
					pA = pB;
				}
				float l = GetLineAlpha(dist, 1);
				color += displayCol * l;

				return color;
			}

			float4 frag(v2f i) : SV_Target
			{
				float3 color = 0;

				float2 p = (i.uv - 0.5) * float2(1000, 500);

				float2 s = float2(250, 250);

				// Saturation / value of colors.
				float2 q = p + 0.5 * s - float2(-310, 80);
				{
					color = DrawGraphRect(color, s, q);

					// Primary colors.
					if (ShowRGB)
					{
						color = DrawSatValGraph(color, float3(1,0,0), s, q, 0.99);
						color = DrawSatValGraph(color, float3(0,1,0), s, q, 0.99);
						color = DrawSatValGraph(color, float3(0,0,1), s, q, 0.99);
						color = DrawSatValGraph(color, float3(1,0,0), s, q, 0.50);
						color = DrawSatValGraph(color, float3(0,1,0), s, q, 0.50);
						color = DrawSatValGraph(color, float3(0,0,1), s, q, 0.50);
					}

					// Secondary colors.
					if (ShowCMY)
					{
						color = DrawSatValGraph(color, float3(1,1,0), s, q, 0.99);
						color = DrawSatValGraph(color, float3(0,1,1), s, q, 0.99);
						color = DrawSatValGraph(color, float3(1,0,1), s, q, 0.99);
						color = DrawSatValGraph(color, float3(1,1,0), s, q, 0.50);
						color = DrawSatValGraph(color, float3(0,1,1), s, q, 0.50);
						color = DrawSatValGraph(color, float3(1,0,1), s, q, 0.50);
					}
				}

				// Saturation loss of colors.
				q = p + 0.5 * s - float2(0, 80);
				{
					color = DrawLinearPlusExpGraphLines(color, s, q, false);
					color = DrawGraphRect(color, s, q);

					// Primary colors.
					if (ShowRGB)
					{
						color = DrawSatGraph(color, float3(1,0,0), s, q, 0.99);
						color = DrawSatGraph(color, float3(0,1,0), s, q, 0.99);
						color = DrawSatGraph(color, float3(0,0,1), s, q, 0.99);
						color = DrawSatGraph(color, float3(1,0,0), s, q, 0.50);
						color = DrawSatGraph(color, float3(0,1,0), s, q, 0.50);
						color = DrawSatGraph(color, float3(0,0,1), s, q, 0.50);
					}

					// Secondary colors.
					if (ShowCMY)
					{
						color = DrawSatGraph(color, float3(1,1,0), s, q, 0.99);
						color = DrawSatGraph(color, float3(0,1,1), s, q, 0.99);
						color = DrawSatGraph(color, float3(1,0,1), s, q, 0.99);
						color = DrawSatGraph(color, float3(1,1,0), s, q, 0.50);
						color = DrawSatGraph(color, float3(0,1,1), s, q, 0.50);
						color = DrawSatGraph(color, float3(1,0,1), s, q, 0.50);
					}
				}

				// Hue shifts of primary, secondary, and tertiary colors.
				q = p + 0.5 * s - float2(310, 80);
				{
					color = DrawLinearPlusExpGraphLines(color, s, q, false);
					color = DrawGraphRect(color, s, q);
					for (int i = 0; i < 24; i++)
					{
						float h = i / 24.0;
						color = DrawHueGraph(
							color, HsvToRgb(float3(h, 1, 1)), s, q);
					}
				}

				// Max channel
				s = float2(870, 145);
				q = p + 0.5 * s - float2(0, -175 - 2.5);
				{
					color = DrawLinearPlusExpGraphLines(color, s.yx, q.yx, true);
					color = DrawGraphRect(color, s, q);
					if (ShowWhite)
					{
						color = DrawMaxChannelGraph(color, float3(1.0,1.0,1.0), s, q, 0.5);
					}
					if (ShowRGB)
					{
						color = DrawMaxChannelGraph(color, float3(1.0,0.0,0.0), s, q, 1.0);
						color = DrawMaxChannelGraph(color, float3(0.0,1.0,0.0), s, q, 1.0);
						color = DrawMaxChannelGraph(color, float3(0.0,0.0,1.0), s, q, 1.0);
					}
					if (ShowCMY)
					{
						color = DrawMaxChannelGraph(color, float3(1.0,1.0,0.0), s, q, 1.0);
						color = DrawMaxChannelGraph(color, float3(0.0,1.0,1.0), s, q, 1.0);
						color = DrawMaxChannelGraph(color, float3(1.0,0.0,1.0), s, q, 1.0);
					}
				}

				return float4(color, 1);
			}
			ENDCG
		}
	}

	FallBack Off
}
