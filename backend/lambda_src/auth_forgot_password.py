import os
import boto3
from botocore.exceptions import ClientError
from common import body, response, success, options_response

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    try:
        data = body(event); email = str(data.get("email", "")).strip().lower()
        if not email: return response(400, {"isSuccess": False, "errorMessage": "El correo es obligatorio."})
        boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION")).forgot_password(
            ClientId=os.environ["COGNITO_USER_POOL_CLIENT_ID"], Username=email)
        # Uniform response avoids disclosing whether the account exists.
        return success({"message": "Si la cuenta existe, recibirás instrucciones para restablecer tu contraseña."})
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code in ("UserNotFoundException", "InvalidParameterException"):
            return success({"message": "Si la cuenta existe, recibirás instrucciones para restablecer tu contraseña."})
        return response(502, {"isSuccess": False, "errorMessage": "No se pudo iniciar la recuperación de contraseña."})
    except Exception:
        print("auth_forgot_password: operation failed")
        return response(502, {"isSuccess": False, "errorMessage": "No se pudo iniciar la recuperación de contraseña."})
