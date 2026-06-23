import io
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient


def make_db_mock():
    """Return a psycopg2 connection mock that supports the context manager protocol."""
    cursor = MagicMock()
    cursor.__enter__ = lambda s: s
    cursor.__exit__ = MagicMock(return_value=False)

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


# ---------------------------------------------------------------------------
# Routes basiques
# ---------------------------------------------------------------------------

def test_root(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert "message" in resp.json()


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_hello(client):
    resp = client.get("/hello/Alice")
    assert resp.status_code == 200
    assert resp.json() == {"message": "Bonjour Alice !"}


def test_hello_special_chars(client):
    resp = client.get("/hello/Jean-Pierre")
    assert resp.status_code == 200
    assert "Jean-Pierre" in resp.json()["message"]


# ---------------------------------------------------------------------------
# Readiness
# ---------------------------------------------------------------------------

def test_readiness_ok(client):
    resp = client.get("/healthz/ready")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ready"}


def test_readiness_db_down():
    # Premier appel = startup (OK), deuxième = readiness check (KO)
    with patch("main.get_db_conn", side_effect=[make_db_mock(), Exception("connection refused")]):
        from main import app
        with TestClient(app) as c:
            resp = c.get("/healthz/ready")
    assert resp.status_code == 503
    assert "DB unreachable" in resp.json()["detail"]


# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------

def test_upload_success(client, monkeypatch):
    s3_mock = MagicMock()
    db_mock = make_db_mock()

    monkeypatch.setenv("S3_BUCKET_NAME", "test-bucket")

    with patch("main.get_s3_client", return_value=s3_mock), \
         patch("main.get_db_conn", return_value=db_mock):

        resp = client.post(
            "/upload",
            files={"file": ("test.txt", io.BytesIO(b"hello"), "text/plain")},
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["filename"] == "test.txt"
    assert body["bucket"] == "test-bucket"
    s3_mock.upload_fileobj.assert_called_once()
    db_mock.cursor.assert_called()


def test_upload_missing_bucket(client):
    import os
    os.environ.pop("S3_BUCKET_NAME", None)

    resp = client.post(
        "/upload",
        files={"file": ("test.txt", io.BytesIO(b"hello"), "text/plain")},
    )

    assert resp.status_code == 500
    assert "S3_BUCKET_NAME" in resp.json()["detail"]


def test_upload_s3_error(client, monkeypatch):
    from botocore.exceptions import ClientError

    monkeypatch.setenv("S3_BUCKET_NAME", "test-bucket")

    s3_mock = MagicMock()
    s3_mock.upload_fileobj.side_effect = ClientError(
        {"Error": {"Code": "NoSuchBucket", "Message": "bucket not found"}},
        "PutObject",
    )

    with patch("main.get_s3_client", return_value=s3_mock):
        resp = client.post(
            "/upload",
            files={"file": ("fail.txt", io.BytesIO(b"data"), "text/plain")},
        )

    assert resp.status_code == 500


def test_upload_no_file(client):
    resp = client.post("/upload")
    assert resp.status_code == 422