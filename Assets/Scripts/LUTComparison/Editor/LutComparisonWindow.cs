/*
 * Copyright (c) 2026 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEngine;
using Mapping = LutSet.Mapping;
using SampleImage = ImageSet.SampleImage;

public class LUTComparisonWindow : EditorWindow {
	LutSet lutSet;
	ImageSet imageSet;

	// Window layout state.
	Vector2 scrollPos;
	int imageW = 480;

	// Comparison state.
	enum CompareScope { Cell, Column, Row, All }
	bool compare;
	int comparisonIndex;
	CompareScope compareScope;

	// Mouse cursor comparison state.
	bool mouseInsideScrollView;
	int compareRow, compareCol;
	bool compareLocked;
	float split;

	// Graphs state.
	bool pinGraphs;
	bool graphClip = true;
	bool graphShowWhite = true;
	bool graphShowRGB = true;
	bool graphShowCMY = true;

	// Visualization overlay state.
	enum Overlay { NoOverlay, MaxChannelOverlay, SaturationOverlay, HueOnlyOverlay }
	Overlay overlay;

	// Constants.
	const float border = 1;
	const float padding = 1;
	const float headerW = 180f + border;
	const float headerH = 22 + border;
	const float minImageW = 200f;
	const float maxImageW = 1920f;
	const string lutSetPref = nameof(lutSetPref);
	const string imageSetPref = nameof(imageSetPref);
	const string lutSetUndoName = "Lut Set Options";
	const string imageSetUndoName = "Image Set Options";

	// Properties.
	float imageH => Mathf.CeilToInt(imageW * 9f / 16f - 0.0001f);
	float cellW => imageW + 2 * padding;
	float cellH => imageH + 2 * padding;
	float cellWInc => cellW + border;
	float cellHInc => cellH + border;

	// Cached variables.
	GUIStyle compareL, compareR;
	Material graphMaterial;
	List<Mapping> mappings;
	string[] mappingNames;
	Rect scrollView;
	Texture2D graphLabels;

	[MenuItem("Window/LUT/LUT Comparison")]
	public static void Open() {
		var window = GetWindow<LUTComparisonWindow>("LUT Comparison");
		window.minSize = new Vector2(600f, 400f);
	}

	void OnEnable() {
		if (lutSet == null) {
			string[] results = AssetDatabase.FindAssets("t:LutSet");
			if (results != null && results.Length == 1) {
				string path = AssetDatabase.GUIDToAssetPath(results[0]);
				lutSet = AssetDatabase.LoadAssetAtPath<LutSet>(path);
				SavePrefs();
			}
		}
		if (imageSet == null) {
			string[] results = AssetDatabase.FindAssets("t:ImageSet");
			if (results != null && results.Length == 1) {
				string path = AssetDatabase.GUIDToAssetPath(results[0]);
				imageSet = AssetDatabase.LoadAssetAtPath<ImageSet>(path);
				SavePrefs();
			}
		}
		LoadPrefs();

		if (graphLabels == null) {
			string[] results = AssetDatabase.FindAssets("t:Texture2D GraphLabels");
			if (results != null && results.Length >= 1) {
				string path = AssetDatabase.GUIDToAssetPath(results[0]);
				graphLabels = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
			}
		}

		var graphShader = Shader.Find("Hidden/LUTGraph");
		if (graphShader == null) {
			Debug.LogError("Could not find Hidden/LUTGraph shader.");
		}
		else {
			graphMaterial = new Material(graphShader);
		}

		mappings = lutSet.mappings.Where(e => e.active).ToList();

		Undo.undoRedoEvent += OnUndoRedoEvent;
	}

	void OnDisable() {
		foreach (var mapping in lutSet.mappings) {
			if (mapping.graph)
				DestroyImmediate(mapping.graph);
		}
		Undo.undoRedoEvent -= OnUndoRedoEvent;
	}

	void OnUndoRedoEvent(in UndoRedoInfo info) {
		if (info.undoName == lutSetUndoName) {
			UpdateGraphs();
			Repaint();
		}
		if (info.undoName == imageSetUndoName) {
			Repaint();
		}
	}

	void OnFocus() {
		if (!lutSet)
			return;
		mappings = lutSet.mappings.Where(e => e.active).ToList();
		mappingNames = lutSet.mappings
			.Select(e => GetMappingLabels(e, out _)).ToArray();
		UpdateGraphs();
	}

	void OnGUI() {
		if (compareL == null) {
			compareL = new GUIStyle(EditorStyles.whiteBoldLabel);
			compareL.padding = new RectOffset(1, 7, 1, 2);
			compareR = new GUIStyle(compareL);
			compareL.alignment = TextAnchor.UpperRight;
			compareR.padding = new RectOffset(7, 1, 1, 2);
		}

		if (Event.current.type == EventType.KeyDown && Event.current.modifiers == EventModifiers.None) {
			if (Event.current.keyCode == KeyCode.C) {
				compare = !compare;
				Repaint();
			}
			if (Event.current.keyCode == KeyCode.G) {
				pinGraphs = !pinGraphs;
				Repaint();
			}
		}

		DrawToolbar();
		wantsMouseMove = compare;

		bool abort = false;
		if (lutSet == null) {
			EditorGUILayout.HelpBox("Assign a LUT Set.", MessageType.Info);
			abort = true;
		}
		else if (lutSet.mappings.Count == 0) {
			EditorGUILayout.HelpBox("No mappings in LUT Set.", MessageType.Warning);
			abort = true;
		}
		else if (mappings.Count == 0) {
			EditorGUILayout.HelpBox("No mappings are active in mappings dropdown.", MessageType.Warning);
			abort = true;
		}

		if (imageSet == null) {
			EditorGUILayout.HelpBox("Assign an Image Set.", MessageType.Info);
			abort = true;
		}
		else if (imageSet.screenshots.Count == 0) {
			EditorGUILayout.HelpBox("No images in Image Set.", MessageType.Warning);
			abort = true;
		}

		if (abort)
			return;

		// Set up materials.
		int rows = mappings.Count;
		for (int y = 0; y < rows; y++) {
			Mapping mapping = mappings[y];
			if (mapping.shader == null)
				continue;
			if (mapping.material != null && mapping.material.shader == mapping.shader)
				continue;
			mapping.material = new Material(mapping.shader);
		}
		// Set up cached RenderTextures.
		foreach (var mapping in mappings) {
			if (mapping.graph == null) {
				mapping.graph = new RenderTexture(1024, 512, 0);
				mapping.graph.useMipMap = true;
				UpdateGraph(mapping);
			}
		}

		if (!compareLocked && Event.current.type == EventType.MouseMove)
			split = -1f;

		float toolbarHeight = 21f;
		Rect tableRect = new Rect(0f, toolbarHeight, position.width, position.height - toolbarHeight);
		DrawTable(tableRect);

		if (Event.current.type == EventType.MouseMove && wantsMouseMove)
			Repaint();
	}

	void SetShaderKeyword(string keyword, bool enabled) {
		if (enabled)
			Shader.EnableKeyword(keyword);
		else {
			Shader.DisableKeyword(keyword);
		}
	}

	void SavePrefs() {
		if (lutSet) {
			string guid = AssetDatabase.GUIDFromAssetPath(AssetDatabase.GetAssetPath(lutSet)).ToString();
			EditorPrefs.SetString(lutSetPref, guid);
		}
		if (imageSet) {
			string guid = AssetDatabase.GUIDFromAssetPath(AssetDatabase.GetAssetPath(imageSet)).ToString();
			EditorPrefs.SetString(imageSetPref, guid);
		}
	}

	void LoadPrefs() {
		string lutGuid = EditorPrefs.GetString(lutSetPref);
		if (lutSet == null && !string.IsNullOrEmpty(lutGuid)) {
			lutSet = AssetDatabase.LoadAssetAtPath<LutSet>(AssetDatabase.GUIDToAssetPath(lutGuid));
		}
		string imageGuid = EditorPrefs.GetString(imageSetPref);
		if (imageSet == null && !string.IsNullOrEmpty(imageGuid)) {
			imageSet = AssetDatabase.LoadAssetAtPath<ImageSet>(AssetDatabase.GUIDToAssetPath(imageGuid));
		}
	}

	void DrawToolbar() {
		EditorGUILayout.BeginHorizontal(EditorStyles.toolbar);

		EditorGUI.BeginChangeCheck();
		var newLutSet = (LutSet)EditorGUILayout.ObjectField(
			lutSet, typeof(LutSet), false,
			GUILayout.Width(160f));
		if (EditorGUI.EndChangeCheck()) {
			lutSet = newLutSet;
			Repaint();
		}

		MapperSelection();

		EditorGUILayout.Space();

		EditorGUI.BeginChangeCheck();
		var newImageSet = (ImageSet)EditorGUILayout.ObjectField(
			imageSet, typeof(ImageSet), false,
			GUILayout.Width(160f));
		if (EditorGUI.EndChangeCheck()) {
			imageSet = newImageSet;
			SavePrefs();
			Repaint();
		}

		EditorGUILayout.Space();

		compare = GUILayout.Toggle(compare, "Compare", EditorStyles.toolbarButton);
		compareScope = (CompareScope)EditorGUILayout.EnumPopup(compareScope, EditorStyles.toolbarPopup, GUILayout.Width(65));

		EditorGUILayout.Space();

		// Overlay shader state.
		overlay = (Overlay)EditorGUILayout.EnumPopup(overlay, EditorStyles.toolbarPopup, GUILayout.Width(140));
		SetShaderKeyword("VisMaxDelta", overlay == Overlay.MaxChannelOverlay);
		SetShaderKeyword("VisSatDelta", overlay == Overlay.SaturationOverlay);
		SetShaderKeyword("VisHueOnly", overlay == Overlay.HueOnlyOverlay);

		EditorGUILayout.Space();

		GUILayout.FlexibleSpace();

		GUILayout.Label("Cell Size", EditorStyles.label);

		EditorGUI.BeginChangeCheck();
		float newImageW = EditorGUILayout.Slider(
			imageW, minImageW, maxImageW, GUILayout.Width(250f));
		if (EditorGUI.EndChangeCheck()) {
			Vector2 zoomPoint = scrollPos + scrollView.size * 0.5f;
			Zoom(newImageW, zoomPoint);
		}

		EditorGUILayout.EndHorizontal();
	}

	void MapperSelection() {
		if (lutSet == null || lutSet.mappings == null) {
			return;
		}

		int activeMask = 0;
		for (int i = 0; i < lutSet.mappings.Count; i++) {
			if (lutSet.mappings[i].active)
				activeMask |= 1 << i;
		}

		EditorGUI.BeginChangeCheck();
		activeMask = EditorGUILayout.MaskField(
			GUIContent.none, activeMask, mappingNames,
			EditorStyles.toolbarDropDown, GUILayout.Width(100));
		if (EditorGUI.EndChangeCheck()) {
			for (int i = 0; i < lutSet.mappings.Count; i++) {
				lutSet.mappings[i].active = (activeMask & 1 << i) != 0;
			}
		}
	}

	void Zoom(float newImageW, Vector2 zoomPoint) {
		float oldCellWInc = cellWInc;
		float oldCellHInc = cellHInc;
		imageW = Mathf.RoundToInt(Mathf.Clamp(newImageW, minImageW, maxImageW));
		Vector2 ratio = new Vector2(cellWInc / oldCellWInc, cellHInc / oldCellHInc);
		scrollPos += Vector2.Scale(zoomPoint, ratio) - zoomPoint;
	}

	void DrawTable(Rect rect) {
		Undo.RecordObject(lutSet, lutSetUndoName);
		Undo.RecordObject(imageSet, imageSetUndoName);
		EditorGUI.BeginChangeCheck();

		// Dark background.
		EditorGUI.DrawRect(new Rect(
			rect.x,
			rect.y + headerH,
			rect.width,
			rect.height - headerH
			), Color.black);

		int cols = imageSet.screenshots.Count;
		int rows = mappings.Count;

		float fixedW = headerW + (pinGraphs ? cellWInc : 0f);
		float scrollW = cols * cellWInc + (pinGraphs ? 0f : cellWInc);
		float scrollStart = (pinGraphs ? 0f : -cellWInc);

		DrawCornerHeader(new Rect(rect.x, rect.y, headerW, headerH));

		if (pinGraphs)
			DrawGraphsHeader(new Rect(rect.x + headerW, rect.y, cellWInc, headerH));

		// Column headers.
		Rect colHeaderRect =
			new Rect(rect.x + fixedW, rect.y, rect.width - fixedW, headerH);
		GUI.BeginClip(
			colHeaderRect,
			new Vector2(-scrollPos.x - scrollStart, 0f),
			new Vector2(0f, 0f), false);
		if (!pinGraphs)
			DrawGraphsHeader(new Rect(-cellWInc, 0f, cellWInc, headerH));
		DrawColumnHeaders();
		GUI.EndClip();

		// Row headers.
		Rect rowHeaderRect =
			new Rect(rect.x, rect.y + headerH, fixedW, rect.height - headerH);
		mouseInsideScrollView = rowHeaderRect.Contains(Event.current.mousePosition);
		Vector2 vScrollPos = GUI.BeginScrollView(
			rowHeaderRect,
			Vector2.Scale(scrollPos, Vector2.up),
			new Rect(0f, 0f, headerW, rows * cellHInc), GUIStyle.none, GUIStyle.none);
		scrollPos.y = vScrollPos.y;
		DrawRowHeaders();
		if (pinGraphs)
			DrawGraphs(headerW);
		GUI.EndScrollView();

		// Handle scrollwheel zooming, part 1.
		float newImageW = imageW;
		mouseInsideScrollView = scrollView.Contains(Event.current.mousePosition);
		if (Event.current.type == EventType.ScrollWheel
			&& mouseInsideScrollView && Event.current.command
		) {
			newImageW = imageW * Mathf.Pow(2f, -Event.current.delta.y * 0.1f);
			Event.current.Use();
		}
		// Cells.
		scrollView = new Rect(
			rect.x + fixedW, rect.y + headerH,
			rect.width - fixedW, rect.height - headerH);
		scrollPos = GUI.BeginScrollView(
			scrollView,
			scrollPos,
			new Rect(scrollStart, 0f, scrollW, rows * cellHInc));

		// Handle scrollwheel zooming, part 2.
		if (newImageW != imageW) {
			Vector2 zoomPoint = Event.current.mousePosition - new Vector2(scrollStart, 0f);
			Zoom(newImageW, zoomPoint);
		}

		if (!pinGraphs)
			DrawGraphs(scrollStart);
		DrawCells();
		GUI.EndScrollView();

		// Line below column headers.
		EditorGUI.DrawRect(new Rect(
			rect.x,
			rect.y + headerH - border,
			rect.width,
			border
		), Color.black);
		// Line to the right of row headers.
		EditorGUI.DrawRect(new Rect(
			rect.x + headerW - border,
			rect.y,
			border,
			headerH
		), Color.black);
		// Line to the right of row headers.
		EditorGUI.DrawRect(new Rect(
			rect.x + headerW - border,
			rect.y + headerH,
			border,
			rect.height - headerH
		), Color.gray);

		if (EditorGUI.EndChangeCheck())
			EditorUtility.SetDirty(lutSet);
	}


	void DrawRowHeaders() {
		int rows = mappings.Count;
		for (int y = 0; y < rows; y++) {
			Mapping mapping = mappings[y];
			Rect rect = new Rect(0f, y * cellHInc, headerW, cellHInc - border);
			DrawRowHeader(rect, y, mapping);
			// Line to the right of row headers.
			EditorGUI.DrawRect(new Rect(rect.x, rect.yMax, rect.width, border), Color.gray);
		}
	}

	string GetMappingLabels(Mapping mapping, out string subLabel) {
		string label = "Missing";
		subLabel = "No LUT or shader found";
		if (mapping.lut != null) {
			label = mapping.lut.name;
			subLabel = "LUT";
		}
		else if (mapping.shader != null) {
			label = mapping.shader.name.Replace("Hidden/", "");
			subLabel = "Shader";
		}
		return label;
	}

	void DrawRowHeader(Rect rect, int index, Mapping mapping) {
		bool active = (compare && index == comparisonIndex);
		if (active)
			EditorGUI.DrawRect(rect, new Color(0.0f, 0.1f, 0.2f));
		GUILayout.BeginArea(rect, GUIContent.none, EditorStyles.inspectorFullWidthMargins);
		string label = GetMappingLabels(mapping, out string subLabel);
		GUILayout.Label(label, EditorStyles.whiteBoldLabel);
		GUILayout.Label(subLabel, EditorStyles.whiteLabel);

		EditorGUILayout.Space();

		bool newActive = GUILayout.Toggle(
			active, "Compare With", EditorStyles.miniButton, GUILayout.ExpandWidth(false));
		if (newActive != active) {
			if (newActive) {
				comparisonIndex = index;
				compare = true;
			}
			else {
				compare = false;
			}
		}

		if (mapping.lut != null) {
			EditorGUILayout.Space();

			GUILayout.Label("Multiplier", EditorStyles.whiteLabel);
			EditorGUI.BeginChangeCheck();
			mapping.multiplier = EditorGUILayout.Slider(
				mapping.multiplier, 0.1f, 4f);
			if (EditorGUI.EndChangeCheck())
				UpdateGraph(mapping);
		}

		GUILayout.EndArea();
	}

	void DrawColumnHeaders() {
		int cols = imageSet.screenshots.Count;
		for (int x = 0; x < cols; x++) {
			Rect rect = new Rect(x * cellWInc, 0f, cellWInc - border, headerH);
			DrawColumnHeader(rect, imageSet.screenshots[x]);
		}
	}

	void DrawColumnHeader(Rect rect, SampleImage image) {
		GUILayout.BeginArea(rect, GUIContent.none, EditorStyles.inspectorFullWidthMargins);
		GUILayout.BeginHorizontal();
		GUILayout.Label(image.image.name, EditorStyles.label, GUILayout.MaxWidth(200));
		GUILayout.FlexibleSpace();
		GUILayout.Label("Exposure", EditorStyles.label);
		image.exposure = EditorGUILayout.Slider(image.exposure, 0f, 10f, GUILayout.MaxWidth(200));
		GUILayout.EndHorizontal();
		GUILayout.EndArea();
		EditorGUI.DrawRect(new Rect(rect.xMax, rect.y, border, rect.height), Color.black);
	}

	void DrawCornerHeader(Rect rect) {
		GUILayout.BeginArea(rect, GUIContent.none, EditorStyles.inspectorFullWidthMargins);
		pinGraphs = GUILayout.Toggle(pinGraphs, "Pin Graphs");
		GUILayout.EndArea();
		EditorGUI.DrawRect(new Rect(rect.xMax - border, rect.y, border, rect.height), Color.black);
	}

	void DrawGraphsHeader(Rect rect) {
		GUILayout.BeginArea(rect, GUIContent.none, EditorStyles.inspectorFullWidthMargins);
		GUILayout.BeginHorizontal();
		EditorGUI.BeginChangeCheck();

		graphClip = GUILayout.Toggle(graphClip, "Clip");
		EditorGUILayout.Space(20);
		graphShowWhite = GUILayout.Toggle(graphShowWhite, "White");
		EditorGUILayout.Space();
		graphShowRGB = GUILayout.Toggle(graphShowRGB, "RGB");
		EditorGUILayout.Space();
		graphShowCMY = GUILayout.Toggle(graphShowCMY, "CMY");
		if (EditorGUI.EndChangeCheck())
			UpdateGraphs();
		GUILayout.FlexibleSpace();
		GUILayout.EndHorizontal();
		GUILayout.EndArea();
		EditorGUI.DrawRect(new Rect(rect.xMax - border, rect.y, border, rect.height), Color.black);
	}

	void DrawGraphs(float xStart) {
		int rows = mappings.Count;
		for (int y = 0; y < rows; y++) {
			Mapping mapping = mappings[y];
			if (mapping.lut == null)
				continue;
			Rect cellRect = new Rect(xStart, y * cellHInc, cellWInc - border, cellHInc - border);
			DrawGraph(cellRect, y, mapping);
		}
	}

	void DrawGraph(Rect rect, int row, Mapping mapping) {
		if (!CompareHere(rect, -1, row, mapping, out Rect croppedL, out Rect croppedR)) {
			DrawGraphImage(rect, rect, mapping);
		}
		else {
			// Draw images.
			Mapping compareMapping = mappings[comparisonIndex];
			DrawGraphImage(rect, croppedL, compareMapping);
			DrawGraphImage(rect, croppedR, mapping);
			DrawCompareLabel(croppedL, croppedR, mapping, compareMapping);
		}
	}

	void DrawGraphImage(Rect rect, Rect cropped, Mapping mapping) {
		if (mapping.lut == null)
			return;

		GUI.BeginClip(
			cropped,
			-cropped.position,
			Vector2.zero,
			false);

		Rect imageRect = new Rect(
			rect.x + padding,
			rect.y + padding,
			rect.width - 2 * padding,
			rect.height - 2 * padding);

		GUI.DrawTexture(imageRect, mapping.graph, ScaleMode.ScaleToFit);
		if (graphLabels)
			GUI.DrawTexture(imageRect, graphLabels, ScaleMode.ScaleToFit);

		GUI.EndClip();
	}

	void DrawCells() {
		int cols = imageSet.screenshots.Count;
		int rows = mappings.Count;
		for (int y = 0; y < rows; y++) {
			Mapping mapping = mappings[y];
			for (int x = 0; x < cols; x++) {
				Rect cellRect = new Rect(x * cellWInc, y * cellHInc, cellWInc - border, cellHInc - border);
				DrawCell(cellRect, x, y, imageSet.screenshots[x], mapping);
			}
		}
	}

	bool CompareHere(Rect rect, int col, int row, Mapping mapping,
	    out Rect croppedL, out Rect croppedR
	) {
		// Figure out if we should compare in this cell.
		Vector2 cursor = Event.current.mousePosition;
		bool inCol = compareCol == col;
		bool inRow = compareRow == row;

		if (mouseInsideScrollView && rect.Contains(cursor)) {
			if (Event.current.type == EventType.MouseDown) {
				compareLocked = !compareLocked;
				Event.current.Use();
			}
			if (!compareLocked) {
				split = (cursor.x - rect.xMin) / rect.width;
				compareCol = col;
				compareRow = row;
			}
		}

		// Calculate cropped rects.
		croppedL = rect;
		croppedR = rect;
		croppedL.width = split * rect.width;
		croppedR.xMin = croppedL.xMax;

		bool compareHere =
			(compareScope == CompareScope.All) ||
			(compareScope == CompareScope.Column && inCol) ||
			(compareScope == CompareScope.Row && inRow) ||
			(compareScope == CompareScope.Cell && inCol && inRow);
		compareHere &= compare && split != -1 && mappings[comparisonIndex] != mapping;
		return compareHere;
	}

	void DrawCompareLabel(Rect croppedL, Rect croppedR,
	    Mapping mapping, Mapping compareMapping
	) {
		// Draw labels.
		string labelSelf = GetMappingLabels(mapping, out _);
		string labelCompare = GetMappingLabels(compareMapping, out _);
		EditorGUI.DropShadowLabel(croppedL, labelCompare, compareL);
		EditorGUI.DropShadowLabel(croppedR, labelSelf, compareR);
		// Vertical line between labels.
		EditorGUI.DrawRect(
			new Rect(croppedL.xMax - 2, croppedL.y + padding, 4, 20),
			new Color(0, 0, 0, 0.6f));
		EditorGUI.DrawRect(
			new Rect(croppedL.xMax - 1, croppedL.y + padding, 2, 18),
			new Color(1, 1, 1, 0.8f));
	}

	void DrawCell(Rect rect, int col, int row, SampleImage screenshot, Mapping mapping) {
		if (screenshot.image == null) {
			GUI.Label(rect, "Missing image");
			return;
		}

		if (!CompareHere(rect, col, row, mapping, out Rect croppedL, out Rect croppedR)) {
			DrawCellImage(rect, rect, screenshot, mapping);
		}
		else {
			// Draw images.
			Mapping compareMapping = mappings[comparisonIndex];
			DrawCellImage(rect, croppedL, screenshot, compareMapping);
			DrawCellImage(rect, croppedR, screenshot, mapping);
			DrawCompareLabel(croppedL, croppedR, mapping, compareMapping);
		}
	}

	void DrawCellImage(
		Rect rect, Rect cropped, SampleImage screenshot, Mapping mapping
	) {
		Material mat = mapping.material;
		if (!mat)
			return;

		GUI.BeginClip(
			cropped,
			-cropped.position,
			Vector2.zero,
			false);

		Rect imageRect = new Rect(
			rect.x + padding,
			rect.y + padding,
			rect.width - 2 * padding,
			rect.height - 2 * padding);

		// Configure the material for this cell.
		mat.SetTexture("_MainTex", screenshot.image);
		mat.SetFloat("_ExposureVal", screenshot.exposure);
		mat.SetFloat("_Multiplier", mapping.multiplier);
		SetShaderKeyword("ShaderTest", mapping.shaderTest);

		Texture3D lut = mapping.lut;
		if (lut != null) {
			mat.SetTexture("_LUT", lut);
			mat.SetVector("_Lut3D_Params",
				new Vector2(1f / lut.width, lut.width - 1f));
		}

		// Draw the source texture directly through the LUT shader.
		EditorGUI.DrawPreviewTexture(
			imageRect,
			screenshot.image,
			mat,
			ScaleMode.ScaleToFit);

		GUI.EndClip();
	}

	void UpdateGraphs() {
		foreach (var mapping in mappings) {
			UpdateGraph(mapping);
		}
		Repaint();
	}

	void UpdateGraph(Mapping mapping) {
		SetShaderKeyword("ClipOutput", graphClip);
		SetShaderKeyword("ShowWhite", graphShowWhite);
		SetShaderKeyword("ShowRGB", graphShowRGB);
		SetShaderKeyword("ShowCMY", graphShowCMY);

		Material mat = graphMaterial;
		mat.SetFloat("_Multiplier", mapping.multiplier);
		Texture3D lut = mapping.lut;
		if (lut != null) {
			mat.SetTexture("_LUT", lut);
			mat.SetVector("_Lut3D_Params",
				new Vector2(1f / lut.width, lut.width - 1f));
		}

		Graphics.Blit(null, mapping.graph, mat);
		RenderTexture.active = null;
	}
}
