<#
.SYNOPSIS
    Verifies the local toolchain for the Contoso Retail Insights Platform build.

.DESCRIPTION
    Checks that PowerShell, Git, Docker, Azure CLI, azd, kubectl, helm, .NET SDK,
    Python, Node.js, GitHub CLI, and Bicep are installed and reachable. Reports
    installed versions and prints an install hint for anything missing.

    Runs from any directory. Non-destructive — reads versions only.

.EXAMPLE
    PS D:\dev\claude\contoso-retail> .\scripts\verify-tools.ps1

.NOTES
    You can safely re-run this. Exit code 0 = all present, 1 = something missing.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Test-Tool {
    param(
        [string]$Name,
        [string]$Command,
        [string[]]$VersionArgs,
        [string]$InstallHint,
        [string]$MinNote = ''
    )
    $found = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $found) {
        [pscustomobject]@{ Tool = $Name; Found = $false; Version = ''; Hint = $InstallHint }
        return
    }
    try {
        $out = & $Command @VersionArgs 2>&1 | Out-String
        $version = ($out -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 1).Trim()
        [pscustomobject]@{ Tool = $Name; Found = $true; Version = $version; Hint = $MinNote }
    } catch {
        [pscustomobject]@{ Tool = $Name; Found = $false; Version = ''; Hint = $InstallHint }
    }
}

Write-Host ""
Write-Host "Contoso Retail — local toolchain check" -ForegroundColor Cyan
Write-Host "PowerShell version: $($PSVersionTable.PSVersion)"
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning "PowerShell 7+ recommended. Install: winget install --id Microsoft.PowerShell -e"
}
Write-Host ""

$checks = @(
    (Test-Tool 'Git'          'git'     @('--version')       'winget install --id Git.Git -e'),
    (Test-Tool 'GitHub CLI'   'gh'      @('--version')       'winget install --id GitHub.cli -e'),
    (Test-Tool 'Azure CLI'    'az'      @('version')         'winget install --id Microsoft.AzureCLI -e'),
    (Test-Tool 'azd'          'azd'     @('version')         'winget install --id Microsoft.Azd -e'),
    (Test-Tool 'Bicep'        'bicep'   @('--version')       'az bicep install'),
    (Test-Tool 'kubectl'      'kubectl' @('version','--client') 'winget install --id Kubernetes.kubectl -e'),
    (Test-Tool 'Helm'         'helm'    @('version','--short') 'winget install --id Helm.Helm -e'),
    (Test-Tool 'Docker'       'docker'  @('--version')       'winget install --id Docker.DockerDesktop -e (needs WSL2)'),
    (Test-Tool '.NET SDK'     'dotnet'  @('--version')       'winget install --id Microsoft.DotNet.SDK.8 -e' '8.0+'),
    (Test-Tool 'Python'       'python'  @('--version')       'winget install --id Python.Python.3.11 -e' '3.11+'),
    (Test-Tool 'Node.js'      'node'    @('--version')       'winget install --id OpenJS.NodeJS.LTS -e' 'LTS'),
    (Test-Tool 'Claude Code'  'claude'  @('--version')       'npm install -g @anthropic-ai/claude-code')
)

$checks | Format-Table -AutoSize @(
    @{ Name = 'Tool';    Expression = { $_.Tool } },
    @{ Name = 'Found';   Expression = { if ($_.Found) { '[OK]' } else { '[--]' } } },
    @{ Name = 'Version'; Expression = { $_.Version } },
    @{ Name = 'Note';    Expression = { $_.Hint } }
)

$missing = $checks | Where-Object { -not $_.Found }
if ($missing.Count -eq 0) {
    Write-Host "All tools present. Ready to start Phase 0." -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "Missing tools:" -ForegroundColor Yellow
    foreach ($m in $missing) {
        Write-Host "  - $($m.Tool): $($m.Hint)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Restart Windows Terminal after installing so PATH refreshes." -ForegroundColor Yellow
    exit 1
}
