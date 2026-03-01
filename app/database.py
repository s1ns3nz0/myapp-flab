import os
import json
import boto3
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

def get_secret():
    """Secrets Manager에서 DB 패스워드 가져오기"""
    secret_arn = os.getenv("DB_SECRET")

    # 로컬 개발 환경에서는 환경변수 직접 사용
    if not secret_arn:
        return {
            "username": os.getenv("DB_USER", "admin"),
            "password": os.getenv("DB_PASSWORD", "password")
        }

    client = boto3.client("secretsmanager", region_name="ap-northeast-2")
    response = client.get_secret_value(SecretId=secret_arn)
    return json.loads(response["SecretString"])

def get_database_url():
    secret = get_secret()
    host     = os.getenv("DB_HOST", "localhost")
    port     = os.getenv("DB_PORT", "3306")
    db_name  = os.getenv("DB_NAME", "myappdb")
    username = secret["username"]
    password = secret["password"]

    return f"mysql+pymysql://{username}:{password}@{host}:{port}/{db_name}"

engine = create_engine(
    get_database_url(),
    pool_pre_ping=True,   # 연결 상태 자동 확인
    pool_recycle=3600,    # 1시간마다 연결 재생성
    echo=False
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()