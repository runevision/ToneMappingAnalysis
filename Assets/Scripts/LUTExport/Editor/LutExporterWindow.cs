/*
 * Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;
using Object = UnityEngine.Object;

// Bakes a float3 -> float3 color transformation into a new LUT,
// based on an existing HDR identity LUT.
//
// The identity LUT is expected to be a 1024x32 .exr image:
//
//     32 slices x 32x32 pixels
//
// The LUTs represent 3D textures with Alexa LogC El 1000 encoded
// coordinates. This means a logarithmic encoding is used to determine
// which position in the 3D texture to sample for a given input color.
// The value at that position represents an RGB output color in linear
// space (for the identity LUT) or tone mapped but still linear space
// (not gamma/sRGB) for the baked tone mapping LUT.
//
// The bake process transforms each pixel individually, and writes
// the result to a new 1024x32 floating-point .exr image.
public class LutExporterWindow : EditorWindow {
	Texture2D identityLut;
	PostProcessProfile profile;
	Shader shader;
	Material material;

	string outputFolder = "Assets/LUTs";
	string outputFolderId2D = "Assets/Baking";
	string outputFilename = "NewLUT";
	string outputFilenameId2D = "Identity2D";
	string outputFilenameId3D = "Identity";

	static string[] tabs = new string[] {
		"Shader",
		"Material",
		"Post-Process Profile",
		"Identity",
		"2D Identity",
	};
	int selectedTab;

	bool selectExported = true;

	[MenuItem("Window/LUT/LUT Exporter")]
	public static void Open() {
		var window = GetWindow<LutExporterWindow>("LUT Exporter");
		window.minSize = new Vector2(400f, 440f);
	}

	void Awake() {
		// Find Identity2D LUT.
		string[] results = AssetDatabase.FindAssets("Identity2D t:Texture2D");
		if (results != null && results.Length == 1) {
			string path = AssetDatabase.GUIDToAssetPath(results[0]);
			identityLut = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
		}

		// Find Post-Processing Profile.
		results = AssetDatabase.FindAssets("t:PostProcessProfile");
		if (results != null && results.Length == 1) {
			string path = AssetDatabase.GUIDToAssetPath(results[0]);
			profile = AssetDatabase.LoadAssetAtPath<PostProcessProfile>(path);
		}
	}

	void OnGUI() {
		EditorGUILayout.Space();

		EditorGUILayout.LabelField(
			"This window can export tone mapping Look-Up Textures (LUTs) " +
			"for use with Unity's Post-Processing Stack v2.\n\n" +
			"The exports are 1024 x 32 .exr files.\n" +
			"Via texture import settings they become 32 x 32 x 32 cube Texture3Ds.",
			EditorStyles.helpBox);

		EditorGUILayout.Space();

		GUILayout.BeginHorizontal();
		GUILayout.FlexibleSpace();
		identityLut = (Texture2D)EditorGUILayout.ObjectField(
			"2D Identity LUT", identityLut, typeof(Texture2D), false,
			GUILayout.Width(220));

		EditorGUIUtility.labelWidth = 70f;

		Rect texRect = GUILayoutUtility.GetLastRect();
		texRect.yMin = texRect.yMax - EditorGUIUtility.singleLineHeight;
		texRect.y -= EditorGUIUtility.singleLineHeight;
		EditorGUI.LabelField(texRect, "Resolution",
			identityLut != null ?
				$"{identityLut.width} x {identityLut.height}" :
				"-");
		texRect.y += EditorGUIUtility.singleLineHeight;
		EditorGUI.LabelField(texRect, "Expected", "1024 x 32");

		GUILayout.EndHorizontal();

		EditorGUILayout.Space(16);

		selectedTab = GUILayout.SelectionGrid(selectedTab, tabs, 3);

		EditorGUILayout.Space();

		if (selectedTab == 0) {
			SectionHeaderGUI("Export Shader LUT",
				"Export a LUT from a Shader that performs tone mapping.\n\n" +
				"It should sample the _MainTex input color and return the tone mapped result.\n" +
				"The shader should not convert to sRGB (gamma space).\n" +
				"The 2D identity LUT is automatically assigned to _MainTex.",
				true);

			EditorGUILayout.Space();
			GUILayout.FlexibleSpace();

			EditorGUI.BeginChangeCheck();
			shader = (Shader)EditorGUILayout.ObjectField(
				"Shader", shader, typeof(Shader), false);
			if (EditorGUI.EndChangeCheck())
				outputFilename = Path.GetFileNameWithoutExtension(AssetDatabase.GetAssetPath(shader));

			EditorGUILayout.Space();

			if (FilePathGUI(ref outputFolder, ref outputFilename, false, out string path)) {
				LutExporter.ExportShaderToLut(identityLut, shader, path, selectExported);
			}
		}
		else if (selectedTab == 1) {
			SectionHeaderGUI("Export Material LUT",
				"Export a LUT from a Material that performs tone mapping.\n\n" +
				"It should sample the _MainTex input color and return the tone mapped result.\n" +
				"The shader should not convert to sRGB (gamma space).\n" +
				"The 2D identity LUT is automatically assigned to _MainTex.\n" +
				"Other properties, if any, can be configured via the Material Inspector.",
				true);

			EditorGUILayout.Space();
			GUILayout.FlexibleSpace();

			EditorGUI.BeginChangeCheck();
			material = (Material)EditorGUILayout.ObjectField(
				"Material", material, typeof(Material), false);
			if (EditorGUI.EndChangeCheck())
				outputFilename = Path.GetFileNameWithoutExtension(AssetDatabase.GetAssetPath(material));

			EditorGUILayout.Space();

			if (FilePathGUI(ref outputFolder, ref outputFilename, false, out string path)) {
				LutExporter.ExportMaterialToLut(identityLut, material, path, selectExported);
			}
		}
		else if (selectedTab == 2) {
			SectionHeaderGUI("Export Post-Process Profile LUT",
				"Export a LUT from a post-process profile in Unity's Post-Processing Stack v2.\n\n" +
				"This can be used to export the tone mapping component.\n" +
				"All other components should normally be switched off.",
				true);

			EditorGUILayout.Space();
			GUILayout.FlexibleSpace();

			profile = (PostProcessProfile)EditorGUILayout.ObjectField(
				"Profile", profile, typeof(PostProcessProfile), false);

			EditorGUILayout.Space();

			if (FilePathGUI(ref outputFolder, ref outputFilename, false, out string path)) {
				LutExporter.ExportProfileToLut(identityLut, profile, path, selectExported);
			}
		}
		else if (selectedTab == 3) {
			SectionHeaderGUI("Export Identity LUT",
				"Export an identity LUT that does nothing; the output is the same as the input.\n\n" +
				"An identity LUT can be useful for comparing with other LUTs.",
				false);

			EditorGUILayout.Space();
			GUILayout.FlexibleSpace();

			if (FilePathGUI(ref outputFolder, ref outputFilenameId3D, false, out string path)) {
				LutExporter.GenerateIdentityLut(path, false, selectExported);
			}
		}
		else {
			SectionHeaderGUI("Export 2D Identity LUT",
				"Export a 2D texture that represents the identity LUT but is not imported as 3D.\n\n" +
				"A 2D identity LUT is required by this window for exporting most other LUTs.\n" +
				"If named 'Identity2D', this window can automatically locate the file.",
				false);

			EditorGUILayout.Space();
			GUILayout.FlexibleSpace();

			if (FilePathGUI(ref outputFolderId2D, ref outputFilenameId2D, false, out string path)) {
				LutExporter.GenerateIdentityLut(path, true, selectExported);
				// Assign 2D Identity LUT to this window.
				identityLut = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
			}
		}
	}

	void SectionHeaderGUI(string header, string desc, bool requireIdentity) {
		EditorGUILayout.LabelField(header, EditorStyles.boldLabel);
		bool disabled = requireIdentity && identityLut == null;
		if (disabled) {
			EditorGUILayout.HelpBox(
				"A 2D Identity LUT is required.\nExport one via the 2D Identity tab.",
				MessageType.Info);
		}
		else {
			EditorGUILayout.LabelField(desc, EditorStyles.helpBox);
		}

		EditorGUILayout.Space();
		GUILayout.FlexibleSpace();

		GUI.enabled = !disabled;
	}

	bool FilePathGUI(ref string folder, ref string filename, bool disabled, out string path) {
		// Folder field and button.
		EditorGUILayout.BeginHorizontal();
		folder = EditorGUILayout.TextField("Folder", folder);
		if (GUILayout.Button(
			"Browse",
			GUILayout.Width(70))) {
			string selected = EditorUtility.OpenFolderPanel(
				"LUT Export Folder", "Assets", "");

			if (!string.IsNullOrEmpty(selected)) {
				folder = FileUtil.GetProjectRelativePath(selected);
				if (string.IsNullOrEmpty(folder))
					folder = selected;
			}
		}
		EditorGUILayout.EndHorizontal();

		// Filename field.
		filename = EditorGUILayout.TextField("Filename", filename);

		EditorGUILayout.Space();

		path = null;

		// Export button.
		GUILayout.BeginHorizontal();

		GUILayout.FlexibleSpace();

		selectExported = GUILayout.Toggle(selectExported, "Select Exported");

		EditorGUILayout.Space();

		using (new EditorGUI.DisabledScope(disabled)) {
			if (GUILayout.Button("Export LUT")) {
				path = Path.Combine(folder, filename + ".exr");
			}
		}

		GUILayout.EndHorizontal();

		EditorGUILayout.Space(10);

		return path != null;
	}
}

public static class LutExporter {

	public static void GenerateIdentityLut(string outputPath, bool import2d, bool select) {
		Texture2D identityLut = IdentityLutGenerator.Generate();
		SaveAndImportLutAndDestroyTexture(identityLut, outputPath, select, import2d);
	}

	public static void ExportProfileToLut(
		Texture2D identityLut, PostProcessProfile profile, string outputPath, bool select
	) {
		Texture2D targetLut = CreateTargetTexture(identityLut);
		PostProcessProfileTonemapLutBaker.BakeProfileToTexture(identityLut, targetLut, profile);
		SaveAndImportLutAndDestroyTexture(targetLut, outputPath, select);
	}

	public static void ExportShaderToLut(
		Texture2D identityLut, Shader shader, string outputPath, bool select
	) {
		Material material = new Material(shader);
		ExportMaterialToLut(identityLut, material, outputPath, select);
		Object.DestroyImmediate(material);
	}

	public static void ExportMaterialToLut(
		Texture2D identityLut, Material material, string outputPath, bool select
	) {
		Texture2D targetLut = CreateTargetTexture(identityLut);
		MaterialTonemapLutBaker.BakeMaterialToTexture(identityLut, targetLut, material);
		SaveAndImportLutAndDestroyTexture(targetLut, outputPath, select);
	}

	static Texture2D CreateTargetTexture(Texture2D identityLut) {
		Texture2D tex = new Texture2D(identityLut.width, identityLut.height,
			TextureFormat.RGBAFloat, false, true);
		return tex;
	}

	static void SaveAndImportLutAndDestroyTexture(
		Texture2D targetLut, string outputPath, bool select, bool import2d = false
	) {
		string absoluteOutputPath = Path.GetFullPath(outputPath);
		string directory = Path.GetDirectoryName(absoluteOutputPath);

		if (!Directory.Exists(directory))
			Directory.CreateDirectory(directory);

		try {
			// Save to .exr file.
			byte[] exr = targetLut.EncodeToEXR(Texture2D.EXRFlags.OutputAsFloat);
			File.WriteAllBytes(absoluteOutputPath, exr);

			Object.DestroyImmediate(targetLut);

			AssetDatabase.Refresh();

			TextureImporter importer =
				AssetImporter.GetAtPath(outputPath) as TextureImporter;
			importer.textureShape = import2d ?
				TextureImporterShape.Texture2D :
				TextureImporterShape.Texture3D;
			importer.isReadable = true;
			importer.mipmapEnabled = false;
			importer.wrapMode = TextureWrapMode.Clamp;
			importer.filterMode = FilterMode.Trilinear;
			importer.textureCompression = TextureImporterCompression.Uncompressed;
			importer.SaveAndReimport();

			if (!import2d) {
				TextureImporterSettings settings = new TextureImporterSettings();
				importer.ReadTextureSettings(settings);
				settings.flipbookColumns = 32;
				importer.SetTextureSettings(settings);
				importer.SaveAndReimport();
			}

			Object obj = AssetDatabase.LoadAssetAtPath<Object>(outputPath);
			Debug.Log("LUT exported at " + outputPath, obj);
			if (select)
				Selection.activeObject = obj;
		}
		catch (System.Exception e) {
			Debug.LogException(e);
			EditorUtility.DisplayDialog("LUT Export Failed", e.Message, "OK");
		}
	}
}
