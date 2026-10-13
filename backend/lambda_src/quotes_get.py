from common import response, success, options_response, require_actor, path
from db import get_connection
from quote_repository import read_quote

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    actor,error=require_actor(event or {})
    if error: return error
    code=path(event or {},"quoteCode")
    if not code: return response(400,{"isSuccess":False,"errorMessage":"quoteCode requerido."})
    conn=cursor=None
    try:
        conn=get_connection(); cursor=conn.cursor(); quote=read_quote(cursor,code,actor)
        return success(quote) if quote else response(404,{"isSuccess":False,"errorMessage":"Cotización no encontrada."})
    except Exception:
        return response(503,{"isSuccess":False,"errorMessage":"No se pudo consultar el detalle de la cotización."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
