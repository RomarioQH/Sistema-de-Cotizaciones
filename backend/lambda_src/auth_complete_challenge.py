"""POST /auth/complete-new-password for Cognito-invited users on first sign-in."""
import os
import boto3
from botocore.exceptions import ClientError
from common import body, response, success, options_response
from db import get_connection, rows

def lambda_handler(event, context):
    del context
    early=options_response(event or {})
    if early: return early
    conn=cursor=None
    try:
        data=body(event)
        username=str(data.get("username","")).strip().lower()
        session=str(data.get("session", ""))
        new_password=str(data.get("newPassword", ""))
        if not username or not session or len(new_password)<8:
            return response(400,{"isSuccess":False,"errorMessage":"Usuario, sesión y nueva contraseña válida son obligatorios."})
        idp=boto3.client("cognito-idp",region_name=os.getenv("AWS_REGION"))
        result=idp.respond_to_auth_challenge(ClientId=os.environ["COGNITO_USER_POOL_CLIENT_ID"],
            ChallengeName="NEW_PASSWORD_REQUIRED",Session=session,
            ChallengeResponses={"USERNAME":username,"NEW_PASSWORD":new_password})
        auth=result.get("AuthenticationResult") or {}
        access=auth.get("AccessToken")
        if not access:
            return response(401,{"isSuccess":False,"errorMessage":"No se completó el cambio de contraseña."})
        info=idp.get_user(AccessToken=access)
        sub=next((x["Value"] for x in info.get("UserAttributes",[]) if x["Name"]=="sub"),None)
        if not sub: return response(401,{"isSuccess":False,"errorMessage":"La identidad no es válida."})
        conn=get_connection(); cursor=conn.cursor(); cursor.execute("EXEC dbo.usp_User_GetBySub ?",(sub,)); profiles=rows(cursor)
        if not profiles or profiles[0].get("statusCode")!="ACTIVE":
            try: idp.global_sign_out(AccessToken=access)
            except Exception: pass
            return response(403,{"isSuccess":False,"errorMessage":"El perfil no está habilitado."})
        u=profiles[0]
        return success({"accessToken":access,"idToken":auth.get("IdToken"),"refreshToken":auth.get("RefreshToken"),
          "expiresIn":auth.get("ExpiresIn",3600),"tokenType":auth.get("TokenType","Bearer"),
          "user":{"id":str(u["userId"]),"name":u["name"],"email":u["email"],"phone":u.get("phone") or "",
            "company":u.get("companyName") or "","role":{"ADMIN":"admin","SELLER":"vendedor","CUSTOMER":"cliente"}.get(u.get("roleCode"),"cliente"),"status":"Activo"}})
    except ClientError:
        return response(400,{"isSuccess":False,"errorMessage":"No se pudo completar el cambio de contraseña."})
    except Exception:
        print("auth_complete_challenge: operation failed")
        return response(503,{"isSuccess":False,"errorMessage":"No se pudo completar el cambio de contraseña."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
