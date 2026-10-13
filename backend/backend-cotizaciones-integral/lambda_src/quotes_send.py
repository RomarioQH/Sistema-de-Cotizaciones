"""POST /cotizaciones/{quoteCode}/enviar. Requires SES sender verification and IAM ses:SendEmail."""
import html
import os
import boto3
from common import response, success, options_response, require_actor, path
from db import get_connection
from quote_repository import read_quote
from db import rows

def lambda_handler(event, context):
    del context
    early=options_response(event or {})
    if early: return early
    actor,error=require_actor(event or {},("ADMIN","SELLER"))
    if error: return error
    code=path(event or {},"quoteCode")
    sender=os.getenv("SES_FROM_EMAIL","").strip()
    if not code: return response(400,{"isSuccess":False,"errorMessage":"quoteCode requerido."})
    if not sender: return response(503,{"isSuccess":False,"errorMessage":"El envío de correo aún no está configurado."})
    conn=cursor=None
    try:
        conn=get_connection(); cursor=conn.cursor(); quote=read_quote(cursor,code,actor)
        if not quote: return response(404,{"isSuccess":False,"errorMessage":"Cotización no encontrada."})
        if not quote.get("clientEmail"): return response(409,{"isSuccess":False,"errorMessage":"El cliente no tiene correo registrado."})
        if quote.get("status") not in ("Borrador","Enviada"):
            return response(409,{"isSuccess":False,"errorMessage":"Solo se pueden enviar borradores o reenviar cotizaciones enviadas."})
        code_html=html.escape(str(quote.get("id",code)))
        rows_html="".join(f"<tr><td>{html.escape(str(i.get('title','')))}</td><td>{float(i.get('quantity') or 0):g}</td><td>{float(i.get('unitPrice') or 0):.2f}</td></tr>" for i in quote.get("items",[]))
        total=float(quote.get("total") or 0); currency=html.escape(str(quote.get("currency") or "USD"))
        body_html=f"<h2>Cotización {code_html}</h2><p>Hola {html.escape(str(quote.get('clientName') or ''))},</p><p>Adjuntamos el resumen de tu cotización.</p><table border='1' cellpadding='6'><thead><tr><th>Producto/servicio</th><th>Cantidad</th><th>Precio unitario</th></tr></thead><tbody>{rows_html}</tbody></table><p><strong>Total: {total:.2f} {currency}</strong></p><p>Esta notificación fue enviada por el Sistema de Cotizaciones.</p>"
        boto3.client("ses",region_name=os.getenv("AWS_REGION")).send_email(Source=sender,Destination={"ToAddresses":[quote["clientEmail"]]},
            Message={"Subject":{"Data":f"Cotización {code}","Charset":"UTF-8"},"Body":{"Html":{"Data":body_html,"Charset":"UTF-8"},"Text":{"Data":f"Cotización {code}. Total: {total:.2f} {currency}","Charset":"UTF-8"}}})
        if quote.get("status")=="Borrador":
            cursor.execute("EXEC dbo.usp_Quote_ChangeStatus ?, ?, ?, ?, ?",(code,actor["userId"],actor["roleCode"],"PENDING","Enviada por correo"))
            rows(cursor); conn.commit()
        return success({"quoteCode":code,"status":"Enviada","recipient":quote["clientEmail"],"message":"Correo aceptado por Amazon SES."})
    except Exception:
        if conn:
            try: conn.rollback()
            except Exception: pass
        print("quotes_send: email send or status update failed")
        return response(502,{"isSuccess":False,"errorMessage":"No se pudo completar el envío de correo. Verifica SES, el remitente y la conectividad."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
