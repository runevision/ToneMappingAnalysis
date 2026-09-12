/*
 * Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

Shader "Hidden/DisplayWithLUT"
{
	Properties
	{
		_MainTex ("Source", 2D) = "white" {}
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

			#pragma shader_feature VisMaxDelta
			#pragma shader_feature VisSatDelta
			#pragma shader_feature VisHueOnly
			#pragma shader_feature ShaderTest

			#include "UnityCG.cginc"

			#define EPSILON         1.0e-4

			sampler2D _MainTex;
			sampler3D _LUT;
			float _ExposureVal;
			float _Multiplier;
			float2 _Lut3D_Params;

			sampler2D _GUIClipTexture;
			uniform float4x4 unity_GUIClipTextureMatrix;

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
			// scaleOffset = (1 / lut_size, lut_size - 1)
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

			float3 GetHueOnlyVis(float3 color)
			{
				float3 hsv = RgbToHsv(color);
				// Saturation only. Reduce slightly to avoid burning eyes.
				hsv.y = saturate(hsv.y * 100) * 0.9;
				// Reduce value to be easier on the eyes too.
				hsv.z = 0.6;
				return HsvToRgb(hsv);
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

			float3 ApplyTransform(float3 color)
			{
				float startCompression = 0.8 - 0.04;
				float desaturation = 0.15;

				float x = min(color.r, min(color.g, color.b));
				float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
				color -= offset;

				float peak = max(color.r, max(color.g, color.b));
				if (peak < startCompression) return color;

				float d = 1. - startCompression;
				float newPeak = 1. - d * d / (peak + d - startCompression);
				color *= newPeak / peak;

				float g = 1. - 1. / (desaturation * (peak - newPeak) + 1.);
				return lerp(color, newPeak * float3(1, 1, 1), g);
			}

			float3 MapColor(float3 color)
			{
				float3 colorLutSpace = saturate(LinearToLogC(color));
				return ApplyLut3D(_LUT, colorLutSpace, _Lut3D_Params);
				//return ApplyTransform(color);
			}

			float4 frag(v2f i) : SV_Target
			{
				// Source screenshot is assumed to be linear HDR.
				float3 color = tex2D(_MainTex, i.uv).rgb;

				// Apply exposure.
				color *= _ExposureVal;

				// Apply tonemapping.
				float3 origColor = color;

				color *= _Multiplier;

				float3 mappedColor = MapColor(color);

				// Test
				if (ShaderTest)
				{
					float maxChannelChange = GetMaxChannelChange(origColor, mappedColor);
					float3 newColor = color * (tanh(-maxChannelChange) + 1);
					mappedColor = MapColor(newColor);
				}

				float3 colorWithoutClipping = mappedColor;
				color = saturate(mappedColor);

				if (VisSatDelta)
					color = GetDeltaVis(GetSaturationChange(origColor, color));
				if (VisMaxDelta)
					color = GetDeltaVis(GetMaxChannelChange(origColor, color));
				if (VisHueOnly)
					color = GetHueOnlyVis(colorWithoutClipping);

				// Convert to gamma.
				color = LinearToSRGB(color);
				// Support GUI clipping.
				float clipAlpha = tex2D(_GUIClipTexture, i.clipUV).a;

				return float4(color, clipAlpha);
			}
			ENDCG
		}
	}

	FallBack Off
}
