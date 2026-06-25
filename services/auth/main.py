import os
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
import psycopg2
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

SECRET_KEY = os.getenv("JWT_SECRET", "changeme-in-production")
ALGORITHM = "HS256"
TOKEN_EXPIRE_HOURS = 24

app = FastAPI(title="Auth Service")

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


def get_db_conn():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "5432")),
        dbname=os.getenv("DB_NAME", "postgres"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", "monpassword"),
    )


@app.on_event("startup")
def init_db():
    with get_db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id SERIAL PRIMARY KEY,
                    username TEXT UNIQUE NOT NULL,
                    password_hash TEXT NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT NOW()
                )
            """)
        conn.commit()


class UserCredentials(BaseModel):
    username: str
    password: str


@app.get("/health")
def health():
    return {"status": "ok", "service": "auth"}


@app.get("/healthz/ready")
def readiness():
    try:
        with get_db_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"DB unreachable: {exc}")
    return {"status": "ready", "service": "auth"}


@app.post("/auth/register", status_code=201)
def register(creds: UserCredentials):
    pw_hash = bcrypt.hashpw(creds.password.encode(), bcrypt.gensalt()).decode()
    try:
        with get_db_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO users (username, password_hash) VALUES (%s, %s)",
                    (creds.username, pw_hash),
                )
            conn.commit()
    except psycopg2.IntegrityError:
        raise HTTPException(status_code=409, detail="Username already exists")
    return {"message": f"User {creds.username} created"}


@app.post("/auth/login")
def login(creds: UserCredentials):
    with get_db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT password_hash FROM users WHERE username = %s", (creds.username,))
            row = cur.fetchone()

    if not row or not bcrypt.checkpw(creds.password.encode(), row[0].encode()):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    payload = {
        "sub": creds.username,
        "exp": datetime.now(timezone.utc) + timedelta(hours=TOKEN_EXPIRE_HOURS),
    }
    token = jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)
    return {"access_token": token, "token_type": "bearer"}


@app.get("/auth/verify")
def verify(token: str):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return {"username": payload["sub"]}
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")