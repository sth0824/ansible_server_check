"""
Ansible 점검 결과 수집 API 서버
FastAPI 기반으로 점검 결과를 받아서 DB에 저장
"""
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from typing import Dict, Any, Optional, List
from datetime import datetime, timezone, timedelta
from contextlib import asynccontextmanager
import uvicorn
import json
import asyncio
from database import init_db, save_check_result, get_check_results
from models import CheckResult

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 서버 시작 시
    init_db()
    print("✅ 데이터베이스 초기화 완료")
    yield
    # 서버 종료 시 (필요한 경우 정리 작업)

app = FastAPI(
    title="Ansible 점검 결과 수집 API",
    description="OS/WAS/DB 점검 결과를 수집하고 저장하는 API 서버",
    version="1.0.0",
    lifespan=lifespan
)

# WebSocket 연결 관리
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except:
                pass

manager = ConnectionManager()

# CORS 설정 (필요시 프론트엔드에서 접근 가능하도록)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 프로덕션에서는 특정 도메인만 허용
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class CheckResultRequest(BaseModel):
    """점검 결과 요청 모델"""
    check_type: str  # "os", "was", "mariadb", "postgresql", "cubrid" 등
    hostname: str
    check_time: str
    checker: str
    status: str  # "success", "warning", "error"
    results: Dict[str, Any]




@app.get("/")
async def root():
    """루트 엔드포인트"""
    return {
        "message": "Ansible 점검 결과 수집 API 서버",
        "version": "1.0.0",
        "endpoints": {
            "POST /api/checks": "점검 결과 저장",
            "GET /api/checks": "점검 결과 조회",
            "GET /api/health": "서버 상태 확인",
            "GET /api/db-checks/report": "DB 점검 결과 리포트 (HTML)",
            "GET /api/os-checks/report": "OS 점검 결과 리포트 (HTML)",
            "GET /api/was-checks/report": "WAS 점검 결과 리포트 (HTML)"
        }
    }


@app.get("/api/health")
async def health_check():
    """서버 상태 확인"""
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat()
    }


@app.post("/api/checks")
async def create_check_result(check_result: CheckResultRequest):
    """
    점검 결과를 받아서 DB에 저장
    
    Args:
        check_result: 점검 결과 데이터
        
    Returns:
        저장된 결과 정보
    """
    try:
        # DB에 저장
        result_id = save_check_result(
            check_type=check_result.check_type,
            hostname=check_result.hostname,
            check_time=check_result.check_time,
            checker=check_result.checker,
            status=check_result.status,
            results=check_result.results
        )
        
        # WebSocket으로 실시간 업데이트 브로드캐스트
        try:
            await manager.broadcast({
                "type": "new_check_result",
                "check_type": check_result.check_type,
                "hostname": check_result.hostname,
                "checker": check_result.checker,
                "status": check_result.status,
                "timestamp": datetime.now().isoformat()
            })
        except:
            pass  # WebSocket 브로드캐스트 실패해도 저장은 성공
        
        return {
            "success": True,
            "message": "점검 결과가 성공적으로 저장되었습니다",
            "id": result_id,
            "check_type": check_result.check_type,
            "hostname": check_result.hostname,
            "check_time": check_result.check_time
        }
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"점검 결과 저장 중 오류 발생: {str(e)}"
        )


@app.get("/api/checks")
async def list_check_results(
    check_type: Optional[str] = None,
    hostname: Optional[str] = None,
    checker: Optional[str] = None,
    id: Optional[int] = None,
    limit: int = 100
):
    """
    저장된 점검 결과 조회
    
    Args:
        check_type: 점검 유형 필터
        hostname: 호스트명 필터
        checker: 담당자 필터
        id: 점검 결과 ID (특정 ID 조회 시)
        limit: 최대 조회 개수
        
    Returns:
        점검 결과 목록
    """
    try:
        # ID로 조회하는 경우
        if id is not None:
            from database import SessionLocal
            from models import CheckResult
            db = SessionLocal()
            try:
                result = db.query(CheckResult).filter(CheckResult.id == id).first()
                if result:
                    return {
                        "success": True,
                        "count": 1,
                        "results": [result.to_dict()]
                    }
                else:
                    raise HTTPException(status_code=404, detail=f"ID {id}에 해당하는 점검 결과를 찾을 수 없습니다.")
            finally:
                db.close()
        
        results = get_check_results(
            check_type=check_type,
            hostname=hostname,
            checker=checker,
            limit=limit
        )
        return {
            "success": True,
            "count": len(results),
            "results": results
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"점검 결과 조회 중 오류 발생: {str(e)}"
        )


def format_check_time(check_time_str: str) -> str:
    """점검 시간을 한국어 형식으로 포맷팅"""
    if not check_time_str or check_time_str == "N/A":
        return "N/A"
    
    try:
        # ISO 8601 형식 파싱 (예: "2026-01-09T01:58:51Z")
        if 'T' in check_time_str:
            # ISO 8601 형식 파싱
            dt_str = check_time_str.replace('Z', '+00:00')
            dt = datetime.fromisoformat(dt_str)
            
            # UTC 시간대가 없으면 UTC로 간주
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            
            # 한국 시간대(KST, UTC+9)로 변환
            kst = timezone(timedelta(hours=9))
            dt_kst = dt.astimezone(kst)
            
            # 한국어 형식으로 포맷팅 (예: "2026. 1. 9. 오전 10:58:51")
            # strftime에서 %-m, %-d는 Windows에서 지원되지 않으므로 직접 처리
            year = dt_kst.year
            month = dt_kst.month
            day = dt_kst.day
            hour = dt_kst.hour
            minute = dt_kst.minute
            second = dt_kst.second
            
            # 오전/오후 구분
            am_pm = "오전" if hour < 12 else "오후"
            hour_12 = hour if hour <= 12 else hour - 12
            if hour_12 == 0:
                hour_12 = 12
            
            return f"{year}. {month}. {day}. {am_pm} {hour_12}:{minute:02d}:{second:02d}"
        return check_time_str
    except Exception:
        return check_time_str


def format_db_result(result: Dict[str, Any]) -> Dict[str, Any]:
    """DB 점검 결과를 표 형식으로 정리"""
    check_type = result.get("check_type", "")
    results = result.get("results", {})
    formatted = {
        "id": result.get("id"),
        "점검유형": check_type.upper(),
        "호스트명": result.get("hostname", "N/A"),
        "점검시간": format_check_time(result.get("check_time", "N/A")),
        "check_time": result.get("check_time", "N/A"),  # 원본 날짜 (차트용)
        "담당자": result.get("checker", "N/A"),
        "상태": result.get("status", "N/A"),
    }
    
    if check_type == "mariadb":
        # MariaDB 점검 결과 정리
        installation = results.get("installation", {})
        service_status = results.get("service_status", {})
        listener = results.get("listener", "N/A")
        os_resources = results.get("os_resources", {})
        db_internal = results.get("db_internal", {})
        database = results.get("database", {})
        directory_structure = results.get("directory_structure", "N/A")
        filesystem_usage = results.get("filesystem_usage", "N/A")
        
        # 메모리 정보 파싱 (안전하게)
        memory_total = "N/A"
        memory_used = "N/A"
        memory_available = "N/A"
        try:
            mem_data = os_resources.get("memory", "")
            if isinstance(mem_data, dict):
                mem_str = mem_data.get("detail", "")
            else:
                mem_str = str(mem_data)
            if isinstance(mem_str, str) and "\n" in mem_str:
                lines = mem_str.split("\n")
                if len(lines) > 1:
                    parts = lines[1].split()
                    if len(parts) >= 2:
                        memory_total = parts[1]
                        memory_used = parts[2] if len(parts) > 2 else "N/A"
                        memory_available = parts[6] if len(parts) > 6 else "N/A"
        except:
            pass
        
        # CPU 정보 파싱
        cpu_info = "N/A"
        try:
            cpu_data = os_resources.get("cpu", "")
            if isinstance(cpu_data, dict):
                cpu_str = cpu_data.get("detail", "")
            else:
                cpu_str = str(cpu_data)
            if isinstance(cpu_str, str):
                if "%Cpu" in cpu_str:
                    cpu_info = cpu_str.split("%Cpu")[1].strip()[:50] if "%Cpu" in cpu_str else "N/A"
        except:
            pass
        
        # InnoDB 버퍼풀 파싱
        innodb_bp = "N/A"
        try:
            bp_str = db_internal.get("innodb_buffer_pool", "")
            if isinstance(bp_str, str) and "\t" in bp_str:
                innodb_bp = bp_str.split("\t")[1].strip()
        except:
            pass
        
        # 바이너리 로그 파싱
        log_bin_status = "OFF"
        try:
            log_bin_str = db_internal.get("log_bin", "")
            if "ON" in str(log_bin_str):
                log_bin_status = "ON"
        except:
            pass
        
        # 테이블스페이스 요약
        tablespace_summary = "N/A"
        try:
            ts_str = db_internal.get("tablespace", "")
            if isinstance(ts_str, str):
                lines = ts_str.split("\n")
                if len(lines) > 0:
                    tablespace_summary = f"{len(lines)}개 DB" + (f" | {lines[0][:30]}..." if lines[0] else "")
        except:
            pass
        
        # 온라인 백업 가능 여부 파싱
        online_backup_possible = db_internal.get("online_backup_possible", "N/A")
        
        # 설치 확인 파싱
        installation_status = "✗"
        installation_path = "N/A"
        try:
            installed_str = str(installation.get("installed", "")).strip()
            # 첫 줄만 확인 (여러 줄이 있을 수 있음)
            if "\n" in installed_str:
                installed_str = installed_str.split("\n")[0]
            if installed_str.upper() == "INSTALLED":
                installation_status = "✓"
            installation_path = installation.get("base_directory", installation.get("binary_path", "N/A"))
        except:
            pass
        
        # 데이터베이스 정보 파싱
        db_list = database.get("db_list", "N/A")
        db_count = database.get("db_count", "N/A")
        # 빈 문자열이나 공백만 있는 경우 처리
        if isinstance(db_list, str):
            db_list_stripped = db_list.strip()
            if db_list_stripped and db_list_stripped != "N/A":
                db_list_display = db_list_stripped[:50] + "..." if len(db_list_stripped) > 50 else db_list_stripped
            else:
                db_list_display = "없음"  # 빈 문자열이면 "없음"으로 표시
        else:
            db_list_display = "N/A"
        
        # CPU/메모리 상위 프로세스 파싱
        cpu_top = "N/A"
        mem_top = "N/A"
        try:
            cpu_top_str = os_resources.get("cpu_top_processes", "")
            mem_top_str = os_resources.get("mem_top_processes", "")
            if isinstance(cpu_top_str, str) and cpu_top_str.strip() and cpu_top_str != "N/A":
                cpu_top = "있음"
            if isinstance(mem_top_str, str) and mem_top_str.strip() and mem_top_str != "N/A":
                mem_top = "있음"
        except:
            pass
        
        # OS 기초 체력 점검 항목 파싱
        os_basics = results.get("os_basics", {})
        cpu_model = os_basics.get("cpu_model_name", "N/A")
        
        # Swap 상태 파싱
        swap_status_display = "N/A"
        try:
            swap_str = os_basics.get("swap_status", "")
            if isinstance(swap_str, str) and swap_str.strip():
                # "Swap: 2.0Gi 0B 2.0Gi" 형식에서 사용량 추출
                parts = swap_str.split()
                if len(parts) >= 3:
                    swap_status_display = f"{parts[1]} / {parts[2]}"
        except:
            pass
        
        # 루트 디스크 사용률
        root_disk_usage = os_basics.get("root_disk_usage", "N/A")
        root_disk_display = f"{root_disk_usage}%" if root_disk_usage != "N/A" and root_disk_usage.isdigit() else root_disk_usage
        
        # 전체 디스크 사용 현황 요약
        all_disk_summary = "N/A"
        try:
            all_disk_str = os_basics.get("all_disk_usage", "")
            if isinstance(all_disk_str, str) and all_disk_str.strip():
                # df -h 출력에서 70% 이상인 것만 카운트
                lines = all_disk_str.split("\n")
                high_usage_count = 0
                for line in lines[1:]:  # 첫 줄(헤더) 제외
                    if "%" in line and "Use%" not in line:
                        parts = line.split()
                        for part in parts:
                            if part.endswith("%") and part != "Use%":
                                try:
                                    usage = int(part.replace("%", ""))
                                    if usage >= 70:
                                        high_usage_count += 1
                                except (ValueError, AttributeError):
                                    pass
                if high_usage_count > 0:
                    all_disk_summary = f"{high_usage_count}개 디스크 70% 이상"
                else:
                    all_disk_summary = "정상"
        except Exception:
            pass
        
        # 네트워크 통신 상태
        network_status = "N/A"
        try:
            ping_result = os_basics.get("network_ping_result", "")
            if isinstance(ping_result, str):
                if "0% packet loss" in ping_result or "0 received" not in ping_result:
                    network_status = "✓ 연결됨"
                else:
                    network_status = "✗ 연결실패"
        except:
            pass
        
        # NTP 동기화 상태
        ntp_status = "N/A"
        try:
            ntp_str = os_basics.get("ntp_sync_status", "")
            if isinstance(ntp_str, str):
                if "NTP not configured" in ntp_str:
                    ntp_status = "미설정"
                elif "*" in ntp_str or "^*" in ntp_str:
                    ntp_status = "✓ 동기화됨"
                else:
                    ntp_status = "설정됨"
        except:
            pass
        
        # 파일시스템 사용률 파싱
        db_engine_fs = "N/A"
        archive_log_fs = "N/A"
        system_log_fs = "N/A"
        try:
            if isinstance(filesystem_usage, dict):
                # DB엔진 파일시스템 파싱 (df -h 출력에서 사용률 추출)
                db_engine_str = filesystem_usage.get("db_engine", "")
                if isinstance(db_engine_str, str) and db_engine_str != "N/A" and db_engine_str.strip():
                    # df -h 출력 형식: "/dev/sdd       1007G  4.2G  952G   1% /"
                    parts = db_engine_str.split()
                    if len(parts) >= 5:
                        # 사용률 추출 (예: "1%")
                        usage = parts[-2] if parts[-2].endswith("%") else "N/A"
                        # 파일시스템과 마운트 포인트
                        fs_info = f"{parts[0]} {usage} {parts[-1]}" if usage != "N/A" else db_engine_str[:50]
                        db_engine_fs = fs_info
                    else:
                        db_engine_fs = db_engine_str[:50]
                
                # 아카이브 로그 파일시스템 파싱
                archive_log_str = filesystem_usage.get("archive_log", "")
                if isinstance(archive_log_str, str) and archive_log_str != "N/A" and archive_log_str.strip():
                    if "not found" not in archive_log_str.lower():
                        parts = archive_log_str.split()
                        if len(parts) >= 5:
                            usage = parts[-2] if parts[-2].endswith("%") else "N/A"
                            fs_info = f"{parts[0]} {usage} {parts[-1]}" if usage != "N/A" else archive_log_str[:50]
                            archive_log_fs = fs_info
                        else:
                            archive_log_fs = archive_log_str[:50]
                    else:
                        archive_log_fs = "N/A"
                
                # 시스템 로그 파일시스템 파싱
                system_log_str = filesystem_usage.get("system_log", "")
                if isinstance(system_log_str, str) and system_log_str != "N/A" and system_log_str.strip():
                    if "not found" not in system_log_str.lower():
                        parts = system_log_str.split()
                        if len(parts) >= 5:
                            usage = parts[-2] if parts[-2].endswith("%") else "N/A"
                            fs_info = f"{parts[0]} {usage} {parts[-1]}" if usage != "N/A" else system_log_str[:50]
                            system_log_fs = fs_info
                        else:
                            system_log_fs = system_log_str[:50]
                    else:
                        system_log_fs = "N/A"
        except Exception as e:
            pass
        
        # 최대연결수 파싱
        max_conn = "N/A"
        try:
            max_conn_str = db_internal.get("max_connections", "")
            if isinstance(max_conn_str, str) and max_conn_str.strip() and max_conn_str != "N/A":
                max_conn = max_conn_str.strip()
        except:
            pass
        
        # 활성세션수 파싱
        active_sess = "N/A"
        try:
            sess_str = db_internal.get("active_sessions", "")
            if isinstance(sess_str, str) and sess_str.strip() and sess_str != "N/A":
                active_sess = sess_str.strip()
            elif isinstance(sess_str, (int, float)):
                active_sess = str(int(sess_str))
        except:
            pass
        
        # DB접속상태 파싱
        db_conn_status = "N/A"
        try:
            conn_str = db_internal.get("db_connection_status", "")
            if isinstance(conn_str, str):
                if "CONNECTED" in conn_str.upper():
                    db_conn_status = "✓ 연결됨"
                elif "DISCONNECTED" in conn_str.upper():
                    db_conn_status = "✗ 연결실패"
                else:
                    db_conn_status = conn_str
        except:
            pass
        
        # 관리프로세스 파싱
        admin_proc = "N/A"
        try:
            proc_str = db_internal.get("mariadb_process", "")
            if isinstance(proc_str, str):
                if "RUNNING" in proc_str.upper():
                    admin_proc = "✓ 실행중"
                elif "NOT_RUNNING" in proc_str.upper():
                    admin_proc = "✗ 중지됨"
                else:
                    admin_proc = proc_str
        except:
            pass
        
        # HA상태 파싱
        ha_status_display = "N/A"
        try:
            ha_str = db_internal.get("ha_status", "")
            if isinstance(ha_str, str) and ha_str.strip() and ha_str != "N/A":
                ha_status_display = ha_str.strip()[:50]
        except:
            pass
        
        formatted.update({
            "설치확인": installation_status,
            "설치경로": str(installation_path)[:40],
            "디렉토리구조": "있음" if "not present" not in str(directory_structure).lower() else "없음",
            "파일시스템": "있음" if "not found" not in str(filesystem_usage).lower() else "없음",
            "서비스상태": f"{service_status.get('active', 'N/A')}/{service_status.get('substate', 'N/A')}",
            "리스너(MariaDB)": "LISTENING" if "LISTEN" in str(listener) else "NOT LISTENING",
            "DB엔진파일시스템": db_engine_fs,
            "아카이브로그파일시스템": archive_log_fs,
            "시스템로그파일시스템": system_log_fs,
            "메모리(Total)": memory_total,
            "메모리(Used)": memory_used,
            "메모리(Available)": memory_available,
            "메모리": f"{memory_total} / {memory_available}",
            "메모리사용률": os_resources.get("memory", {}).get("usage_percent", "N/A") if isinstance(os_resources.get("memory"), dict) else "N/A",
            "CPU사용률": cpu_info,
            "CPU": os_resources.get("cpu", {}).get("usage_percent", "N/A") if isinstance(os_resources.get("cpu"), dict) else "N/A",
            "프로세스수": os_resources.get("process_count", "N/A"),
            "InnoDB버퍼풀": innodb_bp,
            "바이너리로그": log_bin_status,
            "테이블스페이스": tablespace_summary,
            "데이터베이스수": str(db_count).strip() if str(db_count).strip() != "0" else "0 (사용자 DB 없음)",
            "데이터베이스목록": db_list_display,
            "최대연결수": max_conn,
            "활성세션수": active_sess,
            "DB접속상태": db_conn_status,
            "관리프로세스": admin_proc,
            "HA상태": ha_status_display,
            "온라인백업가능": "가능" if "POSSIBLE" in str(online_backup_possible).upper() else "불가능",
            "CPU상위프로세스": cpu_top,
            "메모리상위프로세스": mem_top,
            "CPU모델명": cpu_model[:50] if cpu_model != "N/A" else "N/A",
            "Swap상태": swap_status_display,
            "루트디스크사용률": root_disk_display,
            "디스크사용현황": all_disk_summary,
            "파일시스템(70%초과)": all_disk_summary,  # 동일한 값 사용
            "네트워크통신": network_status,
            "NTP동기화": ntp_status,
        })
    
    elif check_type == "postgresql":
        # PostgreSQL 점검 결과 정리
        installation = results.get("installation", {})
        service_status = results.get("service_status", {})
        listener = results.get("listener", {})
        db_parameters = results.get("db_parameters", {})
        tablespace = results.get("tablespace", {})
        wal = results.get("wal", {})
        filesystem_usage = results.get("filesystem_usage", {})
        db_connection = results.get("db_connection", {})
        os_resources = results.get("os_resources", {})
        database = results.get("database", {})
        
        # 파일시스템 사용률 파싱
        fs_usage = "정상"
        try:
            fs_str = filesystem_usage.get("usage_over_70", "")
            if fs_str and fs_str.strip() and fs_str != "N/A":
                fs_usage = "70% 초과 있음"
        except:
            pass
        
        # DB엔진 파일시스템 파싱
        db_engine_fs = "N/A"
        try:
            db_engine_str = filesystem_usage.get("db_engine", "")
            if isinstance(db_engine_str, str) and db_engine_str != "N/A":
                # 사용률 추출 (예: "34%")
                db_engine_fs = db_engine_str.split()[-2] if len(db_engine_str.split()) >= 5 else "N/A"
        except:
            pass
        
        # 리스너 파싱
        listener_status = "NOT LISTENING"
        listener_detail = ""
        try:
            listener_str = str(listener.get("port_5432", ""))
            if "LISTEN" in listener_str:
                listener_status = "LISTENING"
                # IP 주소 추출
                if "127.0.0.1" in listener_str:
                    listener_detail = "localhost"
                elif "0.0.0.0" in listener_str:
                    listener_detail = "all"
        except:
            pass
        
        # DB 접속 상태 파싱
        db_conn_status = "N/A"
        session_count = "N/A"
        try:
            db_conn_str = db_connection.get("status", "")
            if isinstance(db_conn_str, str):
                if "CONNECTED" in db_conn_str.upper():
                    db_conn_status = "✓ 연결됨"
                elif "DISCONNECTED" in db_conn_str.upper() or "NO_CONNECTIONS" in db_conn_str.upper():
                    db_conn_status = "✗ 연결실패"
                else:
                    db_conn_status = db_conn_str
            
            # 활성세션수 파싱
            session_str = db_connection.get("active_sessions", "")
            if isinstance(session_str, str) and session_str != "N/A" and session_str.strip():
                session_count = session_str.strip()
            elif isinstance(session_str, (int, float)):
                session_count = str(int(session_str))
            else:
                # session_detail에서 줄 수 계산 (fallback)
                session_detail = db_connection.get("session_detail", "")
                if isinstance(session_detail, str) and session_detail != "N/A" and session_detail.strip():
                    if "\n" in session_detail:
                        session_count = str(len([l for l in session_detail.split("\n") if l.strip()]))
                    else:
                        session_count = "1" if session_detail.strip() else "0"
        except:
            pass
        
        # 관리프로세스 파싱
        admin_proc = "N/A"
        try:
            proc_str = results.get("postgres_process", "")
            if isinstance(proc_str, str):
                if "RUNNING" in proc_str.upper():
                    admin_proc = "✓ 실행중"
                elif "NOT_RUNNING" in proc_str.upper():
                    admin_proc = "✗ 중지됨"
                else:
                    admin_proc = proc_str
        except:
            pass
        
        # HA상태 파싱
        ha_status_display = "N/A"
        try:
            ha_str = results.get("ha_status", "")
            if isinstance(ha_str, str) and ha_str.strip() and ha_str != "N/A":
                ha_status_display = ha_str.strip()[:50]
        except:
            pass
        
        # 메모리 정보 파싱
        memory_info = "N/A"
        memory_percent = "N/A"
        try:
            mem_detail = os_resources.get("memory", {})
            if isinstance(mem_detail, dict):
                mem_str = mem_detail.get("detail", "")
                memory_percent = mem_detail.get("usage_percent", "N/A")
                if isinstance(mem_str, str) and "\n" in mem_str:
                    lines = mem_str.split("\n")
                    if len(lines) > 1:
                        parts = lines[1].split()
                        if len(parts) >= 2:
                            memory_info = f"{parts[1]} / {parts[2]}"
            elif isinstance(mem_detail, str):
                # 이전 형식 호환
                if "\n" in mem_detail:
                    lines = mem_detail.split("\n")
                    if len(lines) > 1:
                        parts = lines[1].split()
                        if len(parts) >= 2:
                            memory_info = f"{parts[1]} / {parts[2]}"
        except:
            pass
        
        # CPU 정보 파싱
        cpu_info = "N/A"
        cpu_percent = "N/A"
        try:
            cpu_detail = os_resources.get("cpu", {})
            if isinstance(cpu_detail, dict):
                cpu_str = cpu_detail.get("detail", "")
                cpu_percent = cpu_detail.get("usage_percent", "N/A")
                cpu_info = cpu_str[:50] if isinstance(cpu_str, str) else "N/A"
            elif isinstance(cpu_detail, str):
                cpu_info = cpu_detail[:50]
        except:
            pass
        
        # WAL 크기 파싱
        wal_size = "N/A"
        try:
            wal_str = wal.get("wal_size", "")
            if isinstance(wal_str, str) and wal_str != "N/A":
                wal_size = wal_str.strip()
        except:
            pass
        
        # 테이블스페이스 요약
        tablespace_summary = "N/A"
        try:
            ts_str = tablespace.get("usage", "")
            if isinstance(ts_str, str) and ts_str != "N/A":
                lines = ts_str.split("\n")
                if len(lines) > 0:
                    tablespace_summary = f"{len(lines)}개" + (f" | {lines[0][:30]}..." if lines[0] else "")
        except:
            pass
        
        # 설치 확인 파싱
        installation_status = "✗"
        installation_path = "N/A"
        try:
            installed_str = str(installation.get("installed", "")).strip()
            # 첫 줄만 확인 (여러 줄이 있을 수 있음)
            if "\n" in installed_str:
                installed_str = installed_str.split("\n")[0]
            if installed_str.upper() == "INSTALLED":
                installation_status = "✓"
            installation_path = installation.get("base_directory", installation.get("binary_path", "N/A"))
        except:
            pass
        
        # 데이터베이스 정보 파싱
        db_list = database.get("db_list", "N/A")
        db_count = database.get("db_count", "N/A")
        # 빈 문자열이나 공백만 있는 경우 처리
        if isinstance(db_list, str):
            db_list_stripped = db_list.strip()
            if db_list_stripped and db_list_stripped != "N/A":
                db_list_display = db_list_stripped[:50] + "..." if len(db_list_stripped) > 50 else db_list_stripped
            else:
                db_list_display = "없음"  # 빈 문자열이면 "없음"으로 표시
        else:
            db_list_display = "N/A"
        
        # CPU/메모리 상위 프로세스 파싱
        cpu_top = "N/A"
        mem_top = "N/A"
        try:
            cpu_top_str = os_resources.get("cpu_top_processes", "")
            mem_top_str = os_resources.get("mem_top_processes", "")
            if isinstance(cpu_top_str, str) and cpu_top_str.strip() and cpu_top_str != "N/A":
                cpu_top = "있음"
            if isinstance(mem_top_str, str) and mem_top_str.strip() and mem_top_str != "N/A":
                mem_top = "있음"
        except:
            pass
        
        # OS 기초 체력 점검 항목 파싱
        os_basics = results.get("os_basics", {})
        cpu_model = os_basics.get("cpu_model_name", "N/A")
        
        # Swap 상태 파싱
        swap_status_display = "N/A"
        try:
            swap_str = os_basics.get("swap_status", "")
            if isinstance(swap_str, str) and swap_str.strip():
                # "Swap: 2.0Gi 0B 2.0Gi" 형식에서 사용량 추출
                parts = swap_str.split()
                if len(parts) >= 3:
                    swap_status_display = f"{parts[1]} / {parts[2]}"
        except:
            pass
        
        # 루트 디스크 사용률
        root_disk_usage = os_basics.get("root_disk_usage", "N/A")
        root_disk_display = f"{root_disk_usage}%" if root_disk_usage != "N/A" and root_disk_usage.isdigit() else root_disk_usage
        
        # 전체 디스크 사용 현황 요약
        all_disk_summary = "N/A"
        try:
            all_disk_str = os_basics.get("all_disk_usage", "")
            if isinstance(all_disk_str, str) and all_disk_str.strip():
                # df -h 출력에서 70% 이상인 것만 카운트
                lines = all_disk_str.split("\n")
                high_usage_count = 0
                for line in lines[1:]:  # 첫 줄(헤더) 제외
                    if "%" in line and "Use%" not in line:
                        parts = line.split()
                        for part in parts:
                            if part.endswith("%") and part != "Use%":
                                try:
                                    usage = int(part.replace("%", ""))
                                    if usage >= 70:
                                        high_usage_count += 1
                                except (ValueError, AttributeError):
                                    pass
                if high_usage_count > 0:
                    all_disk_summary = f"{high_usage_count}개 디스크 70% 이상"
                else:
                    all_disk_summary = "정상"
        except Exception:
            pass
        
        # 네트워크 통신 상태
        network_status = "N/A"
        try:
            ping_result = os_basics.get("network_ping_result", "")
            if isinstance(ping_result, str):
                if "0% packet loss" in ping_result or "0 received" not in ping_result:
                    network_status = "✓ 연결됨"
                else:
                    network_status = "✗ 연결실패"
        except:
            pass
        
        # NTP 동기화 상태
        ntp_status = "N/A"
        try:
            ntp_str = os_basics.get("ntp_sync_status", "")
            if isinstance(ntp_str, str):
                if "NTP not configured" in ntp_str:
                    ntp_status = "미설정"
                elif "*" in ntp_str or "^*" in ntp_str:
                    ntp_status = "✓ 동기화됨"
                else:
                    ntp_status = "설정됨"
        except:
            pass
        
        # 디렉토리구조 파싱
        directory_structure = results.get("directory_structure", "N/A")
        
        # 메모리 상세 정보 파싱 (Total, Used, Available)
        memory_total = "N/A"
        memory_used = "N/A"
        memory_available = "N/A"
        try:
            mem_detail = os_resources.get("memory", {})
            if isinstance(mem_detail, dict):
                mem_str = mem_detail.get("detail", "")
                if isinstance(mem_str, str) and "\n" in mem_str:
                    lines = mem_str.split("\n")
                    if len(lines) > 1:
                        parts = lines[1].split()
                        if len(parts) >= 2:
                            memory_total = parts[1]
                            memory_used = parts[2] if len(parts) > 2 else "N/A"
                            memory_available = parts[6] if len(parts) > 6 else "N/A"
        except:
            pass
        
        formatted.update({
            "설치확인": installation_status,
            "설치경로": str(installation_path)[:40],
            "디렉토리구조": "있음" if "not present" not in str(directory_structure).lower() else "없음",
            "DB엔진파일시스템": db_engine_fs,
            "아카이브로그파일시스템": filesystem_usage.get("archive_log", "N/A")[:50],
            "시스템로그파일시스템": filesystem_usage.get("system_log", "N/A")[:50],
            "파일시스템": "있음" if "not found" not in str(filesystem_usage).lower() else "없음",
            "파일시스템(70%초과)": fs_usage if isinstance(fs_usage, str) else "정상",
            "서비스상태": f"{service_status.get('active', 'N/A')}/{service_status.get('substate', 'N/A')}",
            "리스너(PostgreSQL)": f"{listener_status} ({listener_detail})",
            "DB접속상태": db_conn_status,
            "활성세션수": session_count,
            "관리프로세스": admin_proc,
            "HA상태": ha_status_display,
            "메모리(Total)": memory_total,
            "메모리(Used)": memory_used,
            "메모리(Available)": memory_available,
            "메모리": memory_info,
            "메모리사용률": memory_percent,
            "CPU": cpu_info,
            "CPU사용률": cpu_percent,
            "프로세스수": os_resources.get("process_count", "N/A"),
            "공유버퍼": str(db_parameters.get("shared_buffers", "N/A")).strip(),
            "최대연결수": str(db_parameters.get("max_connections", "N/A")).strip(),
            "테이블스페이스": tablespace_summary,
            "아카이브모드": str(wal.get("archive_mode", "N/A")).strip(),
            "온라인백업가능": "가능" if "POSSIBLE" in str(wal.get("online_backup_possible", "")).upper() else "불가능",
            "WAL크기": wal_size,
            "데이터베이스수": str(db_count).strip() if str(db_count).strip() != "0" else "0 (사용자 DB 없음)",
            "데이터베이스목록": db_list_display,
            "CPU상위프로세스": cpu_top,
            "메모리상위프로세스": mem_top,
            "CPU모델명": cpu_model[:50] if cpu_model != "N/A" else "N/A",
            "Swap상태": swap_status_display,
            "루트디스크사용률": root_disk_display,
            "디스크사용현황": all_disk_summary,
            "네트워크통신": network_status,
            "NTP동기화": ntp_status,
        })

    elif check_type == "os":
        # OS 점검 결과 정리 (DB/OS 공통 컬럼 스키마에 맞춤)
        cpu = results.get("cpu", {})
        memory = results.get("memory", {})
        disk = results.get("disk", {})
        network = results.get("network", {})
        ntp = results.get("ntp", {})

        # CPU 모델명
        cpu_model = "N/A"
        try:
            if isinstance(cpu, dict):
                cpu_model = cpu.get("model", "N/A")
            elif isinstance(cpu, str):
                cpu_model = cpu
        except:
            pass

        # Swap 상태 (예: "Swap: 2.0Gi 0B 2.0Gi" → "2.0Gi / 0B")
        swap_status_display = "N/A"
        try:
            if isinstance(memory, dict):
                swap_str = memory.get("swap", "")
                if isinstance(swap_str, str) and swap_str.strip():
                    parts = swap_str.split()
                    if len(parts) >= 3:
                        swap_status_display = f"{parts[1]} / {parts[2]}"
        except:
            pass

        # 루트 디스크 사용률
        root_disk_usage = "N/A"
        try:
            if isinstance(disk, dict):
                root_disk_usage = disk.get("root_usage_percent", "N/A")
        except:
            pass
        if isinstance(root_disk_usage, str) and root_disk_usage.isdigit():
            root_disk_display = f"{root_disk_usage}%"
        else:
            root_disk_display = root_disk_usage

        # 전체 디스크 사용 현황 요약 (간단히 high-level 요약만)
        all_disk_summary = "N/A"
        try:
            if isinstance(disk, dict):
                all_disk_str = disk.get("all", "")
                if isinstance(all_disk_str, str) and all_disk_str.strip():
                    # 70% 이상 사용 중인 디스크 수 계산
                    lines = all_disk_str.split("\n")
                    high_usage_count = 0
                    for line in lines[1:]:
                        if "%" in line and "Use%" not in line:
                            parts = line.split()
                            for part in parts:
                                if part.endswith("%") and part != "Use%":
                                    try:
                                        usage = int(part.replace("%", ""))
                                        if usage >= 70:
                                            high_usage_count += 1
                                    except (ValueError, AttributeError):
                                        pass
                    if high_usage_count > 0:
                        all_disk_summary = f"{high_usage_count}개 디스크 70% 이상"
                    else:
                        all_disk_summary = "정상"
        except:
            pass

        # 네트워크 통신 상태
        network_status = "N/A"
        try:
            if isinstance(network, dict):
                ping_result = network.get("ping_result", "")
                if isinstance(ping_result, str):
                    if "0% packet loss" in ping_result:
                        network_status = "✓ 연결됨"
                    elif "packet loss" in ping_result:
                        network_status = "✗ 연결실패"
                    else:
                        network_status = ping_result[:50]
        except:
            pass

        # NTP 동기화 상태
        ntp_status = "N/A"
        try:
            if isinstance(ntp, dict):
                ntp_str = ntp.get("status", "")
                if isinstance(ntp_str, str):
                    if "NTP not configured" in ntp_str:
                        ntp_status = "미설정"
                    elif "*" in ntp_str or "^*" in ntp_str:
                        ntp_status = "✓ 동기화됨"
                    else:
                        ntp_status = "설정됨"
        except:
            pass

        # CPU/메모리 상위 프로세스
        cpu_top = "N/A"
        mem_top = "N/A"
        try:
            if isinstance(cpu, dict):
                cpu_top_str = cpu.get("top_processes", "")
                if isinstance(cpu_top_str, str) and cpu_top_str.strip() and cpu_top_str != "N/A":
                    cpu_top = "있음"
            if isinstance(memory, dict):
                mem_top_str = memory.get("top_processes", "")
                if isinstance(mem_top_str, str) and mem_top_str.strip() and mem_top_str != "N/A":
                    mem_top = "있음"
        except:
            pass

        # OS용 포맷 결과 (DB와 동일한 공통 19개 컬럼 구조 맞추기)
        formatted.update({
            # 설치 정보 (OS는 별도 설치 개념이 없으므로 N/A)
            "설치확인": "N/A",
            "설치경로": "N/A",

            # OS 기초 체력
            "CPU모델명": cpu_model[:50] if isinstance(cpu_model, str) else "N/A",
            "Swap상태": swap_status_display,
            "루트디스크사용률": root_disk_display,
            "디스크사용현황": all_disk_summary,
            "네트워크통신": network_status,
            "NTP동기화": ntp_status,

            # OS 리소스
            "CPU상위프로세스": cpu_top,
            "메모리상위프로세스": mem_top,

            # 공통 DB 정보 (OS는 DB가 없으므로 N/A)
            "프로세스수": "N/A",
            "데이터베이스수": "N/A",
            "데이터베이스목록": "N/A",
            "테이블스페이스": "N/A",
        })

    elif check_type == "cubrid":
        # CUBRID 점검 결과 정리
        installation = results.get("installation", {})
        service_status = results.get("service_status", {})
        processes = results.get("processes", {})
        database = results.get("database", {})
        os_resources = results.get("os_resources", {})
        tablespace = results.get("tablespace", {})
        filesystem = results.get("filesystem", {})
        ha = results.get("ha", {})
        
        # CUBRID 서비스 상태 확인
        service_state = "STOPPED"
        server_state = "STOPPED"
        broker_state = "STOPPED"
        try:
            service_str = str(service_status.get("service", "")).strip()
            server_str = str(service_status.get("server", "")).strip()
            broker_str = str(service_status.get("broker", "")).strip()
            
            # 서비스 상태 파싱
            if not service_str or service_str == "":
                service_state = "STOPPED"
            elif "error" in service_str.lower() or "failed" in service_str.lower():
                service_state = "ERROR"
            elif "running" in service_str.lower() and "not running" not in service_str.lower():
                service_state = "RUNNING"
            elif "not running" in service_str.lower() or "stopped" in service_str.lower():
                service_state = "STOPPED"
            else:
                # 알 수 없는 상태는 간단히 표시
                if "unknown" in service_str.lower():
                    service_state = "UNKNOWN"
                else:
                    service_state = "STOPPED"
            
            # 서버 상태 파싱
            if not server_str or server_str == "":
                server_state = "STOPPED"
            elif "error" in server_str.lower() or "failed" in server_str.lower():
                server_state = "ERROR"
            elif "running" in server_str.lower() and "not running" not in server_str.lower():
                server_state = "RUNNING"
            elif "not running" in server_str.lower() or "stopped" in server_str.lower():
                server_state = "STOPPED"
            else:
                if "unknown" in server_str.lower():
                    server_state = "UNKNOWN"
                else:
                    server_state = "STOPPED"
            
            # 브로커 상태 파싱
            if not broker_str or broker_str == "":
                broker_state = "STOPPED"
            elif "error" in broker_str.lower() or "failed" in broker_str.lower():
                broker_state = "ERROR"
            elif "running" in broker_str.lower() or "active" in broker_str.lower():
                if "not running" not in broker_str.lower():
                    broker_state = "RUNNING"
                else:
                    broker_state = "STOPPED"
            elif "not running" in broker_str.lower() or "stopped" in broker_str.lower():
                broker_state = "STOPPED"
            else:
                if "unknown" in broker_str.lower():
                    broker_state = "UNKNOWN"
                else:
                    broker_state = "STOPPED"
        except:
            pass
        
        # 데이터베이스 목록 파싱
        db_list = database.get("db_list", "N/A")
        db_count = "0"
        try:
            if isinstance(db_list, str) and db_list != "N/A":
                db_count = str(len(db_list.split()))
        except:
            pass
        
        # CPU/메모리 사용률 상위 프로세스
        cpu_top = "N/A"
        mem_top = "N/A"
        try:
            # CUBRID는 cpu_top_processes/mem_top_processes도 확인
            cpu_str = os_resources.get("cpu_top_processes", "") or os_resources.get("cpu_usage_top", "")
            mem_str = os_resources.get("mem_top_processes", "") or os_resources.get("mem_usage_top", "")
            if isinstance(cpu_str, str) and cpu_str.strip() and cpu_str != "N/A":
                cpu_top = "있음"
            if isinstance(mem_str, str) and mem_str.strip() and mem_str != "N/A":
                mem_top = "있음"
        except:
            pass
        
        # 테이블스페이스 정보
        tablespace_info = "N/A"
        try:
            ts_str = tablespace.get("spacedb_info", "")
            if isinstance(ts_str, str) and ts_str.strip():
                tablespace_info = "있음"
        except:
            pass
        
        # 파일시스템 정보
        ncia_fs = "없음"
        try:
            fs_str = filesystem.get("ncia_usage", "")
            if isinstance(fs_str, str) and fs_str.strip():
                ncia_fs = "있음"
        except:
            pass
        
        # HA 상태
        ha_status = "미구성"
        try:
            ha_str = ha.get("ha_status", "")
            if isinstance(ha_str, str) and ha_str.strip():
                ha_status = "구성됨"
        except:
            pass
        
        # OS 기초 체력 점검 항목 파싱
        os_basics = results.get("os_basics", {})
        cpu_model = os_basics.get("cpu_model_name", "N/A")
        
        # Swap 상태 파싱
        swap_status_display = "N/A"
        try:
            swap_str = os_basics.get("swap_status", "")
            if isinstance(swap_str, str) and swap_str.strip():
                # "Swap: 2.0Gi 0B 2.0Gi" 형식에서 사용량 추출
                parts = swap_str.split()
                if len(parts) >= 3:
                    swap_status_display = f"{parts[1]} / {parts[2]}"
        except:
            pass
        
        # 루트 디스크 사용률
        root_disk_usage = os_basics.get("root_disk_usage", "N/A")
        root_disk_display = f"{root_disk_usage}%" if root_disk_usage != "N/A" and root_disk_usage.isdigit() else root_disk_usage
        
        # 전체 디스크 사용 현황 요약
        all_disk_summary = "N/A"
        try:
            all_disk_str = os_basics.get("all_disk_usage", "")
            if isinstance(all_disk_str, str) and all_disk_str.strip():
                # df -h 출력에서 70% 이상인 것만 카운트
                lines = all_disk_str.split("\n")
                high_usage_count = 0
                for line in lines[1:]:  # 첫 줄(헤더) 제외
                    if "%" in line and "Use%" not in line:
                        parts = line.split()
                        for part in parts:
                            if part.endswith("%") and part != "Use%":
                                try:
                                    usage = int(part.replace("%", ""))
                                    if usage >= 70:
                                        high_usage_count += 1
                                except (ValueError, AttributeError):
                                    pass
                if high_usage_count > 0:
                    all_disk_summary = f"{high_usage_count}개 디스크 70% 이상"
                else:
                    all_disk_summary = "정상"
        except Exception:
            pass
        
        # 네트워크 통신 상태
        network_status = "N/A"
        try:
            ping_result = os_basics.get("network_ping_result", "")
            if isinstance(ping_result, str):
                if "0% packet loss" in ping_result or "0 received" not in ping_result:
                    network_status = "✓ 연결됨"
                else:
                    network_status = "✗ 연결실패"
        except:
            pass
        
        # NTP 동기화 상태
        ntp_status = "N/A"
        try:
            ntp_str = os_basics.get("ntp_sync_status", "")
            if isinstance(ntp_str, str):
                if "NTP not configured" in ntp_str:
                    ntp_status = "미설정"
                elif "*" in ntp_str or "^*" in ntp_str:
                    ntp_status = "✓ 동기화됨"
                else:
                    ntp_status = "설정됨"
        except:
            pass
        
        formatted.update({
            "설치확인": "✓" if installation.get("home_exists") and installation.get("bin_exists") else "✗",
            "설치경로": str(installation.get("cubrid_home", "N/A"))[:40],
            "서비스상태": service_state,
            "서버상태": server_state,
            "브로커상태": broker_state,
            "브로커개수": processes.get("broker_count", "N/A"),
            "프로세스수": processes.get("total_proc_count", "N/A"),
            "관리프로세스": "있음" if processes.get("admin_proc") else "없음",
            "데이터베이스수": db_count,
            "데이터베이스목록": str(db_list)[:50],
            "CPU상위프로세스": cpu_top,
            "메모리상위프로세스": mem_top,
            "테이블스페이스": tablespace_info,
            "NCIA파일시스템": ncia_fs,
            "HA상태": ha_status,
            "CPU모델명": cpu_model[:50] if cpu_model != "N/A" else "N/A",
            "Swap상태": swap_status_display,
            "루트디스크사용률": root_disk_display,
            "디스크사용현황": all_disk_summary,
            "네트워크통신": network_status,
            "NTP동기화": ntp_status,
        })
    
    elif check_type == "tomcat" or check_type == "was":
        # WAS(Tomcat) 점검 결과 정리
        installation = results.get("installation", {})
        service_status = results.get("service_status", {})
        listener = results.get("listener", {})
        os_resources = results.get("os_resources", {})
        applications = results.get("applications", {})
        process = results.get("process", {})
        filesystem_usage = results.get("filesystem_usage", {})
        directory_structure = results.get("directory_structure", "N/A")
        configuration = results.get("configuration", {})
        logs_data = results.get("logs", {})
        script = results.get("script", {})
        
        # 설치 확인 파싱
        installation_status = "✗"
        installation_path = "N/A"
        try:
            installed_str = str(installation.get("installed", "")).strip()
            if installed_str.upper() == "INSTALLED":
                installation_status = "✓"
            installation_path = installation.get("catalina_home", installation.get("binary_path", "N/A"))
            if isinstance(installation_path, str):
                installation_path = installation_path[:40]
        except:
            pass
        
        # 디렉토리 구조 파싱
        directory_structure_display = "N/A"
        try:
            if isinstance(directory_structure, str) and directory_structure.strip() and directory_structure != "N/A":
                directory_structure_display = "있음"
        except:
            pass
        
        # 파일시스템 파싱
        filesystem_display = "N/A"
        try:
            fs_keys = ["catalina_home", "catalina_base", "logs", "temp"]
            fs_found = False
            for key in fs_keys:
                fs_val = filesystem_usage.get(key, "")
                if isinstance(fs_val, str) and fs_val.strip() and fs_val != "N/A":
                    fs_found = True
                    break
            if fs_found:
                filesystem_display = "있음"
        except:
            pass
        
        # 서비스 상태 파싱
        service_state = "N/A"
        try:
            active = service_status.get("active", "")
            substate = service_status.get("substate", "")
            if active and substate:
                service_state = f"{active}/{substate}"
            elif active:
                service_state = active
        except:
            pass
        
        # 리스너 상태 파싱 (8080, 8005, 8009)
        listener_8080_status = "NOT LISTENING"
        listener_8005_status = "NOT LISTENING"
        listener_8009_status = "NOT LISTENING"
        try:
            listener_8080 = str(listener.get("port_8080", ""))
            listener_8005 = str(listener.get("port_8005", ""))
            listener_8009 = str(listener.get("port_8009", ""))
            if "LISTEN" in listener_8080:
                listener_8080_status = "LISTENING"
            if "LISTEN" in listener_8005:
                listener_8005_status = "LISTENING"
            if "LISTEN" in listener_8009:
                listener_8009_status = "LISTENING"
        except:
            pass
        
        # 메모리 정보 파싱
        memory_detail = "N/A"
        memory_usage_percent = "N/A"
        try:
            memory = os_resources.get("memory", {})
            if isinstance(memory, dict):
                memory_detail = memory.get("detail", "N/A")
                memory_usage_percent = memory.get("usage_percent", "N/A")
            elif isinstance(memory, str):
                memory_detail = memory
        except:
            pass
        
        # CPU 정보 파싱
        cpu_detail = "N/A"
        cpu_usage_percent = "N/A"
        try:
            cpu = os_resources.get("cpu", {})
            if isinstance(cpu, dict):
                cpu_detail = cpu.get("detail", "N/A")
                cpu_usage_percent = cpu.get("usage_percent", "N/A")
            elif isinstance(cpu, str):
                cpu_detail = cpu
        except:
            pass
        
        # 프로세스 정보
        process_count = os_resources.get("process_count", "N/A")
        process_running = "N/A"
        try:
            running_str = str(process.get("running", "")).upper()
            if running_str == "YES":
                process_running = "실행중"
            elif running_str == "NO":
                process_running = "정지됨"
        except:
            pass
        
        # 애플리케이션 정보
        app_count = applications.get("app_count", "N/A")
        deployed_apps = applications.get("deployed_apps", "N/A")
        deployed_apps_display = "N/A"
        try:
            if isinstance(deployed_apps, str) and deployed_apps.strip() and deployed_apps != "N/A":
                # 첫 몇 줄만 표시
                lines = deployed_apps.split("\n")
                if len(lines) > 0:
                    deployed_apps_display = lines[0][:50] + ("..." if len(lines[0]) > 50 else "")
        except:
            pass
        
        # CPU/메모리 상위 프로세스
        cpu_top = "N/A"
        mem_top = "N/A"
        try:
            cpu_top_str = os_resources.get("cpu_top_processes", "")
            mem_top_str = os_resources.get("mem_top_processes", "")
            if isinstance(cpu_top_str, str) and cpu_top_str.strip() and cpu_top_str != "N/A":
                cpu_top = "있음"
            if isinstance(mem_top_str, str) and mem_top_str.strip() and mem_top_str != "N/A":
                mem_top = "있음"
        except:
            pass
        
        # 파일시스템 상세 파싱
        catalina_home_fs = "N/A"
        catalina_base_fs = "N/A"
        logs_fs = "N/A"
        temp_fs = "N/A"
        try:
            catalina_home_fs_raw = filesystem_usage.get("catalina_home", "")
            catalina_base_fs_raw = filesystem_usage.get("catalina_base", "")
            logs_fs_raw = filesystem_usage.get("logs", "")
            temp_fs_raw = filesystem_usage.get("temp", "")
            
            # df -h 출력에서 사용률 추출
            if isinstance(catalina_home_fs_raw, str) and "%" in catalina_home_fs_raw:
                parts = catalina_home_fs_raw.split()
                for i, part in enumerate(parts):
                    if part.endswith("%"):
                        catalina_home_fs = part
                        break
            
            if isinstance(catalina_base_fs_raw, str) and "%" in catalina_base_fs_raw:
                parts = catalina_base_fs_raw.split()
                for i, part in enumerate(parts):
                    if part.endswith("%"):
                        catalina_base_fs = part
                        break
                        
            if isinstance(logs_fs_raw, str) and "%" in logs_fs_raw:
                parts = logs_fs_raw.split()
                for i, part in enumerate(parts):
                    if part.endswith("%"):
                        logs_fs = part
                        break
                        
            if isinstance(temp_fs_raw, str) and "%" in temp_fs_raw:
                parts = temp_fs_raw.split()
                for i, part in enumerate(parts):
                    if part.endswith("%"):
                        temp_fs = part
                        break
        except:
            pass
        
        # 설정 정보 파싱
        server_xml = configuration.get("server_xml", "N/A")
        java_opts = configuration.get("java_opts", "N/A")
        max_heap = configuration.get("max_heap", "N/A")
        
        server_xml_display = "N/A"
        try:
            if isinstance(server_xml, str) and server_xml.strip() and server_xml != "N/A":
                server_xml_display = "있음" if "not found" not in server_xml.lower() else "없음"
        except:
            pass
        
        # 로그 정보 파싱
        catalina_log = logs_data.get("catalina_log", "N/A")
        error_log = logs_data.get("error_log", "N/A")
        access_log_error_count = logs_data.get("access_log_error_count", "N/A")
        
        catalina_log_display = "N/A"
        error_log_display = "N/A"
        try:
            if isinstance(catalina_log, str) and catalina_log.strip() and catalina_log != "N/A":
                catalina_log_display = "있음" if "not found" not in catalina_log.lower() else "없음"
            if isinstance(error_log, str) and error_log.strip() and error_log != "N/A":
                error_log_display = "있음" if "not found" not in error_log.lower() else "없음"
        except:
            pass
        
        # 기동 스크립트 날짜
        startup_script_date = script.get("startup_script_date", "N/A")

        formatted.update({
            # WAS 기본 항목
            "설치확인": installation_status,
            "설치경로": installation_path if isinstance(installation_path, str) else "N/A",
            "CPU상위프로세스": cpu_top,
            "메모리상위프로세스": mem_top,
            "프로세스수": str(process_count) if process_count != "N/A" else "N/A",
            
            # WAS 전용 항목
            "디렉토리구조": directory_structure_display,
            "파일시스템": filesystem_display,
            "서비스상태": service_state,
            "리스너(8080)": listener_8080_status,
            "리스너(8005)": listener_8005_status,
            "리스너(8009)": listener_8009_status,
            "메모리(Total)": memory_detail[:50] if isinstance(memory_detail, str) and memory_detail != "N/A" else "N/A",
            "메모리사용률": memory_usage_percent,
            "CPU": cpu_detail[:50] if isinstance(cpu_detail, str) and cpu_detail != "N/A" else "N/A",
            "CPU사용률": cpu_usage_percent,
            "관리프로세스": process_running,
            "애플리케이션수": str(app_count) if app_count != "N/A" else "N/A",
            "애플리케이션목록": deployed_apps_display,
            "CATALINA_HOME파일시스템": catalina_home_fs,
            "CATALINA_BASE파일시스템": catalina_base_fs,
            "로그파일시스템": logs_fs,
            "임시파일시스템": temp_fs,
            "server.xml": server_xml_display,
            "JAVA_OPTS": java_opts[:50] if isinstance(java_opts, str) and java_opts != "N/A" else "N/A",
            "Max_Heap": max_heap if max_heap != "N/A" else "N/A",
            "catalina.out": catalina_log_display,
            "error.log": error_log_display,
            "접속로그에러수": access_log_error_count if access_log_error_count != "N/A" else "N/A",
            "기동스크립트수정일": startup_script_date if startup_script_date != "N/A" else "N/A",
            
            # DB 전용 항목 (WAS에서는 N/A)
            "서버상태": "N/A",
            "브로커상태": "N/A",
            "브로커개수": "N/A",
            "NCIA파일시스템": "N/A",
            "HA상태": "N/A",
        })
    
    # 원본 results 객체도 포함 (모달에서 사용하기 위해)
    formatted["results"] = results
    
    return formatted


@app.get("/api/db-checks/report", response_class=HTMLResponse)
async def db_checks_report():
    """
    DB 점검 결과를 HTML 테이블 형식으로 표시 (필터링, 정렬, 페이지네이션, 차트, 실시간 업데이트 포함)
    
    Returns:
        HTML 형식의 리포트
    """
    try:
        # HTML 템플릿 파일 읽기
        import os
        template_path = os.path.join(os.path.dirname(__file__), "report_template.html")
        with open(template_path, "r", encoding="utf-8") as f:
            html = f.read()
        
        return HTMLResponse(content=html)
        
    except Exception as e:
        error_html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>오류</title>
        </head>
        <body>
            <h1>오류 발생</h1>
            <p>{str(e)}</p>
        </body>
        </html>
        """
        return HTMLResponse(content=error_html, status_code=500)


@app.get("/api/os-checks/report", response_class=HTMLResponse)
async def os_checks_report():
    """
    OS 점검 결과 리포트
    
    Returns:
        HTML 형식의 리포트
    """
    try:
        import os
        template_path = os.path.join(os.path.dirname(__file__), "os_report_template.html")
        with open(template_path, "r", encoding="utf-8") as f:
            html = f.read()
        
        return HTMLResponse(content=html)
        
    except Exception as e:
        error_html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>오류</title>
        </head>
        <body>
            <h1>오류 발생</h1>
            <p>{str(e)}</p>
        </body>
        </html>
        """
        return HTMLResponse(content=error_html, status_code=500)


@app.get("/api/was-checks/report", response_class=HTMLResponse)
async def was_checks_report():
    """
    WAS 점검 결과 리포트
    
    Returns:
        HTML 형식의 리포트
    """
    try:
        import os
        template_path = os.path.join(os.path.dirname(__file__), "was_report_template.html")
        with open(template_path, "r", encoding="utf-8") as f:
            html = f.read()
        
        return HTMLResponse(content=html)
        
    except Exception as e:
        error_html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>오류</title>
        </head>
        <body>
            <h1>오류 발생</h1>
            <p>{str(e)}</p>
        </body>
        </html>
        """
        return HTMLResponse(content=error_html, status_code=500)


@app.get("/api/report", response_class=HTMLResponse)
async def unified_report():
    """
    통합 점검 결과 리포트 - DB, OS, WAS를 탭으로 통합
    
    Returns:
        HTML 형식의 통합 리포트
    """
    try:
        import os
        template_path = os.path.join(os.path.dirname(__file__), "unified_report_template.html")
        with open(template_path, "r", encoding="utf-8") as f:
            html = f.read()
        
        return HTMLResponse(content=html)
        
    except Exception as e:
        error_html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>오류</title>
        </head>
        <body>
            <h1>오류 발생</h1>
            <p>{str(e)}</p>
        </body>
        </html>
        """
        return HTMLResponse(content=error_html, status_code=500)


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket 엔드포인트 - 실시간 업데이트"""
    await manager.connect(websocket)
    try:
        while True:
            # 클라이언트로부터 메시지 수신 (ping/pong)
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_json({"type": "pong", "timestamp": datetime.now().isoformat()})
    except WebSocketDisconnect:
        manager.disconnect(websocket)


@app.get("/api/db-checks/data")
async def get_db_checks_data(limit: int = 100):
    """DB 점검 결과를 JSON 형식으로 반환 (차트/필터링용)"""
    try:
        db_types = ["mariadb", "postgresql", "cubrid"]
        all_results = []
        
        for db_type in db_types:
            results = get_check_results(check_type=db_type, limit=limit)
            all_results.extend(results)
        
        all_results.sort(key=lambda x: x.get("created_at", ""), reverse=True)
        formatted_results = [format_db_result(result) for result in all_results[:limit]]
        
        return {
            "success": True,
            "count": len(formatted_results),
            "results": formatted_results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/os-checks/data")
async def get_os_checks_data(limit: int = 100):
    """OS 점검 결과를 JSON 형식으로 반환 (DB/OS 공통 테이블용)"""
    try:
        results = get_check_results(check_type="os", limit=limit)
        results.sort(key=lambda x: x.get("created_at", ""), reverse=True)
        formatted_results = [format_db_result(result) for result in results[:limit]]

        return {
            "success": True,
            "count": len(formatted_results),
            "results": formatted_results,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/was-checks/data")
async def get_was_checks_data(limit: int = 1000):
    """WAS 점검 결과를 JSON 형식으로 반환 (DB/OS 공통 테이블용)"""
    try:
        # "was"와 "tomcat" 둘 다 조회 (플레이북에서 "was"로 저장하지만 이전에는 "tomcat"일 수 있음)
        results_was = get_check_results(check_type="was", limit=limit)
        results_tomcat = get_check_results(check_type="tomcat", limit=limit)
        
        # 두 결과 합치기
        all_results = list(results_was) + list(results_tomcat)
        
        # 중복 제거 (id 기준) 및 정렬
        seen_ids = set()
        unique_results = []
        for result in all_results:
            result_id = result.get("id")
            if result_id and result_id not in seen_ids:
                seen_ids.add(result_id)
                unique_results.append(result)
        
        unique_results.sort(key=lambda x: x.get("created_at", ""), reverse=True)
        formatted_results = [format_db_result(result) for result in unique_results[:limit]]
        
        return {
            "success": True,
            "count": len(formatted_results),
            "results": formatted_results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    # 개발 서버 실행
    from config import HOST, PORT
    uvicorn.run(
        "main:app",
        host=HOST,
        port=PORT,
        reload=True  # 개발 모드: 코드 변경 시 자동 재시작
    )

