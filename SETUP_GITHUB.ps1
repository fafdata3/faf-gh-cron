# ─────────────────────────────────────────────────────────────────────────
# SETUP GITHUB (ejecutar una vez, desde este PC)
#   Hace TODO: auth en GitHub, crea faf-runner (privado) y faf-gh-cron
#   (publico), sube los codigos, guarda los 7 secrets y dispara la primera
#   sync.
#   Uso:  powershell -ExecutionPolicy Bypass -File SETUP_GITHUB.ps1
# ─────────────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Stop"

$gh = "C:\Program Files\GitHub CLI\gh.exe"
if (-not (Test-Path $gh)) { $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source }
if (-not $gh) { Write-Error "No encuentro gh. Instala GitHub CLI."; exit 1 }

$runner = "C:\Users\Pablo\Documents\Default Project\faf-cloud-sync"
$cron   = "C:\Users\Pablo\Documents\Default Project\faf-gh-cron"

Write-Host "== 1/5 Autenticando en GitHub (si sale un navegador, haz clic en Authorize) =="
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    & $gh auth login --hostname github.com --git-protocol https --web
}
$pat   = & $gh auth token
$owner = & $gh api user --jq .login
Write-Host "   Cuenta: $owner"

Write-Host "== 2/5 Creando/subiendo repos =="
foreach ($r in @(@{n="faf-runner"; vis="--private"; src=$runner},
                 @{n="faf-gh-cron"; vis="--public";  src=$cron})) {
    & $gh repo view "$owner/$($r.n)" *> $null
    if ($LASTEXITCODE -ne 0) {
        & $gh repo create "$($r.n)" $r.vis --source $r.src --push
    } else {
        Write-Host "   $($r.n) ya existe: solo push"
        Push-Location $r.src
        & $gh repo set-default "$owner/$($r.n)"
        & $gh repo sync "$owner/$($r.n)" --source 2> $null
        Pop-Location
    }
}

Write-Host "== 3/5 Leyendo credenciales B2 del .env =="
$vals = @{}
Get-Content (Join-Path $runner ".env") | ForEach-Object {
    if ($_ -match "^\s*([A-Z0-9_]+)=(.*)$") { $vals[$matches[1]] = $matches[2].Trim('"') }
}
if (-not $vals["CLOUDFLARE_API_TOKEN"]) {
    $vals["CLOUDFLARE_API_TOKEN"] = Read-Host "  Pega el API Token de Cloudflare (permiso Pages Edit). vacio = luego"
}
if (-not $vals["CLOUDFLARE_ACCOUNT_ID"]) {
    $vals["CLOUDFLARE_ACCOUNT_ID"] = Read-Host "  Pega tu Account ID de Cloudflare (dashboard -> arriba derecha)"
}

Write-Host "== 4/5 Guardando secrets en $owner/faf-gh-cron =="
$secrets = [ordered]@{
    GH_PAT                 = $pat
    S3_ENDPOINT            = $vals["S3_ENDPOINT"]
    S3_ACCESS_KEY          = $vals["S3_ACCESS_KEY"]
    S3_SECRET_KEY          = $vals["S3_SECRET_KEY"]
    S3_BUCKET              = $vals["S3_BUCKET"]
    S3_REGION              = $vals["S3_REGION"]
    CLOUDFLARE_API_TOKEN   = $vals["CLOUDFLARE_API_TOKEN"]
    CLOUDFLARE_ACCOUNT_ID  = $vals["CLOUDFLARE_ACCOUNT_ID"]
}
foreach ($k in $secrets.Keys) {
    if (-not $secrets[$k]) { Write-Warning "   $k vacio, se omite"; continue }
    & $gh secret set $k --repo "$owner/faf-gh-cron" --body $secrets[$k]
}

Write-Host "== 5/5 Primer disparo manual =="
& $gh workflow run faf-sync --repo "$owner/faf-gh-cron" --ref main
Write-Host ""
Write-Host "Hecho."
Write-Host "  Acciones: https://github.com/$owner/faf-gh-cron/actions"
Write-Host "  El cron seguira cada 2h. Si quieres revisar que no haya infracciones al monologo,"
Write-Host "  el workflow clona faf-runner (privado) en tiempo de ejecucion."