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

  # Busca imagem com prioridade: featuredmedia.source_url -> sizes.medium_large -> sizes.medium -> sizes.large
  $img = $null
  if ($it._embedded -and $it._embedded."wp:featuredmedia" -and $it._embedded."wp:featuredmedia".Count -gt 0) {
    $media = $it._embedded."wp:featuredmedia"[0]
    if ($media -and $media.source_url) { $img = $media.source_url }
    if (-not $img -and $media.media_details -and $media.media_details.sizes) {
      if ($media.media_details.sizes.medium_large -and $media.media_details.sizes.medium_large.source_url) { $img = $media.media_details.sizes.medium_large.source_url }
      elseif ($media.media_details.sizes.medium -and $media.media_details.sizes.medium.source_url) { $img = $media.media_details.sizes.medium.source_url }
      elseif ($media.media_details.sizes.large -and $media.media_details.sizes.large.source_url) { $img = $media.media_details.sizes.large.source_url }
    }
  }

  # Fallback ACF e GUID
  if (-not $img -and $it.acf -and $it.acf.imagem_principal -and $it.acf.imagem_principal.Count -gt 0) {
    $acfImg = $it.acf.imagem_principal[0]
    if ($acfImg -and $acfImg.guid) {
      $cand = ($acfImg.guid | Out-String).Trim()
      if ($cand -match "^https?://.*\.(jpg|jpeg|png|webp)($|\?)") { $img = $cand }
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

# Utilitários de texto com RectangleF para medição consistente
function DrawWrappedString(
  [System.Drawing.Graphics]$g, [string]$text, [System.Drawing.Font]$font,
  [System.Drawing.Brush]$brush, [float]$x, [float]$y, [float]$maxWidth, [int]$maxLines
) {
  if ([string]::IsNullOrWhiteSpace($text)) { return 0 }
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Trimming   = [System.Drawing.StringTrimming]::EllipsisWord
  $fmt.FormatFlags = [System.Drawing.StringFormatFlags]::LineLimit
  $rect = New-Object System.Drawing.RectangleF($x, $y, $maxWidth, 2000.0)
  $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  # Medida aproximada de linha
  $lineHeight = [int]($g.MeasureString('A', $font).Height)
  $rect.Height = $lineHeight * [Math]::Max(1,$maxLines)
  $g.DrawString($text, $font, $brush, $rect, $fmt)
  $size = $g.MeasureString($text, $font, [int]$maxWidth, $fmt)
  return [Math]::Min([int][Math]::Ceiling($size.Height), $lineHeight * $maxLines)
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

# Área segura no verde
$greenSafeLeft   = [int]($width * 0.60)
$greenSafeRight  = $width - 60
$greenSafeTop    = 120
$greenSafeBottom = $height - 90
$padX = 24; $padY = 12
$xArea = $greenSafeLeft + $padX
$yArea = $greenSafeTop + $padY
$areaW = ($greenSafeRight - $greenSafeLeft) - (2*$padX)
$areaH = ($greenSafeBottom - $greenSafeTop) - (2*$padY)

# Fontes e pincéis - REMOVIDAS AS SOMBRAS
$headerFont = New-Object System.Drawing.Font("Segoe UI", 40, [System.Drawing.FontStyle]::Bold)
$titleFont  = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Regular)
$dateFont   = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Regular)
$footerFont = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)  # Aumentado para fonte mais visível

# Cores sem sombras - melhor contraste no fundo verde
$white      = [System.Drawing.Brushes]::White
$lightGray  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 245, 245))
$darkGreen  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 100, 0))  # Para fonte destacada

# Título principal - SEM SOMBRA
# Título
$secTitle = "Not"+[char]0x00ED+"cias SEPLAN"
$g.DrawString($secTitle, $headerFont, $white, $xArea, $yArea)
$y = $yArea + [int]($g.MeasureString('A', $headerFont).Height) + 15

# PROPORÇÃO FIXA para todas as imagens
$thumbW = 200; $thumbH = 112  # Proporção 16:9 consistente
$gapY   = 20
$boxH   = $thumbH + 70  # Mais espaço para texto

for ($i=0; $i -lt $top.Count; $i++) {
  if ($y + $boxH -gt ($yArea + $areaH)) { break }

  $xImg = $xArea
  $yImg = $y

  # Container da imagem com borda limpa
  $imgContainer = New-Object System.Drawing.Rectangle($xImg, $yImg, $thumbW, $thumbH)
  $g.FillRectangle($lightGray, $imgContainer)
  
  if ($thumbPaths[$i] -and (Test-Path $thumbPaths[$i])) {
    $img = [System.Drawing.Image]::FromFile($thumbPaths[$i])
    
    # CROP para manter proporção 16:9 sempre
    $srcW = $img.Width
    $srcH = $img.Height
    $targetRatio = $thumbW / $thumbH
    $srcRatio = $srcW / $srcH
    
    if ($srcRatio -gt $targetRatio) {
      # Imagem mais larga - crop nas laterais
      $cropH = $srcH
      $cropW = [int]($srcH * $targetRatio)
      $cropX = [int](($srcW - $cropW) / 2)
      $cropY = 0
    } else {
      # Imagem mais alta - crop no topo/base
      $cropW = $srcW
      $cropH = [int]($srcW / $targetRatio)
      $cropX = 0
      $cropY = [int](($srcH - $cropH) / 2)
    }
    
    $cropRect = New-Object System.Drawing.Rectangle($cropX, $cropY, $cropW, $cropH)
    $destRect = New-Object System.Drawing.Rectangle($xImg, $yImg, $thumbW, $thumbH)
    $g.DrawImage($img, $destRect, $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
    $img.Dispose()
  }

  $xText = $xImg + $thumbW + 16
  $maxTitleWidth = $xArea + $areaW - $xText
  $prefix = "{0}. " -f ($i+1)
  $titleToDraw = "$prefix$($top[$i].Titulo)"

  # Título SEM SOMBRA - texto limpo
  $usedHeight = DrawWrappedString $g $titleToDraw $titleFont $white $xText $y $maxTitleWidth 3
  if ($usedHeight -eq 0) { $usedHeight = [int]($g.MeasureString($titleToDraw, $titleFont).Height) }

  $yDate = $y + $usedHeight + 4
  $dateStr = if ($top[$i].Data) { $top[$i].Data.ToString("dd/MM/yyyy HH:mm") } else { ""  }
  if ($dateStr) {
    $g.DrawString($dateStr, $dateFont, $lightGray, $xText, $yDate)
  }

  $y = $y + $boxH + $gapY
}

# Rodapé com fonte MAIS VISÍVEL e destacada
$footerY = $greenSafeBottom + 15

# Fundo semi-transparente para destacar a fonte
$footerBg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180, 255, 255, 255))
$footerText = "Fonte: https://www.seplan.rn.gov.br/noticias"
$footerSize = $g.MeasureString($footerText, $footerFont)

# Coerce variables to numeric scalars safely (handle accidental arrays)
if ($xArea -is [System.Array]) { $xPos = [float]$xArea[0] } else { $xPos = [float]$xArea }
if ($footerY -is [System.Array]) { $yPos = [float]$footerY[0] } else { $yPos = [float]$footerY }

$rectX = $xPos - 8.0
$rectY = $yPos - 4.0
$rectW = [float]($footerSize.Width + 16.0)
$rectH = [float]($footerSize.Height + 8.0)
$footerRect = New-Object System.Drawing.RectangleF($rectX, $rectY, $rectW, $rectH)
$g.FillRectangle($footerBg, $footerRect)

# Texto da fonte em verde escuro para máximo contraste (usar posições coerentes)
$g.DrawString($footerText, $footerFont, $darkGreen, $xPos, $yPos)

# Salvar
$outFile = Join-Path (Get-Location) "wallpaper_melhorado.png"
$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)

# Limpeza
$g.Dispose(); $bmp.Dispose()
$headerFont.Dispose(); $titleFont.Dispose(); $dateFont.Dispose(); $footerFont.Dispose()
$lightGray.Dispose(); $darkGreen.Dispose(); $footerBg.Dispose()

Write-Host "Wallpaper melhorado salvo em: $outFile" -ForegroundColor Green