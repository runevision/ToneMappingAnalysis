# Tone Mapping Analysis

A Unity project with editor windows and tools for comparing tone mapping LUTs (look-up textures).

Developed and tested in Unity 2022.3. The LUTs are HDR .exr files representing 3D textures with Alexa LogC El 1000 encoded coordinates.

## Features

A **LUT Comparison window** for comparing and analyzing LUTs.

* Compare how they look when applied to HDR .exr images.
* Compare their effects on said images with multiple overlays.
* Compare their properties via multiple graphs.

A **LUT Exporter window** for exporting LUTs from multiple sources.

* Export a LUT from a *shader* (with no properties).
* Export a LUT from a *Material*.
* Export a LUT from a *post-processing profile* in Unity's Post-Processing Stack v.2.

A **tone mapper called Tony Vibrant** implemented in Unity's Post-Processing Stack v.2 and exported as a LUT.

## License

Tone Mapping Analysis is primarily licensed under the [Mozilla Public License, v. 2.0](https://www.mozilla.org/en-US/MPL/2.0/).

Some files are licensed under other licenses. See the [LICENSE](LICENSE.md) file for details.
