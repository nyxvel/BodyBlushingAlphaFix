# Body Blushing Alpha Fix

Removes the faint grey film that **Body Blushing - RaceMenu Overlays** (CBBE 4K, Nexus Mods SE mod
130454) lays over most of the body.

## The problem

The blush textures (`textures\Actors\Character\Overlays\CheeseBlushOverlays\Blush_*.dds`) are BC7
with alpha. Their fully transparent pixels are grey 127, and BC7 shares a p-bit between colour and
alpha, so encoding grey 127 exactly forces alpha to 1. On `Blush_Spank.dds`, 16,595,876 of the
16,777,216 pixels end up at alpha 1/255 instead of 0: every blush layer is a barely visible grey
coat over the whole body, and with several layers on at once it adds up.

## The fix

Each texture is decoded, then:

- alpha <= 8 (about 3% opacity) becomes 0, and the rest is stretched back to 1..255;
- fully transparent pixels get grey 128, which BC7 can store with alpha 0;

and it's encoded again as BC7 (sRGB, full mip chain). `Blush_Spank.dds`: 16,595,876 -> 6,011
alpha-1 pixels.

## Building the patch

The textures belong to Body Blushing, so this repository ships a patcher instead of the textures. It
needs `texconv.exe` from DirectXTex (github.com/microsoft/DirectXTex/releases; xEdit ships it too, as
`Edit Scripts\Texconvx64.exe`):

    powershell -ExecutionPolicy Bypass -File patch.ps1 -Texconv <path>\texconv.exe
    powershell -ExecutionPolicy Bypass -File patch.ps1 -Texconv <path>\texconv.exe -Source "<Body Blushing>\textures\Actors\Character\Overlays\CheeseBlushOverlays" -Output out

Without `-Source` it reads the textures from the game's Data folder. About 15-20 s per texture (22
textures). Textures that are already fixed are skipped. Zip the `out` folder and install it with your
mod manager, loaded after Body Blushing.

Don't write the result into Data by hand when you use Vortex: Data files are hardlinks to Vortex's
staging copy, so that would overwrite Body Blushing's own files too.

## License

MIT (`LICENSE`). The textures belong to Body Blushing's author; none are included here.
