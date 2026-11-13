# Integration With files

The result surface follows the `files` grid conventions through adapters. Search-specific metadata is supplied as result and row model fields rather than by changing grid layout internals.

search does not depend on the `files` crate. The grid and the text rendering are guikit's (`Guikit.Item_Grid`, `Guikit.Text`), shared with files rather than taken from it, and the fonts are found by `Search.Fonts`, a small host adapter over `Guikit.Fonts` and `Hostkit.Fs.Font_Directories` -- the same arrangement the launcher uses. One difference follows: files decodes the PNG pictures inside bitmap colour-emoji fonts with its own image decoder, which neither guikit nor textrender carries, so search lists only the layered (COLR) emoji fonts textrender draws unaided; where only a bitmap emoji font is installed, an emoji in a result draws monochrome.
