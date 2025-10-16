$ErrorActionPreference = "Stop"

# Endpoint WordPress
$apiUrl  = "https://www.seplan.rn.gov.br/wp-json/wp/v2/materia?per_page=20&page=1"
$baseUrl = "https://www.seplan.rn.gov.br"

# 1) Baixar JSON
try {
    $resp = Invoke-WebRequest -Uri $apiUrl -Headers @{ "Accept" = "application/json" } -UseBasicParsing
} catch {
    Write-Error "Falha ao acessar API: $apiUrl. $_"
    exit 1
}

# 2) Parse do JSON
try {
    $items = $resp.Content | ConvertFrom-Json
} catch {
    Write-Error "Falha ao converter JSON do endpoint."
    exit 1
}

if (-not $items -or $items.Count -eq 0) {
    Write-Error "API não retornou matérias."
    exit 1
}

# 3) Extrair campos relevantes: title.rendered, link, date
# Alguns WP retornam 'date_gmt' ou 'modified', ajustar se necessário.
$materias = foreach ($it in $items) {
    $titulo = $null
    $link   = $null
    $date   = $null

    if ($it.title -and $it.title.rendered) {
        # remover tags HTML do título
        $titulo = ($it.title.rendered -replace "<.*?>","").Trim()
    }
    if ($it.link) {
        $link = $it.link.Trim()
    } elseif ($it.slug) {
        $link = "$baseUrl/materia/$($it.slug.Trim('/'))/"
    }
    if ($it.date) {
        $date = Get-Date $it.date
    }

    if ($titulo -and $link) {
        [pscustomobject]@{
            Titulo = $titulo
            Url    = $link
            Data   = $date
        }
    }
}

if (-not $materias -or $materias.Count -eq 0) {
    Write-Error "Sem matérias válidas após o parsing."
    exit 1
}

# 4) Ordenar por data desc e pegar 3
$top3 = $materias | Sort-Object Data -Descending | Select-Object -First 3

# 5) Preparar texto do wallpaper
function Trunca($s, $limite) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $s }
    if ($s.Length -le $limite) { return $s }
    return ($s.Substring(0, [Math]::Max(0, $limite-1)) + "…")
}

$maxTitulo = 95
$maxLink   = 110

$header = "Notícias SEPLAN-RN"
$lines  = @()
$idx = 1
foreach ($item in $top3) {
    $dataFmt = if ($item.Data) { $item.Data.ToString("dd/MM/yyyy HH:mm") } else { "" }
    $titulo  = Trunca $item.Titulo $maxTitulo
    $url     = Trunca $item.Url    $maxLink

    $lines += ("$idx. " + $titulo)
    if ($dataFmt) { $lines += ("   " + $dataFmt) }
    $lines += ("   " + $url)
    $lines += ""
    $idx++
}

# 6) Renderizar imagem 1920x1080
Add-Type -AssemblyName System.Drawing

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
$subFont    = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Regular)

$white      = [System.Drawing.Brushes]::White
$muted      = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 220, 230))
$accent     = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 171, 169))

$marginX = 120
$y = 120

# Cabeçalho
$g.DrawString($header, $headerFont, $white, $marginX, $y)
$y += 80
$g.FillRectangle($accent, $marginX, $y, 600, 6)
$y += 30

# Corpo
foreach ($line in $lines) {
    if ($line -match "^\s*\d+\.\s") {
        $g.DrawString($line, $itemFont, $white, $marginX, $y); $y += 48
    } elseif ($line -match "^\s{3,}\d{2}/\d{2}/\d{4}") {
        $g.DrawString($line, $subFont, $muted, $marginX, $y); $y += 38
    } elseif ($line -match "^\s{3,}https?://") {
        $g.DrawString($line, $subFont, $muted, $marginX, $y); $y += 38
    } else {
        $y += 16
    }
    if ($y -gt ($height - 100)) { break }
}

# Rodapé
$footer = "Fonte: API WordPress - /wp-json/wp/v2/materia"
$footerFont = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Regular)
$g.DrawString($footer, $footerFont, $muted, $marginX, $height - 80)

# Salvar
$outFile = Join-Path (Get-Location) "wallpaper.png"
$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)

# Cleanup
$g.Dispose(); $bmp.Dispose()
$headerFont.Dispose(); $itemFont.Dispose(); $subFont.Dispose()
$muted.Dispose(); $accent.Dispose()

Write-Host "Wallpaper gerado: $outFile"
