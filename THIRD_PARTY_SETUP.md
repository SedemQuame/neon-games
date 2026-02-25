# Third-Party Service Setup Guide

This document walks through the credentials, sandbox programs, and local configuration that GameHub’s backend expects for each external dependency. Copy `apis/example.env` to `apis/.env` and fill in the variables referenced in each section.

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

## 2. Paystack (MoMo Deposits & Withdrawals)

### 2.1 Sandbox / Test Credentials
1. Create a Paystack account at [https://dashboard.paystack.com/](https://dashboard.paystack.com/), enable **Test Mode**, and switch the toggle at the top-right so the dashboard shows a purple banner.
2. In **Settings → API Keys & Webhooks** copy:
   - **Test Secret Key** (e.g., `sk_test_xxx`)
   - **Test Public Key** (e.g., `pk_test_xxx`)
   - **Webhook signing secret** (the dashboard displays it after you add a URL)
3. Contact Paystack support (chat or email) to enable **Ghana Mobile Money** channels on the sub-account. Test mode is enabled instantly; production requires KYC + bank account.
4. Optional but recommended: create a dedicated **Subaccount** for GameHub payouts so settlements remain isolated.

### 2.2 Configure `.env`
```
PAYSTACK_SECRET_KEY=sk_test_xxx
PAYSTACK_PUBLIC_KEY=pk_test_xxx
PAYSTACK_SUBACCOUNT=ACCT_xxx             # optional; used for split settlements
PAYSTACK_BASE_URL=https://api.paystack.co
PAYSTACK_WEBHOOK_SECRET=whsec_xxx
PAYSTACK_MOMO_CALLBACK_URL=https://api.gamehub.local/webhooks/payment/paystack
PAYSTACK_WITHDRAWAL_CALLBACK_URL=https://api.gamehub.local/webhooks/payment/paystack/withdrawal
PAYSTACK_ALLOWED_CHANNELS=mtn-gh,vodafone-gh,airteltigo-gh
PAYSTACK_DEFAULT_CURRENCY=GHS
```

### 2.3 Testing
1. Start the stack: `./setup.sh up`.
2. Use curl/Postman to hit:
   ```
   curl -X POST http://127.0.0.1/api/v1/payments/momo/deposit \
     -H "Authorization: Bearer <jwt>" \
     -d '{"phone":"+233201234567","amount":5,"channel":"mtn-gh"}'
   ```
   Paystack will return a `reference` immediately and (in test mode) auto-approve after a few seconds.
3. For withdrawals, run:
   ```
   curl -X POST http://127.0.0.1/api/v1/payments/momo/withdraw \
     -H "Authorization: Bearer <jwt>" \
     -d '{"phone":"+233201234567","amount":2,"channel":"mtn-gh"}'
   ```
4. Tail logs: `./setup.sh logs payment-gateway` and ensure `/webhooks/payment/paystack` (deposit) and `/webhooks/payment/paystack/withdrawal` fire with signatures.
5. In the Paystack dashboard, visit **Transactions** (deposits) and **Transfers** (withdrawals) to confirm the same references appear in test mode.

---

## 3. Tatum (Crypto Deposits)

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

## 4. Transactional Email (Password Reset)

GameHub uses [Resend](https://resend.com) for lightweight transactional emails (password reset links). Any SMTP/HTTP provider works as long as it accepts JSON requests — Resend just keeps the code path simple.

### 4.1 Generate an API Key
1. Create a Resend account and add your sending domain (or use the auto-generated sandbox domain for quick tests).
2. Create an API key from **Dashboard → API Keys** and keep it handy.

### 4.2 Configure `.env`
```
RESEND_API_KEY=rk_live_xxx_or_test_key
EMAIL_FROM="GameHub Support <support@gamehub.dev>"
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

## 5. Vault (Development Secrets)

For local development we run HashiCorp Vault in dev mode (see `docker-compose.yml`):
```
VAULT_ADDR=http://vault:8200
VAULT_TOKEN=dev-root-token
```

The dev token is fine locally; for staging/production configure an AppRole and place the credentials in the `.env` file or your secrets manager. Vault is used for:
- Future secure storage (e.g., HD wallet seeds, Deriv tokens)
- Centralized configuration once dev moves off static `.env` files

---

## 6. Other Prerequisites

| Service | Why we need it | Default |
|---|---|---|
| **MongoDB 7** | Primary data store | `MONGO_URI=mongodb://gamehub:password@mongo:27017/...` |
| **Redis 7** | Session locks, trade order queue, PubSub | `REDIS_ADDR=redis:6379` |
| **NGINX** | TLS termination + routing | Included in `docker-compose.yml` |

Use `./setup.sh infra` to bring up Mongo, Redis, Vault, and NGINX without the Go services, or `./setup.sh up` for the full stack.

---

## 7. Verification Checklist

1. **Deriv**: Run `./setup.sh logs trader-pool` and place a real bet from the Flutter app. You should see `[trace=...] contract=... outcome=...`.
2. **Paystack**: Call `POST /api/v1/payments/momo/deposit` from the app and confirm Paystack hits `/webhooks/payment/paystack`.
3. **Tatum**: Fire a test deposit webhook and confirm `/internal/ledger/credit` entries in `wallet-service`.
4. **Vault**: `docker exec -it gamehub_vault vault status` → `Sealed false`.

If any service is missing credentials, the code logs a warning (e.g., trader-pool switches to simulation mode when no Deriv tokens are loaded).
