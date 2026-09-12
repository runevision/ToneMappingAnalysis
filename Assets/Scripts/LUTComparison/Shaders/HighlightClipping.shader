/*
 * Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

Shader "Hidden/Highlight Clipping"
{
	Properties
	{
		_MainTex ("Source", 2D) = "white" {}
		_LUT ("LUT", 3D) = "" {}
		_ExposureVal ("Exposure", Range(0,100)) = 1
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

			#include "UnityCG.cginc"

			sampler2D _MainTex;
			sampler3D _LUT;
			float _ExposureVal;
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

			float3 LinearToLogC(float3 x)
			{
				#if USE_PRECISE_LOGC
				return float3(
					LinearToLogC_Precise(x.x),
					LinearToLogC_Precise(x.y),
					LinearToLogC_Precise(x.z)
				);
				#else
				return LogC.c * log10(LogC.a * x + LogC.b) + LogC.d;
				#endif
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

			float4 frag(v2f i) : SV_Target
			{
				// Source screenshot is assumed to be linear HDR.
				float3 color = tex2D(_MainTex, i.uv).rgb;

				color.rgb *= _ExposureVal;

				color.rgb = lerp(saturate(color.rgb), step(1.0001, color.rgb), 0.9);

				color.rgb = LinearToSRGB(color.rgb);

				float clipAlpha = tex2D(_GUIClipTexture, i.clipUV).a;

				return float4(color.rgb, clipAlpha);
			}
			ENDCG
		}
	}

	FallBack Off
}
