/*
 * Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

using System;
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;
using Object = UnityEngine.Object;

// Bakes a tone mapping LUT based on a PPSv2 Post-Process Profile's
// transformation of the colors in the provided identity LUT.
//
// The LUT uses the same input coordinate domain as the provided identity LUT.
//
// The supplied profile should contain only the effects to be baked.
// This normally means that only the Tonemapping component should be active.
//
// The transformed colors are rendered through the actual PPSv2 camera stack
// and saved as linear (but tone mapped) HDR pixels.
// The baker does not convert the output to sRGB (gamma space).
public static class PostProcessProfileTonemapLutBaker {

	static readonly int mainTexId = Shader.PropertyToID("_MainTex");

	// Main bake operation.
	public static void BakeProfileToTexture(
		Texture2D identityLut, Texture2D targetLut, PostProcessProfile profile
	) {
		if (identityLut == null)
			throw new ArgumentNullException(nameof(identityLut));
		if (targetLut == null)
			throw new ArgumentNullException(nameof(identityLut));
		if (profile == null)
			throw new ArgumentNullException(nameof(profile));
		if (identityLut.width != targetLut.width || identityLut.height != targetLut.height)
			throw new ArgumentException("Identity LUT must same size as target LUT.");

		int cullingLayer = 30;

		// Camera to render the LUT texture with the post-process stack applied.
		GameObject camGO = new GameObject("PPSv2 LUT Baker");
		camGO.hideFlags = HideFlags.HideAndDontSave;
		Camera camera = camGO.AddComponent<Camera>();
		camera.enabled = false;
		camera.clearFlags = CameraClearFlags.SolidColor;
		camera.backgroundColor = Color.black;
		camera.orthographic = true;
		camera.orthographicSize = 1.0f;
		camera.nearClipPlane = -10.0f;
		camera.farClipPlane = 10.0f;
		camera.allowHDR = true;
		camera.allowMSAA = false; // Important: no MSAA.
		camera.useOcclusionCulling = false;
		camera.cullingMask = 1 << cullingLayer;

		// HDR destination RenderTexture for the camera to render into.
		RenderTexture outputRT = new RenderTexture(targetLut.width, targetLut.height,
			24, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
		outputRT.name = "PPSv2 LUT Bake Output";
		outputRT.filterMode = FilterMode.Point;
		outputRT.wrapMode = TextureWrapMode.Clamp;
		outputRT.useMipMap = false;
		outputRT.autoGenerateMips = false;
		outputRT.Create();

		camera.targetTexture = outputRT;

		// Fullscreen quad for the LUT texture to be displayed on.
		GameObject quadGO = GameObject.CreatePrimitive(PrimitiveType.Quad);
		quadGO.name = "LUT Input";
		quadGO.hideFlags = HideFlags.HideAndDontSave;
		quadGO.transform.SetParent(camGO.transform, false);
		quadGO.transform.localPosition = new Vector3(0, 0, 0);
		quadGO.transform.localRotation = Quaternion.identity;
		quadGO.transform.localScale = new Vector3(64, 2, 1);
		quadGO.layer = cullingLayer;
		MeshRenderer renderer = quadGO.GetComponent<MeshRenderer>();

		// Use an unlit texture shader and create a Material with it.
		// This shader must NOT perform sRGB conversion or similar.
		Shader copyShader = Shader.Find("Hidden/CopyTexture");
		if (copyShader == null) {
			throw new Exception("Could not find CopyTexture shader.");
		}
		Material copyMaterial = new Material(copyShader);
		copyMaterial.hideFlags = HideFlags.HideAndDontSave;
		copyMaterial.SetTexture(mainTexId, identityLut);
		renderer.sharedMaterial = copyMaterial;

		// Create a PPSv2 layer.
		PostProcessLayer layer = camGO.AddComponent<PostProcessLayer>();
		layer.volumeLayer = ~0;
		layer.antialiasingMode = PostProcessLayer.Antialiasing.None;
		layer.stopNaNPropagation = false;
		layer.finalBlitToCameraTarget = false;
		// Initialize the layer. Passing null is intentional here;
		// PPSv2 will use its normal resource initialization path.
		layer.Init(null);

		// Temporary global volume.
		GameObject volumeGO = new GameObject("PPSv2 LUT Bake Volume");
		volumeGO.hideFlags = HideFlags.HideAndDontSave;
		volumeGO.layer = 0;
		PostProcessVolume volume = volumeGO.AddComponent<PostProcessVolume>();
		volume.isGlobal = true;
		volume.weight = 1.0f;
		volume.priority = 100000.0f;
		volume.sharedProfile = profile;

		// Render the PPSv2 camera stack.
		camera.Render();

		// Read the post-processed HDR buffer.
		RenderTexture previous = RenderTexture.active;
		RenderTexture.active = outputRT;

		// Read the RenderTexture into target LUT.
		targetLut.ReadPixels(new Rect(0, 0, targetLut.width, targetLut.height),
			0, 0, false);
		targetLut.Apply(false, false);

		RenderTexture.active = previous;

		camera.targetTexture = null;
		if (outputRT != null) {
			outputRT.Release();
			Object.DestroyImmediate(outputRT);
		}
		Object.DestroyImmediate(copyMaterial);
		Object.DestroyImmediate(camGO);
		Object.DestroyImmediate(volumeGO);
	}
}

