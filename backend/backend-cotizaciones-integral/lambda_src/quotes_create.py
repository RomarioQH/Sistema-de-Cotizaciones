import json
from decimal import Decimal, InvalidOperation
from common import body, response, success, options_response, require_actor
from db import get_connection, rows

def lambda_handler(event, context):
    del context
    early=options_response(event or {})
    if early: return early
    actor,error=require_actor(event or {},("ADMIN","SELLER","CUSTOMER"))
    if error: return error
    conn=cursor=None
    try:
        data=body(event)
        discount=Decimal(str(data.get("discountPercent",0)))
        tax=Decimal(str(data.get("taxPercent",18)))
        message=str(data.get("customerMessage", "")).strip() or None
        items=data.get("items")
        if not (Decimal(0)<=discount<=Decimal(100)) or not (Decimal(0)<=tax<=Decimal(100)):
            return response(400,{"isSuccess":False,"errorMessage":"Descuento e impuesto deben estar entre 0 y 100."})
        if not isinstance(items,list) or not 1<=len(items)<=100:
            return response(400,{"isSuccess":False,"errorMessage":"Incluye entre 1 y 100 productos."})
        cleaned=[]
        for item in items:
            if not isinstance(item,dict): raise ValueError("invalid item")
            slug=str(item.get("productId", "")).strip()
            qty=Decimal(str(item.get("quantity",0)))
            if not slug or len(slug)>80 or qty<=0 or qty>Decimal("1000000"): raise ValueError("invalid item")
            cleaned.append({"productId":slug,"quantity":str(qty)})
        if len({x["productId"] for x in cleaned})!=len(cleaned):
            return response(400,{"isSuccess":False,"errorMessage":"No repitas el mismo producto. Ajusta su cantidad."})
        customer_id=None; seller_id=None
        if actor["roleCode"]!="CUSTOMER":
            try: customer_id=int(data.get("customerId"))
            except (TypeError,ValueError): return response(400,{"isSuccess":False,"errorMessage":"customerId es obligatorio para crear por un cliente."})
            if actor["roleCode"]=="SELLER": seller_id=int(actor["userId"])
            elif data.get("sellerId") is not None: seller_id=int(data["sellerId"])
        conn=get_connection(); cursor=conn.cursor()
        cursor.execute("EXEC dbo.usp_Quote_Create ?, ?, ?, ?, ?, ?, ?, ?", (actor["userId"],actor["roleCode"],customer_id,seller_id,discount,tax,message,json.dumps(cleaned)))
        result=rows(cursor); conn.commit()
        if not result: raise RuntimeError("Quote procedure did not return an identifier")
        return success({"quoteId":result[0]["quoteId"],"quoteCode":result[0]["quoteCode"],"subtotal":result[0]["subtotal"],
                        "discountAmount":result[0]["discountAmount"],"taxAmount":result[0]["taxAmount"],"total":result[0]["total"]},201)
    except (KeyError,TypeError,ValueError,InvalidOperation,json.JSONDecodeError):
        if conn:
            try: conn.rollback()
            except Exception: pass
        return response(400,{"isSuccess":False,"errorMessage":"El contenido de la cotización no es válido."})
    except Exception:
        if conn:
            try: conn.rollback()
            except Exception: pass
        print("quotes_create: operation failed")
        return response(400,{"isSuccess":False,"errorMessage":"No se pudo registrar la cotización. Verifica cliente, vendedor y productos activos."})
    finally:
        if cursor: cursor.close()
        if conn: conn.close()
