"""POST /auth/refresh. Public route; the refresh token itself is a bearer secret."""
import os
import boto3
from botocore.exceptions import ClientError
from common import body, response, success, options_response

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    try:
        data = body(event or {})
        refresh = str(data.get("refreshToken", "")).strip()
        if not refresh:
            return response(400, {"isSuccess": False, "errorMessage": "refreshToken requerido."})
        idp = boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION"))
        result = idp.initiate_auth(ClientId=os.environ["COGNITO_USER_POOL_CLIENT_ID"],
            AuthFlow="REFRESH_TOKEN_AUTH", AuthParameters={"REFRESH_TOKEN": refresh})
        auth = result.get("AuthenticationResult") or {}
        if not auth.get("IdToken") or not auth.get("AccessToken"):
            return response(401, {"isSuccess": False, "errorMessage": "La sesión ya no es válida. Inicia sesión nuevamente."})
        return success({"accessToken": auth["AccessToken"], "idToken": auth["IdToken"],
            "expiresIn": auth.get("ExpiresIn", 3600), "tokenType": auth.get("TokenType", "Bearer")})
    except ClientError:
        return response(401, {"isSuccess": False, "errorMessage": "La sesión expiró. Inicia sesión nuevamente."})
    except Exception:
        return response(502, {"isSuccess": False, "errorMessage": "No se pudo renovar la sesión."})
