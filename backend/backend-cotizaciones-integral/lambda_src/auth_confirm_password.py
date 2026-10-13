import os
import boto3
from botocore.exceptions import ClientError
from common import body, response, success, options_response

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    try:
        data = body(event)
        email = str(data.get("email", "")).strip().lower()
        code = str(data.get("code", "")).strip()
        password = str(data.get("newPassword", ""))
        if not email or not code or len(password) < 8:
            return response(400, {"isSuccess": False, "errorMessage": "Correo, código y nueva contraseña válida son obligatorios."})
        boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION")).confirm_forgot_password(
            ClientId=os.environ["COGNITO_USER_POOL_CLIENT_ID"], Username=email,
            ConfirmationCode=code, Password=password)
        return success({"message": "Contraseña actualizada. Ya puedes iniciar sesión."})
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        status = 400 if code in ("CodeMismatchException", "ExpiredCodeException", "InvalidPasswordException", "InvalidParameterException") else 502
        return response(status, {"isSuccess": False, "errorMessage": "No se pudo actualizar la contraseña. Verifica el código y la política de contraseña."})
    except Exception:
        print("auth_confirm_password: operation failed")
        return response(502, {"isSuccess": False, "errorMessage": "No se pudo actualizar la contraseña."})
