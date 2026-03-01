import os
import json
import boto3
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

def get_secret():
    """Secrets Manager에서 DB 패스워드 가져오기"""
    db_secret = os.getenv("DB_SECRET")

    if not db_secret:
        return {
            "username": os.getenv("DB_USER", "admin"),
            "password": os.getenv("DB_PASSWORD", "password")
        }

    # 1. JSON 문자열로 직접 주입된 경우 (ECS secrets valueFrom)
    try:
        secret_data = json.loads(db_secret)
        return {
            "username": secret_data.get("username", "admin"),
            "password": secret_data.get("password", "")
        }
    except json.JSONDecodeError:
        pass

    # 2. ARN으로 주입된 경우 → Secrets Manager 직접 호출
    if db_secret.startswith("arn:aws:secretsmanager"):
        client = boto3.client("secretsmanager", region_name="ap-northeast-2")
        response = client.get_secret_value(SecretId=db_secret)
        secret_data = json.loads(response["SecretString"])
        return {
            "username": secret_data.get("username", "admin"),
            "password": secret_data.get("password", "")
        }

    # 3. 패스워드 문자열 자체인 경우
    return {
        "username": os.getenv("DB_USER", "admin"),
        "password": db_secret
    }

def get_database_url():
    secret   = get_secret()
    host     = os.getenv("DB_HOST", "localhost")
    port     = os.getenv("DB_PORT", "3306")
    db_name  = os.getenv("DB_NAME", "myappdb")
    username = secret["username"]
    password = secret["password"]

    return f"mysql+pymysql://{username}:{password}@{host}:{port}/{db_name}"

engine = create_engine(
    get_database_url(),
    pool_pre_ping=True,
    pool_recycle=3600,
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