/**
 * {{ PROJECT }} — Cloudflare Worker
 * Deploy with: wrangler deploy
 */
export default {
	async fetch(request, env, ctx) {
		const url = new URL(request.url);

		if (url.pathname === "/health") {
			return new Response(JSON.stringify({
				app: "{{ PROJECT }}",
				status: "ok",
				ts: Date.now(),
			}), {
				headers: { "content-type": "application/json" },
			});
		}

		return new Response(`Hello from {{ PROJECT }}!\n`, {
			headers: { "content-type": "text/plain" },
		});
	},
};