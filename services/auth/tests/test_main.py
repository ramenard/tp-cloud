from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import jwt
import psycopg2
import pytest
from fastapi.testclient import TestClient


def make_db_mock(fetchone=None):
    cursor = MagicMock()
    cursor.__enter__ = lambda s: s
    cursor.__exit__ = MagicMock(return_value=False)
    cursor.fetchone.return_value = fetchone
    conn = MagicMock()
    conn.__enter__ = lambda s: s
    conn.__exit__ = MagicMock(return_value=False)
    conn.cursor.return_value = cursor
    return conn


@pytest.fixture()
def client():
    with patch("main.get_db_conn", return_value=make_db_mock()):
        from main import app
        with TestClient(app) as c:
            yield c


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["service"] == "auth"


def test_readiness_ok(client):
    resp = client.get("/healthz/ready")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"


def test_readiness_db_down():
    with patch("main.get_db_conn", side_effect=[make_db_mock(), Exception("DB down")]):
        from main import app
        with TestClient(app) as c:
            resp = c.get("/healthz/ready")
    assert resp.status_code == 503


def test_register(client):
    resp = client.post("/auth/register", json={"username": "alice", "password": "secret"})
    assert resp.status_code == 201
    assert "alice" in resp.json()["message"]


def test_register_duplicate(client):
    with patch("main.get_db_conn") as mock_conn:
        conn = make_db_mock()
        conn.cursor.return_value.execute.side_effect = psycopg2.IntegrityError()
        mock_conn.return_value = conn
        resp = client.post("/auth/register", json={"username": "alice", "password": "secret"})
    assert resp.status_code == 409


def test_login_success(client):
    import bcrypt
    pw_hash = bcrypt.hashpw(b"secret", bcrypt.gensalt()).decode()
    with patch("main.get_db_conn", return_value=make_db_mock(fetchone=(pw_hash,))):
        resp = client.post("/auth/login", json={"username": "alice", "password": "secret"})
    assert resp.status_code == 200
    assert "access_token" in resp.json()


def test_login_wrong_password(client):
    import bcrypt
    pw_hash = bcrypt.hashpw(b"correct", bcrypt.gensalt()).decode()
    with patch("main.get_db_conn", return_value=make_db_mock(fetchone=(pw_hash,))):
        resp = client.post("/auth/login", json={"username": "alice", "password": "wrong"})
    assert resp.status_code == 401


def test_login_unknown_user(client):
    with patch("main.get_db_conn", return_value=make_db_mock(fetchone=None)):
        resp = client.post("/auth/login", json={"username": "nobody", "password": "x"})
    assert resp.status_code == 401


def test_verify_valid_token(client):
    from main import ALGORITHM, SECRET_KEY
    token = jwt.encode(
        {"sub": "alice", "exp": datetime.now(timezone.utc) + timedelta(hours=1)},
        SECRET_KEY,
        algorithm=ALGORITHM,
    )
    resp = client.get(f"/auth/verify?token={token}")
    assert resp.status_code == 200
    assert resp.json()["username"] == "alice"


def test_verify_invalid_token(client):
    resp = client.get("/auth/verify?token=invalid.token.here")
    assert resp.status_code == 401


def test_verify_expired_token(client):
    from main import ALGORITHM, SECRET_KEY
    token = jwt.encode(
        {"sub": "alice", "exp": datetime.now(timezone.utc) - timedelta(hours=1)},
        SECRET_KEY,
        algorithm=ALGORITHM,
    )
    resp = client.get(f"/auth/verify?token={token}")
    assert resp.status_code == 401
