# Generate PDFMathTranslate app icon (multi-size PNG-in-ICO)
# Output: launcher\Assets\app.ico  (16/32/48/256, slate-900 rounded square + white glyph)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AssetDir = Join-Path (Split-Path -Parent $Root) 'launcher\Assets'
$OutPath = Join-Path $AssetDir 'app.ico'
New-Item -ItemType Directory -Force -Path $AssetDir | Out-Null

Add-Type -AssemblyName System.Drawing

# U+8BD1 (the CJK glyph shown on the logo)
$Glyph = [string][char]0x8BD1

function New-IconPng([int]$size, [bool]$drawText) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # Rounded square background: slate-900 #0F172A, full canvas
    $r = [Math]::Max(2, [int]($size * 0.22))
    $d = 2 * $r
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($size - $d, 0, $d, $d, 270, 90)
    $path.AddArc($size - $d, $size - $d, $d, $d, 0, 90)
    $path.AddArc(0, $size - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 15, 23, 42))
    $g.FillPath($bg, $path)

    if ($drawText) {
        $fontSize = [int]($size * 0.58)
        $font = New-Object System.Drawing.Font('Microsoft YaHei UI', $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $white = [System.Drawing.Brushes]::White
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rect = New-Object System.Drawing.RectangleF(0, [single]($size * 0.02), $size, $size)
        $g.DrawString($Glyph, $font, $white, $rect, $fmt)
        $font.Dispose(); $fmt.Dispose()
    }
    $g.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    # The leading comma prevents the pipeline from unrolling the byte[] into Object[].
    return , $ms.ToArray()
}

# Sizes: skip the glyph below 32px (illegible)
$sizes = @(
    @{ Size = 16;  Text = $false },
    @{ Size = 32;  Text = $true },
    @{ Size = 48;  Text = $true },
    @{ Size = 256; Text = $true }
)

$pngs = @()
foreach ($entry in $sizes) { $pngs += , (New-IconPng $entry.Size $entry.Text) }

# Assemble ICO: ICONDIR(6B) + ICONDIRENTRY(16B x n) + PNG blobs
$fs = [System.IO.File]::Create($OutPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0)          # reserved
$bw.Write([UInt16]1)          # type = icon
$bw.Write([UInt16]$pngs.Count)

$offset = 6 + 16 * $pngs.Count
for ($i = 0; $i -lt $pngs.Count; $i++) {
    $s = $sizes[$i].Size
    $data = $pngs[$i]
    $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))     # width
    $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))     # height
    $bw.Write([byte]0)   # colors
    $bw.Write([byte]0)   # reserved
    $bw.Write([UInt16]1)  # planes
    $bw.Write([UInt16]32) # bitcount
    $bw.Write([UInt32]$data.Length)
    $bw.Write([UInt32]$offset)
    $offset += $data.Length
}
foreach ($data in $pngs) { $bw.Write($data) }
$bw.Flush(); $bw.Close()

Write-Host "Icon written: $OutPath"
