# ===== Configuração e UTF-8 =====
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
[System.Threading.Thread]::CurrentThread.CurrentCulture  = 'pt-BR'
[System.Threading.Thread]::CurrentThread.CurrentUICulture = 'pt-BR'

function Fail($msg) { Write-Error $msg; exit 1 }

# ===== Arquivo de fundo =====
$baseWallpaper = Join-Path (Get-Location) "fundo.png"

# ===== Endpoint WP =====
$apiUrl = "https://www.seplan.rn.gov.br/wp-json/wp/v2/materia?per_page=20&page=1&_embed=1"

# ===== Busca JSON =====
try {
  $resp = Invoke-WebRequest -Uri $apiUrl -Headers @{ "Accept" = "application/json" } -UseBasicParsing
} catch { Fail "Falha ao acessar a API ($apiUrl): $_" }
if (-not $resp -or -not $resp.Content) { Fail "API não retornou conteúdo." }

# ===== Parsing sem reencode =====
Add-Type -AssemblyName System.Web
function LimpaHtml($s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return $s }
  $s = $s -replace "<.*?>",""
  $s = [System.Web.HttpUtility]::HtmlDecode($s)
  return $s.Trim()
}
try {
  $items = $resp.Content | ConvertFrom-Json
} catch { Fail "Falha ao converter JSON: $_" }
if (-not $items -or $items.Count -eq 0) { Fail "API não retornou matérias." }

# ===== Extrai campos =====
$materias = foreach ($it in $items) {
  $titulo = if ($it.title -and $it.title.rendered) { LimpaHtml $it.title.rendered } else { $null }
  $data   = $null
  if ($it.date) { try { $data = Get-Date $it.date } catch { $data = $null } }
  $img = $null

  if ($it.acf -and $it.acf.imagem_principal -and $it.acf.imagem_principal.Count -gt 0) {
    $acfImg = $it.acf.imagem_principal[0]
    if ($acfImg -and $acfImg.guid) {
      $cand = ($acfImg.guid | Out-String).Trim()
      if ($cand -match "^https?://.*\.(jpg|jpeg|png|webp)($|\?)") { $img = $cand }
    }
  }
  if (-not $img -and $it._embedded -and $it._embedded."wp:featuredmedia" -and $it._embedded."wp:featuredmedia".Count -gt 0) {
    $media = $it._embedded."wp:featuredmedia"[0]
    if ($media -and $media.source_url) { $img = $media.source_url }
    elseif ($media.media_details -and $media.media_details.sizes) {
      if ($media.media_details.sizes.medium_large -and $media.media_details.sizes.medium_large.source_url) { $img = $media.media_details.sizes.medium_large.source_url }
      elseif ($media.media_details.sizes.medium -and $media.media_details.sizes.medium.source_url) { $img = $media.media_details.sizes.medium.source_url }
      elseif ($media.media_details.sizes.large -and $media.media_details.sizes.large.source_url) { $img = $media.media_details.sizes.large.source_url }
    }
  }
  if (-not $img -and $it.guid -and $it.guid.rendered) {
    $gr = ($it.guid.rendered | Out-String).Trim()
    if ($gr -match "^https?://.*\.(jpg|jpeg|png|webp)($|\?)") { $img = $gr }
  }

  if ($titulo) { [pscustomobject]@{ Titulo=$titulo; Data=$data; Imagem=$img } }
}
if (-not $materias -or $materias.Count -eq 0) { Fail "Sem matérias válidas após parsing." }

# ===== Top 4 =====
$top = $materias | Sort-Object Data -Descending | Select-Object -First 4

# ===== Baixar miniaturas =====
$thumbsDir = Join-Path (Get-Location) "thumbs"
if (-not (Test-Path $thumbsDir)) { New-Item -ItemType Directory $thumbsDir | Out-Null }
$thumbPaths = @()
for ($i=0; $i -lt $top.Count; $i++) {
  $imgUrl = $top[$i].Imagem
  $local = $null
  if ($imgUrl) {
    try {
      $ext = ".jpg"
      if ($imgUrl -match "\.png($|\?)") { $ext = ".png" }
      elseif ($imgUrl -match "\.jpeg($|\?)") { $ext = ".jpeg" }
      elseif ($imgUrl -match "\.webp($|\?)") { $ext = ".webp" }
      $local = Join-Path $thumbsDir ("n$($i+1)$ext")
      Invoke-WebRequest -Uri $imgUrl -OutFile $local -UseBasicParsing
    } catch { $local = $null }
  }
  $thumbPaths += $local
}

# ===== Renderização =====
Add-Type -AssemblyName System.Drawing
function DrawWrappedString(
  [System.Drawing.Graphics]$g, [string]$text, [System.Drawing.Font]$font,
  [System.Drawing.Brush]$brush, [int]$x, [int]$y, [int]$maxWidth, [int]$maxLines
) {
  if ([string]::IsNullOrWhiteSpace($text)) { return 0 }
  $words = $text -split '\s+'
  $lines = @()
  $current = ''
  foreach ($w in $words) {
    $trial = if ($current -eq '') { $w } else { $current + ' ' + $w }
    $size = $g.MeasureString($trial, $font)
    if ($size.Width -le $maxWidth) { $current = $trial }
    else {
      if ($current -ne '') { $lines += $current }
      $current = $w
      $wsize = $g.MeasureString($w, $font)
      if ($wsize.Width -gt $maxWidth) {
        $part = ''
        foreach ($c in $w.ToCharArray()) {
          $t = $part + $c
          if ($g.MeasureString($t, $font).Width -le $maxWidth) { $part = $t } else { $lines += $part; $part = $c }
        }
        if ($part -ne '') { $current = $part }
      }
    }
    if ($lines.Count -ge $maxLines) { break }
  }
  if ($current -ne '' -and $lines.Count -lt $maxLines) { $lines += $current }
  if ($lines.Count -gt $maxLines) { $lines = $lines[0..($maxLines-1)] }
  if ($lines.Count -eq $maxLines) {
    $last = $lines[-1]
    while ($g.MeasureString($last + '…', $font).Width -gt $maxWidth -and $last.Length -gt 0) { $last = $last.Substring(0, $last.Length -1) }
    $lines[-1] = $last + '…'
  }
  $lineHeight = [int]($g.MeasureString('A', $font).Height)
  $i = 0
  foreach ($ln in $lines) {
    $g.DrawString($ln, $font, $brush, $x, $y + ($i * $lineHeight))
    $i++
    if ($i -ge $maxLines) { break }
  }
  return ($i * $lineHeight)
}

$width = 1920; $height = 1080
if (-not (Test-Path $baseWallpaper)) { Fail "Arquivo de fundo não encontrado: $baseWallpaper" }
$baseImg = [System.Drawing.Image]::FromFile($baseWallpaper)

$bmp = New-Object System.Drawing.Bitmap($width, $height)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

# Fundo base ajustado (cover)
$g.Clear([System.Drawing.Color]::White)
$scale = [Math]::Max($width / $baseImg.Width, $height / $baseImg.Height)
$bw = [int]($baseImg.Width * $scale)
$bh = [int]($baseImg.Height * $scale)
$bx = - [int](($bw - $width) / 2)
$by = - [int](($bh - $height) / 2)
$g.DrawImage($baseImg, $bx, $by, $bw, $bh)
$baseImg.Dispose()

# Área segura no verde (ajuste se necessário)
$greenSafeLeft   = [int]($width * 0.60)
$greenSafeRight  = $width - 60
$greenSafeTop    = 120
$greenSafeBottom = $height - 90
$padX = 24; $padY = 12
$xArea = $greenSafeLeft + $padX
$yArea = $greenSafeTop + $padY
$areaW = ($greenSafeRight - $greenSafeLeft) - (2*$padX)
$areaH = ($greenSafeBottom - $greenSafeTop) - (2*$padY)

# Fontes e pincéis
$headerFont = New-Object System.Drawing.Font("Segoe UI Semibold", 40, [System.Drawing.FontStyle]::Bold)
$titleFont  = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Regular)  # menor para caber 4
$dateFont   = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Regular)
$white      = [System.Drawing.Brushes]::White
# Sombra sutíl para legibilidade
$shadow     = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, 0, 0, 0))
$muted      = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 245, 245))

# Título
$secTitle = "Not"+[char]0x00ED+"cias SEPLAN"
# sombra
$g.DrawString($secTitle, $headerFont, $shadow, $xArea+2, $yArea+2)
$g.DrawString($secTitle, $headerFont, $white,  $xArea,   $yArea)
$y = $yArea + [int]($g.MeasureString('A', $headerFont).Height) + 10

# 4 itens, sem faixa amarela
$thumbW = 200; $thumbH = 112
$gapY   = 18
$boxH   = $thumbH + 62

for ($i=0; $i -lt $top.Count; $i++) {
  if ($y + $boxH -gt ($yArea + $areaH)) { break }

  $xImg = $xArea
  $yImg = $y

  if ($thumbPaths[$i] -and (Test-Path $thumbPaths[$i])) {
    $img = [System.Drawing.Image]::FromFile($thumbPaths[$i])
    $scaleI = [Math]::Min($thumbW / $img.Width, $thumbH / $img.Height)
    $wI = [int]($img.Width * $scaleI)
    $hI = [int]($img.Height * $scaleI)
    $xI = $xImg + [int](($thumbW - $wI) / 2)
    $yI = $yImg + [int](($thumbH - $hI) / 2)
    # pequena sombra da miniatura
    $g.FillRectangle($shadow, $xI+3, $yI+3, $wI, $hI)
    $g.DrawImage($img, $xI, $yI, $wI, $hI)
    $img.Dispose()
  }

  $xText = $xImg + $thumbW + 14
  $maxTitleWidth = $xArea + $areaW - $xText
  $prefix = "{0}. " -f ($i+1)
  $titleToDraw = "$prefix$($top[$i].Titulo)"

  # sombra do título
  [void](DrawWrappedString $g $titleToDraw $titleFont $shadow ($xText+2) ($y+2) $maxTitleWidth 3)
  $usedHeight = DrawWrappedString $g $titleToDraw $titleFont $white  $xText      $y      $maxTitleWidth 3
  if ($usedHeight -eq 0) { $usedHeight = [int]($g.MeasureString($titleToDraw, $titleFont).Height) }

  $yDate = $y + $usedHeight + 2
  $dateStr = if ($top[$i].Data) { $top[$i].Data.ToString("dd/MM/yyyy HH:mm") } else { "" }
  if ($dateStr) {
    $g.DrawString($dateStr, $dateFont, $shadow, $xText+2, $yDate+2)
    $g.DrawString($dateStr, $dateFont, $muted,  $xText,   $yDate)
  }

  $y = $y + $boxH + $gapY
}

# Rodapé
$footerFont = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Regular)
$g.DrawString("Fonte: https://www.seplan.rn.gov.br/noticias", $footerFont, $muted, $xArea, $greenSafeBottom + 10)

# Salvar
$outFile = Join-Path (Get-Location) "wallpaper.png"
$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)

# Limpeza
$g.Dispose(); $bmp.Dispose()
$headerFont.Dispose(); $titleFont.Dispose(); $dateFont.Dispose(); $footerFont.Dispose()
$shadow.Dispose(); $muted.Dispose()
