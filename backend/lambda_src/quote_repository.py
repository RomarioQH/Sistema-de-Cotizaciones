"""Shared reading of the quote-header, item and status-history result sets."""
from db import rows
from common import map_quote

def read_quote(cursor, quote_code: str, actor: dict):
    cursor.execute("EXEC dbo.usp_Quote_GetByCode ?, ?, ?", (quote_code, actor["userId"], actor["roleCode"]))
    headers = rows(cursor)
    if not headers:
        return None
    quote = map_quote(headers[0])
    if cursor.nextset():
        quote["items"] = rows(cursor)
    else:
        quote["items"] = []
    if cursor.nextset():
        quote["history"] = rows(cursor)
    else:
        quote["history"] = []
    quote["itemCount"] = len(quote["items"])
    # Map history codes to the labels used by the Angular UI.
    for entry in quote["history"]:
        entry["previousStatus"] = __import__("common").to_quote_status(entry.get("previousStatus")) if entry.get("previousStatus") else None
        entry["newStatus"] = __import__("common").to_quote_status(entry.get("newStatus"))
    return quote
