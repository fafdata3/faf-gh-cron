# ─────────────────────────────────────────────────────────────────────────
# SETUP GITHUB (ejecutar una vez, desde este PC)
#   Hace TODO: auth en GitHub, crea faf-runner (privado) y faf-gh-cron
#   (publico), sube los codigos, guarda los 8 secrets y dispara la primera
#   sync.
#   Uso:  powershell -ExecutionPolicy Bypass -File SETUP_GITHUB.ps1
#
#   Nota: todas las llamadas a gh se hacen via cmd /c para evitar que el
#   stderr nativo de gh rompa el pipeline de errores de PowerShell 5.1.
# ─────────────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Continue"

$gh = "C:\Program Files\GitHub CLI\gh.exe"
if (-not (Test-Path $gh)) { $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source }
if (-not $gh) { Write-Host "No encuentro gh. Instala GitHub CLI (winget install GitHub.cli)."; exit 1 }

$runner = "C:\Users\Pablo\Documents\Default Project\faf-cloud-sync"
$cron   = "C:\Users\Pablo\Documents\Default Project\faf-gh-cron"

function Invoke-Gh {
    # llama a gh via cmd /c y devuelve (salida, exitcode)
    param([string]$cmdline)
    $out = cmd /c "`"$gh`" $cmdline 2>&1"
    return ,$out
}
function Gh-Ok([int]$code) { return ($code -eq 0) }

# ── 1/5 Autenticación ────────────────────────────────────────────────────
Write-Host "== 1/5 Autenticando en GitHub (si sale un navegador, haz clic en Authorize) =="
Invoke-Gh "auth status >nul 2>&1" | Out-Null
$logState = $LASTEXITCODE
if ($logState -ne 0) {
    # pre-responde "y" (x2) a los prompts interactivos de gh login --web
    cmd /c "(echo y& echo.)" | cmd /c "`"$gh`" auth login --hostname github.com --git-protocol https --web"
}
$patOut = Invoke-Gh "auth token"
$pat = ($patOut -join "").Trim()
if ($LASTEXITCODE -ne 0 -or -not $pat) { Write-Host "Fallo la autenticacion. Vuelve a ejecutar este script."; exit 1 }
$ownerOut = Invoke-Gh "api user --jq .login"
$owner = ($ownerOut -join "").Trim()
Write-Host "   Cuenta: $owner"

# ── 2/5 Repos ────────────────────────────────────────────────────────────
Write-Host "== 2/5 Creando/subiendo repos =="
foreach ($r in @(@{n="faf-runner"; vis="--private"; src=$runner},
                 @{n="faf-gh-cron"; vis="--public";  src=$cron})) {
    Invoke-Gh "repo view `"$owner/$($r.n)`" >nul 2>&1" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   creando $($r.n)..."
        Invoke-Gh "repo create `"$($r.n)`" $($r.vis) --source `"$($r.src)`" --push --remote origin" | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Host "   ERROR al crear $($r.n) (codigo $LASTEXITCODE)" }
    } else {
        Write-Host "   $($r.n) ya existe: corriendo push"
        Push-Location $r.src
        $git = "C:\Program Files\Git\bin\git.exe"
        try {
            if (-not (Invoke-Gh "repo view `"$owner/$($r.n)`" >nul 2>&1")) { }
            cmd /c "`"$git`" remote remove origin 2>nul" | Out-Null
            cmd /c "`"$git`" remote add origin https://github.com/$owner/$($r.n).git 2>nul" | Out-Null
            cmd /c "`"$git`" push -u origin main" | Out-Null
        } finally { Pop-Location }
    }
}

# ── 3/5 Credenciales B2 + CF ────────────────────────────────────────────
Write-Host "== 3/5 Leyendo credenciales B2 del .env =="
$vals = @{}
Get-Content (Join-Path $runner ".env") | ForEach-Object {
    if ($_ -match "^\s*([A-Z0-9_]+)=(.*)$") { $vals[$matches[1]] = $matches[2].Trim('"') }
}
$cfToken = $vals["CLOUDFLARE_API_TOKEN"]
$cfAcct  = $vals["CLOUDFLARE_ACCOUNT_ID"]
if (-not $cfToken) {
    $cfToken = Read-Host "  Pega el API Token de Cloudflare (permiso Pages Edit). Enter = luego"
}
if (-not $cfAcct) {
    $cfAcct = Read-Host "  Pega tu Account ID de Cloudflare (dashboard -> arriba derecha)"
}

# ── 4/5 Secrets ─────────────────────────────────────────────────────────
Write-Host "== 4/5 Guardando secrets en $owner/faf-gh-cron =="
$secrets = [ordered]@{
    "GH_PAT"                = $pat
    "S3_ENDPOINT"           = $vals["S3_ENDPOINT"]
    "S3_ACCESS_KEY"         = $vals["S3_ACCESS_KEY"]
    "S3_SECRET_KEY"         = $vals["S3_SECRET_KEY"]
    "S3_BUCKET"             = $vals["S3_BUCKET"]
    "S3_REGION"             = $vals["S3_REGION"]
    "CLOUDFLARE_API_TOKEN"  = $cfToken
    "CLOUDFLARE_ACCOUNT_ID" = $cfAcct
}
foreach ($k in $secrets.Keys) {
    if (-not $secrets[$k]) { Write-Host "   $k vacio, se omite (configuralo luego con: gh secret set $k --repo $owner/faf-gh-cron)"; continue }
    Invoke-Gh "secret set $k --repo `"$owner/faf-gh-cron`" --body `"$($secrets[$k])`"" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "   ERROR al guardar $k (codigo $LASTEXITCODE)" }
}

# ── 5/5 Primer disparo ──────────────────────────────────────────────────
Write-Host "== 5/5 Primer disparo manual =="
Invoke-Gh "workflow run sync.yml --repo `"$owner/faf-gh-cron`" --ref main" | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "   (el workflow aun se esta indexando; entra en Acciones y pulsa Run workflow)" }

Write-Host ""
Write-Host "Hecho."
Write-Host "  Acciones: https://github.com/$owner/faf-gh-cron/actions"
Write-Host "  Verificacion rapida de secrets: gh secret list --repo $owner/faf-gh-cron"