"""POST /auth/register. Self-registration is always CLIENT; never accepts a role from browser."""
import os
import re
import boto3
from botocore.exceptions import ClientError
from common import body, response, success, options_response
from db import get_connection


def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    conn = cursor = None
    cognito = boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION"))
    username = ""
    sub = ""
    try:
        data = body(event)
        name = str(data.get("name", "")).strip()
        email = str(data.get("email", "")).strip().lower()
        phone = str(data.get("phone", "")).strip()
        company = str(data.get("company", "")).strip()
        password = str(data.get("password", ""))
        if not name or len(name) > 150 or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email) or len(email) > 254:
            return response(400, {"isSuccess": False, "errorMessage": "Nombre o correo no válido."})
        if len(password) < 8:
            return response(400, {"isSuccess": False, "errorMessage": "La contraseña no cumple la longitud mínima."})
        client_id = os.environ["COGNITO_USER_POOL_CLIENT_ID"]
        # Phone is stored in SQL only; omitting Cognito's phone_number avoids forcing E.164 format.
        attrs = [{"Name": "email", "Value": email}, {"Name": "name", "Value": name}]
        created = cognito.sign_up(ClientId=client_id, Username=email, Password=password, UserAttributes=attrs)
        username = email
        sub = created["UserSub"]
        conn = get_connection(); cursor = conn.cursor()
        cursor.execute("EXEC dbo.usp_User_RegisterPending ?, ?, ?, ?, ?", (sub, name, email, phone or None, company or None))
        conn.commit()
        if created.get("UserConfirmed"):
            cursor.execute("EXEC dbo.usp_User_ActivateByEmail ?", (email,))
            conn.commit()
        return success({"email": email, "confirmationRequired": not bool(created.get("UserConfirmed")), "message": "Revisa tu correo para confirmar la cuenta."}, 201)
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        messages = {
            "UsernameExistsException": (409, "Ya existe una cuenta con ese correo."),
            "InvalidPasswordException": (400, "La contraseña no cumple la política de seguridad."),
            "InvalidParameterException": (400, "Los datos no cumplen los requisitos del registro."),
            "LimitExceededException": (429, "Se alcanzó el límite temporal de solicitudes."),
        }
        status, message = messages.get(code, (502, "No se pudo registrar la cuenta."))
        return response(status, {"isSuccess": False, "errorMessage": message})
    except Exception:
        if conn:
            try: conn.rollback()
            except Exception: pass
        # Compensating action for the case where Cognito created the user but SQL registration failed.
        if username and sub:
            try: cognito.admin_delete_user(UserPoolId=os.environ["COGNITO_USER_POOL_ID"], Username=username)
            except Exception: print("auth_register: cleanup of orphan identity failed")
        print("auth_register: registration operation failed")
        return response(503, {"isSuccess": False, "errorMessage": "No se pudo registrar la cuenta. Inténtalo de nuevo más tarde."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
