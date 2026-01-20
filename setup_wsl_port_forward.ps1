# WSL 포트 8001 포워딩 설정 (Windows PowerShell - 관리자 권한 필요)

Write-Host "🔧 WSL 포트 8001 포워딩 설정 중..." -ForegroundColor Cyan

# WSL IP 주소 가져오기
$wslIp = (wsl hostname -I).Trim()
Write-Host "📡 WSL IP: $wslIp" -ForegroundColor Yellow

# Windows 호스트 IP 확인
$hostIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -like "192.168.*"} | Select-Object -First 1).IPAddress
Write-Host "📡 Windows 호스트 IP: $hostIp" -ForegroundColor Yellow

# 기존 포트 포워딩 규칙 삭제
Write-Host "`n🗑️  기존 포트 포워딩 규칙 삭제 중..." -ForegroundColor Yellow
netsh interface portproxy delete v4tov4 listenport=8001 listenaddress=0.0.0.0 2>$null
Write-Host "✅ 기존 규칙 삭제 완료" -ForegroundColor Green

# 새로운 포트 포워딩 규칙 추가
Write-Host "`n➕ 포트 포워딩 규칙 추가 중..." -ForegroundColor Yellow
Write-Host "   Windows 포트 8001 → WSL 포트 8001 ($wslIp)" -ForegroundColor Gray

netsh interface portproxy add v4tov4 listenport=8001 listenaddress=0.0.0.0 connectport=8001 connectaddress=$wslIp

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ 포트 포워딩 설정 완료!" -ForegroundColor Green
    
    # 방화벽 규칙 추가
    Write-Host "`n🔥 방화벽 규칙 추가 중..." -ForegroundColor Yellow
    $firewallRule = Get-NetFirewallRule -DisplayName "WSL API Server 8001" -ErrorAction SilentlyContinue
    if (-not $firewallRule) {
        New-NetFirewallRule -DisplayName "WSL API Server 8001" -Direction Inbound -LocalPort 8001 -Protocol TCP -Action Allow | Out-Null
        Write-Host "✅ 방화벽 규칙 추가 완료" -ForegroundColor Green
    } else {
        Write-Host "ℹ️  방화벽 규칙이 이미 존재합니다" -ForegroundColor Gray
    }
    
    Write-Host "`n📋 현재 포트 포워딩 규칙:" -ForegroundColor Cyan
    netsh interface portproxy show v4tov4 | Select-String "8001"
    
    Write-Host "`n🌐 접속 URL:" -ForegroundColor Cyan
    Write-Host "   http://localhost:8001/api/report" -ForegroundColor Green
    Write-Host "   http://$hostIp:8001/api/report" -ForegroundColor Green
    Write-Host "   http://$wslIp:8001/api/report (WSL IP 직접 접속)" -ForegroundColor Green
} else {
    Write-Host "❌ 포트 포워딩 설정 실패" -ForegroundColor Red
    Write-Host "   관리자 권한으로 실행해주세요" -ForegroundColor Yellow
}

Write-Host "`n💡 참고:" -ForegroundColor Cyan
Write-Host "   - 포트 포워딩 규칙 삭제: netsh interface portproxy delete v4tov4 listenport=8001" -ForegroundColor Gray
Write-Host "   - 모든 규칙 확인: netsh interface portproxy show v4tov4" -ForegroundColor Gray
