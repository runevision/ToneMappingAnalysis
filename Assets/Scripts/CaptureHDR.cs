/*
 * Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

using System.IO;
using UnityEngine;

// Captures a HDR screenshot.
// The [ImageEffectOpaque] order is used to captured prior to tonemapping,
// though it probably means transparent effects also won't be included.
public class CaptureHDR : MonoBehaviour {

	string filename;

	[UnityEditor.MenuItem("Tools/Capture HDR Screenshot")]
	public static void Capture() {
		CaptureThisFrame($"Assets/Images/{System.DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss")}_HDR.exr");
	}

	public static void CaptureThisFrame(string filename) {
		Camera cam = Camera.main;
		CaptureHDR cap = cam.gameObject.AddComponent<CaptureHDR>();
		cap.filename = filename; ;
	}

	[ImageEffectOpaque]
	void OnRenderImage(RenderTexture src, RenderTexture dest) {
		// Create texture.
		Texture2D tex = new Texture2D(src.width, src.height, TextureFormat.RGBAFloat, false, true);

		// Read screen contents into the texture
		Graphics.SetRenderTarget(src);
		tex.ReadPixels(new Rect(0, 0, src.width, src.width), 0, 0);
		tex.Apply();

		// Encode texture into the EXR
		byte[] bytes = ImageConversion.EncodeToEXR(tex, Texture2D.EXRFlags.CompressZIP);
		File.WriteAllBytes(Path.Combine(Application.dataPath, "../" + filename), bytes);

		// Just to avoid warning message and black frame.
		Graphics.Blit(src, dest);

		// Cleanup.
		DestroyImmediate(tex);
		DestroyImmediate(this);
	}

}
