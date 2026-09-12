// Implementation of the Khronos BPR Neutral tone mapper
//
//     https://github.com/KhronosGroup/ToneMapping
//
// Adapted as Unity shader by Rune Skovbo Johansen, 2026.

// Copyright 2024 Khronos® Group
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

Shader "Tone Mapping/PBR Neutral"
{
	Properties
	{
		_MainTex ("Identity LUT", 2D) = "white" {}
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

			// Input color is non-negative and resides in the Linear Rec. 709 color space.
			// Output color is also Linear Rec. 709, but in the [0, 1] range.
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
