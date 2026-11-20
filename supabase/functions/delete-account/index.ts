// Windowsill: delete-account
//
// Called by the app (signed in) from settings → account & privacy → delete account.
// 1. Works out who is asking from their access token.
// 2. Cancels the app's Sign in with Apple link for them, using the authorization code
//    the app just got from Apple (Apple requires this when an account is deleted).
// 3. Deletes their auth user. Their profile, memberships, petals and widget tokens go
//    with it (the tables cascade), then any windowsill left with nobody on it.
//
// Secrets (Edge Functions → Secrets), for step 2:
//   APPLE_SIWA_KEY_ID       Key ID of an Apple key with "Sign in with Apple" enabled
//   APPLE_SIWA_PRIVATE_KEY  the whole .p8 file for that key, BEGIN/END lines included
//   APNS_TEAM_ID, APNS_BUNDLE_ID (already set for widget-push) are reused as the
//   team ID and client ID.
// Without the two APPLE_SIWA_* secrets the account is still deleted; only step 2 is skipped.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

const supabaseURL = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };

function base64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let text = "";
  for (const byte of raw) text += String.fromCharCode(byte);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Apple's client secret: a short-lived ES256 JWT signed with the Sign in with Apple key. */
async function appleClientSecret(keyID: string, pem: string, teamID: string, clientID: string) {
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyID }));
  const claims = base64url(JSON.stringify({
    iss: teamID, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: clientID,
  }));
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
}

/** Trades the authorization code for a refresh token, then revokes it. */
async function revokeApple(code: string) {
  const keyID = Deno.env.get("APPLE_SIWA_KEY_ID");
  const pem = Deno.env.get("APPLE_SIWA_PRIVATE_KEY");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const clientID = Deno.env.get("APNS_BUNDLE_ID");
  if (!keyID || !pem || !teamID || !clientID) {
    console.log("Sign in with Apple secrets not set; skipping revoke");
    return;
  }
  const secret = await appleClientSecret(keyID, pem, teamID, clientID);
  const form = (fields: Record<string, string>) => ({
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: clientID, client_secret: secret, ...fields }),
  });
  const tokenResponse = await fetch("https://appleid.apple.com/auth/token",
    form({ grant_type: "authorization_code", code }));
  const token = await tokenResponse.json();
  if (!tokenResponse.ok || !token.refresh_token) {
    console.log(`apple token exchange failed: ${tokenResponse.status} ${JSON.stringify(token)}`);
    return;
  }
  const revoke = await fetch("https://appleid.apple.com/auth/revoke",
    form({ token: token.refresh_token, token_type_hint: "refresh_token" }));
  if (!revoke.ok) console.log(`apple revoke failed: ${revoke.status} ${await revoke.text()}`);
}

Deno.serve(async (request) => {
  try {
    if (request.method !== "POST") return new Response("POST only", { status: 405 });

    // Who's asking: the signed-in user behind this access token.
    const userResponse = await fetch(`${supabaseURL}/auth/v1/user`, {
      headers: { apikey: serviceKey, Authorization: request.headers.get("Authorization") ?? "" },
    });
    if (!userResponse.ok) return new Response("not signed in", { status: 401 });
    const user = await userResponse.json();
    if (!user?.id) return new Response("not signed in", { status: 401 });

    const body = await request.json().catch(() => ({}));
    if (typeof body?.authorization_code === "string" && body.authorization_code) {
      await revokeApple(body.authorization_code);
    }

    // The windowsills they're on, so the empty ones can be tidied up afterwards.
    const memberships = await fetch(
      `${supabaseURL}/rest/v1/members?select=group_id&profile_id=eq.${user.id}`, { headers: admin },
    ).then((r) => r.json());

    const deleted = await fetch(`${supabaseURL}/auth/v1/admin/users/${user.id}`, {
      method: "DELETE", headers: admin,
    });
    if (!deleted.ok) {
      console.log(`delete user failed: ${deleted.status} ${await deleted.text()}`);
      return new Response("could not delete", { status: 500 });
    }

    for (const { group_id } of Array.isArray(memberships) ? memberships : []) {
      const left = await fetch(
        `${supabaseURL}/rest/v1/members?select=profile_id&group_id=eq.${group_id}&limit=1`, { headers: admin },
      ).then((r) => r.json());
      if (Array.isArray(left) && left.length === 0) {
        await fetch(`${supabaseURL}/rest/v1/groups?id=eq.${group_id}`, { method: "DELETE", headers: admin });
      }
    }
    return new Response(JSON.stringify({ deleted: true }), { headers: { "content-type": "application/json" } });
  } catch (error) {
    console.log(`delete-account failed: ${error}`);
    return new Response(String(error), { status: 500 });
  }
});
