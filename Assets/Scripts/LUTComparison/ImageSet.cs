/*
 * Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

using System;
using System.Collections.Generic;
using UnityEngine;

[CreateAssetMenu(fileName = "Image Set", menuName = "LUT Comparison/Image Set")]
public class ImageSet : ScriptableObject {
	[Serializable]
	public class SampleImage {
		public Texture2D image;
		public float exposure;
	}

	[Tooltip("HDR screenshots. EXR files should be imported as HDR.")]
	public List<SampleImage> screenshots = new List<SampleImage>();
}
