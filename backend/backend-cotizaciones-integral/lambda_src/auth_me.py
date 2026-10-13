from common import require_actor, success, response, options_response, map_user

def lambda_handler(event, context):
    del context
    early = options_response(event or {})
    if early: return early
    actor, error = require_actor(event or {})
    if error: return error
    actor["statusCode"] = "ACTIVE"
    return success(map_user(actor))
