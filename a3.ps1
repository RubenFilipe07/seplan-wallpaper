# Execução robusta e UTF-8
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
[System.Threading.Thread]::CurrentThread.CurrentCulture  = 'pt-BR'
[System.Threading.Thread]::CurrentThread.CurrentUICulture = 'pt-BR'

function Fail($msg) { Write-Error $msg; exit 1 }

# Endpoint WP com mídia incorporada
$apiUrl = "https://www.seplan.rn.gov.br/wp-json/wp/v2/materia?per_page=20&page=1&_embed=1"

# 1) Buscar JSON (PS 5.x)
try {
    $resp = Invoke-WebRequest -Uri $apiUrl -Headers @{ "Accept" = "application/json" } -UseBasicParsing
} catch { Fail "Falha ao acessar a API ($apiUrl): $_" }
if (-not $resp -or -not $resp.Content) { Fail "API não retornou conteúdo." }

# 2) JSON e normalização
Add-Type -AssemblyName System.Web
function LimpaHtml($s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $s }
    $s = $s -replace "<.*?>",""
    $s = [System.Web.HttpUtility]::HtmlDecode($s)
    return $s.Trim()
}
try {
    $jsonText = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes($resp.Content))
    $items = $jsonText | ConvertFrom-Json
} catch { Fail "Falha ao converter JSON: $_" }
if (-not $items -or $items.Count -eq 0) { Fail "API não retornou matérias." }

# 3) Título, data e imagem (prioriza ACF -> _embedded -> sizes -> guid)
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

# 4) Top 3
$top3 = $materias | Sort-Object Data -Descending | Select-Object -First 3

# 5) Baixar miniaturas locais
$thumbsDir = Join-Path (Get-Location) "thumbs"
if (-not (Test-Path $thumbsDir)) { New-Item -ItemType Directory $thumbsDir | Out-Null }
$thumbPaths = @()
for ($i=0; $i -lt $top3.Count; $i++) {
    $imgUrl = $top3[$i].Imagem
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

# 6) Renderização (proporção preservada e título corrigido)
Add-Type -AssemblyName System.Drawing
function Trunca([string]$s, [int]$limite) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $s }
    if ($s.Length -le $limite) { return $s }
    return ($s.Substring(0, [Math]::Max(0, $limite-1)) + "…")
}

$width  = 1920; $height = 1080
$bmp    = New-Object System.Drawing.Bitmap($width, $height)
$g      = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

# Fundo e fontes
$bgColor = [System.Drawing.Color]::FromArgb(18, 32, 47); $g.Clear($bgColor)
$headerFont = New-Object System.Drawing.Font("Segoe UI Semibold", 52, [System.Drawing.FontStyle]::Bold)
$titleFont  = New-Object System.Drawing.Font("Segoe UI", 30, [System.Drawing.FontStyle]::Regular)
$dateFont   = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Regular)
$footerFont = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Regular)
$white  = [System.Drawing.Brushes]::White
$muted  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 220, 230))
$accent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 171, 169))

$marginX = 100; $y = 110

# Cabeçalho correto

# \u00ED = í
$g.DrawString("Not"+[char]0x00ED+"cias SEPLAN-RN", $headerFont, $white, $marginX, $y)
$y += 86; $g.FillRectangle($accent, $marginX, $y, 620, 6); $y += 34


# Itens
$thumbW = 280; $thumbH = 160; $gapX = 24; $boxH = 210; $maxTitulo = 95

for ($i=0; $i -lt $top3.Count; $i++) {
    $m = $top3[$i]
    $titulo = Trunca $m.Titulo $maxTitulo
    $dataFmt = if ($m.Data) { $m.Data.ToString("dd/MM/yyyy HH:mm") } else { "" }

    $xImg = $marginX; $yImg = $y + 6

    # Moldura do slot
    $slotBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(32, 48, 64))
    $g.FillRectangle($slotBrush, $xImg, $yImg, $thumbW, $thumbH)
    $slotBrush.Dispose()

    if ($thumbPaths[$i] -and (Test-Path $thumbPaths[$i])) {
        $img = [System.Drawing.Image]::FromFile($thumbPaths[$i])

        # calcular escala para caber mantendo proporção e sem cortes (letterbox)
        $scale = [Math]::Min($thumbW / $img.Width, $thumbH / $img.Height)
        $w = [int]($img.Width * $scale)
        $h = [int]($img.Height * $scale)
        $x = $xImg + [int](($thumbW - $w) / 2)
        $ypos = $yImg + [int](($thumbH - $h) / 2)

        $g.DrawImage($img, $x, $ypos, $w, $h)
        $img.Dispose()
    }

    $xText = $xImg + $thumbW + $gapX
    $g.DrawString(("{0}. {1}" -f ($i+1), $titulo), $titleFont, $white, $xText, $y)
    $y += 54
    if ($dataFmt) { $g.DrawString($dataFmt, $dateFont, $muted, $xText, $y); $y += 40 }

    $y = 110 + 86 + 34 + ($i+1)*$boxH
    if ($y -gt ($height - 140)) { break }
}

# Rodapé
$g.DrawString("Fonte: https://www.seplan.rn.gov.br/noticias", $footerFont, $muted, $marginX, $height - 80)

# Salvar
$outFile = Join-Path (Get-Location) "wallpaper.png"
$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)

# Limpeza
$g.Dispose(); $bmp.Dispose()
$headerFont.Dispose(); $titleFont.Dispose(); $dateFont.Dispose(); $footerFont.Dispose()
$muted.Dispose(); $accent.Dispose()
