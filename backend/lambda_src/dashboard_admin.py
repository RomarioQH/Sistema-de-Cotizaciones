from common import response, success, options_response, require_actor, map_quote
from db import get_connection, rows

def lambda_handler(event, context):
    del context
    early=options_response(event or {})
    if early: return early
    _,error=require_actor(event or {},("ADMIN",))
    if error: return error
    conn=cursor=None
    try:
        conn=get_connection(); cursor=conn.cursor(); cursor.execute("EXEC dbo.usp_Dashboard_Admin")
        metrics=(rows(cursor) or [{}])[0]
        recent=[]
        if cursor.nextset():
            for row in rows(cursor):
                quote=map_quote(row); quote["itemCount"]=int(row.get("itemCount") or 0); quote["items"]=[]; recent.append(quote)
        for key in ("totalQuotes","sentQuotes","acceptedQuotes","activeClients","activeUsers"):
            metrics[key]=int(metrics.get(key) or 0)
        for key in ("acceptedRevenue","conversionRate"):
            metrics[key]=float(metrics.get(key) or 0)
        return success({"metrics":metrics,"recentQuotes":recent})
    except Exception:
        return response(503,{"isSuccess":False,"errorMessage":"No se pudo cargar el panel administrativo."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
