import io
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient


def make_db_mock():
    cursor = MagicMock()
    cursor.__enter__ = lambda s: s
    cursor.__exit__ = MagicMock(return_value=False)
    cursor.fetchall.return_value = []
    conn = MagicMock()
    conn.__enter__ = lambda s: s
    conn.__exit__ = MagicMock(return_value=False)
    conn.cursor.return_value = cursor
    return conn


def make_auth_ok(username="alice"):
    resp = MagicMock()
    resp.status_code = 200
    resp.json.return_value = {"username": username}
    return resp


@pytest.fixture()
def client():
    with patch("main.get_db_conn", return_value=make_db_mock()):
        from main import app
        with TestClient(app) as c:
            yield c


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["service"] == "core"


def test_readiness_ok(client):
    with patch("main.httpx.get", return_value=MagicMock(status_code=200)):
        resp = client.get("/healthz/ready")
    assert resp.status_code == 200


def test_readiness_auth_down(client):
    import httpx
    with patch("main.httpx.get", side_effect=httpx.RequestError("timeout")):
        resp = client.get("/healthz/ready")
    assert resp.status_code == 503


def test_upload_success(client, monkeypatch):
    monkeypatch.setenv("S3_BUCKET_NAME", "test-bucket")
    s3_mock = MagicMock()
    with patch("main.get_s3_client", return_value=s3_mock), \
         patch("main.get_db_conn", return_value=make_db_mock()), \
         patch("main.httpx.get", return_value=make_auth_ok()):
        resp = client.post(
            "/upload",
            files={"file": ("test.txt", io.BytesIO(b"hello"), "text/plain")},
            headers={"Authorization": "Bearer valid-token"},
        )
    assert resp.status_code == 200
    assert resp.json()["filename"] == "test.txt"
    assert resp.json()["uploaded_by"] == "alice"


def test_upload_unauthorized(client):
    resp = client.post(
        "/upload",
        files={"file": ("test.txt", io.BytesIO(b"hello"), "text/plain")},
    )
    assert resp.status_code in (401, 403)


def test_upload_invalid_token(client):
    with patch("main.httpx.get", return_value=MagicMock(status_code=401)):
        resp = client.post(
            "/upload",
            files={"file": ("test.txt", io.BytesIO(b"hello"), "text/plain")},
            headers={"Authorization": "Bearer bad-token"},
        )
    assert resp.status_code == 401


def test_upload_missing_bucket(client, monkeypatch):
    monkeypatch.delenv("S3_BUCKET_NAME", raising=False)
    with patch("main.httpx.get", return_value=make_auth_ok()):
        resp = client.post(
            "/upload",
            files={"file": ("test.txt", io.BytesIO(b"hello"), "text/plain")},
            headers={"Authorization": "Bearer valid-token"},
        )
    assert resp.status_code == 500


def test_list_files(client):
    with patch("main.httpx.get", return_value=make_auth_ok()):
        resp = client.get("/files", headers={"Authorization": "Bearer valid-token"})
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
