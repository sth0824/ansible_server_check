# WSL 포트 포워딩 설정 (Windows PowerShell)
# UI_sunmin 브랜치용 포트 8001 포워딩

Write-Host "🔧 WSL 포트 포워딩 설정 중..." -ForegroundColor Cyan

# WSL IP 주소 가져오기
$wslIp = (wsl hostname -I).Trim()
Write-Host "📡 WSL IP: $wslIp" -ForegroundColor Yellow

# 기존 포트 포워딩 규칙 삭제 (있는 경우)
Write-Host "`n🗑️  기존 포트 포워딩 규칙 삭제 중..." -ForegroundColor Yellow
netsh interface portproxy delete v4tov4 listenport=8001 listenaddress=0.0.0.0 2>$null
Write-Host "✅ 기존 규칙 삭제 완료" -ForegroundColor Green

# 새로운 포트 포워딩 규칙 추가
Write-Host "`n➕ 포트 포워딩 규칙 추가 중..." -ForegroundColor Yellow
Write-Host "   Windows 포트 8001 → WSL 포트 8001" -ForegroundColor Gray

netsh interface portproxy add v4tov4 listenport=8001 listenaddress=0.0.0.0 connectport=8001 connectaddress=$wslIp

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ 포트 포워딩 설정 완료!" -ForegroundColor Green
    Write-Host "`n📋 현재 포트 포워딩 규칙:" -ForegroundColor Cyan
    netsh interface portproxy show v4tov4 | Select-String "8001"
    
    Write-Host "`n🌐 접속 URL:" -ForegroundColor Cyan
    Write-Host "   http://192.168.0.18:8001/api/report" -ForegroundColor Green
    Write-Host "   http://localhost:8001/api/report" -ForegroundColor Green
} else {
    Write-Host "❌ 포트 포워딩 설정 실패" -ForegroundColor Red
    Write-Host "   관리자 권한으로 실행해주세요" -ForegroundColor Yellow
}

Write-Host "`n💡 참고:" -ForegroundColor Cyan
Write-Host "   - 포트 포워딩 규칙 삭제: netsh interface portproxy delete v4tov4 listenport=8001" -ForegroundColor Gray
Write-Host "   - 모든 규칙 확인: netsh interface portproxy show v4tov4" -ForegroundColor Gray
