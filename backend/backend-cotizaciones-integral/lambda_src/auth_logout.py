"""POST /auth/logout; send the Cognito accessToken in the body."""
import os
import boto3
from common import body, response, success, options_response

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    try:
        data = body(event or {})
        token = str(data.get("accessToken", "")).strip()
        if not token:
            return response(400, {"isSuccess": False, "errorMessage": "accessToken requerido."})
        boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION")).global_sign_out(AccessToken=token)
        return success({"message": "Sesión cerrada."})
    except Exception:
        # Client must clear local tokens regardless of remote sign-out result.
        return success({"message": "Sesión cerrada en este dispositivo."})
