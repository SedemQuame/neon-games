# Third-Party Service Setup Guide

This document walks through the credentials, sandbox programs, and local configuration that Glory Grid’s backend expects for each external dependency. Copy `apis/example.env` to `apis/.env` and fill in the variables referenced in each section.

---

## 1. Deriv (Trading / Game Outcomes)

### 1.1 Create a Deriv App ID
1. Sign in to [Deriv’s developer dashboard](https://developers.deriv.com/).
2. Register a new application, enabling the contract types you plan to trade (e.g., Rise/Fall, Digit Differs, Multipliers).
3. Copy the generated **App ID** and set:
   ```
   DERIV_APP_ID=<your_app_id>
   DERIV_WS_URL=wss://ws.binaryws.com/websockets/v3
   ```

### 1.2 Generate API Tokens (One per Account)
1. Log in to each Deriv account that will participate in the trader pool (add both demo and real accounts as needed).
2. Navigate to **Security → API token** and create a token with the `trade` and `read` scopes.
3. Add each token to `.env` sequentially:
   ```
   DERIV_ACCOUNT_1_TOKEN=a1-xxxxxxxxxxxxxxxx
   DERIV_ACCOUNT_2_TOKEN=a1-yyyyyyyyyyyyyyyy
   DERIV_ACCOUNT_3_TOKEN=a1-zzzzzzzzzzzzzzzz
   ```
   The trader pool automatically discovers all `DERIV_ACCOUNT_{N}_TOKEN` entries and balances requests across them.

### 1.3 Optional Overrides
| Variable | Purpose | Default |
|---|---|---|
| `DERIV_LANGUAGE` | WebSocket language header | `en` |
| `DERIV_ORIGIN` | Origin header Deriv expects | `https://gamehub.local` |
| `DERIV_SYMBOL` | Default underlying (e.g., `R_50`) | `R_50` |

Restart the services after updating `.env`:
```
./setup.sh services
```

---

## 2. Social Login (Passport.js)

The `passport-auth` Node service handles the interactive OAuth flows for Google, Facebook, and Apple, then calls the Go Auth Service to mint JWTs. Configure the provider credentials plus callback URLs in `.env` (or your secret manager) before exposing any login buttons.

### 2.1 Google OAuth
1. Create a project in the [Google Cloud Console](https://console.cloud.google.com/).
2. Under **APIs & Services → Credentials → Create Credentials → OAuth client ID**, choose **Web application**.
3. Add your frontend URL(s) to **Authorized JavaScript origins** (e.g. `https://app.gamehub.io`).
4. Add the passport gateway callback (e.g. `https://api.gamehub.io/auth/google/callback`) to **Authorized redirect URIs**.
5. Copy the generated **Client ID** and **Client Secret** into `.env`:
   ```
   GOOGLE_CLIENT_ID=...
   GOOGLE_CLIENT_SECRET=...
   GOOGLE_CALLBACK_URL=https://api.gamehub.io/auth/google/callback
   ```

### 2.2 Facebook OAuth
1. Create a Facebook App in [Meta for Developers](https://developers.facebook.com/).
2. Enable **Facebook Login → Web** and set the **Valid OAuth Redirect URI** to `https://api.gamehub.io/auth/facebook/callback` (or your ngrok URL in development).
3. Copy the **App ID** and **App Secret** into `.env`:
   ```
   FACEBOOK_CLIENT_ID=...
   FACEBOOK_CLIENT_SECRET=...
   FACEBOOK_CALLBACK_URL=https://api.gamehub.io/auth/facebook/callback
   ```

### 2.3 Apple Sign-In
1. In the [Apple Developer portal](https://developer.apple.com/account/), create a **Services ID** (e.g. `com.gamehub.passport`).
2. Create a **Sign in with Apple** key and download the `.p8` private key once.
3. Collect **Team ID**, **Key ID**, **Client ID (Services ID)**, and either:
   - Mount the `.p8` into the container and point `APPLE_PRIVATE_KEY_PATH` to it, **or**
   - Paste the PEM contents into `APPLE_AUTH_PRIVATE_KEY` (newlines as `\n`).
4. Set `APPLE_CALLBACK_URL` (e.g. `https://api.gamehub.io/auth/apple/callback`).

### 2.4 Passport Auth Gateway Settings
```
PASSPORT_AUTH_PORT=8080
PASSPORT_SESSION_SECRET=super_secret
PASSPORT_ALLOWED_ORIGINS=https://app.gamehub.io,https://staging.gamehub.io
AUTH_SERVICE_URL=http://auth-service:8001   # inside Docker network
```
Expose the `/auth/{provider}` routes via NGINX so the frontend can open `/auth/google?redirect_uri=<front-end-url>` etc. Successful logins will redirect back with `accessToken`, `refreshToken`, and a base64 user blob appended to the redirect URI.

## 3. Flutterwave (MoMo Deposits & Withdrawals)

### 2.1 Sandbox / Test Credentials
1. Create a Flutterwave account at [https://dashboard.flutterwave.com/](https://dashboard.flutterwave.com/), switch the toggle in the top-left to **Test Mode**, and ensure the header turns purple.
2. Navigate to **Settings → API** and copy:
   - **Test Public Key** (`FLWPUBK_TEST-...`)
   - **Test Secret Key** (`FLWSECK_TEST-...`)
   - **Test Encryption Key** (`FLWSECK_TEST...`)
3. Still under **Settings → Webhooks**, set a **Secret Hash** (this becomes the `verif-hash` header) and add your callback URLs (they can be ngrok URLs in development).
4. Under **Collections → Mobile Money**, enable **Ghana** and confirm MTN/Vodafone/AirtelTigo are toggled on. Production access requires KYC approval and a settlement account, but the sandbox works immediately.

### 2.2 Configure `.env`
```
FLUTTERWAVE_MODE=test
FLUTTERWAVE_BASE_URL=https://api.flutterwave.com
FLUTTERWAVE_TRANSFERS_BASE_URL=
FLUTTERWAVE_TEST_PUBLIC_KEY=FLWPUBK_TEST-709b880ad1143ac0d05f2a32e96dd1cf-X
FLUTTERWAVE_TEST_SECRET_KEY=FLWSECK_TEST-591d8156acb8e7830de8323f8d0fdfd4-X
FLUTTERWAVE_TEST_ENCRYPTION_KEY=FLWSECK_TEST11a8d3197414
FLUTTERWAVE_LIVE_PUBLIC_KEY=
FLUTTERWAVE_LIVE_SECRET_KEY=
FLUTTERWAVE_LIVE_ENCRYPTION_KEY=
FLUTTERWAVE_WEBHOOK_SECRET=<your_secret_hash>
FLUTTERWAVE_MOMO_CALLBACK_URL=https://api.gamehub.local/webhooks/payment/flutterwave
FLUTTERWAVE_TRANSFER_CALLBACK_URL=https://api.gamehub.local/webhooks/payment/flutterwave/withdrawal
MOMO_ALLOWED_CHANNELS=mtn-gh,vodafone-gh,airteltigo-gh
MOMO_DEFAULT_CURRENCY=GHS
```
Set the live values once production credentials are issued; the app auto-selects the correct set based on `FLUTTERWAVE_MODE` or `APP_ENV`.

### 2.3 Testing
1. Start the stack: `./setup.sh up`.
2. Trigger a deposit:
   ```
   curl -X POST http://127.0.0.1/api/v1/payments/momo/deposit \
     -H "Authorization: Bearer <jwt>" \
     -H "Content-Type: application/json" \
     -d '{"phone":"+233201234567","amount":5,"channel":"mtn-gh"}'
   ```
   Flutterwave returns a `tx_ref` immediately; approve the USSD prompt to complete the flow.
3. Trigger a withdrawal:
   ```
   curl -X POST http://127.0.0.1/api/v1/payments/momo/withdraw \
     -H "Authorization: Bearer <jwt>" \
     -H "Content-Type: application/json" \
     -d '{"phone":"+233201234567","amount":2,"channel":"mtn-gh"}'
   ```
4. Tail logs: `./setup.sh logs payment-gateway` and ensure `/webhooks/payment/flutterwave` (deposit) and `/webhooks/payment/flutterwave/withdrawal` fire with valid `verif-hash` headers.
5. In the Flutterwave dashboard, open **Transactions** and **Transfers** to confirm the same references appear in test mode.

---

## 4. Tatum (Crypto Deposits)

### 3.1 Obtain an API Key
1. Sign up at [https://tatum.io](https://tatum.io) and create an API key (use the **Testnet** plan for development).
2. Create a webhook signature secret inside the Tatum dashboard.

### 3.2 Configure `.env`
```
TATUM_API_KEY=<api_key>
TATUM_WEBHOOK_SECRET=<signature_secret>
TATUM_TESTNET=true
```

### 3.3 Testing
1. In Tatum, configure a webhook pointing to `https://api.gamehub.local/webhooks/payment/crypto`.
2. Use Tatum’s simulator to fire a deposit confirmation. Watch `./setup.sh logs payment-gateway` for `CryptoDepositCallback`.

---

## 5. Transactional Email (Password Reset)

Glory Grid uses [Resend](https://resend.com) for lightweight transactional emails (password reset links). Any SMTP/HTTP provider works as long as it accepts JSON requests — Resend just keeps the code path simple.

### 4.1 Generate an API Key
1. Create a Resend account and add your sending domain (or use the auto-generated sandbox domain for quick tests).
2. Create an API key from **Dashboard → API Keys** and keep it handy.

### 4.2 Configure `.env`
```
RESEND_API_KEY=rk_live_xxx_or_test_key
EMAIL_FROM="Glory Grid Support <support@glorygrid.dev>"
PASSWORD_RESET_URL=https://app.gamehub.dev/reset-password
PASSWORD_RESET_TTL_MINUTES=30
```

- `EMAIL_FROM` must match a verified address/domain inside Resend (or your provider).
- `PASSWORD_RESET_URL` is the frontend route that accepts `?token=...` and lets the user set a new password.
- TTL defaults to 30 minutes; adjust if needed.

### 4.3 Testing
1. Start the stack (`./setup.sh up`), then hit the new endpoint:
   ```
   curl -X POST http://127.0.0.1/api/v1/auth/email/forgot \
     -H "Content-Type: application/json" \
     -d '{"email":"player@example.com"}'
   ```
2. Check Resend’s dashboard (or your inbox if the domain is verified). The link follows the shape `PASSWORD_RESET_URL?token=...`.
3. To complete the flow without email, call:
   ```
   curl -X POST http://127.0.0.1/api/v1/auth/email/reset \
     -H "Content-Type: application/json" \
     -d '{"token":"<copied_token>","password":"NewSecure123!"}'
   ```
4. The Flutter login modal exposes both steps so QA can test resets entirely from the app.

If the env vars are omitted, the auth-service logs the reset link to stdout so local development still works.

---

## 6. Vault (Development Secrets)

For local development we run HashiCorp Vault in dev mode (see `docker-compose.yml`):
```
VAULT_ADDR=http://vault:8200
VAULT_TOKEN=dev-root-token
```

The dev token is fine locally; for staging/production configure an AppRole and place the credentials in the `.env` file or your secrets manager. Vault is used for:
- Future secure storage (e.g., HD wallet seeds, Deriv tokens)
- Centralized configuration once dev moves off static `.env` files

---

## 7. Other Prerequisites

| Service | Why we need it | Default |
|---|---|---|
| **MongoDB 7** | Primary data store | `MONGO_URI=mongodb://gamehub:password@mongo:27017/...` |
| **Redis 7** | Session locks, trade order queue, PubSub | `REDIS_ADDR=redis:6379` |
| **NGINX** | TLS termination + routing | Included in `docker-compose.yml` |

Use `./setup.sh infra` to bring up Mongo, Redis, Vault, and NGINX without the Go services, or `./setup.sh up` for the full stack.

---

## 8. Verification Checklist

1. **Deriv**: Run `./setup.sh logs trader-pool` and place a real bet from the Flutter app. You should see `[trace=...] contract=... outcome=...`.
2. **Passport Auth**: Hit `/auth/google` (or Facebook/Apple) in the browser with a `redirect_uri`. Ensure you land back on the frontend with tokens set, and `/api/v1/auth/social/exchange` returns a user document in the auth-service logs.
3. **Flutterwave**: Call `POST /api/v1/payments/momo/deposit` and confirm `/webhooks/payment/flutterwave` fires with the correct `verif-hash`.
4. **Tatum**: Fire a test deposit webhook and confirm `/internal/ledger/credit` entries in `wallet-service`.
5. **Vault**: `docker exec -it gamehub_vault vault status` → `Sealed false`.

If any service is missing credentials, the code logs a warning (e.g., trader-pool switches to simulation mode when no Deriv tokens are loaded).
