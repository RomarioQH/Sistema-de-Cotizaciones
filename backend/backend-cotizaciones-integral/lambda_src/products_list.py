from common import body, response, success, options_response, require_actor
from db import get_connection, rows
from common import query

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    _, error = require_actor(event or {})
    if error: return error
    conn = cursor = None
    try:
        conn = get_connection(); cursor = conn.cursor()
        cursor.execute("EXEC dbo.usp_Product_ListActive ?, ?", (query(event, "search"), query(event, "category")))
        return success(rows(cursor))
    except Exception:
        return response(503, {"isSuccess": False, "errorMessage": "No se pudo consultar el catálogo."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
