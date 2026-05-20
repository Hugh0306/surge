const rules = [{"pattern":"<GetADResult>\\.\\*\\?<\\/GetADResult>","replacement":"<GetADResult>{\"ret\":0,\"msg\":\"正常\",\"err_code\":0,\"data\":{\"ad\":[]}}</GetADResult>"}];
let body = $response.body || "";

for (const rule of rules) {
  body = body.replace(new RegExp(rule.pattern, "g"), rule.replacement);
}

$done({ body });
