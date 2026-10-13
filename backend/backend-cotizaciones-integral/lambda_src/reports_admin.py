from common import response, success, options_response, require_actor, to_quote_status
from db import get_connection, rows

def lambda_handler(event, context):
    del context
    early=options_response(event or {})
    if early: return early
    _,error=require_actor(event or {},("ADMIN",))
    if error: return error
    conn=cursor=None
    try:
        conn=get_connection(); cursor=conn.cursor(); cursor.execute("EXEC dbo.usp_Report_AdminOverview")
        summary=(rows(cursor) or [{}])[0]
        status_rows=[]; best_seller=None
        if cursor.nextset():
            for row in rows(cursor):
                status_rows.append({"status":to_quote_status(row.get("status")),"count":int(row.get("count") or 0)})
        if cursor.nextset():
            best=rows(cursor); best_seller=best[0] if best else None
        for key in ("acceptedRevenue","conversionRate"): summary[key]=float(summary.get(key) or 0)
        for key in ("totalQuotes","activeClients"): summary[key]=int(summary.get(key) or 0)
        return success({"summary":summary,"byStatus":status_rows,"bestSeller":best_seller})
    except Exception:
        return response(503,{"isSuccess":False,"errorMessage":"No se pudo generar el reporte."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
