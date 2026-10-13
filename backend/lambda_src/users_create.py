"""POST /usuarios; administrator provisions client/vendor users, never another admin."""
import os
import boto3
from botocore.exceptions import ClientError
from common import body, response, success, options_response, require_actor, from_role, map_user
from db import get_connection, rows

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    actor, error = require_actor(event or {}, ("ADMIN",))
    if error: return error
    conn = cursor = None; created_username = None
    try:
        data = body(event); name = str(data.get("name", "")).strip(); email = str(data.get("email", "")).strip().lower()
        phone = str(data.get("phone", "")).strip(); company = str(data.get("company", "")).strip()
        role = from_role(str(data.get("role", "vendedor")))
        if not name or len(name)>150 or "@" not in email or role not in ("SELLER", "CUSTOMER"):
            return response(400, {"isSuccess": False, "errorMessage": "Nombre, correo o rol inválido. Solo se puede crear vendedor o cliente."})
        idp = boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION"))
        # Phone is stored in SQL only; Cognito's standard phone_number must be E.164.
        attrs = [{"Name":"email","Value":email},{"Name":"name","Value":name}]
        created = idp.admin_create_user(UserPoolId=os.environ["COGNITO_USER_POOL_ID"],Username=email,
            UserAttributes=attrs,DesiredDeliveryMediums=["EMAIL"])
        created_username = email
        sub = next((a["Value"] for a in created["User"].get("Attributes",[]) if a["Name"]=="sub"), None)
        if not sub: raise RuntimeError("Cognito did not return sub")
        conn = get_connection(); cursor = conn.cursor()
        cursor.execute("EXEC dbo.usp_User_CreateInvited ?, ?, ?, ?, ?, ?, ?", (sub,name,email,phone or None,company or None,role,actor["userId"]))
        result = rows(cursor); conn.commit()
        return success({"userId": result[0]["userId"] if result else None, "email":email,
            "role": {"SELLER":"vendedor","CUSTOMER":"cliente"}[role],
            "message":"Usuario creado. Cognito enviará instrucciones al correo."},201)
    except ClientError as exc:
        code = exc.response.get("Error",{}).get("Code","")
        status = 409 if code=="UsernameExistsException" else 400 if code in ("InvalidParameterException","InvalidPasswordException") else 502
        return response(status,{"isSuccess":False,"errorMessage":"Cognito no pudo crear el usuario. Verifica si el correo ya existe y la configuración del User Pool."})
    except Exception:
        if conn:
            try: conn.rollback()
            except Exception: pass
        if created_username:
            try: boto3.client("cognito-idp",region_name=os.getenv("AWS_REGION")).admin_delete_user(UserPoolId=os.environ["COGNITO_USER_POOL_ID"],Username=created_username)
            except Exception: print("users_create: cleanup of orphan Cognito user failed")
        print("users_create: operation failed")
        return response(503,{"isSuccess":False,"errorMessage":"No se pudo persistir el usuario."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
