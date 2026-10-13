from common import response, success, options_response, require_actor, path
from db import get_connection, rows

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    _, error = require_actor(event or {})
    if error: return error
    slug = path(event or {}, "productId")
    if not slug: return response(400, {"isSuccess": False, "errorMessage": "productId requerido."})
    conn = cursor = None
    try:
        conn = get_connection(); cursor = conn.cursor()
        cursor.execute("EXEC dbo.usp_Product_GetBySlug ?", (slug,)); data = rows(cursor)
        return success(data[0]) if data else response(404, {"isSuccess": False, "errorMessage": "Producto no encontrado."})
    except Exception:
        return response(503, {"isSuccess": False, "errorMessage": "No se pudo consultar el producto."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
