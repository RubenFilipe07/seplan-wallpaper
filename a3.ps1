$ErrorActionPreference = "Stop"

# Endpoint e parâmetros
$apiUrl  = "https://www.seplan.rn.gov.br/wp-json/wp/v2/materia?per_page=20&page=1&_embed=1"
$baseUrl = "https://www.seplan.rn.gov.br"

# 1) Baixar JSON (UTF-8) e converter
try {
    $bytes = Invoke-WebRequest -Uri $apiUrl -Headers @{ "Accept" = "application/json" } -UseBasicParsing
    $json  = [System.Text.Encoding]::UTF8.GetString($bytes.Content)
} catch {
    Write-Error "Falha ao acessar API: $apiUrl. $_"
    exit 1
}

try {
    $items = $json | ConvertFrom-Json
} catch {
    Write-Error "Falha ao converter JSON."
    exit 1
}

if (-not $items -or $items.Count -eq 0) {
    Write-Error "API não retornou matérias."
    exit 1
}

# 2) Extrair título (UTF-8 + sem tags), data e imagem destacada via _embedded
function LimpaHtml($s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $s }
    $s = $s -replace "<.*?>",""
    $s = [System.Web.HttpUtility]::HtmlDecode($s)
    return $s.Trim()
}

$materias = foreach ($it in $items) {
    $titulo = if ($it.title -and $it.title.rendered) { LimpaHtml $it.title.rendered } else { $null }
    $data   = $null
    if ($it.date) { $data = Get-Date $it.date }

    # Tenta imagem via _embedded."wp:featuredmedia"[0].source_url
    $img = $null
    if ($it._embedded -and $it._embedded."wp:featuredmedia" -and $it._embedded."wp:featuredmedia".Count -gt 0) {
        $media = $it._embedded."wp:featuredmedia"[0]
        if ($media -and $media.source_url) { $img = $media.source_url }
        elseif ($media.media_details -and $media.media_details.sizes -and $media.media_details.sizes.medium_large.source_url) {
            $img = $media.media_details.sizes.medium_large.source_url
        }
    }

    if ($titulo) {
        [pscustomobject]@{
            Titulo = $titulo
            Data   = $data
            Imagem = $img
        }
    }
}

$top3 = $materias | Sort-Object Data -Descending | Select-Object -First 3

if (-not $top3 -or $top3.Count -eq 0) {
    Write-Error "Sem matérias válidas."
    exit 1
}

# 3) Baixar imagens para miniaturas locais (quando houver)
$thumbs = @()
$thumbDir = Join-Path (Get-Location) "thumbs"
if (-not (Test-Path $thumbDir)) { New-Item -ItemType Directory -Path $thumbDir | Out-Null }

$idx = 1
foreach ($m in $top3) {
    $local = $null
    if ($m.Imagem) {
        try {
            $ext = ".jpg"
            if ($m.Imagem -match "\.png($|\?)") { $ext = ".png" }
            elseif ($m.Imagem -match "\.jpeg($|\?)") { $ext = ".jpeg" }
            $local = Join-Path $thumbDir ("n" + $idx + $ext)
            Invoke-WebRequest -Uri $m.Imagem -OutFile $local -UseBasicParsing
        } catch {
            $local = $null
        }
    }
    $thumbs += $local
    $idx++
}

# 4) Renderizar wallpaper 1920x1080
Add-Type -AssemblyName System.Drawing

function Trunca($s, $limite) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $s }
    if ($s.Length -le $limite) { return $s }
    return ($s.Substring(0, [Math]::Max(0, $limite-1)) + "…")
}

$width  = 1920
$height = 1080
$bmp    = New-Object System.Drawing.Bitmap($width, $height)
$g      = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode  = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

# Fundo
$bgColor = [System.Drawing.Color]::FromArgb(18, 32, 47)
$g.Clear($bgColor)

# Tipografia
$headerFont = New-Object System.Drawing.Font("Segoe UI Semibold", 46, [System.Drawing.FontStyle]::Bold)
$itemFont   = New-Object System.Drawing.Font("Segoe UI", 28, [System.Drawing.FontStyle]::Regular)
$dateFont   = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Regular)

$white      = [System.Drawing.Brushes]::White
$muted      = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 220, 230))
$accent     = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 171, 169))

$marginX = 120
$y = 120

# Cabeçalho (corrigido título com acento)
$g.DrawString("Notícias SEPLAN-RN", $headerFont, $white, $marginX, $y)
$y += 80
$g.FillRectangle($accent, $marginX, $y, 600, 6)
$y += 30

# Layout por item: miniatura 280x160 à esquerda, textos à direita
$thumbW = 280
$thumbH = 160
$gapX   = 24
$boxH   = 200  # altura alocada por item
$maxTitulo = 95

for ($i=0; $i -lt $top3.Count; $i++) {
    $m = $top3[$i]
    $t = Trunca $m.Titulo $maxTitulo
    $d = if ($m.Data) { $m.Data.ToString("dd/MM/yyyy HH:mm") } else { "" }

    $xImg = $marginX
    $yImg = $y + 6

    # Desenhar thumb se existir
    if ($thumbs[$i] -and (Test-Path $thumbs[$i])) {
        $img = [System.Drawing.Image]::FromFile($thumbs[$i])
        # Ajuste simples para caber no box mantendo proporção
        $scale = [Math]::Min($thumbW / $img.Width, $thumbH / $img.Height)
        $w = [int]($img.Width * $scale)
        $h = [int]($img.Height * $scale)
        $x = $xImg + [int](($thumbW - $w) / 2)
        $ypos = $yImg + [int](($thumbH - $h) / 2)
        $g.DrawImage($img, $x, $ypos, $w, $h)
        $img.Dispose()
    } else {
        # Placeholder discreto
        $ph = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 55, 75))
        $g.FillRectangle($ph, $xImg, $yImg, $thumbW, $thumbH)
        $ph.Dispose()
    }

    # Textos
    $xText = $xImg + $thumbW + $gapX
    $g.DrawString(("{0}. {1}" -f ($i+1), $t), $itemFont, $white, $xText, $y)
    $y += 52
    if ($d) {
        $g.DrawString($d, $dateFont, $muted, $xText, $y)
        $y += 38
    }

    # Avança para próximo bloco
    $y = $marginX + ($i+1) * $boxH
    if ($y -gt ($height - 140)) { break }
}

# Rodapé com a fonte solicitada
$footer = "Fonte: https://www.seplan.rn.gov.br/noticias"
$footerFont = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Regular)
$g.DrawString($footer, $footerFont, $muted, $marginX, $height - 80)

# Salvar
$outFile = Join-Path (Get-Location) "wallpaper.png"
$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)

# Cleanup
$g.Dispose(); $bmp.Dispose()
$headerFont.Dispose(); $itemFont.Dispose(); $dateFont.Dispose()
$muted.Dispose(); $accent.Dispose()

Write-Host "Wallpaper gerado: $outFile"
