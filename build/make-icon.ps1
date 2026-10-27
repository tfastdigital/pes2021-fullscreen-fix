param([string]$Out = "$PSScriptRoot\tfast.ico")

Add-Type -AssemblyName System.Drawing

# ---- draw a branded 64x64 icon in memory -------------------------------------
$size = 64
$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'AntiAliasGridFit'
$g.Clear([System.Drawing.Color]::Transparent)

# rounded background with a violet -> blue diagonal gradient
$rect = New-Object System.Drawing.Rectangle(1, 1, ($size - 2), ($size - 2))
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$r = 13
$path.AddArc($rect.X, $rect.Y, $r, $r, 180, 90)
$path.AddArc(($rect.Right - $r), $rect.Y, $r, $r, 270, 90)
$path.AddArc(($rect.Right - $r), ($rect.Bottom - $r), $r, $r, 0, 90)
$path.AddArc($rect.X, ($rect.Bottom - $r), $r, $r, 90, 90)
$path.CloseFigure()

$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect,
    [System.Drawing.Color]::FromArgb(255, 108, 45, 214),
    [System.Drawing.Color]::FromArgb(255, 24, 132, 230),
    45.0)
$g.FillPath($brush, $path)
$brush.Dispose()

# white "T" bar
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$g.FillRectangle($white, 14, 15, 36, 9)      # top bar
$g.FillRectangle($white, 27, 15, 10, 34)     # stem
$white.Dispose()

# green "go" accent
$accent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 74, 222, 128))
$g.FillRectangle($accent, 41, 39, 9, 10)
$accent.Dispose()

$g.Dispose()

# ---- write a 32bpp BMP-in-ICO file (widely compatible) -----------------------
$bytes = New-Object System.Collections.Generic.List[byte]
$maskRowBytes = [int]([Math]::Ceiling($size / 32.0) * 4)
$imageSize = 40 + ($size * $size * 4) + ($maskRowBytes * $size)

# ICONDIR
$bytes.AddRange([BitConverter]::GetBytes([uint16]0))   # reserved
$bytes.AddRange([BitConverter]::GetBytes([uint16]1))   # type = icon
$bytes.AddRange([BitConverter]::GetBytes([uint16]1))   # count

# ICONDIRENTRY
$bytes.Add([byte]$size)
$bytes.Add([byte]$size)
$bytes.Add([byte]0)                                    # palette colours
$bytes.Add([byte]0)                                    # reserved
$bytes.AddRange([BitConverter]::GetBytes([uint16]1))   # planes
$bytes.AddRange([BitConverter]::GetBytes([uint16]32))  # bpp
$bytes.AddRange([BitConverter]::GetBytes([uint32]$imageSize))
$bytes.AddRange([BitConverter]::GetBytes([uint32]22))  # offset

# BITMAPINFOHEADER (height doubled: XOR image + AND mask)
$bytes.AddRange([BitConverter]::GetBytes([uint32]40))
$bytes.AddRange([BitConverter]::GetBytes([int32]$size))
$bytes.AddRange([BitConverter]::GetBytes([int32]($size * 2)))
$bytes.AddRange([BitConverter]::GetBytes([uint16]1))
$bytes.AddRange([BitConverter]::GetBytes([uint16]32))
$bytes.AddRange([BitConverter]::GetBytes([uint32]0))   # BI_RGB
$bytes.AddRange([BitConverter]::GetBytes([uint32]($imageSize - 40)))
$bytes.AddRange([BitConverter]::GetBytes([int32]0))
$bytes.AddRange([BitConverter]::GetBytes([int32]0))
$bytes.AddRange([BitConverter]::GetBytes([uint32]0))
$bytes.AddRange([BitConverter]::GetBytes([uint32]0))

# pixel data, bottom-up BGRA
for ($y = $size - 1; $y -ge 0; $y--) {
    for ($x = 0; $x -lt $size; $x++) {
        $c = $bmp.GetPixel($x, $y)
        $bytes.Add($c.B); $bytes.Add($c.G); $bytes.Add($c.R); $bytes.Add($c.A)
    }
}
# AND mask (all zero = use alpha channel)
for ($i = 0; $i -lt ($maskRowBytes * $size); $i++) { $bytes.Add(0) }

[IO.File]::WriteAllBytes($Out, $bytes.ToArray())
$bmp.Dispose()
Write-Output ("icon written: {0} ({1} bytes)" -f $Out, (Get-Item $Out).Length)
