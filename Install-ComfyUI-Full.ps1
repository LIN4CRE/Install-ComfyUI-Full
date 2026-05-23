#Requires -Version 5.1
<#
  ComfyUI Full Auto-Installer -- RTX 3070 Ti Edition
  ====================================================
  Use START_INSTALLER.bat to run this -- it handles
  admin rights and the execution policy automatically.

  Installs:
    Git, Python 3.12 (ComfyUI venv), Python 3.10 (Kohya venv)
    ComfyUI + PyTorch CUDA 12.6 + xformers
    5 custom nodes: Manager, ReActor, ControlNet, AnimateDiff, VideoHelper
    Visual C++ Redistributable
    Kohya_ss LoRA trainer
    All model folders with readme guides
    Desktop shortcuts + batch launchers
    ComfyUI workflow JSON (embedded -- no extra files needed)
#>

# -- If run directly without bypass, re-launch with it ----------------------
if ((Get-ExecutionPolicy -Scope Process) -eq 'Restricted') {
    $me = if ($PSCommandPath) { $PSCommandPath }
          elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path }
          else { $PSScriptRoot + '\Install-ComfyUI-Full.ps1' }
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$me`"" `
        -Verb RunAs
    exit 0
}

# -- Keep window open on any crash ------------------------------------------
$ErrorActionPreference = 'Continue'
trap {
    Write-Host ''
    Write-Host '  [FATAL ERROR] Installer stopped.' -ForegroundColor Red
    Write-Host "  $_"                               -ForegroundColor Red
    Write-Host ''
    Write-Host '  Check the log on your Desktop for details.' -ForegroundColor Yellow
    Write-Host '  Press ENTER to close...'
    $null = Read-Host
    exit 1
}
Set-StrictMode -Off

# ===========================================================================
#  HELPERS
# ===========================================================================
function Show-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Cyan
    Write-Host '   ComfyUI Full Auto-Installer  |  RTX 3070 Ti Edition'         -ForegroundColor Cyan
    Write-Host '  ============================================================'  -ForegroundColor Cyan
    Write-Host ''
}
function Step  { param($n,$t) Write-Host "`n  [Step $n] $t" -ForegroundColor Yellow }
function OK    { param($t)    Write-Host "    [OK] $t"      -ForegroundColor Green  }
function Info  { param($t)    Write-Host "    [..] $t"      -ForegroundColor Cyan   }
function Warn  { param($t)    Write-Host "    [!!] $t"      -ForegroundColor DarkYellow }
function Err   { param($t)    Write-Host "    [XX] $t"      -ForegroundColor Red    }
function Sub   { param($t)    Write-Host "         $t"      -ForegroundColor Gray   }
function Hold  {
    param([string]$msg = 'Press ENTER to continue...')
    Write-Host "`n  $msg" -ForegroundColor DarkCyan
    $null = Read-Host
}

# Download with 3 fallback methods
function Fetch {
    param([string]$Url, [string]$Out, [string]$Label)
    if (Test-Path $Out) { Info "$Label already downloaded."; return $true }
    Info "Downloading $Label ..."
    Sub  $Url
    # WebClient
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent','Mozilla/5.0')
        $wc.DownloadFile($Url, $Out)
        if ((Test-Path $Out) -and (Get-Item $Out).Length -gt 10000) { OK "Got $Label"; return $true }
    } catch { Sub "WebClient: $_" }
    # Invoke-WebRequest
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing -ErrorAction Stop
        if ((Test-Path $Out) -and (Get-Item $Out).Length -gt 10000) { OK "Got $Label"; return $true }
    } catch { Sub "IWR: $_" }
    # curl.exe (Windows 10+ built-in)
    try {
        & curl.exe -L -s -o $Out $Url
        if ((Test-Path $Out) -and (Get-Item $Out).Length -gt 10000) { OK "Got $Label"; return $true }
    } catch { Sub "curl: $_" }
    Err "Failed to download $Label"; return $false
}

# ===========================================================================
#  STEP 0  --  DRIVE / FOLDER SELECTION
# ===========================================================================
function Pick-Root {
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Cyan
    Write-Host '   Where do you want to install ComfyUI?'                        -ForegroundColor Cyan
    Write-Host '  ============================================================'  -ForegroundColor Cyan
    Write-Host ''

    $drives = @()
    try {
        $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction Stop |
            Where-Object { $_.Name -match '^[A-Z]$' -and $_.Free -gt 100MB } |
            Sort-Object Name
    } catch {}
    if ($drives.Count -eq 0) {
        Warn 'Could not list drives -- defaulting to C:\'
        $drives = @([PSCustomObject]@{ Name='C'; Free=60GB; Used=40GB })
    }

    $idx = 0
    foreach ($d in $drives) {
        $free  = [math]::Round($d.Free  / 1GB, 1)
        $total = [math]::Round(($d.Free + $d.Used) / 1GB, 1)
        $note  = if   ($free -lt 20)  { '  <-- WARNING: very low space' }
                 elseif ($free -lt 60) { '  <-- enough for ComfyUI only' }
                 else                  { '  <-- recommended' }
        Write-Host "    [$idx]  $($d.Name):\   $free GB free / $total GB total$note" -ForegroundColor White
        $idx++
    }

    Write-Host ''
    Write-Host '  Minimum recommended: 60 GB free space.' -ForegroundColor DarkCyan
    Write-Host '  (Software ~10 GB + AI model files up to 50 GB)' -ForegroundColor DarkCyan
    Write-Host ''

    $pick = $null
    do {
        $raw = (Read-Host '  Type the number next to the drive you want').Trim()
        if ($raw -match '^\d+$' -and [int]$raw -lt $drives.Count) {
            $pick = $drives[[int]$raw].Name
        } else { Warn 'Please type one of the numbers shown.' }
    } while (-not $pick)

    Write-Host ''
    Write-Host '  What folder name do you want?' -ForegroundColor White
    Write-Host "  Example: AI_Studio  ->  ${pick}:\AI_Studio" -ForegroundColor Gray
    Write-Host '  Press ENTER for default [AI_Studio]' -ForegroundColor DarkGray
    Write-Host ''
    $name = (Read-Host '  Folder name').Trim()
    if ($name -eq '') { $name = 'AI_Studio' }
    $name = ($name -replace '[\\/:*?"<>|]','_').Trim()
    if ($name -eq '') { $name = 'AI_Studio' }

    $root = "${pick}:\${name}"
    Write-Host ''
    OK "Install location: $root"
    return $root
}

# ===========================================================================
#  STEP 1  --  GIT
# ===========================================================================
function Get-Git {
    Step '1/8' 'Checking Git...'

    # Always try to refresh PATH before checking
    $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User') + ';' +
                'C:\Program Files\Git\cmd'

    if (Get-Command git -ErrorAction SilentlyContinue) {
        OK "Git found: $(git --version 2>&1)"
        return
    }

    Warn 'Git not found -- downloading Git 2.49.0...'
    $inst = "$env:TEMP\git_setup.exe"
    $ok = Fetch `
        'https://github.com/git-for-windows/git/releases/download/v2.49.0.windows.1/Git-2.49.0-64-bit.exe' `
        $inst 'Git for Windows'

    if (-not $ok) {
        Err 'Git download failed. Install from https://git-scm.com then re-run.'
        Hold 'Press ENTER to exit...'
        exit 1
    }

    Info 'Installing Git silently (~60 seconds)...'
    $p = Start-Process $inst '/VERYSILENT /NORESTART /NOCANCEL /SP-' -Wait -PassThru
    Sub "Git installer exit code: $($p.ExitCode)"

    $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User') + ';' +
                'C:\Program Files\Git\cmd;C:\Program Files\Git\bin'

    if (Get-Command git -ErrorAction SilentlyContinue) { OK "Git installed: $(git --version 2>&1)" }
    else { Warn 'Git installed but may need a restart to appear on PATH -- continuing anyway.' }
}

# ===========================================================================
#  STEP 2  --  PYTHON 3.12 (ComfyUI venv)
# ===========================================================================
function Get-Py312 {
    param([string]$Root)
    Step '2/8' 'Setting up Python 3.12 for ComfyUI...'
    Info 'Your system Python 3.14 will NOT be changed.'

    $pyExe = $null

    # Try py launcher
    try {
        if (Get-Command py -ErrorAction SilentlyContinue) {
            $v = (& py -3.12 --version 2>&1)
            if ($v -match '3\.12') { $pyExe = 'PY'; OK "Python 3.12 via py launcher: $v" }
        }
    } catch {}

    # Try known paths
    if (-not $pyExe) {
        @("$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
          'C:\Python312\python.exe',
          'C:\Program Files\Python312\python.exe') | ForEach-Object {
            if (-not $pyExe -and (Test-Path $_)) {
                $v = (& $_ --version 2>&1)
                if ($v -match '3\.12') { $pyExe = $_; OK "Python 3.12 at: $_" }
            }
        }
    }

    # Download and install
    if (-not $pyExe) {
        Info 'Downloading Python 3.12.10...'
        $inst = "$env:TEMP\py312_setup.exe"
        $ok = Fetch 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' $inst 'Python 3.12.10'
        if ($ok) {
            Info 'Installing Python 3.12 (will not affect your Python 3.14)...'
            $p = Start-Process $inst `
                'InstallAllUsers=0 PrependPath=0 Include_launcher=1 Include_pip=1 /quiet' `
                -Wait -PassThru
            Sub "Installer exit: $($p.ExitCode)"
            $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                        [Environment]::GetEnvironmentVariable('Path','User')
            try { $v = (& py -3.12 --version 2>&1); if ($v -match '3\.12') { $pyExe = 'PY' } } catch {}
            if (-not $pyExe) {
                $kp = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
                if (Test-Path $kp) { $pyExe = $kp }
            }
        }
    }

    if (-not $pyExe) {
        Err 'Python 3.12 not found. Install from python.org then re-run.'
        Hold; exit 1
    }

    # Create isolated venv
    $venv   = Join-Path $Root 'comfyui_venv'
    $venvPy = Join-Path $venv 'Scripts\python.exe'
    if (Test-Path $venvPy) {
        OK 'ComfyUI venv already exists.'
    } else {
        Info "Creating Python 3.12 virtual environment at: $venv"
        if ($pyExe -eq 'PY') { & py -3.12 -m venv $venv }
        else                  { & $pyExe   -m venv $venv }
        if (Test-Path $venvPy) { OK 'Virtual environment created.' }
        else { Err 'Venv creation failed.'; Hold; exit 1 }
    }
    return $venvPy
}

# ===========================================================================
#  STEP 3  --  COMFYUI
# ===========================================================================
function Get-ComfyUI {
    param([string]$Root, [string]$VenvPy)
    Step '3/8' 'Installing ComfyUI...'

    $dir = Join-Path $Root 'ComfyUI'
    $pip = Join-Path (Split-Path $VenvPy) 'pip.exe'

    if (Test-Path (Join-Path $dir '.git')) {
        Info 'ComfyUI already downloaded -- checking for updates...'
        Push-Location $dir; & git pull 2>&1 | ForEach-Object { Sub $_ }; Pop-Location
    } else {
        Info 'Cloning ComfyUI from GitHub...'
        & git clone 'https://github.com/comfyanonymous/ComfyUI' $dir 2>&1 | ForEach-Object { Sub $_ }
        if (-not (Test-Path (Join-Path $dir 'main.py'))) {
            Err 'Clone failed -- check internet connection.'
            Hold; exit 1
        }
    }
    OK 'ComfyUI source ready.'

    Info 'Upgrading pip...'
    & $pip install --quiet --upgrade pip setuptools wheel 2>&1 | ForEach-Object { Sub $_ }

    Info 'Installing PyTorch with CUDA 12.6 (2-3 GB download -- please wait)...'
    & $pip install torch torchvision torchaudio `
        --index-url https://download.pytorch.org/whl/cu126 2>&1 | ForEach-Object { Sub $_ }
    OK 'PyTorch installed.'

    $req = Join-Path $dir 'requirements.txt'
    if (Test-Path $req) {
        Info 'Installing ComfyUI requirements...'
        & $pip install --quiet -r $req 2>&1 | ForEach-Object { Sub $_ }
        OK 'Requirements done.'
    }

    Info 'Installing xformers (saves VRAM on RTX 3070 Ti)...'
    & $pip install --quiet xformers --index-url https://download.pytorch.org/whl/cu126 2>&1 |
        ForEach-Object { Sub $_ }
    OK 'xformers done.'

    return $dir
}

# ===========================================================================
#  STEP 4  --  FOLDER STRUCTURE + GUIDES
# ===========================================================================
function Make-Folders {
    param([string]$ComfyDir, [string]$Root)
    Step '4/8' 'Creating folder structure...'

    $comfyFolders = @(
        'models\checkpoints','models\loras','models\vae','models\controlnet',
        'models\insightface','models\facerestore_models','models\upscale_models',
        'models\embeddings','input','output','custom_nodes','user\default\workflows'
    )
    foreach ($f in $comfyFolders) {
        $p = Join-Path $ComfyDir $f
        if (-not (Test-Path $p)) { New-Item -ItemType Directory $p -Force | Out-Null }
    }

    $extraFolders = @(
        'LoRA_Training\dataset\my_subject_10',
        'LoRA_Training\output',
        'LoRA_Training\logs',
        '_downloads'
    )
    foreach ($f in $extraFolders) {
        $p = Join-Path $Root $f
        if (-not (Test-Path $p)) { New-Item -ItemType Directory $p -Force | Out-Null }
    }

    # Guide files
    $g = @{}
    $g[(Join-Path $ComfyDir 'models\checkpoints\HOW_TO_USE.txt')] = @'
CHECKPOINTS (Base Models)
=========================
Put .safetensors or .ckpt model files here.

Recommended:
  dreamshaper_8.safetensors
  realisticVisionV60B1_v51VAE.safetensors

Download from: https://civitai.com  or  https://huggingface.co
'@
    $g[(Join-Path $ComfyDir 'models\loras\HOW_TO_USE.txt')] = @'
LORA FILES
==========
Put LoRA .safetensors files here.
After Kohya_ss training, copy the output file here.
Community LoRAs: https://civitai.com/models?type=LORA
'@
    $g[(Join-Path $ComfyDir 'models\vae\HOW_TO_USE.txt')] = @'
VAE MODELS
==========
Put VAE .safetensors files here.

Recommended:
  vae-ft-mse-840000-ema-pruned.safetensors

Download: https://huggingface.co/stabilityai/sd-vae-ft-mse-original
'@
    $g[(Join-Path $ComfyDir 'models\controlnet\HOW_TO_USE.txt')] = @'
CONTROLNET MODELS
=================
For the Pose Reference section you need:
  control_v11p_sd15_openpose.pth

Download: https://huggingface.co/lllyasviel/ControlNet-v1-1/tree/main
'@
    $g[(Join-Path $ComfyDir 'models\insightface\HOW_TO_USE.txt')] = @'
FACESWAP ENGINE
===============
Put inswapper_128.onnx directly in THIS folder.

Get it from: https://github.com/Gourieff/ComfyUI-ReActor/releases

buffalo_l folder is created automatically on first run.
'@
    $g[(Join-Path $ComfyDir 'models\facerestore_models\HOW_TO_USE.txt')] = @'
FACE RESTORE MODELS
===================
  codeformer.pth   (recommended)
  GFPGANv1.4.pth   (alternative)

codeformer: https://github.com/sczhou/CodeFormer/releases
GFPGAN:     https://github.com/TencentARC/GFPGAN/releases
'@
    $g[(Join-Path $Root 'LoRA_Training\dataset\my_subject_10\HOW_TO_USE.txt')] = @'
TRAINING IMAGES
===============
Put your images here (.jpg or .png).
The '10' in the folder name = repeats per epoch.

Each image needs a matching .txt caption:
  photo_001.jpg
  photo_001.txt  <-- write: mysubject, woman, red hair

Include your trigger word in every caption.
Use 20-100 quality images cropped to 512x512.
'@

    foreach ($path in $g.Keys) {
        if (-not (Test-Path $path)) {
            Set-Content $path $g[$path] -Encoding UTF8
        }
    }
    OK 'All folders and guide files created.'
}

# ===========================================================================
#  STEP 5  --  CUSTOM NODES
# ===========================================================================
function Get-Nodes {
    param([string]$ComfyDir, [string]$VenvPy)
    Step '5/8' 'Installing custom nodes...'

    $nodesDir = Join-Path $ComfyDir 'custom_nodes'
    $pip      = Join-Path (Split-Path $VenvPy) 'pip.exe'

    $nodes = @(
        [PSCustomObject]@{
            Name  = 'ComfyUI-Manager'
            Url   = 'https://github.com/ltdrdata/ComfyUI-Manager.git'
            Extra = @()
            Note  = 'Node manager'
        },
        [PSCustomObject]@{
            Name  = 'ComfyUI-ReActor'
            Url   = 'https://github.com/Gourieff/ComfyUI-ReActor.git'
            Extra = @(
                'https://github.com/Gourieff/Assets/raw/main/Insightface/insightface-0.7.3-cp312-cp312-win_amd64.whl',
                'onnxruntime-gpu'
            )
            Note  = 'Face Swap'
        },
        [PSCustomObject]@{
            Name  = 'comfyui_controlnet_aux'
            Url   = 'https://github.com/Fannovel16/comfyui_controlnet_aux.git'
            Extra = @()
            Note  = 'OpenPose / DWPose'
        },
        [PSCustomObject]@{
            Name  = 'ComfyUI-AnimateDiff-Evolved'
            Url   = 'https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved.git'
            Extra = @()
            Note  = 'AnimateDiff animation'
        },
        [PSCustomObject]@{
            Name  = 'ComfyUI-VideoHelperSuite'
            Url   = 'https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git'
            Extra = @()
            Note  = 'GIF / video export'
        }
    )

    $i = 1
    foreach ($node in $nodes) {
        Write-Host ''
        Info "[$i/$($nodes.Count)] $($node.Name)  --  $($node.Note)"
        $dest = Join-Path $nodesDir $node.Name

        if (Test-Path (Join-Path $dest '.git')) {
            Sub 'Already installed -- updating...'
            Push-Location $dest; & git pull 2>&1 | ForEach-Object { Sub $_ }; Pop-Location
        } else {
            Sub 'Cloning...'
            & git clone $node.Url $dest 2>&1 | ForEach-Object { Sub $_ }
        }

        $req = Join-Path $dest 'requirements.txt'
        if (Test-Path $req) {
            Sub 'Installing requirements...'
            & $pip install --quiet -r $req 2>&1 | ForEach-Object { Sub $_ }
        }

        foreach ($pkg in $node.Extra) {
            Sub "pip install $pkg"
            & $pip install --quiet $pkg 2>&1 | ForEach-Object { Sub $_ }
        }

        OK "$($node.Name) done."
        $i++
    }

    # AnimateDiff motion models folder
    $adm = Join-Path $nodesDir 'ComfyUI-AnimateDiff-Evolved\models'
    if (-not (Test-Path $adm)) { New-Item -ItemType Directory $adm -Force | Out-Null }
    if (-not (Test-Path (Join-Path $adm 'HOW_TO_USE.txt'))) {
        Set-Content (Join-Path $adm 'HOW_TO_USE.txt') @'
ANIMATEDIFF MOTION MODELS
==========================
Put .ckpt or .safetensors motion models here.

Recommended:
  mm_sd_v15_v2.ckpt
  Download: https://huggingface.co/guoyww/animatediff-motion-adapter-v1-5-2

Faster (fewer steps needed):
  animatediff_lightning_4step_comfyui.safetensors
  Download: https://huggingface.co/ByteDance/AnimateDiff-Lightning
'@ -Encoding UTF8
    }
    OK 'All custom nodes done.'
}

# ===========================================================================
#  STEP 6  --  VISUAL C++ REDISTRIBUTABLE
# ===========================================================================
function Get-VCRedist {
    Step '6/8' 'Checking Visual C++ Redistributable...'
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X64'
    )
    $found = $keys | Where-Object { Test-Path $_ }
    if ($found) { OK 'Already installed.'; return }

    Info 'Downloading VC++ 2015-2022 Redistributable...'
    $inst = "$env:TEMP\vc_redist_x64.exe"
    $ok = Fetch 'https://aka.ms/vs/17/release/vc_redist.x64.exe' $inst 'VC++ Redist'
    if ($ok) {
        $p = Start-Process $inst '/quiet /norestart' -Wait -PassThru
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { OK 'Installed.' }
        else { Warn "Exit $($p.ExitCode) -- may already be installed." }
    } else { Warn 'Download failed -- face swap may not work without this.' }
}

# ===========================================================================
#  STEP 7  --  KOHYA_SS
# ===========================================================================
function Get-Kohya {
    param([string]$Root)
    Step '7/8' 'Installing Kohya_ss LoRA Trainer...'

    $kohyaDir = Join-Path $Root 'kohya_ss'

    # Find Python 3.10
    $py310 = $null
    try {
        if (Get-Command py -ErrorAction SilentlyContinue) {
            $v = (& py -3.10 --version 2>&1)
            if ($v -match '3\.10') { $py310 = 'PY'; OK "Python 3.10: $v" }
        }
    } catch {}
    if (-not $py310) {
        @("$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
          'C:\Python310\python.exe') | ForEach-Object {
            if (-not $py310 -and (Test-Path $_)) {
                $v = (& $_ --version 2>&1)
                if ($v -match '3\.10') { $py310 = $_; OK "Python 3.10 at: $_" }
            }
        }
    }
    if (-not $py310) {
        Info 'Downloading Python 3.10.11 for Kohya_ss...'
        $inst = "$env:TEMP\py310_setup.exe"
        $ok = Fetch 'https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe' `
                    $inst 'Python 3.10.11'
        if ($ok) {
            $p = Start-Process $inst `
                'InstallAllUsers=0 PrependPath=0 Include_launcher=1 Include_pip=1 /quiet' `
                -Wait -PassThru
            Sub "Installer exit: $($p.ExitCode)"
            $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                        [Environment]::GetEnvironmentVariable('Path','User')
            try { $v=(& py -3.10 --version 2>&1); if ($v -match '3\.10') { $py310='PY' } } catch {}
            if (-not $py310) {
                $kp = "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe"
                if (Test-Path $kp) { $py310 = $kp }
            }
        }
    }

    # Clone
    if (Test-Path (Join-Path $kohyaDir '.git')) {
        Info 'Kohya_ss already cloned -- updating...'
        Push-Location $kohyaDir; & git pull 2>&1 | ForEach-Object { Sub $_ }; Pop-Location
    } else {
        Info 'Cloning Kohya_ss...'
        & git clone --recursive 'https://github.com/bmaltais/kohya_ss.git' $kohyaDir 2>&1 |
            ForEach-Object { Sub $_ }
    }

    # Create venv
    if ($py310) {
        $venv   = Join-Path $kohyaDir 'venv'
        $venvPy = Join-Path $venv 'Scripts\python.exe'
        if (-not (Test-Path $venvPy)) {
            Info 'Creating Python 3.10 venv for Kohya_ss...'
            if ($py310 -eq 'PY') { & py -3.10 -m venv $venv }
            else                  { & $py310   -m venv $venv }
            if (Test-Path $venvPy) { OK 'Kohya venv created.' }
            else { Warn 'Venv issue -- setup.bat will handle it on first launch.' }
        } else { OK 'Kohya venv already exists.' }
    } else {
        Warn 'Python 3.10 unavailable -- run setup.bat in kohya_ss folder manually.'
    }

    OK "Kohya_ss at: $kohyaDir"
    return $kohyaDir
}

# ===========================================================================
#  STEP 8  --  WORKFLOW + LAUNCHERS + SHORTCUTS
# ===========================================================================
function Make-Launchers {
    param([string]$Root, [string]$ComfyDir, [string]$VenvPy, [string]$KohyaDir)
    Step '8/8' 'Writing workflow, launchers, and Desktop shortcuts...'

    # ── Embedded workflow JSON ─────────────────────────────────────────────
    # NOTE: The workflow JSON is stored as a single-quoted PS here-string below.
    # Single-quoted here-strings are 100% literal -- no variable expansion.
    $wf = @'
{"last_node_id":120,"last_link_id":200,"groups":[{"title":"SECTION 0  BEGINNER GUIDE (READ THIS FIRST!)","bounding":[0,0,900,400],"color":"#1a1a2e","font_size":18,"locked":false},{"title":"SECTION 1  LoRA TRAINING SETUP (Kohya Reference + ComfyUI Prep)","bounding":[0,450,1400,600],"color":"#16213e","font_size":16,"locked":false},{"title":"SECTION 2  FACESWAP + TEXT PROMPTING","bounding":[0,1100,1800,700],"color":"#0f3460","font_size":16,"locked":false},{"title":"SECTION 3  FACESWAP + POSE REFERENCE (ControlNet OpenPose)","bounding":[0,1850,2200,750],"color":"#162032","font_size":16,"locked":false},{"title":"SECTION 4  LoRA USAGE (Text-to-Image with LoRA)  START HERE","bounding":[0,2650,1600,600],"color":"#1b2838","font_size":16,"locked":false},{"title":"SECTION 5  GIF / ANIMATION (AnimateDiff)","bounding":[0,3300,1800,700],"color":"#1a0533","font_size":16,"locked":false}],"nodes":[{"id":1,"type":"Note","pos":[20,20],"size":{"0":860,"1":380},"flags":{},"order":0,"mode":0,"properties":{"Node name for S&R":"Note"},"widgets_values":["WELCOME  RTX 3070 Ti ComfyUI Master Workflow\n\n\n HOW TO USE THIS WORKFLOW:\n1. Each colored group = one workflow section (use them independently)\n2. DISABLE sections you're not using: Right-click group  'Set Group Nodes as Muted'\n3. Only run ONE section at a time to save VRAM on your RTX 3070 Ti\n\n WHAT YOU NEED FIRST:\n ComfyUI installed and running\n ComfyUI-Manager installed (to add custom nodes)\n Models downloaded and placed in correct folders\n See _WORKFLOW_INFO at the top of this JSON for full details\n\n RECOMMENDED STARTING ORDER FOR BEGINNERS:\n Start with SECTION 4 (LoRA Usage)  simplest, just text-to-image\n Try SECTION 2 (FaceSwap + Text)  add a face reference\n Try SECTION 5 (Animation)  make GIFs\n Try SECTION 3 (FaceSwap + Pose)  most advanced\n Read SECTION 1 (LoRA Training)  for creating your own styles\n\n VRAM WARNING: This 3070 Ti has 8GB. Keep resolution at 512x512 or 512x768!\nLaunch ComfyUI with: python main.py --medvram   for best balance of speed/VRAM"],"color":"#1a1a2e","bgcolor":"#16213e"},{"id":2,"type":"Note","pos":[20,470],"size":{"0":1360,"1":560},"flags":{},"order":0,"mode":0,"properties":{"Node name for S&R":"Note"},"widgets_values":["SECTION 1  LoRA TRAINING REFERENCE\n\nLoRA training happens OUTSIDE ComfyUI using Kohya_ss SD-Scripts.\nThis section gives you the recommended settings for your RTX 3070 Ti.\n\n\n INSTALL KOHYA_SS: https://github.com/bmaltais/kohya_ss\n   OR use the simpler EveryDream2 trainer for beginners.\n\n RECOMMENDED TRAINING SETTINGS (RTX 3070 Ti, 8GB VRAM):\n\n   Base Model:          SD 1.5 (NOT SDXL  too heavy for 8GB training)\n   Network Type:        LoRA\n   Network Rank (dim):  16 to 32  (16 = smaller file, 32 = more detail. Start with 16)\n   Network Alpha:       8 to 16   (usually half of rank. Start with 8)\n   Resolution:          512x512   (safe for 8GB VRAM. Never exceed 768x768 for training)\n   Batch Size:          1         (IMPORTANT: keep at 1 for 8GB VRAM. Never go higher)\n   Learning Rate:       0.0001    (1e-4 for LoRA. Safe default for beginners)\n   Text Encoder LR:     0.00005   (5e-5. Half of main LR is safe)\n   Scheduler:           cosine_with_restarts\n   Optimizer:           AdamW8bit  (IMPORTANT: use 8-bit Adam to save VRAM)\n   Steps/Epochs:        10-15 epochs OR ~1500-3000 steps for ~100 training images\n   Training Images:     20-50 high quality images minimum. 100+ for best results.\n   Repeats:             10-20 repeats per image (so total steps = images  repeats  epochs)\n   Mixed Precision:     fp16  (saves VRAM significantly)\n   Save every N epochs: 1     (so you can test intermediate checkpoints)\n   Clip Skip:           2     (for anime style) or 1 (for realistic)\n\n TRAINING IMAGE TIPS:\n    Crop all images to 512x512 (use Birme.net for batch cropping)\n    Write a caption .txt file for each image (use WD14 tagger for auto-captions)\n    Use a trigger word in every caption: e.g. 'mycharacter, woman, red hair, ...'\n    Remove unwanted words from captions that describe the style you're learning\n\n PLACE TRAINED LoRA: Copy output .safetensors to ComfyUI/models/loras/\n   Then use it in SECTION 4 of this workflow!\n\n NOTE: LoRA training is NOT done inside ComfyUI nodes. Use Kohya_ss GUI separately.\n   The ComfyUI nodes below are for USING LoRAs, not training them."],"color":"#16213e","bgcolor":"#1a2a4a"},{"id":10,"type":"CheckpointLoaderSimple","pos":[20,1120],"size":{"0":315,"1":98},"flags":{},"order":1,"mode":0,"outputs":[{"name":"MODEL","type":"MODEL","links":[101],"slot_index":0},{"name":"CLIP","type":"CLIP","links":[102,103],"slot_index":1},{"name":"VAE","type":"VAE","links":[104],"slot_index":2}],"properties":{"Node name for S&R":"CheckpointLoaderSimple"},"widgets_values":["realisticVisionV60B1_v51VAE.safetensors"],"color":"#222","bgcolor":"#333","title":"[S2-STEP1] Load Checkpoint Model"},{"id":11,"type":"Note","pos":[20,1080],"size":{"0":600,"1":30},"flags":{},"order":0,"mode":0,"properties":{"Node name for S&R":"Note"},"widgets_values":["SECTION 2 START: FaceSwap + Text Prompting  Run nodes top to bottom in the order labeled [S2-STEP1] through [S2-STEP8]"],"color":"#0f3460","bgcolor":"#1a4a80"},{"id":12,"type":"CLIPTextEncode","pos":[355,1120],"size":{"0":425,"1":180},"flags":{},"order":5,"mode":0,"inputs":[{"name":"clip","type":"CLIP","link":102}],"outputs":[{"name":"CONDITIONING","type":"CONDITIONING","links":[105],"slot_index":0}],"properties":{"Node name for S&R":"CLIPTextEncode"},"widgets_values":["beautiful woman, 30 years old, professional portrait, studio lighting, sharp focus, high quality, 8k photo, realistic skin texture, elegant"],"color":"#1a4400","bgcolor":"#234d00","title":"[S2-STEP2] POSITIVE PROMPT  Describe what you want to generate here"},{"id":13,"type":"CLIPTextEncode","pos":[355,1320],"size":{"0":425,"1":180},"flags":{},"order":6,"mode":0,"inputs":[{"name":"clip","type":"CLIP","link":103}],"outputs":[{"name":"CONDITIONING","type":"CONDITIONING","links":[106],"slot_index":0}],"properties":{"Node name for S&R":"CLIPTextEncode"},"widgets_values":["ugly, deformed, blurry, bad anatomy, extra fingers, mutated hands, watermark, signature, low quality, worst quality, jpeg artifacts, duplicate, morbid, poorly drawn face, bad proportions"],"color":"#440000","bgcolor":"#6b0000","title":"[S2-STEP3] NEGATIVE PROMPT  What to AVOID. These are safe defaults, don't change unless needed"},{"id":14,"type":"EmptyLatentImage","pos":[800,1120],"size":{"0":315,"1":106},"flags":{},"order":2,"mode":0,"outputs":[{"name":"LATENT","type":"LATENT","links":[107],"slot_index":0}],"properties":{"Node name for S&R":"EmptyLatentImage"},"widgets_values":[512,768,1],"color":"#333","bgcolor":"#444","title":"[S2-STEP4] Image Size  512x768 = portrait. 512x512 = square. Keep width+height  768 for 8GB VRAM"},{"id":15,"type":"KSampler","pos":[800,1280],"size":{"0":315,"1":474},"flags":{},"order":7,"mode":0,"inputs":[{"name":"model","type":"MODEL","link":101},{"name":"positive","type":"CONDITIONING","link":105},{"name":"negative","type":"CONDITIONING","link":106},{"name":"latent_image","type":"LATENT","link":107}],"outputs":[{"name":"LATENT","type":"LATENT","links":[108],"slot_index":0}],"properties":{"Node name for S&R":"KSampler"},"widgets_values":[42,"fixed",20,7,"euler","normal",1.0],"color":"#333","bgcolor":"#444","title":"[S2-STEP5] KSampler  steps=20 (quality/speed balance). cfg=7 (creativity). seed=42 (change for variety)"},{"id":16,"type":"VAEDecode","pos":[1150,1280],"size":{"0":140,"1":46},"flags":{},"order":8,"mode":0,"inputs":[{"name":"samples","type":"LATENT","link":108},{"name":"vae","type":"VAE","link":104}],"outputs":[{"name":"IMAGE","type":"IMAGE","links":[109],"slot_index":0}],"properties":{"Node name for S&R":"VAEDecode"},"color":"#333","bgcolor":"#444","title":"[S2-STEP6] VAE Decode  Converts AI latent data into a viewable image"},{"id":17,"type":"LoadImage","pos":[1150,1120],"size":{"0":315,"1":314},"flags":{},"order":0,"mode":0,"outputs":[{"name":"IMAGE","type":"IMAGE","links":[110],"slot_index":0},{"name":"MASK","type":"MASK","links":null,"slot_index":1}],"properties":{"Node name for S&R":"LoadImage"},"widgets_values":["your_face_reference.jpg","image"],"color":"#333","bgcolor":"#444","title":"[S2-STEP7] Load Face Image  Upload your face reference photo here. Use a clear front-facing photo!"},{"id":18,"type":"ReActorFaceSwap","pos":[1500,1120],"size":{"0":315,"1":338},"flags":{},"order":9,"mode":0,"inputs":[{"name":"input_image","type":"IMAGE","link":109},{"name":"source_image","type":"IMAGE","link":110},{"name":"face_model","type":"FACE_MODEL","link":null}],"outputs":[{"name":"IMAGE","type":"IMAGE","links":[111],"slot_index":0},{"name":"FACE_MODEL","type":"FACE_MODEL","links":null,"slot_index":1}],"properties":{"Node name for S&R":"ReActorFaceSwap"},"widgets_values":[true,"inswapper_128.onnx","YOLOv5l","codeformer.pth",1,0.7,"no","no","0","0",1],"color":"#2a1a4a","bgcolor":"#3d2a6b","title":"[S2-STEP8] ReActor FaceSwap  Requires ReActor custom node + inswapper_128.onnx model"},{"id":19,"type":"SaveImage","pos":[1850,1120],"size":{"0":420,"1":440},"flags":{},"order":10,"mode":0,"inputs":[{"name":"images","type":"IMAGE","link":111}],"properties":{"Node name for S&R":"SaveImage"},"widgets_values":["S2_FaceSwap_Output"],"color":"#1a3a1a","bgcolor":"#2a5a2a","title":"[S2-STEP9] Save Image  Output saved to ComfyUI/output/S2_FaceSwap_Output/"},{"id":20,"type":"Note","pos":[20,1850],"size":{"0":600,"1":30},"flags":{},"order":0,"mode":0,"properties":{"Node name for S&R":"Note"},"widgets_values":["SECTION 3: FaceSwap + Pose Reference  This adds OpenPose ControlNet. Upload a pose reference image, extract the skeleton, then generate + swap face. Follow [S3-STEP1] through [S3-STEP10]"],"color":"#162032","bgcolor":"#1e3048"},{"id":21,"type":"CheckpointLoaderSimple","pos":[20,1900],"size":{"0":315,"1":98},"flags":{},"order":1,"mode":0,"outputs":[{"name":"MODEL","type":"MODEL","links":[120,121],"slot_index":0},{"name":"CLIP","type":"CLIP","links":[122,123],"slot_index":1},{"name":"VAE","type":"VAE","links":[124],"slot_index":2}],"properties":{"Node name for S&R":"CheckpointLoaderSimple"},"widgets_values":["realisticVisionV60B1_v51VAE.safetensors"],"color":"#222","bgcolor":"#333","title":"[S3-STEP1] Load Checkpoint  Same model as Section 2. Change to your preferred model."},{"id":22,"type":"LoadImage","pos":[20,2030],"size":{"0":315,"1":314},"flags":{},"order":0,"mode":0,"outputs":[{"name":"IMAGE","type":"IMAGE","links":[125],"slot_index":0},{"name":"MASK","type":"MASK","links":null,"slot_index":1}],"properties":{"Node name for S&R":"LoadImage"},"widgets_values":["pose_reference_photo.jpg","image"],"color":"#333","bgcolor":"#444","title":"[S3-STEP2] Load Pose Reference Image  Upload a photo with the pose you want to mimic"},{"id":23,"type":"DWPreprocessor","pos":[360,2030],"size":{"0":315,"1":150},"flags":{},"order":3,"mode":0,"inputs":[{"name":"image","type":"IMAGE","link":125}],"outputs":[{"name":"IMAGE","type":"IMAGE","links":[126],"slot_index":0},{"name":"POSE_KEYPOINT","type":"POSE_KEYPOINT","links":null,"slot_index":1}],"properties":{"Node name for S&R":"DWPreprocessor"},"widgets_values":["enable","enable","enable",512,768],"color":"#1a3a4a","bgcolor":"#2a5a6b","title":"[S3-STEP3] DWPose Preprocessor  Extracts skeleton/pose from your reference image (from comfyui_controlnet_aux)"},{"id":24,"type":"PreviewImage","pos":[360,2200],"size":{"0":315,"1":250},"flags":{},"order":4,"mode":0,"inputs":[{"name":"images","type":"IMAGE","link":126}],"properties":{"Node name for S&R":"PreviewImage"},"title":"[S3-STEP4] Preview Pose  Check that pose skeleton looks correct before generating"},{"id":25,"type":"ControlNetLoader","pos":[700,1900],"size":{"0":315,"1":58},"flags":{},"order":0,"mode":0,"outputs":[{"name":"CONTROL_NET","type":"CONTROL_NET","links":[127],"slot_index":0}],"properties":{"Node name for S&R":"ControlNetLoader"},"widgets_values":["control_v11p_sd15_openpose.pth"],"color":"#1a3a4a","bgcolor":"#2a5a6b","title":"[S3-STEP5] ControlNet Loader  Load the OpenPose ControlNet model. File goes in ComfyUI/models/controlnet/"},{"id":26,"type":"CLIPTextEncode","pos":[700,1980],"size":{"0":425,"1":180},"flags":{},"order":5,"mode":0,"inputs":[{"name":"clip","type":"CLIP","link":122}],"outputs":[{"name":"CONDITIONING","type":"CONDITIONING","links":[128],"slot_index":0}],"properties":{"Node name for S&R":"CLIPTextEncode"},"widgets_values":["beautiful woman, full body shot, professional photography, high quality, sharp focus, cinematic lighting, elegant clothing"],"color":"#1a4400","bgcolor":"#234d00","title":"[S3-STEP6] Positive Prompt  Describe your desired image. The pose will come from the reference."},{"id":27,"type":"CLIPTextEncode","pos":[700,2180],"size":{"0":425,"1":180},"flags":{},"order":6,"mode":0,"inputs":[{"name":"clip","type":"CLIP","link":123}],"outputs":[{"name":"CONDITIONING","type":"CONDITIONING","links":[129],"slot_index":0}],"properties":{"Node name for S&R":"CLIPTextEncode"},"widgets_values":["ugly, deformed, blurry, bad anatomy, extra fingers, mutated hands, watermark, signature, low quality, worst quality, jpeg artifacts, missing limbs"],"color":"#440000","bgcolor":"#6b0000","title":"[S3-STEP7] Negative Prompt  Prevents bad results. Keep these defaults."},{"id":28,"type":"ControlNetApplyAdvanced","pos":[1150,1900],"size":{"0":315,"1":230},"flags":{},"order":7,"mode":0,"inputs":[{"name":"positive","type":"CONDITIONING","link":128},{"name":"negative","type":"CONDITIONING","link":129},{"name":"control_net","type":"CONTROL_NET","link":127},{"name":"image","type":"IMAGE","link":126}],"outputs":[{"name":"positive","type":"CONDITIONING","links":[130],"slot_index":0},{"name":"negative","type":"CONDITIONING","links":[131],"slot_index":1}],"properties":{"Node name for S&R":"ControlNetApplyAdvanced"},"widgets_values":[1.0,0.0,1.0],"color":"#1a3a4a","bgcolor":"#2a5a6b","title":"[S3-STEP8] Apply ControlNet  strength=1.0 (full pose control). Lower to 0.7 for looser interpretation."},{"id":29,"type":"EmptyLatentImage","pos":[1150,2150],"size":{"0":315,"1":106},"flags":{},"order":2,"mode":0,"outputs":[{"name":"LATENT","type":"LATENT","links":[132],"slot_index":0}],"properties":{"Node name for S&R":"EmptyLatentImage"},"widgets_values":[512,768,1],"color":"#333","bgcolor":"#444","title":"[S3] Image Size  Match this to your pose reference aspect ratio (512x768 for portrait)"},{"id":30,"type":"KSampler","pos":[1500,1900],"size":{"0":315,"1":474},"flags":{},"order":8,"mode":0,"inputs":[{"name":"model","type":"MODEL","link":120},{"name":"positive","type":"CONDITIONING","link":130},{"name":"negative","type":"CONDITIONING","link":131},{"name":"latent_image","type":"LATENT","link":132}],"outputs":[{"name":"LATENT","type":"LATENT","links":[133],"slot_index":0}],"properties":{"Node name for S&R":"KSampler"},"widgets_values":[123,"fixed",25,7.5,"dpmpp_2m","karras",1.0],"color":"#333","bgcolor":"#444","title":"[S3] KSampler  steps=25 (more quality for complex pose), dpmpp_2m+karras is good for realism"},{"id":31,"type":"VAEDecode","pos":[1850,1900],"size":{"0":140,"1":46},"flags":{},"order":9,"mode":0,"inputs":[{"name":"samples","type":"LATENT","link":133},{"name":"vae","type":"VAE","link":124}],"outputs":[{"name":"IMAGE","type":"IMAGE","links":[134],"slot_index":0}],"properties":{"Node name for S&R":"VAEDecode"},"title":"[S3] VAE Decode"},{"id":32,"type":"LoadImage","pos":[1850,1970],"size":{"0":315,"1":314},"flags":{},"order":0,"mode":0,"outputs":[{"name":"IMAGE","type":"IMAGE","links":[135],"slot_index":0},{"name":"MASK","type":"MASK","links":null,"slot_index":1}],"properties":{"Node name for S&R":"LoadImage"},"widgets_values":["your_face_reference.jpg","image"],"color":"#333","bgcolor":"#444","title":"[S3-STEP9] Load Face  Same face reference as Section 2, or a different one"},{"id":33,"type":"ReActorFaceSwap","pos":[2000,1900],"size":{"0":315,"1":338},"flags":{},"order":10,"mode":0,"inputs":[{"name":"input_image","type":"IMAGE","link":134},{"name":"source_image","type":"IMAGE","link":135},{"name":"face_model","type":"FACE_MODEL","link":null}],"outputs":[{"name":"IMAGE","type":"IMAGE","links":[136],"slot_index":0},{"name":"FACE_MODEL","type":"FACE_MODEL","links":null,"slot_index":1}],"properties":{"Node name for S&R":"ReActorFaceSwap"},"widgets_values":[true,"inswapper_128.onnx","YOLOv5l","codeformer.pth",1,0.7,"no","no","0","0",1],"color":"#2a1a4a","bgcolor":"#3d2a6b","title":"[S3-STEP10] ReActor FaceSwap  Applies your face to the pose-controlled generated image"},{"id":34,"type":"SaveImage","pos":[2200,1900],"size":{"0":420,"1":440},"flags":{},"order":11,"mode":0,"inputs":[{"name":"images","type":"IMAGE","link":136}],"properties":{"Node name for S&R":"SaveImage"},"widgets_values":["S3_PoseFaceSwap_Output"],"color":"#1a3a1a","bgcolor":"#2a5a2a","title":"[S3] Save  Output saved to ComfyUI/output/S3_PoseFaceSwap_Output/"},{"id":40,"type":"Note","pos":[20,2650],"size":{"0":600,"1":30},"flags":{},"order":0,"mode":0,"properties":{"Node name for S&R":"Note"},"widgets_values":["SECTION 4: LoRA Usage (Text-to-Image)   BEST PLACE TO START! Simple and reliable. Follow [S4-STEP1] through [S4-STEP7]"],"color":"#1b2838","bgcolor":"#2a3f55"},{"id":41,"type":"CheckpointLoaderSimple","pos":[20,2700],"size":{"0":315,"1":98},"flags":{},"order":1,"mode":0,"outputs":[{"name":"MODEL","type":"MODEL","links":[150],"slot_index":0},{"name":"CLIP","type":"CLIP","links":[151,152],"slot_index":1},{"name":"VAE","type":"VAE","links":[153],"slot_index":2}],"properties":{"Node name for S&R":"CheckpointLoaderSimple"},"widgets_values":["dreamshaper_8.safetensors"],"color":"#222","bgcolor":"#333","title":"[S4-STEP1] Load Base Model  File goes in ComfyUI/models/checkpoints/. Try dreamshaper_8 or realisticVision."},{"id":42,"type":"LoraLoader","pos":[20,2820],"size":{"0":315,"1":126},"flags":{},"order":3,"mode":0,"inputs":[{"name":"model","type":"MODEL","link":150},{"name":"clip","type":"CLIP","link":151}],"outputs":[{"name":"MODEL","type":"MODEL","links":[154],"slot_index":0},{"name":"CLIP","type":"CLIP","links":[155],"slot_index":1}],"properties":{"Node name for S&R":"LoraLoader"},"widgets_values":["your_lora_file.safetensors",0.8,0.8],"color":"#2a1a4a","bgcolor":"#3d2a6b","title":"[S4-STEP2] LoRA Loader   Place LoRA in ComfyUI/models/loras/ then select here. strength=0.8 is safe default. Lower for subtlety."},{"id":43,"type":"Note","pos":[345,2820],"size":{"0":350,"1":126},"flags":{},"order":0,"mode":0,"properties":{"Node name for S&R":"Note"},"widgets_values":["LoRA TIPS:\n Add more LoraLoader nodes for multiple LoRAs\n Keep total LoRA strength  1.5 combined\n Use trigger words in your positive prompt\n Strength 0.5-0.9 is the sweet spot\n You can chain: ModelLoRA1LoRA2LoRA3"],"color":"#2a1a4a","bgcolor":"#3d2a6b"},{"id":44,"type":"CLIPTextEncode","pos":[700,2700],"size":{"0":425,"1":200},"flags":{},"order":5,"mode":0,"inputs":[{"name":"clip","type":"CLIP","link":155}],"outputs":[{"name":"CONDITIONING","type":"CONDITIONING","links":[156],"slot_index":0}],"properties":{"Node name for S&R":"CLIPTextEncode"},"widgets_values":["YOUR_LORA_TRIGGER_WORD, masterpiece, best quality, 1girl, beautiful face, detailed eyes, photorealistic, professional photography, soft lighting, bokeh background"],"color":"#1a4400","bgcolor":"#234d00","title":"[S4-STEP3] Positive Prompt   IMPORTANT: Add your LoRA trigger word at the start!"},{"id":45,"type":"CLIPTextEncode","pos":[700,2920],"size":{"0":425,"1":180},"flags":{},"order":6,"mode":0,"inputs":[{"name":"clip","type":"CLIP","link":152}],"outputs":[{"name":"CONDITIONING","type":"CONDITIONING","links":[157],"slot_index":0}],"properties":{"Node name for S&R":"CLIPTextEncode"},"widgets_values":["ugly, deformed, blurry, bad anatomy, watermark, signature, low quality, worst quality, poorly drawn face, extra limbs, text, cropped"],"color":"#440000","bgcolor":"#6b0000","title":"[S4-STEP4] Negative Prompt  Keeps outputs clean. Use with embedding:badhandv4 if you have it."},{"id":46,"type":"EmptyLatentImage","pos":[1150,2700],"size":{"0":315,"1":106},"flags":{},"order":2,"mode":0,"outputs":[{"name":"LATENT","type":"LATENT","links":[158],"slot_index":0}],"properties":{"Node name for S&R":"EmptyLatentImage"},"widgets_values":[512,512,1],"color":"#333","bgcolor":"#444","title":"[S4-STEP5] Image Size  512x512 recommended. Use 512x768 for portrait. Max 768x768 on 8GB VRAM"},{"id":47,"type":"KSampler","pos":[1150,2820],"size":{"0":315,"1":474},"flags":{},"order":7,"mode":0,"inputs":[{"name":"model","type":"MODEL","link":154},{"name":"positive","type":"CONDITIONING","link":156},{"name":"negative","type":"CONDITIONING","link":157},{"name":"latent_image","type":"LATENT","link":158}],"outputs":[{"name":"LATENT","type":"LATENT","links":[159],"slot_index":0}],"properties":{"Node name for S&R":"KSampler"},"widgets_values":[42,"randomize",20,7,"euler","normal",1.0],"color":"#333","bgcolor":"#444","title":"[S4-STEP6] KSampler  seed=randomize (new image each time). steps=20 is good. cfg=7 is balanced."},{"id":48,"type":"VAEDecode","pos":[1500,2820],"size":{"0":140,"1":46},"flags":{},"order":8,"mode":0,"inputs":[{"name":"samples","type":"LATENT","link":159},{"name":"vae","type":"VAE","link":153}],"outputs":[{"name":"IMAGE","type":"IMAGE","links":[160],"slot_index":0}],"properties":{"Node name for S&R":"VAEDecode"},"title":"[S4] VAE Decode"},{"id":49,"type":"SaveImage","pos":[1500,2880],"size":{"0":420,"1":440},"flags":{},"order":9,"mode":0,"inputs":[{"name":"images","type":"IMAGE","link":160}],"properties":{"Node name for S&R":"SaveImage"},"widgets_values":["S4_LoRA_Output"],"color":"#1a3a1a","bgcolor":"#2a5a2a","title":"[S4-STEP7] Save Image  Saved to ComfyUI/output/S4_LoRA_Output/"},{"id":50,"type":"Note","pos":[20,3300],"size":{"0":600,"1":60},"flags":{},"order":0,"mode":0,"properties":{"Node name for S&R":"Note"},"widgets_values":["SECTION 5: GIF / Animation (AnimateDiff)  Creates short looping GIFs. Requires ComfyUI-AnimateDiff-Evolved + VideoHelperSuite.\n VRAM NOTE: Keep frames=16 max. Use 512x512 only. This is the most VRAM-intensive section."],"color":"#1a0533","bgcolor":"#2a0a4a"},{"id":51,"type":"CheckpointLoaderSimple","pos":[20,3390],"size":{"0":315,"1":98},"flags":{},"order":1,"mode":0,"outputs":[{"name":"MODEL","type":"MODEL","links":[170],"slot_index":0},{"name":"CLIP","type":"CLIP","links":[171,172],"slot_index":1},{"name":"VAE","type":"VAE","links":[173],"slot_index":2}],"properties":{"Node name for S&R":"CheckpointLoaderSimple"},"widgets_values":["dreamshaper_8.safetensors"],"color":"#222","bgcolor":"#333","title":"[S5-STEP1] Load Model  Use SD 1.5 based models only (dreamshaper_8, realisticVision, etc). NO SDXL!"},{"id":52,"type":"ADE_AnimateDiffLoaderGen1","pos":[20,3510],"size":{"0":315,"1":222},"flags":{},"order":4,"mode":0,"inputs":[{"name":"model","type":"MODEL","link":170},{"name":"context_options","type":"CONTEXT_OPTIONS","link":null},{"name":"motion_lora","type":"MOTION_LORA","link":null},{"name":"ad_settings","type":"AD_SETTINGS","link":null},{"name":"ad_keyframes","type":"AD_KEYFRAMES","link":null},{"name":"sample_settings","type":"SAMPLE_SETTINGS","link":null},{"name":"scale_multival","type":"MULTIVAL","link":null},{"name":"effect_multival","type":"MULTIVAL","link":null}],"outputs":[{"name":"MODEL","type":"MODEL","links":[174],"slot_index":0}],"properties":{"Node name for S&R":"ADE_AnimateDiffLoaderGen1"},"widgets_values":["mm_sd_v15_v2.ckpt","sqrt_linear (AnimateDiff)"],"color":"#330a5e","bgcolor":"#4a1080","title":"[S5-STEP2] AnimateDiff Loader  Load motion model. Place in AnimateDiff-Evolved/models/. 'mm_sd_v15_v2.ckpt' is recommended."},{"id":53,"type":"CLIPTextEncode","pos":[360,3390],"size":{"0":425,"1":180},"flags":{},"order":5,"mode":0,"inputs":[{"name":"clip","type":"CLIP","link":171}],"outputs":[{"name":"CONDITIONING","type":"CONDITIONING","links":[175],"slot_index":0}],"properties":{"Node name for S&R":"CLIPTextEncode"},"widgets_values":["beautiful woman walking in a flower garden, flowing dress, golden hour lighting, cinematic, smooth animation, high quality"],"color":"#1a4400","bgcolor":"#234d00","title":"[S5-STEP3] Positive Prompt  Describe the scene. Include motion words like 'walking', 'flowing', 'waving'."},{"id":54,"type":"CLIPTextEncode","pos":[360,3590],"size":{"0":425,"1":180},"flags":{},"order":6,"mode":0,"inputs":[{"name":"clip","type":"CLIP","link":172}],"outputs":[{"name":"CONDITIONING","type":"CONDITIONING","links":[176],"slot_index":0}],"properties":{"Node name for S&R":"CLIPTextEncode"},"widgets_values":["ugly, deformed, blurry, watermark, bad quality, static, frozen, flickering, jittery motion, worst quality, low quality"],"color":"#440000","bgcolor":"#6b0000","title":"[S5-STEP4] Negative Prompt  'static, frozen, flickering' helps AnimateDiff produce smoother motion"},{"id":55,"type":"EmptyLatentImage","pos":[800,3390],"size":{"0":315,"1":106},"flags":{},"order":2,"mode":0,"outputs":[{"name":"LATENT","type":"LATENT","links":[177],"slot_index":0}],"properties":{"Node name for S&R":"EmptyLatentImage"},"widgets_values":[512,512,16],"color":"#333","bgcolor":"#444","title":"[S5-STEP5] Frame Canvas  Width=512, Height=512, Batch=16 frames.  MAX 16 frames on 8GB VRAM! Use 8 frames if you get OOM errors."},{"id":56,"type":"KSampler","pos":[800,3520],"size":{"0":315,"1":474},"flags":{},"order":7,"mode":0,"inputs":[{"name":"model","type":"MODEL","link":174},{"name":"positive","type":"CONDITIONING","link":175},{"name":"negative","type":"CONDITIONING","link":176},{"name":"latent_image","type":"LATENT","link":177}],"outputs":[{"name":"LATENT","type":"LATENT","links":[178],"slot_index":0}],"properties":{"Node name for S&R":"KSampler"},"widgets_values":[42,"fixed",20,7,"euler","normal",1.0],"color":"#333","bgcolor":"#444","title":"[S5-STEP6] KSampler  steps=20 is recommended for AnimateDiff. More steps = slower but smoother."},{"id":57,"type":"VAEDecode","pos":[1150,3520],"size":{"0":140,"1":46},"flags":{},"order":8,"mode":0,"inputs":[{"name":"samples","type":"LATENT","link":178},{"name":"vae","type":"VAE","link":173}],"outputs":[{"name":"IMAGE","type":"IMAGE","links":[179],"slot_index":0}],"properties":{"Node name for S&R":"VAEDecode"},"title":"[S5] VAE Decode  Converts all 16 frames from latent to image"},{"id":58,"type":"ADE_AnimateDiffCombine","pos":[1320,3390],"size":{"0":315,"1":300},"flags":{},"order":9,"mode":0,"inputs":[{"name":"images","type":"IMAGE","link":179}],"outputs":[{"name":"GIF","type":"GIF","links":null,"slot_index":0}],"properties":{"Node name for S&R":"ADE_AnimateDiffCombine"},"widgets_values":[8,0,true,"S5_Animation_Output","image/gif",true],"color":"#330a5e","bgcolor":"#4a1080","title":"[S5-STEP7] Combine Frames to GIF  fps=8 (smooth enough). Output saved to ComfyUI/output/. Try fps=12 for smoother GIFs."},{"id":59,"type":"Note","pos":[1320,3720],"size":{"0":400,"1":200},"flags":{},"order":0,"mode":0,"properties":{"Node name for S&R":"Note"},"widgets_values":["AnimateDiff Settings Guide:\n\n frames=8: Fast, low VRAM, choppy\n frames=16: Good balance  (recommended)\n frames=24: High VRAM risk on 8GB\n\n fps=8: Smooth enough for most GIFs\n fps=12: Smoother but larger file\n\n If you get Out of Memory:\n   Reduce to 8 frames\n   Reduce to 512x512\n   Close other apps\n   Add --lowvram launch flag\n\n Motion LoRAs (PanLeft, ZoomIn, etc.)\n  go in AnimateDiff-Evolved/loras/"],"color":"#1a0533","bgcolor":"#2a0a4a"},{"id":60,"type":"Note","pos":[1650,2700],"size":{"0":350,"1":400},"flags":{},"order":0,"mode":0,"properties":{"Node name for S&R":"Note"},"widgets_values":["KSampler Quick Reference:\n\nSEED:\n Fixed = same image each time\n Randomize = new image each time\n\nSTEPS:\n 15 = fast but lower quality\n 20 = good balance \n 30 = slower but more detail\n\nCFG SCALE:\n 5-6 = more creative/loose\n 7-8 = balanced \n 10-12 = very prompt-adherent\n\nSAMPLER + SCHEDULER:\n euler + normal = fast, good \n dpmpp_2m + karras = high quality\n dpmpp_sde + karras = detailed\n\nDENOISE:\n 1.0 = full generation (txt2img)\n 0.5-0.8 = img2img variation"],"color":"#1b2838","bgcolor":"#2a3f55"}],"links":[[101,10,0,15,0,"MODEL"],[102,10,1,12,0,"CLIP"],[103,10,1,13,0,"CLIP"],[104,10,2,16,1,"VAE"],[105,12,0,15,1,"CONDITIONING"],[106,13,0,15,2,"CONDITIONING"],[107,14,0,15,3,"LATENT"],[108,15,0,16,0,"LATENT"],[109,16,0,18,0,"IMAGE"],[110,17,0,18,1,"IMAGE"],[111,18,0,19,0,"IMAGE"],[120,21,0,30,0,"MODEL"],[121,21,0,28,0,"MODEL"],[122,21,1,26,0,"CLIP"],[123,21,1,27,0,"CLIP"],[124,21,2,31,1,"VAE"],[125,22,0,23,0,"IMAGE"],[126,23,0,24,0,"IMAGE"],[127,25,0,28,2,"CONTROL_NET"],[128,26,0,28,0,"CONDITIONING"],[129,27,0,28,1,"CONDITIONING"],[130,28,0,30,1,"CONDITIONING"],[131,28,1,30,2,"CONDITIONING"],[132,29,0,30,3,"LATENT"],[133,30,0,31,0,"LATENT"],[134,31,0,33,0,"IMAGE"],[135,32,0,33,1,"IMAGE"],[136,33,0,34,0,"IMAGE"],[150,41,0,42,0,"MODEL"],[151,41,1,42,1,"CLIP"],[152,41,1,45,0,"CLIP"],[153,41,2,48,1,"VAE"],[154,42,0,47,0,"MODEL"],[155,42,1,44,0,"CLIP"],[156,44,0,47,1,"CONDITIONING"],[157,45,0,47,2,"CONDITIONING"],[158,46,0,47,3,"LATENT"],[159,47,0,48,0,"LATENT"],[160,48,0,49,0,"IMAGE"],[170,51,0,52,0,"MODEL"],[171,51,1,53,0,"CLIP"],[172,51,1,54,0,"CLIP"],[173,51,2,57,1,"VAE"],[174,52,0,56,0,"MODEL"],[175,53,0,56,1,"CONDITIONING"],[176,54,0,56,2,"CONDITIONING"],[177,55,0,56,3,"LATENT"],[178,56,0,57,0,"LATENT"],[179,57,0,58,0,"IMAGE"]],"config":{},"extra":{"ds":{"scale":0.5,"offset":[0,0]},"groupNodes":{}},"version":0.4}
'@

    $wfDir = Join-Path $ComfyDir 'user\default\workflows'
    if (-not (Test-Path $wfDir)) { New-Item -ItemType Directory $wfDir -Force | Out-Null }
    Set-Content (Join-Path $wfDir  'RTX3070Ti_Master_Workflow.json') $wf -Encoding UTF8
    Set-Content (Join-Path $Root   'ComfyUI_Workflow.json')          $wf -Encoding UTF8
    OK 'Workflow JSON saved to ComfyUI and root folder.'

    # ── Launchers ──────────────────────────────────────────────────────────
    Set-Content (Join-Path $Root 'Launch-ComfyUI.bat') -Encoding ASCII @"
@echo off
title ComfyUI
color 0B
echo.
echo  ComfyUI -- RTX 3070 Ti
echo  Opens at http://127.0.0.1:8188
echo  If you get memory errors use Launch-ComfyUI-LowVRAM.bat
echo.
cd /d "$ComfyDir"
"$VenvPy" main.py --medvram --auto-launch
echo.
echo  Closed. Press any key.
pause >nul
"@

    Set-Content (Join-Path $Root 'Launch-ComfyUI-LowVRAM.bat') -Encoding ASCII @"
@echo off
title ComfyUI LowVRAM
color 0E
echo.
echo  ComfyUI -- LOW VRAM MODE
echo  Slower but uses less VRAM. Use if you get errors.
echo.
cd /d "$ComfyDir"
"$VenvPy" main.py --lowvram --auto-launch
echo.
echo  Closed. Press any key.
pause >nul
"@

    Set-Content (Join-Path $Root 'Setup-Kohya-FirstTime.bat') -Encoding ASCII @"
@echo off
title Kohya_ss Setup
color 0C
echo.
echo  KOHYA_SS FIRST-TIME SETUP -- Run this ONCE
echo  ------------------------------------------
echo  When asked about Accelerate:
echo    Compute: This machine
echo    GPU:     NVIDIA CUDA
echo    Precision: fp16
echo    Everything else: press ENTER
echo.
pause
cd /d "$KohyaDir"
call setup.bat
pause
"@

    Set-Content (Join-Path $Root 'Launch-Kohya-Trainer.bat') -Encoding ASCII @"
@echo off
title Kohya_ss
color 0D
echo.
echo  Kohya_ss LoRA Trainer
echo  First time? Run Setup-Kohya-FirstTime.bat first!
echo.
cd /d "$KohyaDir"
if exist "venv\Scripts\activate.bat" call venv\Scripts\activate.bat
if exist "gui.bat" (
    call gui.bat --listen 127.0.0.1 --server_port 7860 --inbrowser
) else (
    call setup.bat
)
pause
"@

    # ── START_HERE.txt ─────────────────────────────────────────────────────
    Set-Content (Join-Path $Root 'START_HERE.txt') -Encoding UTF8 @"
ComfyUI AI Studio -- RTX 3070 Ti
=================================
Installed to: $Root

HOW TO START
------------
1. Double-click  Launch-ComfyUI.bat  (on Desktop or in this folder)
2. Browser opens at http://127.0.0.1:8188
3. Your workflow is already there -- look in the workflows menu
   or drag ComfyUI_Workflow.json from this folder into ComfyUI
4. Start with Section 4 (LoRA Usage) -- the simplest one

MODELS STILL NEEDED (download manually)
-----------------------------------------
$ComfyDir\models\checkpoints\
  dreamshaper_8.safetensors           civitai.com
  realisticVisionV60B1_v51VAE.safetensors  civitai.com

$ComfyDir\models\vae\
  vae-ft-mse-840000-ema-pruned.safetensors  huggingface.co

$ComfyDir\models\controlnet\
  control_v11p_sd15_openpose.pth      huggingface.co/lllyasviel

$ComfyDir\models\insightface\
  inswapper_128.onnx                  github.com/Gourieff/ComfyUI-ReActor

$ComfyDir\models\facerestore_models\
  codeformer.pth                      github.com/sczhou/CodeFormer

$ComfyDir\custom_nodes\ComfyUI-AnimateDiff-Evolved\models\
  mm_sd_v15_v2.ckpt                   huggingface.co/guoyww

See HOW_TO_USE.txt in each folder for direct download links.

LORA TRAINING
-------------
1. Run Setup-Kohya-FirstTime.bat  (once only)
2. Run Launch-Kohya-Trainer.bat
3. Training images go in: $Root\LoRA_Training\dataset\
4. Copy finished .safetensors to: $ComfyDir\models\loras\

VRAM TIPS
---------
Normal use    : Launch-ComfyUI.bat          (--medvram)
Memory errors : Launch-ComfyUI-LowVRAM.bat  (--lowvram)
Resolution    : always 512x512 or 512x768
Batch size    : always 1
AnimateDiff   : max 16 frames at 512x512
"@

    # ── Desktop shortcuts ──────────────────────────────────────────────────
    try {
        $wsh  = New-Object -ComObject WScript.Shell
        $desk = [System.Environment]::GetFolderPath('Desktop')
        foreach ($lnk in @(
            @{N='Launch ComfyUI';       T=Join-Path $Root 'Launch-ComfyUI.bat'},
            @{N='Launch Kohya Trainer'; T=Join-Path $Root 'Launch-Kohya-Trainer.bat'},
            @{N='AI Studio Folder';     T=$Root}
        )) {
            $sc = $wsh.CreateShortcut((Join-Path $desk "$($lnk.N).lnk"))
            $sc.TargetPath       = $lnk.T
            $sc.WorkingDirectory = $Root
            $sc.Save()
            OK "Desktop shortcut: $($lnk.N)"
        }
    } catch { Warn "Desktop shortcuts: $_ -- launchers are in $Root" }

    OK 'All done.'
}

# ===========================================================================
#  SUMMARY
# ===========================================================================
function Show-Done {
    param([string]$Root, [string]$Mins)
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Green
    Write-Host "   DONE!  Finished in $Mins minutes."                            -ForegroundColor Green
    Write-Host '  ============================================================'  -ForegroundColor Green
    Write-Host ''
    Write-Host "   Installed to: $Root"                                           -ForegroundColor White
    Write-Host ''
    Write-Host '   NEXT STEPS:'                                                   -ForegroundColor Cyan
    Write-Host '   1. Download models -- read HOW_TO_USE.txt in each model folder' -ForegroundColor White
    Write-Host '   2. Double-click  Launch ComfyUI  on your Desktop'              -ForegroundColor White
    Write-Host '   3. The workflow is already in ComfyUI'                          -ForegroundColor White
    Write-Host '   4. LoRA training: run Setup-Kohya-FirstTime.bat first'         -ForegroundColor White
    Write-Host ''
    Write-Host '   Model files (.safetensors, .onnx, .pth) must be downloaded'   -ForegroundColor Yellow
    Write-Host '   manually -- see HOW_TO_USE.txt files in each model folder.'    -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  ============================================================'  -ForegroundColor Green
    Write-Host ''
    Hold 'Installation complete! Press ENTER to close.'
}

# ===========================================================================
#  MAIN
# ===========================================================================
function Main {
    Show-Banner

    # Admin check
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
             ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($admin) { OK 'Running as Administrator.' }
    else {
        Warn 'Not running as Administrator.'
        Warn 'Use START_INSTALLER.bat for best results.'
        Hold 'Press ENTER to continue anyway, or close window to cancel...'
    }

    $root = Pick-Root
    if (-not (Test-Path $root)) { New-Item -ItemType Directory $root -Force | Out-Null }

    # Show plan
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Cyan
    Write-Host '   INSTALLATION PLAN'                                             -ForegroundColor Cyan
    Write-Host '  ============================================================'  -ForegroundColor Cyan
    Write-Host "   Location  : $root"                                             -ForegroundColor White
    Write-Host "   ComfyUI   : $root\ComfyUI"                                    -ForegroundColor White
    Write-Host "   Kohya_ss  : $root\kohya_ss"                                   -ForegroundColor White
    Write-Host '   Python    : 3.12 venv for ComfyUI, 3.10 venv for Kohya'       -ForegroundColor White
    Write-Host '   Nodes     : Manager, ReActor, ControlNet, AnimateDiff, Video' -ForegroundColor White
    Write-Host '   Shortcuts : 3 Desktop shortcuts + .bat launchers'              -ForegroundColor White
    Write-Host '   Workflow  : Embedded -- saved automatically into ComfyUI'      -ForegroundColor White
    Write-Host ''
    Write-Host '   Estimated time: 15-30 minutes'                                  -ForegroundColor DarkCyan
    Write-Host '  ============================================================'  -ForegroundColor Cyan
    Write-Host ''
    Hold 'Press ENTER to BEGIN, or close this window to cancel...'

    $t0 = Get-Date

    Get-Git
    $venvPy   = Get-Py312   -Root $root
    $comfyDir = Get-ComfyUI -Root $root -VenvPy $venvPy
    Make-Folders             -ComfyDir $comfyDir -Root $root
    Get-Nodes                -ComfyDir $comfyDir -VenvPy $venvPy
    Get-VCRedist
    $kohyaDir = Get-Kohya   -Root $root
    Make-Launchers           -Root $root -ComfyDir $comfyDir -VenvPy $venvPy -KohyaDir $kohyaDir

    $mins = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
    try { Start-Process explorer.exe $root } catch {}
    Show-Done -Root $root -Mins $mins
}

Main
