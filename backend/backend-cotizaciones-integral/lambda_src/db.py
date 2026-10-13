"""SQL Server connection via the prebuilt Python 3.13 + ODBC Driver 18 Lambda layer."""
from __future__ import annotations
import os
import pyodbc


def _odbc_value(value: str) -> str:
    return "{" + value.replace("}", "}}") + "}"


def get_connection():
    server = os.getenv("DB_SERVER", "").strip()
    database = os.getenv("DB_NAME", "").strip()
    username = os.getenv("DB_USER", "").strip()
    password = os.getenv("DB_PASSWORD", "")
    port = os.getenv("DB_PORT", "1433").strip()
    missing = [key for key, value in (("DB_SERVER", server), ("DB_NAME", database), ("DB_USER", username), ("DB_PASSWORD", password)) if not value]
    if missing:
        raise RuntimeError("Faltan variables de entorno: " + ", ".join(missing))
    if not port.isdigit() or not 1 <= int(port) <= 65535:
        raise RuntimeError("DB_PORT inválido")
    cs = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER=tcp:{server},{port};"
        f"DATABASE={_odbc_value(database)};"
        f"UID={_odbc_value(username)};"
        f"PWD={_odbc_value(password)};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=5;"
    )
    return pyodbc.connect(cs, timeout=5)


def rows(cursor):
    if cursor.description is None:
        return []
    cols = [col[0] for col in cursor.description]
    return [dict(zip(cols, row)) for row in cursor.fetchall()]


def exec_rows(proc: str, params: tuple = ()):
    conn = cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()
        placeholders = ", ".join("?" for _ in params)
        cursor.execute(f"EXEC {proc}" + (f" {placeholders}" if placeholders else ""), params)
        result = rows(cursor)
        conn.commit()
        return result
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
