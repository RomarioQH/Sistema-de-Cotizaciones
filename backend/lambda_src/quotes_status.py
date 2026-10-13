from common import body, response, success, options_response, require_actor, path, from_quote_status, to_quote_status
from db import get_connection, rows

def lambda_handler(event, context):
    del context
    early=options_response(event or {})
    if early: return early
    actor,error=require_actor(event or {})
    if error: return error
    code=path(event or {},"quoteCode")
    try:
        data=body(event); target=from_quote_status(str(data.get("status", "")))
        comment=str(data.get("comment", "")).strip() or None
        if not code or target not in ("PENDING","APPROVED","OBSERVED"): raise ValueError()
    except Exception:
        return response(400,{"isSuccess":False,"errorMessage":"Cotización, estado o cuerpo no válido."})
    conn=cursor=None
    try:
        conn=get_connection(); cursor=conn.cursor()
        cursor.execute("EXEC dbo.usp_Quote_ChangeStatus ?, ?, ?, ?, ?",(code,actor["userId"],actor["roleCode"],target,comment))
        result=rows(cursor); conn.commit()
        if not result: return response(404,{"isSuccess":False,"errorMessage":"Cotización no encontrada."})
        return success({"quoteCode":result[0]["quoteCode"],"status":to_quote_status(result[0]["status"]),"updatedAt":result[0]["updatedAt"]})
    except Exception:
        if conn:
            try: conn.rollback()
            except Exception: pass
        return response(409,{"isSuccess":False,"errorMessage":"Cambio de estado rechazado: revisa el estado actual y tu rol."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
