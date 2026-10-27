<#
.SYNOPSIS
    Generates the site images: social preview card, favicon and app icon.

.DESCRIPTION
    Everything is drawn with System.Drawing, so there are no binary sources to keep in
    the repository and the result is reproducible.

    Outputs, all into docs/assets:
      og-image.png   1200x630 social preview (Open Graph / Twitter card)
      favicon.ico    32x32 site icon
      favicon.png    32x32 fallback and apple-touch source
      icon-192.png   192x192 for high-density tab icons

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build\make-site-images.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    if (-not $PSScriptRoot) { throw 'Run this script from disk.' }
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$assets = Join-Path $RepoRoot 'docs\assets'
if (-not (Test-Path -LiteralPath $assets)) { New-Item -ItemType Directory -Path $assets -Force | Out-Null }

Add-Type -AssemblyName System.Drawing

# Palette, kept in step with docs/assets/site.css.
$bg       = [System.Drawing.Color]::FromArgb(22, 23, 27)
$panel    = [System.Drawing.Color]::FromArgb(31, 33, 38)
$border   = [System.Drawing.Color]::FromArgb(51, 54, 63)
$text     = [System.Drawing.Color]::FromArgb(230, 232, 236)
$muted    = [System.Drawing.Color]::FromArgb(150, 155, 166)
$accent   = [System.Drawing.Color]::FromArgb(45, 108, 223)
$accentHi = [System.Drawing.Color]::FromArgb(110, 160, 255)

function New-Canvas([int]$width, [int]$height) {
    $bmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    return @{ Bitmap = $bmp; Graphics = $g }
}

function New-RoundedPath([System.Drawing.RectangleF]$r, [float]$radius) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $p.AddArc($r.X, $r.Y, $d, $d, 180, 90)
    $p.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
    $p.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# ---------------------------------------------------------------- brand mark
function Draw-Mark([System.Drawing.Graphics]$g, [System.Drawing.RectangleF]$r) {
    $path = New-RoundedPath $r ([float]($r.Width * 0.22))
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillPath($brush, $path)
    $brush.Dispose()
    $path.Dispose()

    $ink = New-Object System.Drawing.SolidBrush($accent)
    $barW = $r.Width * 0.56
    $barH = $r.Height * 0.13
    $g.FillRectangle($ink, ($r.X + $r.Width * 0.22), ($r.Y + $r.Height * 0.24), $barW, $barH)
    $g.FillRectangle($ink, ($r.X + $r.Width * 0.435), ($r.Y + $r.Height * 0.24), ($r.Width * 0.13), ($r.Height * 0.52))
    $ink.Dispose()
}

# ---------------------------------------------------------------- social card
$w = 1200; $h = 630
$card = New-Canvas $w $h
$g = $card.Graphics

$g.Clear($bg)
$bgBrush = New-Object System.Drawing.SolidBrush($panel)
$g.FillRectangle($bgBrush, 0, 0, $w, 96)
$bgBrush.Dispose()
$linePen = New-Object System.Drawing.Pen($border, 2)
$g.DrawLine($linePen, 0, 96, $w, 96)

Draw-Mark $g (New-Object System.Drawing.RectangleF(48, 26, 44, 44))

$fBrand = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
$fTitle = New-Object System.Drawing.Font('Segoe UI', 38, [System.Drawing.FontStyle]::Bold)
$fLead  = New-Object System.Drawing.Font('Segoe UI', 18)
$fSmall = New-Object System.Drawing.Font('Segoe UI', 16)
$fPill  = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)

$inkBrush  = New-Object System.Drawing.SolidBrush($text)
$mutedBrush = New-Object System.Drawing.SolidBrush($muted)

$g.DrawString('PES 2021 Fullscreen Fix', $fBrand, $inkBrush, 108, 34)

# Text column is deliberately narrow: the screenshot occupies the right third, and
# GDI+ does not clip DrawString, so overflow would run straight through the image.
$g.DrawString('Stops PES 2021', $fTitle, $inkBrush, 48, 152)
$g.DrawString('dropping to', $fTitle, $inkBrush, 48, 202)
$g.DrawString('the taskbar', $fTitle, $inkBrush, 48, 252)

$g.DrawString('Fullscreen, focus and GPU fix', $fLead, $mutedBrush, 50, 322)
$g.DrawString('for eFootball PES 2021 on', $fLead, $mutedBrush, 50, 350)
$g.DrawString('Windows 10 and 11.', $fLead, $mutedBrush, 50, 378)

# accent rule
$ruleBrush = New-Object System.Drawing.SolidBrush($accent)
$g.FillRectangle($ruleBrush, 48, 424, 96, 4)
$ruleBrush.Dispose()

# feature pills
$pillTexts = @('Reversible', 'Portable', 'No telemetry')
$x = 48
foreach ($t in $pillTexts) {
    $sz = $g.MeasureString($t, $fPill)
    $pw = [int]$sz.Width + 28
    $rect = New-Object System.Drawing.RectangleF($x, 452, $pw, 38)
    $pp = New-RoundedPath $rect 8
    $pb = New-Object System.Drawing.SolidBrush($panel)
    $g.FillPath($pb, $pp)
    $pb.Dispose()
    $pen = New-Object System.Drawing.Pen($border, 1)
    $g.DrawPath($pen, $pp)
    $pen.Dispose()
    $pp.Dispose()
    $g.DrawString($t, $fPill, $inkBrush, ($x + 14), 460)
    $x += $pw + 12
}

$g.DrawString('TFast Digital   |   tfastdigital.com', $fSmall, $mutedBrush, 48, 552)

# screenshot inset, right side
$shotPath = Join-Path $assets 'screenshot.png'
if (Test-Path -LiteralPath $shotPath) {
    $shot = [System.Drawing.Image]::FromFile($shotPath)
    $maxW = 452; $maxH = 420
    $scale = [Math]::Min($maxW / $shot.Width, $maxH / $shot.Height)
    $sw = [int]($shot.Width * $scale)
    $sh = [int]($shot.Height * $scale)
    $sx = 664; $sy = [int](($h - $sh) / 2)

    $outer = New-Object System.Drawing.RectangleF(($sx - 8), ($sy - 8), ($sw + 16), ($sh + 16))
    $op = New-RoundedPath $outer 10
    $ob = New-Object System.Drawing.SolidBrush($panel)
    $g.FillPath($ob, $op)
    $ob.Dispose()
    $open = New-Object System.Drawing.Pen($border, 2)
    $g.DrawPath($open, $op)
    $open.Dispose()
    $op.Dispose()

    $g.DrawImage($shot, $sx, $sy, $sw, $sh)
    $shot.Dispose()
}

$fBrand.Dispose(); $fTitle.Dispose(); $fLead.Dispose(); $fSmall.Dispose(); $fPill.Dispose()
$inkBrush.Dispose(); $mutedBrush.Dispose(); $linePen.Dispose()
$g.Dispose()
$card.Bitmap.Save((Join-Path $assets 'og-image.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$card.Bitmap.Dispose()
Write-Host 'og-image.png   1200x630'

# ---------------------------------------------------------------- icon bitmaps
function New-IconBitmap([int]$size) {
    $c = New-Canvas $size $size
    $c.Graphics.Clear([System.Drawing.Color]::Transparent)
    $pad = $size * 0.04
    $rect = New-Object System.Drawing.RectangleF($pad, $pad, ($size - $pad * 2), ($size - $pad * 2))
    $path = New-RoundedPath $rect ([float]($size * 0.22))
    $brush = New-Object System.Drawing.SolidBrush($accent)
    $c.Graphics.FillPath($brush, $path)
    $brush.Dispose()
    $path.Dispose()
    Draw-Mark $c.Graphics (New-Object System.Drawing.RectangleF(0, 0, $size, $size))
    $c.Graphics.Dispose()
    return $c.Bitmap
}

$icon192 = New-IconBitmap 192
$icon192.Save((Join-Path $assets 'icon-192.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$icon192.Dispose()
Write-Host 'icon-192.png   192x192'

$icon32 = New-IconBitmap 32
$icon32.Save((Join-Path $assets 'favicon.png'), [System.Drawing.Imaging.ImageFormat]::Png)

# 32bpp BMP-in-ICO, the most widely compatible icon container
$bytes = New-Object System.Collections.Generic.List[byte]
$maskRow = [int]([Math]::Ceiling(32 / 32.0) * 4)
$imageSize = 40 + (32 * 32 * 4) + ($maskRow * 32)
$bytes.AddRange([BitConverter]::GetBytes([uint16]0))
$bytes.AddRange([BitConverter]::GetBytes([uint16]1))
$bytes.AddRange([BitConverter]::GetBytes([uint16]1))
$bytes.Add([byte]32); $bytes.Add([byte]32); $bytes.Add([byte]0); $bytes.Add([byte]0)
$bytes.AddRange([BitConverter]::GetBytes([uint16]1))
$bytes.AddRange([BitConverter]::GetBytes([uint16]32))
$bytes.AddRange([BitConverter]::GetBytes([uint32]$imageSize))
$bytes.AddRange([BitConverter]::GetBytes([uint32]22))
$bytes.AddRange([BitConverter]::GetBytes([uint32]40))
$bytes.AddRange([BitConverter]::GetBytes([int32]32))
$bytes.AddRange([BitConverter]::GetBytes([int32]64))
$bytes.AddRange([BitConverter]::GetBytes([uint16]1))
$bytes.AddRange([BitConverter]::GetBytes([uint16]32))
$bytes.AddRange([BitConverter]::GetBytes([uint32]0))
$bytes.AddRange([BitConverter]::GetBytes([uint32]($imageSize - 40)))
$bytes.AddRange([BitConverter]::GetBytes([int32]0))
$bytes.AddRange([BitConverter]::GetBytes([int32]0))
$bytes.AddRange([BitConverter]::GetBytes([uint32]0))
$bytes.AddRange([BitConverter]::GetBytes([uint32]0))
for ($y = 31; $y -ge 0; $y--) {
    for ($x = 0; $x -lt 32; $x++) {
        $c = $icon32.GetPixel($x, $y)
        $bytes.Add($c.B); $bytes.Add($c.G); $bytes.Add($c.R); $bytes.Add($c.A)
    }
}
for ($i = 0; $i -lt ($maskRow * 32); $i++) { $bytes.Add(0) }
[IO.File]::WriteAllBytes((Join-Path $assets 'favicon.ico'), $bytes.ToArray())
$icon32.Dispose()
Write-Host 'favicon.ico    32x32'
Write-Host 'favicon.png    32x32'

Write-Host ''
Get-ChildItem -LiteralPath $assets | Select-Object Name, Length | Format-Table -AutoSize
