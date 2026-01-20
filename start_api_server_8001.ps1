# API 서버 시작 스크립트 (포트 8001, Windows PowerShell)

Write-Host "🚀 API 서버 시작 중 (포트 8001)..." -ForegroundColor Cyan

# API 서버 디렉토리로 이동
$apiDir = Join-Path $PSScriptRoot "api_server"
Set-Location $apiDir

# 포트 8001을 사용하는 프로세스 찾기
Write-Host "`n📋 포트 8001 사용 중인 프로세스 확인..." -ForegroundColor Cyan
$processes = Get-NetTCPConnection -LocalPort 8001 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique

if ($processes) {
    foreach ($pid in $processes) {
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "   발견: PID $pid - $($proc.ProcessName)" -ForegroundColor Yellow
            Write-Host "   종료 중..." -ForegroundColor Yellow
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 2
    Write-Host "✅ 기존 프로세스 종료 완료" -ForegroundColor Green
} else {
    Write-Host "   실행 중인 프로세스 없음" -ForegroundColor Gray
}

# 환경변수 설정 (포트 8001)
$env:API_PORT = "8001"
$env:API_HOST = "0.0.0.0"

Write-Host "`n🚀 API 서버 시작 중..." -ForegroundColor Cyan
Write-Host "   포트: 8001" -ForegroundColor Gray

# 가상환경 확인
$venvPath = Join-Path $apiDir "venv"
if (Test-Path $venvPath) {
    $pythonPath = Join-Path $venvPath "Scripts\python.exe"
    if (Test-Path $pythonPath) {
        Write-Host "   가상환경 사용: $pythonPath" -ForegroundColor Gray
        & $pythonPath main.py
    } else {
        Write-Host "   가상환경 Python 없음, 시스템 Python 사용" -ForegroundColor Yellow
        python main.py
    }
} else {
    Write-Host "   가상환경 없음, 시스템 Python 사용" -ForegroundColor Yellow
    # py 또는 python 명령어 시도
    if (Get-Command py -ErrorAction SilentlyContinue) {
        py main.py
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        python main.py
    } else {
        Write-Host "❌ Python을 찾을 수 없습니다!" -ForegroundColor Red
        exit 1
    }
}
