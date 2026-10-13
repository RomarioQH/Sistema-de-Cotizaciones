"""PATCH /usuarios/{userId}. Admins cannot edit or assign the ADMIN role via this endpoint."""
from common import body, response, success, options_response, require_actor, path, from_role, to_role, map_user
from db import get_connection, rows


def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early:
        return early
    _, error = require_actor(event or {}, ("ADMIN",))
    if error:
        return error
    try:
        user_id = int(path(event or {}, "userId"))
        if user_id <= 0:
            raise ValueError()
        data = body(event or {})
    except Exception:
        return response(400, {"isSuccess": False, "errorMessage": "userId o cuerpo inválido."})

    conn = cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC dbo.usp_User_GetById ?", (user_id,))
        existing_rows = rows(cursor)
        if not existing_rows:
            return response(404, {"isSuccess": False, "errorMessage": "Usuario no encontrado."})
        existing = existing_rows[0]
        if existing.get("roleCode") == "ADMIN":
            return response(403, {"isSuccess": False, "errorMessage": "No se puede modificar una cuenta de administrador desde este endpoint."})

        name = str(data.get("name", existing.get("name") or "")).strip()
        if not name or len(name) > 150:
            return response(400, {"isSuccess": False, "errorMessage": "El nombre es obligatorio (máximo 150 caracteres)."})
        current_role = to_role(existing.get("roleCode")) or "cliente"
        requested_role = str(data.get("role", current_role))
        role = from_role(requested_role)
        current_status = existing.get("statusCode") or "ACTIVE"
        status_was_sent = "status" in data
        requested_status = str(data.get("status", current_status))
        status = {"Activo": "ACTIVE", "Pendiente": "PENDING", "Bloqueado": "BLOCKED",
                  "ACTIVE": "ACTIVE", "PENDING": "PENDING", "BLOCKED": "BLOCKED"}.get(requested_status)
        if role not in ("CUSTOMER", "SELLER") or status not in ("ACTIVE", "BLOCKED", "PENDING"):
            return response(400, {"isSuccess": False, "errorMessage": "Rol o estado inválido. No se puede asignar ADMIN."})
        # A pending profile may be edited without changing its state, but the admin API cannot activate it
        # before email confirmation nor reset an active profile back to pending.
        if status == "PENDING" and not (current_status == "PENDING" and not status_was_sent):
            return response(400, {"isSuccess": False, "errorMessage": "Una cuenta pendiente debe confirmar su correo antes de activarse."})
        phone = str(data.get("phone", existing.get("phone") or "")).strip() or None
        company = str(data.get("company", existing.get("companyName") or "")).strip() or None
        notes = str(data.get("notes", existing.get("notes") or "")).strip() or None

        cursor.execute("EXEC dbo.usp_User_Update ?, ?, ?, ?, ?, ?, ?",
                       (user_id, name, phone, company, role, status, notes))
        updated_rows = rows(cursor)
        conn.commit()
        return success(map_user(updated_rows[0])) if updated_rows else response(404, {"isSuccess": False, "errorMessage": "Usuario no encontrado."})
    except Exception:
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        print("users_update: operation failed")
        return response(400, {"isSuccess": False, "errorMessage": "No se pudo actualizar el usuario. Verifica que exista y que no sea administrador."})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()
