/*
 * Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

using System;
using UnityEngine;
using Object = UnityEngine.Object;

// Bakes a tone mapping LUT based on a Material's transformation
// of the colors in the provided identity LUT.
//
// The LUT uses the same input coordinate domain as the provided identity LUT.
//
// The material should not convert the output to sRGB (gamma space).
public static class MaterialTonemapLutBaker {

	static readonly int mainTexId = Shader.PropertyToID("_MainTex");

	public static void BakeMaterialToTexture(
		Texture2D identityLut, Texture2D targetLut, Material material
	) {
		if (identityLut == null)
			throw new ArgumentNullException(nameof(identityLut));
		if (targetLut == null)
			throw new ArgumentNullException(nameof(identityLut));
		if (material == null)
			throw new ArgumentNullException(nameof(material));
		if (identityLut.width != targetLut.width || identityLut.height != targetLut.height)
			throw new ArgumentException("Identity LUT must same size as target LUT.");

		// Render target.
		RenderTexture renderTexture = new RenderTexture(identityLut.width, identityLut.height,
			0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
		renderTexture.useMipMap = false;
		renderTexture.Create();

		try {
			if (material.HasProperty(mainTexId))
				material.SetTexture(mainTexId, identityLut);

			// Run the identity LUT through the transform.
			Graphics.Blit(identityLut, renderTexture, material, 0);

			// Read the floating-point result back.
			RenderTexture previous = RenderTexture.active;
			RenderTexture.active = renderTexture;

			targetLut.ReadPixels(new Rect(0, 0, identityLut.width, identityLut.height),
				0, 0, false);
			targetLut.Apply(false, false);

			RenderTexture.active = previous;
		}
		finally {
			RenderTexture.active = null;
			if (renderTexture != null) {
				renderTexture.Release();
				Object.DestroyImmediate(renderTexture);
			}
		}
	}
}

