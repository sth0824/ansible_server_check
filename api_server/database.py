"""
데이터베이스 연결 및 CRUD 작업
"""
import os
from pathlib import Path
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session
from models import Base, CheckResult
from typing import Optional, List, Dict, Any

# .env 파일에서 환경변수 로드 (있는 경우)
env_file = Path(__file__).parent / ".env"
if env_file.exists():
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ[key.strip()] = value.strip()

# DB 연결 설정 (환경변수 또는 기본값)
# .env 파일 또는 환경변수에서 DATABASE_URL을 읽음
DB_FILE = os.path.join(os.path.dirname(__file__), "check_results.db")
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    f"sqlite:///{DB_FILE}"  # 기본값: SQLite (개발용)
    # PostgreSQL 사용 시: "postgresql://user:password@localhost/dbname"
    # MariaDB 사용 시: "mysql+pymysql://user:password@localhost/dbname"
)

# 엔진 및 세션 생성
# PostgreSQL 연결 풀 설정 (연결 끊김 방지)
if "postgresql" in DATABASE_URL or "postgres" in DATABASE_URL:
    engine = create_engine(
        DATABASE_URL,
        pool_pre_ping=True,  # 연결 유효성 사전 확인
        pool_recycle=3600,   # 1시간마다 연결 재생성
        pool_size=5,         # 연결 풀 크기
        max_overflow=10,     # 추가 연결 허용
        connect_args={
            "client_encoding": "UTF8"  # UTF8 인코딩 설정
        }
    )
else:
    engine = create_engine(
        DATABASE_URL,
        connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {}
    )
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def init_db():
    """데이터베이스 초기화 (테이블 생성)"""
    Base.metadata.create_all(bind=engine)
    print(f"📊 데이터베이스 연결: {DATABASE_URL}")


def get_db() -> Session:
    """DB 세션 가져오기"""
    db = SessionLocal()
    try:
        return db
    finally:
        pass  # 세션은 호출자가 닫아야 함


def save_check_result(
    check_type: str,
    hostname: str,
    check_time: str,
    checker: str,
    status: str,
    results: Dict[str, Any]
) -> int:
    """
    점검 결과를 DB에 저장
    
    Returns:
        저장된 레코드의 ID
    """
    db = SessionLocal()
    try:
        check_result = CheckResult(
            check_type=check_type,
            hostname=hostname,
            check_time=check_time,
            checker=checker,
            status=status,
            results=results
        )
        db.add(check_result)
        db.commit()
        db.refresh(check_result)
        return check_result.id
    except Exception as e:
        db.rollback()
        raise e
    finally:
        db.close()


def get_check_results(
    check_type: Optional[str] = None,
    hostname: Optional[str] = None,
    checker: Optional[str] = None,
    limit: int = 100
) -> List[Dict[str, Any]]:
    """
    점검 결과 조회
    
    Returns:
        점검 결과 리스트
    """
    db = SessionLocal()
    try:
        # 연결 유효성 확인 (PostgreSQL의 경우)
        if "postgresql" in DATABASE_URL or "postgres" in DATABASE_URL:
            try:
                db.execute(text("SELECT 1"))
            except Exception:
                # 연결이 끊어진 경우 세션 재생성
                db.close()
                db = SessionLocal()
        
        query = db.query(CheckResult)
        
        # 필터 적용
        if check_type:
            query = query.filter(CheckResult.check_type == check_type)
        if hostname:
            query = query.filter(CheckResult.hostname == hostname)
        if checker:
            query = query.filter(CheckResult.checker == checker)
        
        # 최신순 정렬 및 제한
        results = query.order_by(CheckResult.created_at.desc()).limit(limit).all()
        
        return [result.to_dict() for result in results]
    except Exception as e:
        # 연결 오류인 경우 재시도
        if "connection" in str(e).lower() or "closed" in str(e).lower():
            db.close()
            db = SessionLocal()
            try:
                query = db.query(CheckResult)
                if check_type:
                    query = query.filter(CheckResult.check_type == check_type)
                if hostname:
                    query = query.filter(CheckResult.hostname == hostname)
                if checker:
                    query = query.filter(CheckResult.checker == checker)
                results = query.order_by(CheckResult.created_at.desc()).limit(limit).all()
                return [result.to_dict() for result in results]
            except Exception as e2:
                raise e2
        else:
            raise e
    finally:
        db.close()

