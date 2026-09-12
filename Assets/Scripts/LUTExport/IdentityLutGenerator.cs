/*
 * Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

using UnityEngine;

// Generates an identity HDR LUT.
//
// It uses Alexa LogC El 1000 encoding for its input coordinate domain.
public static class IdentityLutGenerator {

	// Alexa LogC El 1000 constants.
	// These are the constants used by PPSv2 Colors.hlsl.
	private const float LogCCut = 0.011361f;
	private const float LogCA = 5.555556f;
	private const float LogCB = 0.047996f;
	private const float LogCC = 0.244161f;
	private const float LogCD = 0.386036f;
	private const float LogCE = 5.301883f;
	private const float LogCF = 0.092819f;

	public static Texture2D Generate(int lutSize = 32) {
		// Create the flattened 1024x32 LUT.
		int width = lutSize * lutSize;
		int height = lutSize;

		Texture2D lut = new Texture2D(
			width, height, TextureFormat.RGBAFloat, false, true);

		lut.name = "HDR Identity LUT";
		lut.wrapMode = TextureWrapMode.Clamp;
		lut.filterMode = FilterMode.Point;

		Color[] pixels = new Color[width * height];
		float invSizeMinusOne = 1f / (lutSize - 1);

		// LUT coordinate in LogC space.
		for (int b = 0; b < lutSize; ++b) {
			float logB = b * invSizeMinusOne;
			float linearB = LogCToLinear(logB);

			for (int g = 0; g < lutSize; ++g) {
				float logG = g * invSizeMinusOne;
				float linearG = LogCToLinear(logG);

				for (int r = 0; r < lutSize; ++r) {
					float logR = r * invSizeMinusOne;
					float linearR = LogCToLinear(logR);

					int x = b * lutSize + r;
					int y = g;
					int index = y * width + x;
					pixels[index] = new Color(linearR, linearG, linearB, 1f);
				}
			}
		}

		lut.SetPixels(pixels);
		lut.Apply(false, false);

		return lut;
	}

	// PPSv2 LogC -> Linear conversion.
	// This mirrors Colors.hlsl.
	static float LogCToLinear(float x) {
		float threshold = LogCE * LogCCut + LogCF;

		if (x > threshold)
			return (Mathf.Pow(10f, (x - LogCD) / LogCC) - LogCB) / LogCA;

		return (x - LogCF) / LogCE;
	}
}
