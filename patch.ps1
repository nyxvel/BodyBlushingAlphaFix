<#
.SYNOPSIS
    Builds Body Blushing Alpha Fix from your own Body Blushing textures.
.DESCRIPTION
    Body Blushing's overlay textures leave a faint grey layer over most of the body. Their fully
    transparent pixels are grey 127, and BC7 shares a p-bit between colour and alpha, so encoding 127
    exactly forces alpha to 1. This re-encodes each Blush_*.dds: alpha <= 8 (about 3% opacity) becomes 0,
    the rest is stretched back to 1..255, and fully transparent pixels get grey 128.
    Textures that are already fixed (hardly any alpha-1 pixels) are skipped.
.PARAMETER Source
    Folder with Body Blushing's Blush_*.dds (textures\Actors\Character\Overlays\CheeseBlushOverlays).
    Default: that folder in the game's Data folder (found through the registry).
.PARAMETER Texconv
    texconv.exe from DirectXTex (github.com/microsoft/DirectXTex/releases). xEdit ships it too, as
    Edit Scripts\Texconvx64.exe. Default: texconv.exe next to this script or on PATH.
.PARAMETER Output
    Folder to write into (textures\Actors\Character\Overlays\CheeseBlushOverlays\*.dds).
    Default: out\ next to this script.
.PARAMETER Name
    Only these textures (e.g. Blush_Ass). Default: all Blush_*.dds.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File patch.ps1 -Texconv "D:\xEdit\Edit Scripts\Texconvx64.exe"
#>
param(
    [string]$Source,
    [string]$Texconv,
    [string]$Output = (Join-Path $PSScriptRoot 'out'),
    [string[]]$Name
)
$ErrorActionPreference = 'Stop'
$folder = 'textures\Actors\Character\Overlays\CheeseBlushOverlays'

if (-not $Source) {
    $key = 'HKLM:\SOFTWARE\WOW6432Node\Bethesda Softworks\Skyrim Special Edition'
    $game = (Get-ItemProperty $key -ErrorAction SilentlyContinue).'installed path'
    if ($game) { $Source = Join-Path $game "Data\$folder" }
    if (-not $Source -or -not (Test-Path $Source)) { throw "Body Blushing's textures not found in the game's Data folder: pass -Source <folder with Blush_*.dds>." }
}
if (-not $Texconv) {
    $Texconv = @((Join-Path $PSScriptRoot 'texconv.exe'), (Get-Command texconv.exe -ErrorAction SilentlyContinue).Source) |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $Texconv) { throw 'texconv.exe not found: pass -Texconv <path> (DirectXTex releases, or xEdit''s Edit Scripts\Texconvx64.exe).' }
}

Add-Type -TypeDefinition @'
using System;
using System.IO;

public static class BlushAlpha
{
    // Fixes an uncompressed 32-bit TGA in place. Returns the number of alpha-1 pixels before and after,
    // or null (file untouched) when less than 1% of the pixels have alpha 1: already fixed.
    public static int[] Clean(string path)
    {
        byte[] b = File.ReadAllBytes(path);
        if (b[1] != 0 || b[2] != 2 || b[16] != 32) throw new InvalidDataException(path + ": expected an uncompressed 32-bit TGA");
        int w = BitConverter.ToUInt16(b, 12), h = BitConverter.ToUInt16(b, 14);
        int start = 18 + b[0], end = start + w * h * 4;

        int before = 0;
        for (int i = start + 3; i < end; i += 4) if (b[i] == 1) before++;
        if (before < w * h / 100) return null;

        byte[] alpha = new byte[256];
        for (int a = 9; a < 256; a++) alpha[a] = (byte)Math.Max(1, Math.Round((a - 8) * 255.0 / 247.0));
        int after = 0;
        for (int i = start; i < end; i += 4) {
            byte a = alpha[b[i + 3]];
            b[i + 3] = a;
            if (a == 0) { b[i] = 0x80; b[i + 1] = 0x80; b[i + 2] = 0x80; }   // BGR under alpha 0: grey 128
            else if (a == 1) after++;
        }
        File.WriteAllBytes(path, b);
        return new int[] { before, after };
    }
}
'@

$dest = Join-Path $Output $folder
$work = Join-Path $Output 'work'
New-Item -ItemType Directory -Force $dest, $work | Out-Null
$textures = Get-ChildItem $Source -Filter 'Blush_*.dds' | Where-Object { -not $Name -or $Name -contains $_.BaseName }
if (-not $textures) { throw "No Blush_*.dds in $Source" }

foreach ($t in $textures) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $Texconv -nologo -y -f R8G8B8A8_UNORM_SRGB -ft tga -m 1 -o $work $t.FullName | Out-Null
    if ($LASTEXITCODE) { throw "texconv failed to decode $($t.Name)" }
    $tga = Join-Path $work "$($t.BaseName).tga"
    $counts = [BlushAlpha]::Clean($tga)
    if (-not $counts) {
        Remove-Item $tga
        Write-Host "$($t.Name): already fixed, skipped"
        continue
    }
    & $Texconv -nologo -y -srgb -f BC7_UNORM_SRGB -m 0 -dx10 -o $dest $tga | Out-Null
    if ($LASTEXITCODE) { throw "texconv failed to encode $($t.Name)" }
    Remove-Item $tga
    Write-Host ("{0}: alpha-1 pixels {1} -> {2}, {3:n1} s" -f $t.Name, $counts[0], $counts[1], $sw.Elapsed.TotalSeconds)
}
Remove-Item $work -Recurse -Force
Write-Host "Done: $dest"
