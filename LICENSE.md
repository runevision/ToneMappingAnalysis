# License file for Tone Mapping Analysis

Tone Mapping Analysis is primarily licensed under the [Mozilla Public License, v. 2.0](https://mozilla.org/MPL/2.0/).

Some files are licensed under other licenses as detailed below.

## Tone mapping tools
Location: **Assets/Scripts/**

LUT Comparison window and LUT Exporter window copyright (c) 2026 Rune Skovbo Johansen.

The Source Code Forms (C# and shader files) are subject to the terms of the [Mozilla Public License, v. 2.0](https://mozilla.org/MPL/2.0/).

## Tone mapper sources
Location:
**Assets/Baking/ToneMappers/**
and **Packages/com.unity.postprocessing@3.5.4/PostProcessing/Shaders/TonyVibrant.hlsl**

The tone mapping shaders in these locations are subject to the licenses specified in each individual file.

 * **Tony Vibrant**: [Mozilla Public License, v. 2.0](https://mozilla.org/MPL/2.0/)
 * **PBR Neutral**: [Apache License, Version 2.0](https://opensource.org/licenses/Apache-2.0)
 * **GT7**: [The MIT License](https://opensource.org/licenses/MIT)
 * **Reinhard and Uncharted 2**: No licenses specified, as [the source](https://64.github.io/tonemapping/) they are derived from did not specify any. The code in these files is simple and widely shared.

## Unity Post-Processing Stack v2
Location: **Packages/com.unity.postprocessing@3.5.4/**

The com.unity.postprocessing package has been internalized in the project in order to add an additional tone mapper to it. Apart from the new Tony Vibrant tone mapper, the rest of the package is licensed as follow:

com.unity.postprocessing copyright (c) 2025 Unity Technologies.

Licensed under the Unity Companion License for Unity-dependent projects--see [Unity Companion License](http://www.unity3d.com/legal/licenses/Unity_Companion_License).

