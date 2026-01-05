param(
    [string]$ModelPath = $env:GOLDEVIDENCEBENCH_MODEL,
    [string]$OutRoot = "",
    [float[]]$Rates = @(0.205, 0.209, 0.22, 0.24),
    [int]$Steps = 320,
    [int]$Queries = 16,
    [int]$MaxBookTokens = 400,
    [string]$Adapter = "goldevidencebench.adapters.retrieval_llama_cpp_adapter:create_adapter",
    [string]$LinearModel = ".\\models\\linear_selector.json",
    [int]$K = 16,
    [int]$StepBucket = 10,
    [bool]$FindWall = $false,
    [float]$Threshold = 0.10,
    [ValidateSet("gte", "lte")]
    [string]$Direction = "gte"
)

if (-not $ModelPath) {
    Write-Error "Set -ModelPath or GOLDEVIDENCEBENCH_MODEL before running."
    exit 1
}

if (-not (Test-Path $LinearModel)) {
    Write-Error "Linear model not found at $LinearModel"
    exit 1
}

if (-not $OutRoot) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutRoot = "runs\\wall_update_burst_full_linear_bucket10_$stamp"
}
New-Item -ItemType Directory -Path $OutRoot -Force | Out-Null
Write-Host "RunsDir: $OutRoot"

Remove-Item Env:\GOLDEVIDENCEBENCH_* -ErrorAction SilentlyContinue
$env:GOLDEVIDENCEBENCH_MODEL = $ModelPath
$env:GOLDEVIDENCEBENCH_RETRIEVAL_RERANK = "linear"
$env:GOLDEVIDENCEBENCH_RETRIEVAL_LINEAR_MODEL = $LinearModel
$env:GOLDEVIDENCEBENCH_RETRIEVAL_STEP_BUCKET = "$StepBucket"
$env:GOLDEVIDENCEBENCH_RETRIEVAL_K = "$K"

$commonArgs = @(
    "--adapter", $Adapter,
    "--no-derived-queries",
    "--no-twins",
    "--require-citations",
    "--max-book-tokens", "$MaxBookTokens"
)

foreach ($rate in $Rates) {
    $outDir = Join-Path $OutRoot "wall_update_burst_full_linear_k${K}_bucket${StepBucket}_rate${rate}"
    goldevidencebench sweep --out $outDir --seeds 1 --episodes 1 --steps $Steps --queries $Queries `
        --state-modes kv --distractor-profiles update_burst --update-burst-rate $rate `
        @commonArgs --results-json "$outDir\combined.json"
    python .\scripts\summarize_results.py --in "$outDir\combined.json" --out-json "$outDir\summary.json"
}

if ($FindWall) {
    python .\scripts\find_wall.py --runs-dir $OutRoot `
        --metric retrieval.wrong_update_rate --param update_burst_rate `
        --threshold $Threshold --direction $Direction --state-mode kv --profile update_burst
}
