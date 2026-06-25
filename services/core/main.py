import os
from datetime import datetime, timezone

import boto3
import httpx
import psycopg2
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from prometheus_fastapi_instrumentator import Instrumentator

AUTH_SERVICE_URL = os.getenv("AUTH_SERVICE_URL", "http://auth-service:8080")

app = FastAPI(title="Core Service")

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

Instrumentator().instrument(app).expose(app)

security = HTTPBearer()


def get_db_conn():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "5432")),
        dbname=os.getenv("DB_NAME", "postgres"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", "monpassword"),
    )


def get_s3_client():
    return boto3.client(
        "s3",
        region_name=os.getenv("AWS_REGION", "eu-west-1"),
        aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY"),
    )


@app.on_event("startup")
def init_db():
    with get_db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS uploaded_files (
                    id SERIAL PRIMARY KEY,
                    filename TEXT NOT NULL,
                    uploaded_by TEXT NOT NULL,
                    uploaded_at TIMESTAMPTZ DEFAULT NOW()
                )
            """)
        conn.commit()


def require_auth(credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        resp = httpx.get(
            f"{AUTH_SERVICE_URL}/auth/verify",
            params={"token": credentials.credentials},
            timeout=5.0,
        )
        if resp.status_code != 200:
            raise HTTPException(status_code=401, detail="Invalid token")
        return resp.json()
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail=f"Auth service unreachable: {exc}")


@app.get("/health")
def health():
    return {"status": "ok", "service": "core"}


@app.get("/healthz/ready")
def readiness():
    try:
        with get_db_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"DB unreachable: {exc}")
    try:
        resp = httpx.get(f"{AUTH_SERVICE_URL}/health", timeout=3.0)
        if resp.status_code != 200:
            raise HTTPException(status_code=503, detail="Auth service not healthy")
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail=f"Auth service unreachable: {exc}")
    return {"status": "ready", "service": "core"}


@app.post("/upload")
async def upload_file(
    file: UploadFile = File(...),
    user: dict = Depends(require_auth),
):
    bucket = os.environ.get("S3_BUCKET_NAME")
    if not bucket:
        raise HTTPException(status_code=500, detail="S3_BUCKET_NAME non configuré")
    try:
        get_s3_client().upload_fileobj(
            file.file,
            bucket,
            file.filename,
            ExtraArgs={"ContentType": file.content_type or "application/octet-stream"},
        )
    except (BotoCoreError, ClientError) as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    with get_db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO uploaded_files (filename, uploaded_by, uploaded_at) VALUES (%s, %s, %s)",
                (file.filename, user["username"], datetime.now(timezone.utc)),
            )
        conn.commit()

    return {"filename": file.filename, "bucket": bucket, "uploaded_by": user["username"]}


@app.get("/files")
def list_files(user: dict = Depends(require_auth)):
    with get_db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT filename, uploaded_by, uploaded_at FROM uploaded_files ORDER BY uploaded_at DESC"
            )
            rows = cur.fetchall()
    return [
        {"filename": r[0], "uploaded_by": r[1], "uploaded_at": r[2].isoformat()}
        for r in rows
    ]
