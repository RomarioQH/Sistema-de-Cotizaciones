from common import response, success, options_response, require_actor, map_user, query
from db import get_connection, rows

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    _, error = require_actor(event or {}, ("ADMIN",))
    if error: return error
    conn = cursor = None
    try:
        conn = get_connection(); cursor = conn.cursor(); cursor.execute("EXEC dbo.usp_User_List ?", (query(event, "search"),))
        return success([map_user(item) for item in rows(cursor)])
    except Exception:
        return response(503, {"isSuccess": False, "errorMessage": "No se pudo consultar los usuarios."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
