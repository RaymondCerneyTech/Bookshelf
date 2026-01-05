param(
    [string]$ModelPath = $env:GOLDEVIDENCEBENCH_MODEL,
    [float]$Threshold = 0.10,
    [ValidateSet("gte", "lte")]
    [string]$Direction = "gte",
    [string]$Adapter = "goldevidencebench.adapters.retrieval_llama_cpp_adapter:create_adapter",
    [string]$LinearModel = ".\\models\\linear_selector.json",
    [string]$RunsDir = "",
    [bool]$AutoPin = $true,
    [int]$PinCount = 4,
    [int]$PinDecimals = 3,
    [int]$StartStage = 1,
    [bool]$StopAfterWall = $true,
    [int]$MaxBookTokens = 400
)

if (-not $ModelPath) {
    Write-Error "Set -ModelPath or GOLDEVIDENCEBENCH_MODEL before running."
    exit 1
}

$finalRunsDir = $RunsDir
if (-not $finalRunsDir) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $finalRunsDir = "runs\\wall_update_burst_$stamp"
}
New-Item -ItemType Directory -Path $finalRunsDir -Force | Out-Null
Write-Host "RunsDir: $finalRunsDir"

$stages = @(
    @{
        Name = "full_prefer_update_latest_k8_fast"
        Tag = "k8_fast"
        SelectorOnly = $false
        Rerank = "prefer_update_latest"
        K = 8
        Steps = 160
        Queries = 8
        Rates = @(0.20, 0.30, 0.35, 0.40, 0.45, 0.50)
        WrongType = $null
        StepBucket = $null
    },
    @{
        Name = "linear_selonly_k8"
        Tag = "k8_linear_selonly"
        SelectorOnly = $true
        Rerank = "linear"
        K = 8
        Steps = 240
        Queries = 16
        Rates = @(0.25, 0.30, 0.35, 0.40, 0.45, 0.50)
        WrongType = "same_key"
        StepBucket = $null
    },
    @{
        Name = "linear_selonly_k16_bucket10"
        Tag = "k16_bucket10"
        SelectorOnly = $true
        Rerank = "linear"
        K = 16
        Steps = 320
        Queries = 16
        Rates = @(0.25, 0.30, 0.35, 0.40, 0.45, 0.50)
        WrongType = "same_key"
        StepBucket = 10
    },
    @{
        Name = "linear_selonly_k16_bucket10_low"
        Tag = "k16_bucket10_low"
        SelectorOnly = $true
        Rerank = "linear"
        K = 16
        Steps = 320
        Queries = 16
        Rates = @(0.05, 0.10, 0.15, 0.20)
        WrongType = "same_key"
        StepBucket = 10
    }
)

if ($StartStage -lt 1 -or $StartStage -gt $stages.Count) {
    Write-Error "StartStage must be between 1 and $($stages.Count)."
    exit 1
}

if (-not (Test-Path $LinearModel)) {
    Write-Error "Linear model not found at $LinearModel"
    exit 1
}

$commonArgs = @(
    "--adapter", $Adapter,
    "--no-derived-queries",
    "--no-twins",
    "--require-citations",
    "--max-book-tokens", "$MaxBookTokens"
)

function Reset-GEBEnv {
    Remove-Item Env:\GOLDEVIDENCEBENCH_* -ErrorAction SilentlyContinue
    $env:GOLDEVIDENCEBENCH_MODEL = $ModelPath
}

function Get-WallResult {
    param(
        [float]$Threshold,
        [string]$Direction
    )
    $output = python .\scripts\find_wall.py --runs-dir $finalRunsDir `
        --metric retrieval.wrong_update_rate --param update_burst_rate `
        --threshold $Threshold --direction $Direction --state-mode kv --profile update_burst
    $output | ForEach-Object { Write-Host $_ }
    $wallParam = $null
    $lastOkParam = $null
    foreach ($line in $output) {
        if ($line -match "^wall_param=([^ ]+)") {
            if ($matches[1] -ne "None") {
                $wallParam = [double]$matches[1]
            }
        }
        if ($line -match "^last_ok_param=([^ ]+)") {
            if ($matches[1] -ne "None") {
                $lastOkParam = [double]$matches[1]
            }
        }
    }
    return [PSCustomObject]@{
        WallParam = $wallParam
        LastOkParam = $lastOkParam
    }
}

function Get-PinRates {
    param(
        [double]$Low,
        [double]$High,
        [int]$Count,
        [int]$Decimals
    )
    if ($High -le $Low -or $Count -le 0) {
        return @()
    }
    $rates = @()
    for ($i = 1; $i -le $Count; $i++) {
        $ratio = $i / ($Count + 1)
        $value = $Low + (($High - $Low) * $ratio)
        $rates += [Math]::Round($value, $Decimals)
    }
    return $rates | Sort-Object -Unique
}

$stageIndex = 1
foreach ($stage in $stages) {
    if ($stageIndex -lt $StartStage) {
        $stageIndex += 1
        continue
    }

    Write-Host "Stage $stageIndex/$($stages.Count): $($stage.Name)"
    Reset-GEBEnv
    if ($stage.SelectorOnly) {
        $env:GOLDEVIDENCEBENCH_RETRIEVAL_SELECTOR_ONLY = "1"
    }
    if ($stage.WrongType) {
        $env:GOLDEVIDENCEBENCH_RETRIEVAL_WRONG_TYPE = $stage.WrongType
    }
    if ($stage.StepBucket) {
        $env:GOLDEVIDENCEBENCH_RETRIEVAL_STEP_BUCKET = "$($stage.StepBucket)"
    }
    $env:GOLDEVIDENCEBENCH_RETRIEVAL_RERANK = $stage.Rerank
    $env:GOLDEVIDENCEBENCH_RETRIEVAL_K = "$($stage.K)"
    if ($stage.Rerank -eq "linear") {
        $env:GOLDEVIDENCEBENCH_RETRIEVAL_LINEAR_MODEL = $LinearModel
    }

    foreach ($rate in $stage.Rates) {
        $outDir = Join-Path $finalRunsDir "wall_update_burst_$($stage.Tag)_rate${rate}"
        goldevidencebench sweep --out $outDir --seeds 1 --episodes 1 --steps $stage.Steps --queries $stage.Queries `
            --state-modes kv --distractor-profiles update_burst --update-burst-rate $rate `
            @commonArgs --results-json "$outDir\combined.json"
        python .\scripts\summarize_results.py --in "$outDir\combined.json" --out-json "$outDir\summary.json"
    }

    $wallResult = Get-WallResult -Threshold $Threshold -Direction $Direction
    if ($AutoPin -and $wallResult.WallParam -and $wallResult.LastOkParam) {
        $pinRates = Get-PinRates -Low $wallResult.LastOkParam -High $wallResult.WallParam -Count $PinCount -Decimals $PinDecimals
        $pinRates = $pinRates | Where-Object { $stage.Rates -notcontains $_ }
        if ($pinRates.Count -gt 0) {
            Write-Host "Pin sweep: $($pinRates -join ',')"
            foreach ($rate in $pinRates) {
                $outDir = Join-Path $finalRunsDir "wall_update_burst_$($stage.Tag)_pin_rate${rate}"
                goldevidencebench sweep --out $outDir --seeds 1 --episodes 1 --steps $stage.Steps --queries $stage.Queries `
                    --state-modes kv --distractor-profiles update_burst --update-burst-rate $rate `
                    @commonArgs --results-json "$outDir\combined.json"
                python .\scripts\summarize_results.py --in "$outDir\combined.json" --out-json "$outDir\summary.json"
            }
            $wallResult = Get-WallResult -Threshold $Threshold -Direction $Direction
        }
    }

    if ($wallResult.WallParam -and $StopAfterWall) {
        Write-Host "Wall found. Stopping after stage $stageIndex."
        exit 0
    }
    $stageIndex += 1
}

Write-Host "Completed all stages."
exit 0
