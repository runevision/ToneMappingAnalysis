Shader "Tone Mapping/Uncharted 2"
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

			static const float A = 0.15;
			static const float B = 0.50;
			static const float C = 0.10;
			static const float D = 0.20;
			static const float E = 0.02;
			static const float F = 0.30;

			// Uncharted 2 tone mapping
			// Based on https://64.github.io/tonemapping/#uncharted-2
			float3 Uncharted2TonemapPartial(float3 x)
			{
				return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
			}

			float3 ApplyTransform(float3 v)
			{
				// An exposure bias of 3.5 seems to give a
				// diagonal / 45 degree / neutral starting angle.
				float exposureBias = 3.5f;
				float3 curr = Uncharted2TonemapPartial(v * exposureBias);
			    float3 whiteScale = float3(1, 1, 1)
					/ Uncharted2TonemapPartial(_MaxWhite);
			    return curr * whiteScale;
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
