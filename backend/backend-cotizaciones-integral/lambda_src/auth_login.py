"""POST /auth/login. Cognito authenticates passwords; SQL stores app profile and role."""
import os
import boto3
from botocore.exceptions import ClientError
from common import body, response, success, options_response
from db import get_connection, rows


def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    conn = cursor = None
    try:
        data = body(event)
        email = str(data.get("email", "")).strip().lower()
        password = str(data.get("password", ""))
        if not email or not password:
            return response(400, {"isSuccess": False, "errorMessage": "Correo y contraseña son obligatorios."})
        idp = boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION"))
        result = idp.initiate_auth(ClientId=os.environ["COGNITO_USER_POOL_CLIENT_ID"], AuthFlow="USER_PASSWORD_AUTH",
                                  AuthParameters={"USERNAME": email, "PASSWORD": password})
        if result.get("ChallengeName"):
            challenge = result["ChallengeName"]
            return response(200, {"isSuccess": True, "data": {"challengeName": challenge, "session": result.get("Session"), "username": email}})
        auth = result.get("AuthenticationResult") or {}
        access_token = auth.get("AccessToken")
        if not access_token:
            return response(401, {"isSuccess": False, "errorMessage": "No se pudo completar el inicio de sesión."})
        info = idp.get_user(AccessToken=access_token)
        attributes = {item["Name"]: item["Value"] for item in info.get("UserAttributes", [])}
        sub = attributes.get("sub")
        if not sub:
            return response(401, {"isSuccess": False, "errorMessage": "La cuenta no tiene una identidad válida."})
        conn = get_connection(); cursor = conn.cursor()
        cursor.execute("EXEC dbo.usp_User_GetBySub ?", (sub,))
        matches = rows(cursor)
        if not matches or matches[0].get("statusCode") != "ACTIVE":
            try: idp.global_sign_out(AccessToken=access_token)
            except Exception: pass
            return response(403, {"isSuccess": False, "errorMessage": "La cuenta no está habilitada para ingresar."})
        profile = matches[0]
        return success({
            "accessToken": access_token,
            "idToken": auth.get("IdToken"),
            "refreshToken": auth.get("RefreshToken"),
            "expiresIn": auth.get("ExpiresIn", 3600),
            "tokenType": auth.get("TokenType", "Bearer"),
            "user": {"id": str(profile["userId"]), "name": profile["name"], "email": profile["email"],
                     "phone": profile.get("phone") or "", "company": profile.get("companyName") or "",
                     "role": {"ADMIN": "admin", "SELLER": "vendedor", "CUSTOMER": "cliente"}.get(profile.get("roleCode"), "cliente"),
                     "status": "Activo"}
        })
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        map_err = {
            "NotAuthorizedException": (401, "Correo o contraseña incorrectos."),
            "UserNotFoundException": (401, "Correo o contraseña incorrectos."),
            "UserNotConfirmedException": (403, "Confirma tu correo antes de iniciar sesión."),
            "PasswordResetRequiredException": (403, "Debes restablecer la contraseña antes de ingresar."),
            "TooManyRequestsException": (429, "Demasiados intentos. Espera un momento."),
        }
        status, message = map_err.get(code, (502, "El servicio de autenticación no pudo completar la solicitud."))
        return response(status, {"isSuccess": False, "errorMessage": message})
    except Exception:
        print("auth_login: login operation failed")
        return response(503, {"isSuccess": False, "errorMessage": "No se pudo validar el acceso."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
