import os
import boto3
from botocore.exceptions import ClientError
from common import body, response, success, options_response
from db import get_connection

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    conn = cursor = None
    try:
        data = body(event)
        email = str(data.get("email", "")).strip().lower()
        code = str(data.get("code", "")).strip()
        if not email or not code:
            return response(400, {"isSuccess": False, "errorMessage": "Correo y código son obligatorios."})
        idp = boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION"))
        try:
            idp.confirm_sign_up(ClientId=os.environ["COGNITO_USER_POOL_CLIENT_ID"], Username=email, ConfirmationCode=code)
        except ClientError as exc:
            # Make a retry safe if Cognito confirmation succeeded but SQL activation failed transiently.
            code_name = exc.response.get("Error", {}).get("Code", "")
            if code_name != "NotAuthorizedException":
                raise
            existing = idp.admin_get_user(UserPoolId=os.environ["COGNITO_USER_POOL_ID"], Username=email)
            if existing.get("UserStatus") != "CONFIRMED":
                raise
        conn = get_connection(); cursor = conn.cursor()
        cursor.execute("EXEC dbo.usp_User_ActivateByEmail ?", (email,))
        conn.commit()
        return success({"message": "Cuenta confirmada. Ya puedes iniciar sesión."})
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        status = 400 if code in ("CodeMismatchException", "ExpiredCodeException", "InvalidParameterException") else 502
        return response(status, {"isSuccess": False, "errorMessage": "No se pudo confirmar la cuenta. Verifica el código e inténtalo de nuevo."})
    except Exception:
        if conn:
            try: conn.rollback()
            except Exception: pass
        print("auth_confirm_registration: operation failed")
        return response(503, {"isSuccess": False, "errorMessage": "No se pudo activar el perfil en la base de datos."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
