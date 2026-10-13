from common import response, success, options_response, require_actor, query, from_quote_status, map_quote
from db import get_connection, rows

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    actor, error = require_actor(event or {})
    if error: return error
    requested_status = query(event, "status")
    status = from_quote_status(requested_status) if requested_status else None
    if requested_status and not status:
        return response(400,{"isSuccess":False,"errorMessage":"Filtro de estado no válido."})
    conn = cursor = None
    try:
        conn=get_connection(); cursor=conn.cursor()
        cursor.execute("EXEC dbo.usp_Quote_ListForActor ?, ?, ?, ?", (actor["userId"],actor["roleCode"],query(event,"search"),status))
        data=[]
        for row in rows(cursor):
            quote=map_quote(row); quote["itemCount"]=int(row.get("itemCount") or 0); quote["items"]=[]
            data.append(quote)
        return success(data)
    except Exception:
        return response(503,{"isSuccess":False,"errorMessage":"No se pudieron consultar las cotizaciones."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
