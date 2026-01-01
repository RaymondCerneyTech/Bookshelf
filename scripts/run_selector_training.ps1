[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ModelPath,
  [string]$DataPath = ".\data\goldevidencebench_kv_commentary.jsonl",
  [string]$SelectorOut = ".\models\linear_selector_note_v2.json",
  [int]$K = 4,
  [int]$Seed = 0,
  [string]$StateMode = "kv_commentary",
  [double]$NoteRate = 0.30,
  [switch]$AuthoritativeOnly,
  [switch]$UseAuthorityFilter,
  [int]$EvalSeeds = 2,
  [int]$EvalSteps = 120,
  [int]$EvalQueries = 16
)

if (-not (Test-Path $ModelPath)) {
  throw "ModelPath not found: $ModelPath"
}

$authoritativeFlag = ""
if ($AuthoritativeOnly) { $authoritativeFlag = "--authoritative-only" }

if (-not (Test-Path $DataPath)) {
  Write-Host "Generating dataset: $DataPath"
  $noteArg = ""
  if ($StateMode -eq "kv_commentary") { $noteArg = "--note-rate $NoteRate" }
  goldevidencebench generate --out $DataPath --seed $Seed --episodes 30 --steps 200 --queries 12 `
    --state-mode $StateMode --distractor-profile standard --distractor-rate 0.7 --clear-rate 0.01 `
    --tail-distractor-steps 80 --require-citations --twins $noteArg
}

Write-Host "Exporting selector training data..."
python .\scripts\export_selector_dataset.py `
  --data $DataPath --out .\data\selector_train.jsonl --k $K --wrong-type same_key --order shuffle $authoritativeFlag

Write-Host "Training selector..."
python .\scripts\train_selector_linear.py `
  --data .\data\selector_train.jsonl --out $SelectorOut

$env:GOLDEVIDENCEBENCH_MODEL = $ModelPath
$env:GOLDEVIDENCEBENCH_RETRIEVAL_RERANK = "linear"
$env:GOLDEVIDENCEBENCH_RETRIEVAL_LINEAR_MODEL = $SelectorOut
$env:GOLDEVIDENCEBENCH_RETRIEVAL_K = $K
$env:GOLDEVIDENCEBENCH_RETRIEVAL_WRONG_TYPE = "same_key"
$env:GOLDEVIDENCEBENCH_RETRIEVAL_ORDER = "shuffle"
$env:GOLDEVIDENCEBENCH_RETRIEVAL_ORDER_SEED = "0"

if ($UseAuthorityFilter -or $StateMode -eq "kv_commentary") {
  $env:GOLDEVIDENCEBENCH_RETRIEVAL_AUTHORITY_FILTER = "1"
}

$outDir = "runs\selector_training_quick"
Write-Host "Running quick eval: $outDir"
goldevidencebench sweep --out $outDir --seeds $EvalSeeds --episodes 1 --steps $EvalSteps --queries $EvalQueries `
  --state-modes $StateMode --distractor-profiles standard `
  --adapter goldevidencebench.adapters.retrieval_llama_cpp_adapter:create_adapter --no-derived-queries `
  --no-twins --require-citations --results-json $outDir\combined.json --max-book-tokens 400
python .\scripts\summarize_results.py --in $outDir\combined.json --out-json $outDir\summary.json

Write-Host "Done. Summary: $outDir\summary.json"
