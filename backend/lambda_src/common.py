"""Helpers shared by all Lambda handlers; API Gateway REST API, Lambda proxy integration."""
from __future__ import annotations
import base64
import json
import os
from datetime import date, datetime
from decimal import Decimal
from typing import Any


def json_default(value: Any):
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    raise TypeError(f"Tipo no serializable: {type(value).__name__}")


def response(status: int, data: Any, extra_headers: dict | None = None) -> dict:
    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "Access-Control-Allow-Origin": os.getenv("ALLOWED_ORIGIN", "http://localhost:4200"),
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "GET,POST,PATCH,PUT,DELETE,OPTIONS",
        "Vary": "Origin",
        "Cache-Control": "no-store",
    }
    if extra_headers:
        headers.update(extra_headers)
    return {"statusCode": status, "headers": headers,
            "body": "" if status == 204 else json.dumps(data, ensure_ascii=False, default=json_default)}


def options_response(event: dict) -> dict | None:
    if (event.get("httpMethod") or event.get("requestContext", {}).get("http", {}).get("method")) == "OPTIONS":
        return response(204, {})
    return None


def body(event: dict) -> dict:
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        raise ValueError("El cuerpo JSON debe ser un objeto.")
    return parsed


def query(event: dict, key: str, default=None):
    return (event.get("queryStringParameters") or {}).get(key, default)


def path(event: dict, key: str):
    return (event.get("pathParameters") or {}).get(key)


def claims(event: dict) -> dict:
    """Cognito claims populated by an API Gateway REST API Cognito authorizer."""
    auth = (event.get("requestContext") or {}).get("authorizer") or {}
    claims = auth.get("claims") or auth.get("jwt", {}).get("claims") or {}
    return claims if isinstance(claims, dict) else {}


def cognito_sub(event: dict) -> str | None:
    return claims(event).get("sub")


def email_claim(event: dict) -> str | None:
    return claims(event).get("email")


def safe_error(message: str = "La solicitud no pudo procesarse.", status: int = 500):
    return response(status, {"isSuccess": False, "errorMessage": message})


def success(data: Any, status: int = 200):
    return response(status, {"isSuccess": True, "data": data})


def db_error(name: str):
    # Do not expose connection strings, SQL text, credentials or internal exception details.
    print(f"{name}: database operation failed")
    return safe_error("No se pudo completar la operación en la base de datos.", 503)


def to_role(code: str | None) -> str | None:
    return {"ADMIN": "admin", "SELLER": "vendedor", "CUSTOMER": "cliente", "VENDOR": "vendedor", "CLIENT": "cliente"}.get((code or "").upper())


def from_role(role: str | None) -> str | None:
    return {"admin": "ADMIN", "vendedor": "SELLER", "cliente": "CUSTOMER",
            "ADMIN": "ADMIN", "SELLER": "SELLER", "CUSTOMER": "CUSTOMER", "VENDOR": "SELLER", "CLIENT": "CUSTOMER"}.get(role or "")


def to_quote_status(code: str | None) -> str:
    return {"DRAFT": "Borrador", "PENDING": "Enviada", "APPROVED": "Aceptada", "OBSERVED": "Rechazada", "SENT": "Enviada", "ACCEPTED": "Aceptada", "REJECTED": "Rechazada"}.get((code or "").upper(), code or "")


def from_quote_status(status: str | None) -> str | None:
    return {"Borrador": "DRAFT", "Enviada": "PENDING", "Aceptada": "APPROVED", "Rechazada": "OBSERVED",
            "DRAFT": "DRAFT", "SENT": "PENDING", "ACCEPTED": "APPROVED", "REJECTED": "OBSERVED",
            "PENDING": "PENDING", "APPROVED": "APPROVED", "OBSERVED": "OBSERVED"}.get(status or "")


def map_user(row: dict) -> dict:
    role_code = row.get("roleCode") or row.get("role")
    status_code = row.get("statusCode") or row.get("status")
    name = row.get("name") or row.get("fullName") or ""
    return {
        "id": str(row.get("userId", row.get("id", ""))),
        "name": name,
        "email": row.get("email", ""),
        "phone": row.get("phone") or "",
        "company": row.get("companyName") or row.get("company") or "",
        "role": to_role(role_code) or role_code,
        "status": {"ACTIVE": "Activo", "PENDING": "Pendiente", "BLOCKED": "Bloqueado"}.get((status_code or "").upper(), status_code or ""),
        "registeredAt": row.get("createdAt"),
        "initials": "".join(part[0] for part in name.split()[:2]).upper(),
        "notes": row.get("notes") or "",
    }


def map_quote(row: dict) -> dict:
    created = row.get("createdAt")
    return {
        "id": row.get("quoteCode") or row.get("id"),
        "clientId": str(row.get("customerId") or row.get("clientId") or ""),
        "clientName": row.get("customerName") or "",
        "clientEmail": row.get("customerEmail") or "",
        "clientPhone": row.get("customerPhone") or "",
        "clientCompany": row.get("customerCompany") or "",
        "sellerId": str(row.get("sellerId") or row.get("assignedSellerUserId") or ""),
        "sellerName": row.get("sellerName") or "Sin asignar",
        "sellerEmail": row.get("sellerEmail") or "",
        "status": to_quote_status(row.get("status")),
        "date": created.date().isoformat() if isinstance(created, datetime) else (str(created)[:10] if created else ""),
        "createdAtLabel": created.isoformat(sep=" ", timespec="minutes") if isinstance(created, datetime) else (str(created) if created else ""),
        "discountPercent": float(row.get("discountPercent") or 0),
        "taxPercent": float(row.get("taxPercent") or 18),
        "subtotal": float(row.get("subtotal") or 0),
        "discountAmount": float(row.get("discountAmount") or 0),
        "taxAmount": float(row.get("taxAmount") or 0),
        "total": float(row.get("total") or 0),
        "currency": row.get("currency") or "USD",
        "customerMessage": row.get("customerMessage") or "",
        "reviewComment": row.get("reviewComment") or "",
    }


def actor_for_event(event: dict):
    """Resolve the verified Cognito subject to the active SQL profile and role."""
    sub = cognito_sub(event)
    if not sub:
        return None, response(401, {"isSuccess": False, "errorMessage": "Autenticación requerida."})
    from db import get_connection, rows
    conn = cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC dbo.usp_User_GetBySub @CognitoSub = ?", (sub,))
        data = rows(cursor)
        if not data:
            return None, response(403, {"isSuccess": False, "errorMessage": "El usuario autenticado no tiene un perfil habilitado."})
        record = data[0]
        if (record.get("statusCode") or "").upper() != "ACTIVE":
            return None, response(403, {"isSuccess": False, "errorMessage": "La cuenta está pendiente o bloqueada."})
        record["sub"] = sub
        record["role"] = to_role(record.get("roleCode"))
        return record, None
    except Exception:
        return None, db_error("actor_for_event")
    finally:
        if cursor: cursor.close()
        if conn: conn.close()


def require_actor(event: dict, roles: tuple[str, ...] | None = None):
    actor, error = actor_for_event(event)
    if error:
        return None, error
    if roles and actor.get("roleCode") not in roles:
        return None, response(403, {"isSuccess": False, "errorMessage": "No tienes permisos para esta operación."})
    return actor, None
