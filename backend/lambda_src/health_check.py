from common import success, options_response, db_error
from db import get_connection, rows

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    conn = cursor = None
    try:
        conn = get_connection(); cursor = conn.cursor()
        cursor.execute("EXEC dbo.usp_HealthCheck")
        result = rows(cursor)
        return success({"status": "ok", "databaseConnected": bool(result and result[0].get("databaseOk"))})
    except Exception:
        return db_error("health_check")
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
