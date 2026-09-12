# Tone Mapping Analysis

Tools for comparing tone mapping LUTs (look-up textures), implemented as a Unity project with custom editor windows (developed and tested in Unity 2022.3).

The project also contains my own tone mapper *Tony Vibrant*.

The LUTs are HDR .exr files representing 3D textures with Alexa LogC El 1000 encoded coordinates.


## Features

### A **LUT Comparison window** for comparing and analyzing LUTs

*Open it with `Window > LUT > LUT Comparison`.*

**Compare how different tone mappers look when applied to HDR .exr images.**

* Adjust image size, switch between different image sets, and toggle which tone mappers are active in the table.
* Adjust exposure per image and multiplier per tone mapper (both applied prior to tone mapping).
* Easily compare different tone mappers with left/right comparison sliders for one cell, a row, a column, or all cells at once.

<img width="2560" height="1440" alt="CompareImagesWithSlider" src="https://github.com/user-attachments/assets/7563fffa-7ba1-4fc0-855f-7cecccf06334" />

*A table of different images, each shown with different tone mappers. One cell shows a comparison slider.*

**Compare different tone mappers' effects on images with multiple overlays.**

* Max Channel Overlay: How much a tone mapper changes the value of the maximum channel.
* Saturation Overlay: How much a tone mapper changes the saturation.
* Hue Only Overlay: Display only hue, with constant saturation and brightness, so hues can easily be compared.

<img width="2560" height="1440" alt="CompareOverlays" src="https://github.com/user-attachments/assets/408ac716-49ac-456a-bda5-2e58ee3042a9" />

*The Saturation Overlay applied to the images in the table.*

**Compare different tone mappers' properties via multiple graphs.**

* Out saturation and value graph: See how much of the output color space is reachable with a tone mapper.
* In value to out saturation graph: See how quickly colors lose saturation as input brightness increases.
* In value to out hue graph: See how colors shift hue as input brightness increases.
* In value to out value: The classic graph of the output value.
* Where applicable, graphs show curves for white, RGB and CMY, and for both 99% and 50% saturation.

<img width="2560" height="1440" alt="CompareGraphs" src="https://github.com/user-attachments/assets/bcc710f2-e97a-43aa-95dd-64f19c4c96a8" />

*Graphs are displayed for each tone mapper row.*

### A **LUT Exporter window** for exporting LUTs from multiple sources

*Open it with `Window > LUT > LUT Exporter`.*

* Export a LUT from a *shader* (with no properties).
* Export a LUT from a *Material*.
* Export a LUT from a *post-processing profile* in Unity's Post-Processing Stack v.2.

<img width="581" height="726" alt="LUTExporter" src="https://github.com/user-attachments/assets/548a88ac-5042-4a4f-bf4d-81aab3b6d237" />

*The LUT Exporter window showing the Shader tab.*


### A **tone mapper called Tony Vibrant**

My own tone mapper, which uses most of the output range for input colors that are only a few times brighter than the output range. There's minimal loss of saturation, with almost the entire output color space being reachable, and a moderate shift of hues for bright colors.

Tony Vibrant was inspired by [Tony McMapface](https://github.com/h3r2tic/tony-mc-mapface), but generally creates brighter outputs, and uses simpler methodology that's not based on color perception theory.

Implemented in Unity's Post-Processing Stack v.2 and also available as a LUT.

<img width="2560" height="1440" alt="TonyVibrant" src="https://github.com/user-attachments/assets/88474672-36ef-4e08-905c-fab285186b45" />

*Tony Vibrant compared to Tony McMapface.*


## License

Tone Mapping Analysis is primarily licensed under the [Mozilla Public License, v. 2.0](https://www.mozilla.org/en-US/MPL/2.0/).

Some files are licensed under other licenses. See the [LICENSE](LICENSE.md) file for details.
