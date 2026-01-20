# WSL 포트 포워딩 설정 (Windows PowerShell)
# 포트 8000 (develop)과 포트 8001 (UI_sunmin) 포워딩

Write-Host "🔧 WSL 포트 포워딩 설정 중..." -ForegroundColor Cyan
Write-Host "   포트 8000: develop 브랜치용" -ForegroundColor Gray
Write-Host "   포트 8001: UI_sunmin 브랜치용" -ForegroundColor Gray
Write-Host ""

# WSL IP 주소 가져오기
$wslIp = (wsl hostname -I).Trim()
Write-Host "📡 WSL IP: $wslIp" -ForegroundColor Yellow
Write-Host ""

# Windows 호스트 IP 확인
$hostIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -like "192.168.*"} | Select-Object -First 1).IPAddress
if (-not $hostIp) {
    $hostIp = "192.168.0.18"
}
Write-Host "📡 Windows 호스트 IP: $hostIp" -ForegroundColor Yellow
Write-Host ""

# 포트 목록
$ports = @(8000, 8001)

# 기존 포트 포워딩 규칙 삭제
Write-Host "🗑️  기존 포트 포워딩 규칙 삭제 중..." -ForegroundColor Yellow
foreach ($port in $ports) {
    netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 2>$null
}
Write-Host "✅ 기존 규칙 삭제 완료" -ForegroundColor Green
Write-Host ""

# 새로운 포트 포워딩 규칙 추가
Write-Host "➕ 포트 포워딩 규칙 추가 중..." -ForegroundColor Yellow
$successCount = 0

foreach ($port in $ports) {
    Write-Host "   Windows 포트 $port → WSL 포트 $port ($wslIp)" -ForegroundColor Gray
    netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$wslIp
    
    if ($LASTEXITCODE -eq 0) {
        $successCount++
    }
}

Write-Host ""

# 방화벽 규칙 추가
Write-Host "🔥 방화벽 규칙 추가 중..." -ForegroundColor Yellow
foreach ($port in $ports) {
    $firewallRule = Get-NetFirewallRule -DisplayName "WSL API Server $port" -ErrorAction SilentlyContinue
    if (-not $firewallRule) {
        New-NetFirewallRule -DisplayName "WSL API Server $port" -Direction Inbound -LocalPort $port -Protocol TCP -Action Allow | Out-Null
        Write-Host "   ✅ 포트 $port 방화벽 규칙 추가 완료" -ForegroundColor Green
    } else {
        Write-Host "   ℹ️  포트 $port 방화벽 규칙이 이미 존재합니다" -ForegroundColor Gray
    }
}

Write-Host ""

if ($successCount -eq $ports.Count) {
    Write-Host "✅ 포트 포워딩 설정 완료!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 현재 포트 포워딩 규칙:" -ForegroundColor Cyan
    netsh interface portproxy show v4tov4 | Select-String -Pattern "8000|8001"
    
    Write-Host ""
    Write-Host "🌐 접속 URL:" -ForegroundColor Cyan
    Write-Host "   포트 8000 (develop):" -ForegroundColor Yellow
    Write-Host "      http://$hostIp:8000/api/report" -ForegroundColor Green
    Write-Host "      http://localhost:8000/api/report" -ForegroundColor Green
    Write-Host ""
    Write-Host "   포트 8001 (UI_sunmin):" -ForegroundColor Yellow
    Write-Host "      http://$hostIp:8001/api/report" -ForegroundColor Green
    Write-Host "      http://localhost:8001/api/report" -ForegroundColor Green
} else {
    Write-Host "❌ 포트 포워딩 설정 실패" -ForegroundColor Red
    Write-Host "   관리자 권한으로 실행해주세요" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "💡 참고:" -ForegroundColor Cyan
Write-Host "   - 포트 포워딩 규칙 삭제: netsh interface portproxy delete v4tov4 listenport=<포트>" -ForegroundColor Gray
Write-Host "   - 모든 규칙 확인: netsh interface portproxy show v4tov4" -ForegroundColor Gray
