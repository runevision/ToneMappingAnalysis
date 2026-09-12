Shader "Tone Mapping/Reinhard-Jodie"
{
	Properties
	{
		_MainTex ("Identity LUT", 2D) = "white" {}
		_MaxWhite ("Max White", Range(0.1, 1000.0)) = 64
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
			float _MaxWhite;

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

			float GetLuminance(float3 v)
			{
				return dot(v, float3(0.2126, 0.7152, 0.0722));
			}

			// Reinhard-Jodie tone mapping
			// Based on https://64.github.io/tonemapping/#reinhard-jodie
			// Modified to support max white, like the other Reinhard versions.
			float3 ApplyTransform(float3 v)
			{
				float3 vNumerator = v * (1.0 + (v / (_MaxWhite * _MaxWhite)));
				float3 perChannel = vNumerator / (1.0 + v);

				float lumOld = GetLuminance(v);
				float lumNumerator = lumOld * (1.0 + (lumOld / (_MaxWhite * _MaxWhite)));
				float lumNew = lumNumerator / (1.0 + lumOld);
				float3 perLum = v * lumNew / lumOld;

				return lerp(perLum, perChannel, perChannel);
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
