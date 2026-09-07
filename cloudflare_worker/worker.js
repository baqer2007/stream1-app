// Cloudflare Worker - بروكسي الحماية، وتخطي حجب DNS والتخزين المؤقت
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const targetUrl = url.searchParams.get("url");

    if (!targetUrl) {
      return new Response(JSON.stringify({ error: "Missing target URL parameter (?url=)" }), {
        status: 400,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
      });
    }

    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, HEAD, OPTIONS",
          "Access-Control-Allow-Headers": "*"
        }
      });
    }

    const modifiedHeaders = new Headers(request.headers);
    modifiedHeaders.set("User-Agent", "okhttp/4.9.0");
    modifiedHeaders.delete("host");
    modifiedHeaders.delete("origin");

    try {
      const response = await fetch(targetUrl, {
        method: request.method,
        headers: modifiedHeaders,
        body: request.method !== "GET" && request.method !== "HEAD" ? request.body : undefined
      });

      const newResponse = new Response(response.body, response);
      newResponse.headers.set("Access-Control-Allow-Origin", "*");
      newResponse.headers.set("Cache-Control", "public, max-age=1800"); // كاش لمدة 30 دقيقة
      return newResponse;
    } catch (err) {
      return new Response(JSON.stringify({ error: "Proxy upstream failed", details: err.message }), {
        status: 502,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
      });
    }
  }
};
