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

[CreateAssetMenu(fileName = "LUT Set", menuName = "LUT Comparison/LUT Set")]
public class LutSet : ScriptableObject {
	[Serializable]
	public class Mapping {
		public bool active;
		public Shader shader;
		public Texture3D lut;
		public float multiplier = 1f;
		public bool shaderTest;
		public Material material { get; set; }
		public RenderTexture graph { get; set; }
	}

	public List<Mapping> mappings = new List<Mapping>();
}
