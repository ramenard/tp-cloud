#!/bin/sh
exec alloy run --server.http.listen-addr=0.0.0.0:${PORT:-8080} /etc/alloy/config.alloy
