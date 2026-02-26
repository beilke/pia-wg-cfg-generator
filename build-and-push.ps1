#!/usr/bin/env pwsh
param(
    [string]$DockerUsername = "fbeilke",
    [string]$Image = "pia-wg-generator",
    [string]$BuildType = "dev",
    [string]$Version = "",
    [string]$Dockerfile = "Dockerfile",
    [string]$DockhandUrl = "http://192.168.1.190:3000",
    [string]$DockhandEnv = "1",
    [string]$StackName = "pia",
    [string]$DockhandUser = "fbeilke",
    [string]$DockhandPassword = 'QN^$LwhrkQ0wWe',
    [switch]$SkipDockhand,
    [switch]$DeployOnly,
    [switch]$NoCache,
    [switch]$Buildx,
    [string]$Platforms = "linux/amd64,linux/arm64"
)

$ErrorActionPreference = "Stop"

# Function to deploy via Dockhand
function Invoke-DockhandDeploy {
    Write-Host "`n=== Triggering Dockhand Stack Update ===" -ForegroundColor Yellow
    Write-Host "Dockhand URL: $DockhandUrl" -ForegroundColor Cyan
    Write-Host "Environment: $DockhandEnv" -ForegroundColor Cyan
    Write-Host "Stack Name: $StackName" -ForegroundColor Cyan

    # Check if password is provided
    if ([string]::IsNullOrEmpty($DockhandPassword)) {
        Write-Host "ERROR: Dockhand password not provided. Set DOCKHAND_PASSWORD environment variable or pass as parameter." -ForegroundColor Red
        return $false
    }

    try {
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

        # Authenticate with Dockhand
        Write-Host "Authenticating with Dockhand..." -ForegroundColor Cyan
        $loginBody = @{
            username = $DockhandUser
            password = $DockhandPassword
        } | ConvertTo-Json

        $loginResponse = Invoke-RestMethod -Uri "$DockhandUrl/api/auth/login" -Method Post -Body $loginBody -ContentType "application/json" -SessionVariable session -ErrorAction Stop
        Write-Host "Authentication successful" -ForegroundColor Green

        # Pull fresh image from Docker Hub
        $imageTag = if ($BuildType -eq "latest") { "latest" } else { "dev" }
        Write-Host "Pulling ${DockerUsername}/${Image}:$imageTag from Docker Hub..." -ForegroundColor Cyan
        $pullBody = @{ image = "${DockerUsername}/${Image}:$imageTag" } | ConvertTo-Json
        $pullResponse = Invoke-RestMethod -Uri "$DockhandUrl/api/images/pull?env=$DockhandEnv" -Method Post -Body $pullBody -ContentType "application/json" -WebSession $session -TimeoutSec 300 -ErrorAction Stop
        Write-Host "Image pulled successfully" -ForegroundColor Green

        # Stop the stack
        Write-Host "Stopping stack '$StackName'..." -ForegroundColor Cyan
        $stopResponse = Invoke-RestMethod -Uri "$DockhandUrl/api/stacks/$StackName/stop?env=$DockhandEnv" -Method Post -ContentType "application/json" -WebSession $session -TimeoutSec 60 -ErrorAction Stop
        Write-Host "Stack stopped successfully" -ForegroundColor Green

        Start-Sleep -Seconds 2

        # Start the stack with the new image
        Write-Host "Starting stack '$StackName' with new image..." -ForegroundColor Cyan
        try {
            $startResponse = Invoke-RestMethod -Uri "$DockhandUrl/api/stacks/$StackName/start?env=$DockhandEnv" -Method Post -ContentType "application/json" -WebSession $session -TimeoutSec 120 -ErrorAction Stop
            Write-Host "Stack started successfully with new image!" -ForegroundColor Green
        } catch {
            Write-Host "  Start request interrupted (this is normal during restart)" -ForegroundColor Yellow
            Write-Host "  Waiting for stack to come up..." -ForegroundColor Cyan
            Start-Sleep -Seconds 10

            # Re-authenticate and check status
            $loginResponse = Invoke-RestMethod -Uri "$DockhandUrl/api/auth/login" -Method Post -Body $loginBody -ContentType "application/json" -SessionVariable session -ErrorAction SilentlyContinue
            $stacks = Invoke-RestMethod -Uri "$DockhandUrl/api/stacks?env=$DockhandEnv" -Method Get -WebSession $session -TimeoutSec 30 -ErrorAction SilentlyContinue
            $stack = $stacks | Where-Object { $_.name -eq $StackName }

            if ($stack -and $stack.status -eq "running") {
                Write-Host "Stack verified running!" -ForegroundColor Green
            } else {
                Write-Host "  Stack status: $($stack.status)" -ForegroundColor Yellow
                Write-Host "  Check Dockhand UI to verify stack is running" -ForegroundColor Yellow
            }
        }

        Write-Host "`n=== Dockhand Update Complete ===" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "`nWARNING: Failed to update stack via Dockhand: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "You may need to manually restart the stack in Dockhand" -ForegroundColor Yellow
        Write-Host "  URL: $DockhandUrl" -ForegroundColor Cyan
        return $false
    }
}

# Validate build type
if ($BuildType -notin @("dev", "latest")) {
    Write-Host "ERROR: BuildType must be 'dev' or 'latest'" -ForegroundColor Red
    exit 1
}

# Deploy only mode - skip build and push
if ($DeployOnly) {
    $imageTag = if ($BuildType -eq "latest") { "latest" } else { "dev" }
    Write-Host "=== Deploy Only Mode ===" -ForegroundColor Green
    Write-Host "Skipping build and push, triggering Dockhand deployment..." -ForegroundColor Cyan
    Write-Host "Image Tag: $imageTag" -ForegroundColor Cyan

    $result = Invoke-DockhandDeploy
    if ($result) {
        Write-Host "`n=== SUCCESS! ===" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`nDeployment failed!" -ForegroundColor Red
        exit 1
    }
}

# Auto-detect version based on build type
if ($Version -eq "") {
    if ($BuildType -eq "latest") {
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $gitTag = $(git describe --tags --exact-match 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $Version = $gitTag
            } else {
                # Get the latest tag and append date
                $latestTag = $(git describe --tags --abbrev=0 2>$null)
                if ($latestTag) {
                    $Version = "$latestTag-$(Get-Date -Format 'yyyyMMdd')"
                } else {
                    $Version = "latest-$(Get-Date -Format 'yyyyMMdd')"
                }
            }
        } else {
            $Version = "latest-$(Get-Date -Format 'yyyyMMdd')"
        }
    } else {
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $Version = $(git rev-parse --short HEAD)
            if ($LASTEXITCODE -ne 0) {
                $Version = "dev-$(Get-Date -Format 'yyyyMMdd-HHmm')"
            }
        } else {
            $Version = "dev-$(Get-Date -Format 'yyyyMMdd-HHmm')"
        }
    }
}

Write-Host "=== Building and Pushing PIA WireGuard Generator ===" -ForegroundColor Green
Write-Host "Image:      ${DockerUsername}/${Image}" -ForegroundColor Cyan
Write-Host "Dockerfile: $Dockerfile" -ForegroundColor Cyan
Write-Host "Build Type: $BuildType" -ForegroundColor Cyan
Write-Host "Version:    $Version" -ForegroundColor Cyan
if ($Buildx) {
    Write-Host "Multi-arch: Enabled (Platforms: $Platforms)" -ForegroundColor Magenta
}
if ($NoCache) {
    Write-Host "Cache: DISABLED (--no-cache)" -ForegroundColor Yellow
} else {
    Write-Host "Cache: ENABLED (faster builds)" -ForegroundColor Green
}

try {
    Write-Host "`n=== Building ${Image} ===" -ForegroundColor Yellow

    # Build arguments
    $buildArgs = @(
        "--build-arg", "BUILD_DATE=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')",
        "--build-arg", "VERSION=$Version",
        "--build-arg", "VCS_REF=$(if (Get-Command git) { git rev-parse --short HEAD } else { 'unknown' })"
    )

    if ($NoCache) {
        $buildArgs += "--no-cache"
    }

    if ($Buildx) {
        # Multi-arch build using buildx
        Write-Host "Creating multi-arch manifest..." -ForegroundColor Cyan
        
        # Check if buildx is available
        $buildxVersion = docker buildx version 2>$null
        if (-not $buildxVersion) {
            Write-Host "ERROR: Docker buildx is not available. Install it first." -ForegroundColor Red
            exit 1
        }

        # Create and use a new builder instance if needed
        $builderExists = docker buildx ls | Select-String "multiarch"
        if (-not $builderExists) {
            docker buildx create --name multiarch --use
        } else {
            docker buildx use multiarch
        }

        # Build and push multi-arch image
        $buildxCommand = @(
            "buildx", "build",
            "--platform", $Platforms,
            "--tag", "${DockerUsername}/${Image}:$Version",
            "--push"
        )

        if ($BuildType -eq "latest") {
            $buildxCommand += "--tag", "${DockerUsername}/${Image}:latest"
        } else {
            $buildxCommand += "--tag", "${DockerUsername}/${Image}:dev"
        }

        $buildxCommand += $buildArgs
        $buildxCommand += "-f", $Dockerfile
        $buildxCommand += "."

        & docker $buildxCommand

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to build ${Image} image with buildx"
        }

        Write-Host "Multi-arch image built and pushed successfully!" -ForegroundColor Green
    } else {
        # Standard single-arch build
        if ($NoCache) {
            docker build --no-cache $buildArgs -f $Dockerfile -t "${DockerUsername}/${Image}:$Version" .
        } else {
            docker build $buildArgs -f $Dockerfile -t "${DockerUsername}/${Image}:$Version" .
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to build ${Image} image"
        }

        # Apply additional tags based on build type
        if ($BuildType -eq "latest") {
            Write-Host "Tagging as latest..." -ForegroundColor Cyan
            docker tag "${DockerUsername}/${Image}:$Version" "${DockerUsername}/${Image}:latest"
            Write-Host "  - ${DockerUsername}/${Image}:latest" -ForegroundColor Green
        } else {
            Write-Host "Tagging as dev..." -ForegroundColor Cyan
            docker tag "${DockerUsername}/${Image}:$Version" "${DockerUsername}/${Image}:dev"
            Write-Host "  - ${DockerUsername}/${Image}:dev" -ForegroundColor Yellow
        }

        # Login to Docker Hub
        Write-Host "`n=== Logging in to Docker Hub ===" -ForegroundColor Yellow
        docker login
        if ($LASTEXITCODE -ne 0) {
            throw "Docker login failed"
        }

        # Push images to Docker Hub
        Write-Host "`n=== Pushing to Docker Hub ===" -ForegroundColor Yellow

        Write-Host "Pushing version tag: ${DockerUsername}/${Image}:$Version ..." -ForegroundColor Cyan
        docker push "${DockerUsername}/${Image}:$Version"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to push ${Image}:$Version image"
        }

        if ($BuildType -eq "latest") {
            Write-Host "Pushing ${DockerUsername}/${Image}:latest ..." -ForegroundColor Cyan
            docker push "${DockerUsername}/${Image}:latest"
        } else {
            Write-Host "Pushing ${DockerUsername}/${Image}:dev ..." -ForegroundColor Cyan
            docker push "${DockerUsername}/${Image}:dev"
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to push ${Image} image"
        }
    }

    # Success message
    Write-Host "`n=== SUCCESS! ===" -ForegroundColor Green
    Write-Host "PIA WireGuard Generator image pushed to Docker Hub:" -ForegroundColor White

    if ($BuildType -eq "latest") {
        Write-Host "  - ${DockerUsername}/${Image}:$Version" -ForegroundColor Cyan
        Write-Host "  - ${DockerUsername}/${Image}:latest" -ForegroundColor Green
    } else {
        Write-Host "  - ${DockerUsername}/${Image}:$Version" -ForegroundColor Cyan
        Write-Host "  - ${DockerUsername}/${Image}:dev" -ForegroundColor Yellow
    }

    if ($Buildx) {
        Write-Host "  - Multi-arch: $Platforms" -ForegroundColor Magenta
    }

    Write-Host "`nBuild Information:" -ForegroundColor Yellow
    Write-Host "  Build Type: $BuildType" -ForegroundColor Cyan
    Write-Host "  Version:    $Version" -ForegroundColor Cyan
    Write-Host "  Dockerfile: $Dockerfile" -ForegroundColor Cyan
    Write-Host "  Cache:      $(if ($NoCache) { 'Disabled' } else { 'Enabled' })" -ForegroundColor Cyan

    if (-not $Buildx) {
        Write-Host "`nLocal images created:" -ForegroundColor Yellow
        docker images | Select-String "pia-wg-generator"
    }

    # Trigger Dockhand to pull new image and restart the stack
    if (-not $SkipDockhand) {
        Invoke-DockhandDeploy | Out-Null
    } else {
        Write-Host "`nSkipping Dockhand update (remove -SkipDockhand to auto-update)" -ForegroundColor Yellow
    }

} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Build and push failed!" -ForegroundColor Red
    exit 1
}