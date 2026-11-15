// Windowsill: widget-push
//
// Called by a database webhook whenever a row is inserted into `petals`.
// Sends a WidgetKit push to every *other* member of that windowsill, so their
// widget reloads and shows the new flower. Pushes are budgeted by iOS, so this
// only speeds things up; widgets still refresh on their own timeline.
//
// Secrets (Edge Functions → Secrets):
//   APNS_KEY_ID       the Key ID of your Apple push key
//   APNS_TEAM_ID      your Apple team ID
//   APNS_PRIVATE_KEY  the whole contents of the .p8 file, including the BEGIN/END lines
//   APNS_BUNDLE_ID    the app's bundle ID (com.RohaF.windowsill)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

const supabaseURL = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/** Reads rows with the service role (row-level security doesn't apply). */
async function select(path: string): Promise<any[]> {
  const response = await fetch(`${supabaseURL}/rest/v1/${path}`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
  if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
  return await response.json();
}

async function deleteToken(token: string) {
  await fetch(`${supabaseURL}/rest/v1/widget_tokens?token=eq.${token}`, {
    method: "DELETE",
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
}

// ── APNs authentication: a short-lived ES256 token signed with the .p8 key ──

function base64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let text = "";
  for (const byte of raw) text += String.fromCharCode(byte);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cached: { jwt: string; madeAt: number } | null = null;

async function apnsToken(): Promise<string> {
  // Apple accepts a token for up to an hour; make a new one every 40 minutes.
  if (cached && Date.now() - cached.madeAt < 40 * 60 * 1000) return cached.jwt;
  const pem = Deno.env.get("APNS_PRIVATE_KEY")!;
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  const header = base64url(JSON.stringify({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") }));
  const claims = base64url(JSON.stringify({
    iss: Deno.env.get("APNS_TEAM_ID"),
    iat: Math.floor(Date.now() / 1000),
  }));
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
  cached = { jwt, madeAt: Date.now() };
  return jwt;
}

/** One WidgetKit push. Returns the APNs status code. */
async function pushWidget(token: string, environment: string): Promise<number> {
  const host = environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsToken()}`,
      "apns-push-type": "widgets",
      "apns-topic": `${Deno.env.get("APNS_BUNDLE_ID")}.push-type.widgets`,
      "apns-priority": "5",
    },
    body: JSON.stringify({ aps: { "content-changed": true } }),
  });
  if (!response.ok) console.log(`push to …${token.slice(-6)}: ${response.status} ${await response.text()}`);
  return response.status;
}

Deno.serve(async (request) => {
  try {
    const payload = await request.json();
    const id = payload?.record?.id;
    if (payload?.type !== "INSERT" || payload?.table !== "petals" || !id) {
      return new Response("ignored", { status: 200 });
    }

    // Re-read the petal rather than trusting the request, and only push for new ones.
    const [petal] = await select(`petals?select=id,group_id,profile_id,created_at&id=eq.${id}`);
    if (!petal || Date.now() - Date.parse(petal.created_at) > 5 * 60 * 1000) {
      return new Response("no recent petal", { status: 200 });
    }

    const members = await select(`members?select=profile_id&group_id=eq.${petal.group_id}`);
    const friends = members.map((m) => m.profile_id).filter((p) => p !== petal.profile_id);
    if (friends.length === 0) return new Response("no friends to tell", { status: 200 });

    const tokens = await select(
      `widget_tokens?select=token,environment&profile_id=in.(${friends.join(",")})`,
    );
    const results = await Promise.all(tokens.map(async ({ token, environment }) => {
      const status = await pushWidget(token, environment);
      // 410: the token is no longer valid (widget removed or app deleted).
      if (status === 410) await deleteToken(token);
      return status;
    }));
    return new Response(JSON.stringify({ sent: results.length, statuses: results }), {
      headers: { "content-type": "application/json" },
    });
  } catch (error) {
    console.log(`widget-push failed: ${error}`);
    return new Response(String(error), { status: 500 });
  }
});
