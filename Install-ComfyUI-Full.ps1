#Requires -Version 5.1
<#
.SYNOPSIS
    ComfyUI Full Auto-Installer for RTX 3070 Ti (8GB VRAM)
    Installs: Git, Python 3.12 (venv), ComfyUI, all custom nodes,
              model folder structure, Kohya_ss trainer, and a Desktop launcher.

.NOTES
    Run as Administrator for best results (needed for Git/VC++ installs).
    Your system Python (3.14) is left untouched — everything runs in isolated venvs.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
#  BANNER
# ─────────────────────────────────────────────────────────────────────────────
function Write-Banner {
    Clear-Host
    $w = 72
    $line = '═' * $w
    Write-Host "`n╔$line╗" -ForegroundColor Cyan
    Write-Host   "║$((' ' * $w))║" -ForegroundColor Cyan
    Write-Host   "║$('  🖥️  ComfyUI Full Auto-Installer — RTX 3070 Ti Edition'.PadRight($w))║" -ForegroundColor Cyan
    Write-Host   "║$('     Arena.ai Agent Mode · github.com/comfyanonymous/ComfyUI'.PadRight($w))║" -ForegroundColor DarkCyan
    Write-Host   "║$((' ' * $w))║" -ForegroundColor Cyan
    Write-Host   "╚$line╝`n" -ForegroundColor Cyan
}

# ─────────────────────────────────────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Write-Step  { param($n,$t) Write-Host "`n  [$n] $t" -ForegroundColor Yellow }
function Write-OK    { param($t)    Write-Host "    ✅ $t"   -ForegroundColor Green  }
function Write-Info  { param($t)    Write-Host "    ℹ️  $t"   -ForegroundColor Cyan   }
function Write-Warn  { param($t)    Write-Host "    ⚠️  $t"   -ForegroundColor DarkYellow }
function Write-Err   { param($t)    Write-Host "    ❌ $t"   -ForegroundColor Red    }
function Write-Sub   { param($t)    Write-Host "       $t"   -ForegroundColor Gray   }

function Pause-ForUser {
    param([string]$Msg = "Press ENTER to continue or Ctrl+C to abort...")
    Write-Host "`n  $Msg" -ForegroundColor DarkCyan
    $null = Read-Host
}

function Safe-Invoke {
    param([scriptblock]$Block, [string]$Label)
    try   { & $Block; return $true }
    catch { Write-Warn "Step '$Label' encountered an error: $_"; return $false }
}

function Download-File {
    param([string]$Url, [string]$Dest, [string]$Label)
    if (Test-Path $Dest) { Write-Info "$Label already downloaded, skipping."; return }
    Write-Info "Downloading $Label..."
    Write-Sub  "$Url"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent','Mozilla/5.0')
        $wc.DownloadFile($Url, $Dest)
        Write-OK "Downloaded: $(Split-Path $Dest -Leaf)"
    } catch {
        Write-Warn "WebClient failed, trying Invoke-WebRequest..."
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
        Write-OK "Downloaded: $(Split-Path $Dest -Leaf)"
    }
}

function Run-Command {
    param([string]$Cmd, [string]$Args, [string]$WorkDir = $null, [bool]$NoThrow = $false)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $Cmd
    $psi.Arguments              = $Args
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }

    $proc = [System.Diagnostics.Process]::Start($psi)
    $out  = $proc.StandardOutput.ReadToEnd()
    $err  = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($out.Trim()) { Write-Sub $out.Trim() }
    if ($proc.ExitCode -ne 0 -and -not $NoThrow) {
        if ($err.Trim()) { Write-Sub $err.Trim() }
        throw "Command failed (exit $($proc.ExitCode)): $Cmd $Args"
    }
    return $out
}

# ─────────────────────────────────────────────────────────────────────────────
#  STEP 0 — DRIVE SELECTION
# ─────────────────────────────────────────────────────────────────────────────
function Select-InstallDrive {
    Write-Host "`n  ┌─────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host   "  │        💾  SELECT INSTALLATION DRIVE                   │" -ForegroundColor Cyan
    Write-Host   "  └─────────────────────────────────────────────────────────┘`n" -ForegroundColor Cyan

    # List all fixed drives with free space
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object {
        $_.Used -ne $null -and $_.Free -gt 0 -and $_.Name -match '^[A-Z]$'
    } | Sort-Object Name

    if ($drives.Count -eq 0) {
        Write-Err "No writable drives detected. Exiting."
        exit 1
    }

    Write-Host "  Available drives:`n" -ForegroundColor White
    $i = 0
    foreach ($d in $drives) {
        $freeGB  = [math]::Round($d.Free  / 1GB, 1)
        $totalGB = [math]::Round(($d.Used + $d.Free) / 1GB, 1)
        $pct     = [math]::Round(($d.Used / ($d.Used + $d.Free)) * 100)
        $bar     = ('█' * [math]::Round($pct / 5)).PadRight(20, '░')
        $tag     = if ($freeGB -lt 30)  { " ⚠️  LOW SPACE" }
                   elseif ($freeGB -lt 60) { " ⚡ Enough for ComfyUI only" }
                   else                    { " ✅ Recommended" }
        Write-Host "    [$i] $($d.Name):\" -NoNewline -ForegroundColor Yellow
        Write-Host "  $freeGB GB free / $totalGB GB  [$bar $pct%]$tag" -ForegroundColor White
        $i++
    }

    Write-Host "`n  ℹ️  ComfyUI + models needs ~20-60 GB.  Kohya_ss needs ~5 GB extra." -ForegroundColor DarkCyan
    Write-Host   "  ℹ️  We recommend at least 60 GB free on the selected drive.`n" -ForegroundColor DarkCyan

    do {
        $choice = Read-Host "  Enter drive number (0-$($drives.Count-1))"
        $valid  = $choice -match '^\d+$' -and [int]$choice -ge 0 -and [int]$choice -lt $drives.Count
        if (-not $valid) { Write-Warn "Invalid choice. Please enter a number between 0 and $($drives.Count-1)." }
    } while (-not $valid)

    $selectedDrive = $drives[[int]$choice]
    $driveLetter   = $selectedDrive.Name

    Write-Host "`n  📁 Enter a folder name for the installation" -ForegroundColor White
    Write-Host   "     (will be created at ${driveLetter}:\<YourChoice>)" -ForegroundColor Gray
    Write-Host   "     Press ENTER to use default [AI_Studio]:" -ForegroundColor DarkGray -NoNewline
    $folderName = Read-Host " "
    if ([string]::IsNullOrWhiteSpace($folderName)) { $folderName = 'AI_Studio' }
    # Sanitise
    $folderName = $folderName -replace '[\\/:*?"<>|]', '_'

    $rootPath = "${driveLetter}:\${folderName}"
    Write-OK "Installation root: $rootPath"
    return $rootPath
}

# ─────────────────────────────────────────────────────────────────────────────
#  STEP 1 — CHECK / INSTALL GIT
# ─────────────────────────────────────────────────────────────────────────────
function Ensure-Git {
    Write-Step "1/8" "Checking Git..."
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $ver = (git --version 2>&1)
        Write-OK "Git already installed: $ver"
        return $true
    }

    Write-Warn "Git not found. Downloading Git for Windows..."
    $gitInstaller = Join-Path $env:TEMP 'git-installer.exe'
    # Latest stable Git for Windows 64-bit (2.x)
    $gitUrl = 'https://github.com/git-for-windows/git/releases/download/v2.49.0.windows.1/Git-2.49.0-64-bit.exe'
    Download-File -Url $gitUrl -Dest $gitInstaller -Label "Git 2.49.0"

    Write-Info "Installing Git silently..."
    $proc = Start-Process -FilePath $gitInstaller `
        -ArgumentList '/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh"' `
        -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Err "Git installer returned exit code $($proc.ExitCode). You may need to install manually."
        return $false
    }

    # Refresh PATH so git is immediately available
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH','User')

    $git2 = Get-Command git -ErrorAction SilentlyContinue
    if ($git2) {
        Write-OK "Git installed successfully: $(git --version 2>&1)"
        return $true
    } else {
        Write-Warn "Git installed but not yet on PATH. A system restart may be needed."
        Write-Warn "Common location: C:\Program Files\Git\cmd\git.exe"
        Write-Info "Adding Git to current session PATH..."
        $env:PATH += ';C:\Program Files\Git\cmd'
        return $true
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  STEP 2 — CHECK / INSTALL PYTHON 3.12 (isolated, doesn't touch system 3.14)
# ─────────────────────────────────────────────────────────────────────────────
function Ensure-Python312 {
    param([string]$RootPath)
    Write-Step "2/8" "Setting up Python 3.12 for ComfyUI..."
    Write-Info "Your system Python 3.14 is untouched — ComfyUI uses its own isolated venv."

    # Check if Python 3.12 is already available via py launcher
    $py312 = $null
    try {
        $ver = (py -3.12 --version 2>&1)
        if ($ver -match '3\.12') {
            Write-OK "Python 3.12 found via py launcher: $ver"
            $py312 = 'py -3.12'
        }
    } catch {}

    if (-not $py312) {
        # Check direct path (common install locations)
        $candidates = @(
            'C:\Python312\python.exe',
            'C:\Users\' + $env:USERNAME + '\AppData\Local\Programs\Python\Python312\python.exe',
            'C:\Program Files\Python312\python.exe'
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) {
                $ver = (& $c --version 2>&1)
                if ($ver -match '3\.12') {
                    Write-OK "Python 3.12 found at $c"
                    $py312 = $c
                    break
                }
            }
        }
    }

    if (-not $py312) {
        Write-Warn "Python 3.12 not found. Downloading installer..."
        $pyInstaller = Join-Path $env:TEMP 'python312-installer.exe'
        $pyUrl = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe'
        Download-File -Url $pyUrl -Dest $pyInstaller -Label "Python 3.12.10"

        Write-Info "Installing Python 3.12 (user install, no PATH conflict)..."
        # InstallAllUsers=0 avoids overriding your system Python
        $proc = Start-Process -FilePath $pyInstaller `
            -ArgumentList '/quiet InstallAllUsers=0 PrependPath=0 Include_launcher=1' `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Err "Python 3.12 installer failed (exit $($proc.ExitCode))."
            Write-Warn "Please install Python 3.12 manually from https://python.org and re-run this script."
            Pause-ForUser "Press ENTER after installing Python 3.12 to continue..."
        } else {
            Write-OK "Python 3.12 installed."
        }

        # Refresh PATH and try again
        $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' +
                    [System.Environment]::GetEnvironmentVariable('PATH','User')
        try {
            $ver = (py -3.12 --version 2>&1)
            if ($ver -match '3\.12') { $py312 = 'py -3.12' }
        } catch {}

        # Try known path after install
        $knownPath = $env:LOCALAPPDATA + '\Programs\Python\Python312\python.exe'
        if (-not $py312 -and (Test-Path $knownPath)) {
            $py312 = $knownPath
            Write-OK "Python 3.12 found at $knownPath"
        }
    }

    if (-not $py312) {
        Write-Err "Could not locate Python 3.12. Please install it manually and re-run."
        exit 1
    }

    # Create the ComfyUI venv
    $venvPath = Join-Path $RootPath 'comfyui_venv'
    if (-not (Test-Path (Join-Path $venvPath 'Scripts\python.exe'))) {
        Write-Info "Creating Python 3.12 virtual environment at: $venvPath"
        if ($py312 -like 'py*') {
            & py -3.12 -m venv $venvPath
        } else {
            & $py312 -m venv $venvPath
        }
        Write-OK "Virtual environment created."
    } else {
        Write-OK "Virtual environment already exists at $venvPath"
    }

    return (Join-Path $venvPath 'Scripts\python.exe')
}

# ─────────────────────────────────────────────────────────────────────────────
#  STEP 3 — CLONE / UPDATE COMFYUI
# ─────────────────────────────────────────────────────────────────────────────
function Install-ComfyUI {
    param([string]$RootPath, [string]$PythonExe)
    Write-Step "3/8" "Installing ComfyUI..."

    $comfyPath = Join-Path $RootPath 'ComfyUI'

    if (Test-Path (Join-Path $comfyPath '.git')) {
        Write-Info "ComfyUI already cloned. Pulling latest..."
        Run-Command -Cmd 'git' -Args 'pull' -WorkDir $comfyPath -NoThrow $true
        Write-OK "ComfyUI updated."
    } else {
        Write-Info "Cloning ComfyUI from GitHub..."
        Run-Command -Cmd 'git' -Args "clone https://github.com/comfyanonymous/ComfyUI `"$comfyPath`""
        Write-OK "ComfyUI cloned."
    }

    # Install PyTorch for CUDA 12.6 (RTX 3070 Ti compatible) + ComfyUI requirements
    Write-Info "Installing PyTorch 2.7 + CUDA 12.6 (this may take 5-15 minutes)..."
    $pip = Join-Path (Split-Path $PythonExe) 'pip.exe'

    Run-Command -Cmd $pip -Args 'install --upgrade pip setuptools wheel'
    Run-Command -Cmd $pip -Args `
        'install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126' `
        -WorkDir $comfyPath
    Write-OK "PyTorch installed with CUDA 12.6 support."

    Write-Info "Installing ComfyUI requirements..."
    Run-Command -Cmd $pip -Args "install -r `"$(Join-Path $comfyPath 'requirements.txt')`""
    Write-OK "ComfyUI requirements installed."

    # Install xformers for memory efficiency on 3070 Ti
    Write-Info "Installing xformers (VRAM optimisation)..."
    Run-Command -Cmd $pip -Args 'install xformers --index-url https://download.pytorch.org/whl/cu126' -NoThrow $true
    Write-OK "xformers installed."

    return $comfyPath
}

# ─────────────────────────────────────────────────────────────────────────────
#  STEP 4 — CREATE FOLDER STRUCTURE
# ─────────────────────────────────────────────────────────────────────────────
function Create-FolderStructure {
    param([string]$ComfyPath, [string]$RootPath)
    Write-Step "4/8" "Creating folder structure..."

    $folders = @(
        # ComfyUI model folders
        (Join-Path $ComfyPath 'models\checkpoints'),
        (Join-Path $ComfyPath 'models\loras'),
        (Join-Path $ComfyPath 'models\vae'),
        (Join-Path $ComfyPath 'models\controlnet'),
        (Join-Path $ComfyPath 'models\insightface'),
        (Join-Path $ComfyPath 'models\facerestore_models'),
        (Join-Path $ComfyPath 'models\upscale_models'),
        (Join-Path $ComfyPath 'models\embeddings'),
        (Join-Path $ComfyPath 'models\clip'),
        (Join-Path $ComfyPath 'models\unet'),
        (Join-Path $ComfyPath 'input'),
        (Join-Path $ComfyPath 'output'),
        (Join-Path $ComfyPath 'custom_nodes'),
        # LoRA training workspace
        (Join-Path $RootPath 'LoRA_Training\dataset\my_subject_10'),
        (Join-Path $RootPath 'LoRA_Training\output'),
        (Join-Path $RootPath 'LoRA_Training\logs'),
        # Downloads cache
        (Join-Path $RootPath '_downloads')
    )

    foreach ($f in $folders) {
        if (-not (Test-Path $f)) {
            New-Item -ItemType Directory -Path $f -Force | Out-Null
            Write-Sub "Created: $f"
        }
    }

    # Write README files in key folders
    Set-Content -Path (Join-Path $ComfyPath 'models\checkpoints\README.txt') -Value @"
CHECKPOINTS FOLDER
==================
Place .safetensors or .ckpt base model files here.

Recommended models:
- dreamshaper_8.safetensors          (general purpose, CivitAI)
- realisticVisionV60B1_v51VAE.safetensors  (portraits, CivitAI)
- epicrealism_naturalSinRC1VAE.safetensors  (realistic, CivitAI)

Download from: https://civitai.com or https://huggingface.co
"@

    Set-Content -Path (Join-Path $ComfyPath 'models\loras\README.txt') -Value @"
LORAS FOLDER
============
Place LoRA .safetensors files here.
These are style/character modifiers used on top of base models.

After training with Kohya_ss, copy output .safetensors files here.
Download community LoRAs from: https://civitai.com/models?type=LORA
"@

    Set-Content -Path (Join-Path $ComfyPath 'models\controlnet\README.txt') -Value @"
CONTROLNET FOLDER
=================
Place ControlNet model files here (.pth or .safetensors).

Required for SECTION 3 (FaceSwap + Pose):
- control_v11p_sd15_openpose.pth

Download from: https://huggingface.co/lllyasviel/ControlNet-v1-1/tree/main
"@

    Set-Content -Path (Join-Path $ComfyPath 'models\insightface\README.txt') -Value @"
INSIGHTFACE / FACESWAP MODELS
==============================
Required for ReActor FaceSwap (Sections 2 & 3):
- inswapper_128.onnx   ← place directly in this folder

Also place the 'buffalo_l' folder here (auto-downloaded by ReActor on first run).

Get inswapper_128.onnx from the ReActor GitHub releases:
https://github.com/Gourieff/ComfyUI-ReActor
"@

    Set-Content -Path (Join-Path $ComfyPath 'models\facerestore_models\README.txt') -Value @"
FACE RESTORATION MODELS
========================
Required for ReActor FaceSwap quality:
- codeformer.pth      (recommended)
- GFPGANv1.4.pth      (alternative)

Download codeformer.pth:
https://github.com/sczhou/CodeFormer/releases/tag/v0.1.0

Download GFPGANv1.4.pth:
https://github.com/TencentARC/GFPGAN/releases
"@

    Set-Content -Path (Join-Path $RootPath 'LoRA_Training\dataset\my_subject_10\README.txt') -Value @"
LORA TRAINING DATASET FOLDER
=============================
Place your training images here (.jpg or .png).
The '10' in the folder name = number of repeats per epoch.

REQUIRED: Each image needs a matching caption file.
Example:
  my_image_001.jpg
  my_image_001.txt  ← caption: "mysubject, woman, red hair, outdoor"

Use WD14 Tagger (in Kohya_ss GUI) to auto-generate captions.
Or write them manually - include your trigger word in every caption!

Recommended: 20-100 high quality images at 512x512 resolution.
"@

    Write-OK "All folders created with README guides."
}

# ─────────────────────────────────────────────────────────────────────────────
#  STEP 5 — INSTALL CUSTOM NODES
# ─────────────────────────────────────────────────────────────────────────────
function Install-CustomNodes {
    param([string]$ComfyPath, [string]$PythonExe)
    Write-Step "5/8" "Installing custom nodes..."

    $customNodesPath = Join-Path $ComfyPath 'custom_nodes'
    $pip = Join-Path (Split-Path $PythonExe) 'pip.exe'

    $nodes = @(
        @{
            Name    = 'ComfyUI-Manager'
            Url     = 'https://github.com/ltdrdata/ComfyUI-Manager.git'
            Pip     = @()
            Note    = 'Node manager — required to install more nodes from the UI'
        },
        @{
            Name    = 'ComfyUI-ReActor'
            Url     = 'https://github.com/Gourieff/ComfyUI-ReActor.git'
            Pip     = @(
                # Python 3.12 compatible insightface wheel
                'https://github.com/Gourieff/Assets/raw/main/Insightface/insightface-0.7.3-cp312-cp312-win_amd64.whl',
                'onnxruntime-gpu'
            )
            Note    = 'FaceSwap — used in Sections 2 & 3'
        },
        @{
            Name    = 'comfyui_controlnet_aux'
            Url     = 'https://github.com/Fannovel16/comfyui_controlnet_aux.git'
            Pip     = @()
            Note    = 'OpenPose / DWPose preprocessors — used in Section 3'
        },
        @{
            Name    = 'ComfyUI-AnimateDiff-Evolved'
            Url     = 'https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved.git'
            Pip     = @()
            Note    = 'AnimateDiff animation — used in Section 5'
        },
        @{
            Name    = 'ComfyUI-VideoHelperSuite'
            Url     = 'https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git'
            Pip     = @()
            Note    = 'GIF/Video export — used in Section 5'
        }
    )

    foreach ($node in $nodes) {
        $destPath = Join-Path $customNodesPath $node.Name
        Write-Info "Node: $($node.Name) — $($node.Note)"

        if (Test-Path (Join-Path $destPath '.git')) {
            Write-Sub "Already installed. Updating..."
            Run-Command -Cmd 'git' -Args 'pull' -WorkDir $destPath -NoThrow $true
        } else {
            Write-Sub "Cloning..."
            Run-Command -Cmd 'git' -Args "clone `"$($node.Url)`" `"$destPath`"" -NoThrow $true
        }

        # Install requirements.txt if it exists
        $reqFile = Join-Path $destPath 'requirements.txt'
        if (Test-Path $reqFile) {
            Write-Sub "Installing requirements..."
            Run-Command -Cmd $pip -Args "install -r `"$reqFile`"" -NoThrow $true
        }

        # Install any extra pip packages
        foreach ($pkg in $node.Pip) {
            Write-Sub "Installing: $pkg"
            Run-Command -Cmd $pip -Args "install `"$pkg`"" -NoThrow $true
        }

        Write-OK "$($node.Name) ready."
    }

    # Create AnimateDiff models folder
    $adModelsPath = Join-Path $customNodesPath 'ComfyUI-AnimateDiff-Evolved\models'
    if (-not (Test-Path $adModelsPath)) {
        New-Item -ItemType Directory -Path $adModelsPath -Force | Out-Null
    }
    Set-Content -Path (Join-Path $adModelsPath 'README.txt') -Value @"
ANIMATEDIFF MOTION MODELS
==========================
Place AnimateDiff motion model files here (.ckpt or .safetensors).

Recommended:
- mm_sd_v15_v2.ckpt    (SD 1.5, reliable)

Download from:
https://huggingface.co/guoyww/animatediff-motion-adapter-v1-5-2

For Lightning (faster, fewer steps):
- animatediff_lightning_4step_comfyui.safetensors
Download from: https://huggingface.co/ByteDance/AnimateDiff-Lightning
"@
}

# ─────────────────────────────────────────────────────────────────────────────
#  STEP 6 — INSTALL VISUAL C++ REDISTRIBUTABLE (needed by insightface/onnx)
# ─────────────────────────────────────────────────────────────────────────────
function Install-VCRedist {
    Write-Step "6/8" "Checking Visual C++ Redistributables (required by FaceSwap)..."

    $vcKey = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64'
    $vcInstalled = Test-Path $vcKey

    if ($vcInstalled) {
        Write-OK "Visual C++ 2015-2022 Redistributable already installed."
        return
    }

    Write-Info "Downloading Visual C++ 2015-2022 Redistributable..."
    $vcInstaller = Join-Path $env:TEMP 'vc_redist.x64.exe'
    Download-File -Url 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -Dest $vcInstaller -Label "VC++ Redist"

    Write-Info "Installing Visual C++ Redistributable..."
    $proc = Start-Process -FilePath $vcInstaller -ArgumentList '/quiet /norestart' -Wait -PassThru
    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
        Write-OK "Visual C++ Redistributable installed."
    } else {
        Write-Warn "VC++ install returned code $($proc.ExitCode) — may already be installed or need a restart."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  STEP 7 — INSTALL KOHYA_SS TRAINER
# ─────────────────────────────────────────────────────────────────────────────
function Install-KohyaSS {
    param([string]$RootPath)
    Write-Step "7/8" "Installing Kohya_ss LoRA Trainer..."

    $kohyaPath = Join-Path $RootPath 'kohya_ss'

    # Kohya_ss works best with Python 3.10.x — install it separately
    Write-Info "Kohya_ss requires Python 3.10. Checking..."
    $py310 = $null

    try {
        $ver = (py -3.10 --version 2>&1)
        if ($ver -match '3\.10') {
            $py310 = 'py -3.10'
            Write-OK "Python 3.10 found: $ver"
        }
    } catch {}

    if (-not $py310) {
        $knownPath = $env:LOCALAPPDATA + '\Programs\Python\Python310\python.exe'
        if (Test-Path $knownPath) {
            $ver = (& $knownPath --version 2>&1)
            if ($ver -match '3\.10') { $py310 = $knownPath; Write-OK "Python 3.10 at $knownPath" }
        }
    }

    if (-not $py310) {
        Write-Info "Python 3.10 not found. Downloading Python 3.10.11..."
        $pyInstaller310 = Join-Path $env:TEMP 'python310-installer.exe'
        $pyUrl310 = 'https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe'
        Download-File -Url $pyUrl310 -Dest $pyInstaller310 -Label "Python 3.10.11"
        Write-Info "Installing Python 3.10.11 (parallel install, won't affect system Python)..."
        $proc = Start-Process -FilePath $pyInstaller310 `
            -ArgumentList '/quiet InstallAllUsers=0 PrependPath=0 Include_launcher=1' `
            -Wait -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-OK "Python 3.10.11 installed."
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH','User')
            try { $v2 = (py -3.10 --version 2>&1); if ($v2 -match '3\.10') { $py310 = 'py -3.10' } } catch {}
            if (-not $py310) {
                $p2 = $env:LOCALAPPDATA + '\Programs\Python\Python310\python.exe'
                if (Test-Path $p2) { $py310 = $p2 }
            }
        } else {
            Write-Warn "Python 3.10 installer failed. Kohya_ss may not work correctly."
        }
    }

    # Clone kohya_ss
    if (Test-Path (Join-Path $kohyaPath '.git')) {
        Write-Info "Kohya_ss already cloned. Pulling latest..."
        Run-Command -Cmd 'git' -Args 'pull' -WorkDir $kohyaPath -NoThrow $true
    } else {
        Write-Info "Cloning Kohya_ss..."
        Run-Command -Cmd 'git' -Args "clone --recursive https://github.com/bmaltais/kohya_ss.git `"$kohyaPath`""
        Write-OK "Kohya_ss cloned."
    }

    # Create venv for kohya using Python 3.10
    $kohyaVenv = Join-Path $kohyaPath 'venv'
    if ($py310 -and -not (Test-Path (Join-Path $kohyaVenv 'Scripts\python.exe'))) {
        Write-Info "Creating Kohya_ss Python 3.10 venv..."
        if ($py310 -like 'py*') {
            & py -3.10 -m venv $kohyaVenv
        } else {
            & $py310 -m venv $kohyaVenv
        }
        Write-OK "Kohya_ss venv created."
    }

    # Write a simple launch script for kohya
    $kohyaLauncher = Join-Path $kohyaPath 'Launch-Kohya.ps1'
    Set-Content -Path $kohyaLauncher -Value @"
# Launch Kohya_ss GUI
# Run this from inside the kohya_ss folder
Set-Location "`$PSScriptRoot"
if (Test-Path ".\venv\Scripts\Activate.ps1") {
    . ".\venv\Scripts\Activate.ps1"
}
Write-Host "Starting Kohya_ss GUI..." -ForegroundColor Cyan
if (Test-Path ".\gui.ps1") {
    & ".\gui.ps1" --listen 127.0.0.1 --server_port 7860 --inbrowser
} elseif (Test-Path ".\gui.bat") {
    & cmd /c "gui.bat" --listen 127.0.0.1 --server_port 7860 --inbrowser
} else {
    Write-Host "Run setup.bat first to complete Kohya_ss setup!" -ForegroundColor Yellow
    & cmd /c "setup.bat"
}
"@

    Write-OK "Kohya_ss installed at: $kohyaPath"
    Write-Info "IMPORTANT: Run '$kohyaPath\setup.bat' once to complete Kohya_ss setup."
    Write-Info "(It will ask you to configure Accelerate — accept the defaults.)"

    return $kohyaPath
}

# ─────────────────────────────────────────────────────────────────────────────
#  STEP 8 — CREATE LAUNCHERS & DESKTOP SHORTCUTS
# ─────────────────────────────────────────────────────────────────────────────
function Create-Launchers {
    param([string]$RootPath, [string]$ComfyPath, [string]$PythonExe, [string]$KohyaPath)
    Write-Step "8/8" "Creating launchers and Desktop shortcuts..."

    # ── ComfyUI launcher .bat
    $comfyBat = Join-Path $RootPath 'Launch-ComfyUI.bat'
    Set-Content -Path $comfyBat -Encoding ASCII -Value @"
@echo off
title ComfyUI — RTX 3070 Ti
color 0B
echo.
echo  =========================================
echo   ComfyUI Launcher — RTX 3070 Ti (8GB)
echo  =========================================
echo.
echo  Starting ComfyUI with --medvram flag...
echo  Browser will open at http://127.0.0.1:8188
echo.
echo  TIP: If you get Out-of-Memory errors, close
echo  this window and run Launch-ComfyUI-LowVRAM.bat
echo.
cd /d "$ComfyPath"
"$PythonExe" main.py --medvram --auto-launch
pause
"@

    # ── ComfyUI low-VRAM variant
    $comfyBatLow = Join-Path $RootPath 'Launch-ComfyUI-LowVRAM.bat'
    Set-Content -Path $comfyBatLow -Encoding ASCII -Value @"
@echo off
title ComfyUI — Low VRAM Mode
color 0E
echo.
echo  =========================================
echo   ComfyUI — LOW VRAM MODE (--lowvram)
echo  =========================================
echo.
echo  Use this if you get Out-of-Memory errors.
echo  Slower but safer for complex workflows.
echo.
cd /d "$ComfyPath"
"$PythonExe" main.py --lowvram --auto-launch
pause
"@

    # ── Kohya_ss launcher .bat
    $kohyaBat = Join-Path $RootPath 'Launch-KohyaSS.bat'
    Set-Content -Path $kohyaBat -Encoding ASCII -Value @"
@echo off
title Kohya_ss — LoRA Trainer
color 0D
echo.
echo  =========================================
echo   Kohya_ss LoRA Trainer Launcher
echo  =========================================
echo.
echo  NOTE: Run setup.bat first if this is
echo  your first time launching Kohya_ss!
echo.
cd /d "$KohyaPath"
if exist "venv\Scripts\activate.bat" (
    call venv\Scripts\activate.bat
)
if exist "gui.bat" (
    call gui.bat --listen 127.0.0.1 --server_port 7860 --inbrowser
) else (
    echo Run setup.bat first!
    call setup.bat
)
pause
"@

    # ── Kohya first-time setup .bat
    $kohyaSetupBat = Join-Path $RootPath 'Setup-KohyaSS-FirstTime.bat'
    Set-Content -Path $kohyaSetupBat -Encoding ASCII -Value @"
@echo off
title Kohya_ss First-Time Setup
color 0C
echo.
echo  =========================================
echo   Kohya_ss FIRST-TIME SETUP
echo   Run this ONCE before using Kohya_ss!
echo  =========================================
echo.
echo  When prompted for Accelerate config:
echo    - Compute environment: LOCAL MACHINE
echo    - GPU: NVIDIA (CUDA)
echo    - Mixed precision: fp16
echo    - Leave other options as default
echo.
cd /d "$KohyaPath"
call setup.bat
pause
"@

    # ── Master info .txt
    $infoFile = Join-Path $RootPath 'START_HERE.txt'
    Set-Content -Path $infoFile -Value @"
╔══════════════════════════════════════════════════════════════╗
║      ComfyUI AI Studio — RTX 3070 Ti Edition                ║
║      Installation by Arena.ai ComfyUI Setup Script          ║
╚══════════════════════════════════════════════════════════════╝

📁 INSTALLATION ROOT: $RootPath

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
QUICK START:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Double-click: Launch-ComfyUI.bat
     → Opens ComfyUI at http://127.0.0.1:8188

  2. Drag the workflow JSON into the browser window
     → File: comfyui_rtx3070ti_workflow.json

  3. Start with SECTION 4 (LoRA Usage) — simplest!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MODELS YOU STILL NEED TO DOWNLOAD:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  📂 $ComfyPath\models\checkpoints\
     → dreamshaper_8.safetensors           (CivitAI)
     → realisticVisionV60B1_v51VAE.safetensors (CivitAI)

  📂 $ComfyPath\models\vae\
     → vae-ft-mse-840000-ema-pruned.safetensors (HuggingFace)

  📂 $ComfyPath\models\controlnet\
     → control_v11p_sd15_openpose.pth      (HuggingFace lllyasviel)

  📂 $ComfyPath\models\insightface\
     → inswapper_128.onnx                  (ReActor GitHub releases)

  📂 $ComfyPath\models\facerestore_models\
     → codeformer.pth                      (sczhou/CodeFormer GitHub)

  📂 $ComfyPath\custom_nodes\ComfyUI-AnimateDiff-Evolved\models\
     → mm_sd_v15_v2.ckpt                   (HuggingFace guoyww)

  See README.txt files inside each folder for download links!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LORA TRAINING:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. First time only: Setup-KohyaSS-FirstTime.bat
  2. Launch trainer:  Launch-KohyaSS.bat
  3. Training images: $RootPath\LoRA_Training\dataset\
  4. Trained LoRAs:   Copy .safetensors to models\loras\

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VRAM TIPS (RTX 3070 Ti — 8GB):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  • Normal use:   Launch-ComfyUI.bat         (--medvram)
  • OOM errors:   Launch-ComfyUI-LowVRAM.bat (--lowvram)
  • Resolution:   Keep at 512x512 or 512x768
  • Batch size:   Always 1
  • AnimateDiff:  Max 16 frames at 512x512
  • Only run ONE workflow section at a time!
"@

    # ── Desktop shortcuts (requires COM)
    try {
        $shell    = New-Object -ComObject WScript.Shell
        $desktop  = [System.Environment]::GetFolderPath('Desktop')

        # ComfyUI shortcut
        $sc1 = $shell.CreateShortcut("$desktop\🖥️ Launch ComfyUI.lnk")
        $sc1.TargetPath       = $comfyBat
        $sc1.WorkingDirectory = $RootPath
        $sc1.Description      = 'Launch ComfyUI (RTX 3070 Ti - medvram mode)'
        $sc1.IconLocation     = 'C:\Windows\System32\shell32.dll,14'
        $sc1.Save()
        Write-OK "Desktop shortcut created: '🖥️ Launch ComfyUI'"

        # Kohya_ss shortcut
        $sc2 = $shell.CreateShortcut("$desktop\🎓 Launch Kohya_ss Trainer.lnk")
        $sc2.TargetPath       = $kohyaBat
        $sc2.WorkingDirectory = $RootPath
        $sc2.Description      = 'Launch Kohya_ss LoRA Trainer'
        $sc2.IconLocation     = 'C:\Windows\System32\shell32.dll,21'
        $sc2.Save()
        Write-OK "Desktop shortcut created: '🎓 Launch Kohya_ss Trainer'"

        # AI Studio folder shortcut
        $sc3 = $shell.CreateShortcut("$desktop\📁 AI Studio Folder.lnk")
        $sc3.TargetPath       = $RootPath
        $sc3.Description      = 'Open AI Studio root folder'
        $sc3.IconLocation     = 'C:\Windows\System32\shell32.dll,3'
        $sc3.Save()
        Write-OK "Desktop shortcut created: '📁 AI Studio Folder'"

    } catch {
        Write-Warn "Could not create Desktop shortcuts (COM error): $_"
        Write-Info "Launchers are available directly in: $RootPath"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  STEP 9 — COPY WORKFLOW JSON (if present next to this script)
# ─────────────────────────────────────────────────────────────────────────────
function Copy-WorkflowFile {
    param([string]$ComfyPath, [string]$RootPath)
    $scriptDir = Split-Path $MyInvocation.ScriptName -Parent
    $wfSource  = Join-Path $scriptDir 'comfyui_rtx3070ti_workflow.json'
    if (Test-Path $wfSource) {
        $wfDest = Join-Path $ComfyPath 'user\default\workflows\rtx3070ti_master_workflow.json'
        $wfDir  = Split-Path $wfDest -Parent
        if (-not (Test-Path $wfDir)) { New-Item -ItemType Directory -Path $wfDir -Force | Out-Null }
        Copy-Item -Path $wfSource -Destination $wfDest -Force
        Write-OK "Workflow JSON copied to ComfyUI workflows folder."
        # Also put a copy in root
        Copy-Item -Path $wfSource -Destination (Join-Path $RootPath 'comfyui_rtx3070ti_workflow.json') -Force
    } else {
        Write-Warn "comfyui_rtx3070ti_workflow.json not found next to this script."
        Write-Info "Place it in: $RootPath  or drag it into ComfyUI manually."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  FINAL SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
function Show-Summary {
    param([string]$RootPath, [string]$ComfyPath, [string]$KohyaPath)

    $w = 66
    Write-Host "`n"
    Write-Host "  ╔$('═' * $w)╗" -ForegroundColor Green
    Write-Host "  ║$('  ✅  INSTALLATION COMPLETE!'.PadRight($w))║" -ForegroundColor Green
    Write-Host "  ╠$('═' * $w)╣" -ForegroundColor Green
    Write-Host "  ║$(''.PadRight($w))║" -ForegroundColor Green
    Write-Host "  ║$("  📁 Root:    $RootPath".PadRight($w))║" -ForegroundColor Green
    Write-Host "  ║$("  🖥️  ComfyUI: $ComfyPath".PadRight($w))║" -ForegroundColor Green
    Write-Host "  ║$("  🎓 Kohya:   $KohyaPath".PadRight($w))║" -ForegroundColor Green
    Write-Host "  ║$(''.PadRight($w))║" -ForegroundColor Green
    Write-Host "  ╠$('═' * $w)╣" -ForegroundColor Green
    Write-Host "  ║$('  NEXT STEPS:'.PadRight($w))║" -ForegroundColor Cyan
    Write-Host "  ║$(''.PadRight($w))║" -ForegroundColor Cyan
    Write-Host "  ║$('  1. Download models (see README.txt in each model folder)'.PadRight($w))║" -ForegroundColor Cyan
    Write-Host "  ║$('  2. Double-click  Launch-ComfyUI.bat  on your Desktop'.PadRight($w))║" -ForegroundColor Cyan
    Write-Host "  ║$('  3. Drag the workflow .json into ComfyUI browser window'.PadRight($w))║" -ForegroundColor Cyan
    Write-Host "  ║$('  4. Kohya_ss: Run Setup-KohyaSS-FirstTime.bat ONCE first'.PadRight($w))║" -ForegroundColor Cyan
    Write-Host "  ║$('  5. Read START_HERE.txt in your AI Studio folder'.PadRight($w))║" -ForegroundColor Cyan
    Write-Host "  ║$(''.PadRight($w))║" -ForegroundColor Cyan
    Write-Host "  ║$('  ⚠️  inswapper_128.onnx and model files still need'.PadRight($w))║" -ForegroundColor Yellow
    Write-Host "  ║$('     to be downloaded manually (see README files).'.PadRight($w))║" -ForegroundColor Yellow
    Write-Host "  ║$(''.PadRight($w))║" -ForegroundColor Green
    Write-Host "  ╚$('═' * $w)╝`n" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────────────────────
function Main {
    Write-Banner

    # Check execution policy
    $policy = Get-ExecutionPolicy
    if ($policy -eq 'Restricted') {
        Write-Warn "PowerShell execution policy is 'Restricted'."
        Write-Info "Run this in an Admin PowerShell with:"
        Write-Info "  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass"
        Write-Info "Then re-run this script."
        exit 1
    }

    # Admin check (soft warning — not hard exit, some steps work without it)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                 [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Warn "Script is NOT running as Administrator."
        Write-Warn "Git and VC++ installation may fail. For best results:"
        Write-Warn "Right-click this script → 'Run with PowerShell as Administrator'"
        Pause-ForUser "Press ENTER to continue anyway, or Ctrl+C to abort and re-run as Admin..."
    } else {
        Write-OK "Running as Administrator. Good."
    }

    # ── DRIVE SELECTION
    $rootPath = Select-InstallDrive

    # Create root if needed
    if (-not (Test-Path $rootPath)) {
        New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
        Write-OK "Created installation root: $rootPath"
    }

    # ── CONFIRM
    Write-Host "`n  ┌─────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host   "  │   📋  INSTALLATION PLAN                                │" -ForegroundColor Cyan
    Write-Host   "  ├─────────────────────────────────────────────────────────┤" -ForegroundColor Cyan
    Write-Host   "  │  Root folder   : $($rootPath.PadRight(39))│" -ForegroundColor White
    Write-Host   "  │  ComfyUI       : $($rootPath)\ComfyUI$((' ' * [Math]::Max(0,22-$rootPath.Length)))│" -ForegroundColor White
    Write-Host   "  │  Kohya_ss      : $($rootPath)\kohya_ss$((' ' * [Math]::Max(0,21-$rootPath.Length)))│" -ForegroundColor White
    Write-Host   "  │  Python venvs  : Separate (3.12 for ComfyUI, 3.10 for Kohya)│" -ForegroundColor White
    Write-Host   "  │  Desktop icons : Yes (ComfyUI + Kohya_ss + Folder)     │" -ForegroundColor White
    Write-Host   "  └─────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host   "`n  This will install: Git, Python 3.12, Python 3.10, ComfyUI," -ForegroundColor Gray
    Write-Host   "  5 custom nodes, Kohya_ss, and create all folder structures." -ForegroundColor Gray
    Write-Host   "  Estimated time: 10-30 minutes (depends on internet speed).`n" -ForegroundColor Gray
    Pause-ForUser "Press ENTER to begin installation, or Ctrl+C to cancel..."

    $startTime = Get-Date

    # ── RUN ALL STEPS
    $gitOk    = Ensure-Git
    $pyExe    = Ensure-Python312 -RootPath $rootPath
    $comfyPath = Install-ComfyUI -RootPath $rootPath -PythonExe $pyExe
    Create-FolderStructure -ComfyPath $comfyPath -RootPath $rootPath
    Install-CustomNodes -ComfyPath $comfyPath -PythonExe $pyExe
    Install-VCRedist
    $kohyaPath = Install-KohyaSS -RootPath $rootPath
    Create-Launchers -RootPath $rootPath -ComfyPath $comfyPath -PythonExe $pyExe -KohyaPath $kohyaPath
    Copy-WorkflowFile -ComfyPath $comfyPath -RootPath $rootPath

    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    Write-Info "Total install time: $elapsed minutes"

    Show-Summary -RootPath $rootPath -ComfyPath $comfyPath -KohyaPath $kohyaPath

    # Auto-open the folder
    try { Start-Process explorer.exe -ArgumentList $rootPath } catch {}
}

# ── ENTRY POINT
Main
