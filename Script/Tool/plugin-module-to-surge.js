let body = $response.body || "";

body = body
  .replace(/loon:\/\/import\?plugin=/g, "surge:///install-module?url=")
  .replace(/egern:\/\/\/modules\/new\?url=/g, "surge:///install-module?url=");

$done({ body });
