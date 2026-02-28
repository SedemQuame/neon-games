#!/bin/bash
# Seed crypto master wallet configs via the internal API
# Run this AFTER docker-compose up

GATEWAY_URL="${1:-http://localhost:8003}"
INTERNAL_KEY="${2:-dev-internal-key}"

echo "============================================="
echo "  Seeding Crypto Master Wallets"
echo "  Gateway: ${GATEWAY_URL}"
echo "============================================="
echo ""

# --- BTC ---
echo "🔸 Saving BTC wallet config..."
curl -s -X POST "${GATEWAY_URL}/internal/crypto/wallets/config" \
  -H "Content-Type: application/json" \
  -H "X-Internal-Key: ${INTERNAL_KEY}" \
  -d '{
    "coin": "BTC",
    "xpub": "xpub6EfV4zXYDz9fEJ28Km41n58LexPfe82Xcj9ga7A9QN1wi5EhsvdURJzrHrRdRbjBKgcppkR4RyXcbiXcc4tfYRWcQe6X26AHRdRW6SN2FZF",
    "mnemonic": "unaware fatigue title kidney one learn jeans guilt arrive chapter install license pottery permit install famous taxi gallery envelope fresh display outdoor eight shoulder",
    "network": "BTC"
  }' | python3 -m json.tool 2>/dev/null || echo "(raw response above)"
echo ""

# --- ETH ---
echo "🔸 Saving ETH wallet config..."
curl -s -X POST "${GATEWAY_URL}/internal/crypto/wallets/config" \
  -H "Content-Type: application/json" \
  -H "X-Internal-Key: ${INTERNAL_KEY}" \
  -d '{
    "coin": "ETH",
    "xpub": "xpub6F3Jn7aYGBRFpraJ6B9dSRUDBaqXkXEXGH7uJ2rLnYoLot25Q6h8z7gpcTnHtiJx3wtTFMastXou5nKXgyPRhj73jKnnudoAn6cT6v8w468",
    "mnemonic": "alarm century brother leader spy ketchup abuse true lobster act festival aunt guide never crop hunt volume robust boy among worth host comic toy",
    "network": "ERC20"
  }' | python3 -m json.tool 2>/dev/null || echo "(raw response above)"
echo ""

# --- USDT (TRON/TRC20) ---
echo "🔸 Saving USDT wallet config..."
curl -s -X POST "${GATEWAY_URL}/internal/crypto/wallets/config" \
  -H "Content-Type: application/json" \
  -H "X-Internal-Key: ${INTERNAL_KEY}" \
  -d '{
    "coin": "USDT",
    "xpub": "xpub6FAV7LZnBUB9oUs4FU27AKfkZdUeCh5yZLHY45mxAjyFoAk1us2hBwdBDB4rQEVq1CRFqe3XaY9PUJniAGBas5XZN23in3YwLiZdqdE9tRq",
    "mnemonic": "village attend leader across direct artwork rival near remember edge basic buzz surge fan hint silver vapor rebel identify harvest object best used deny",
    "network": "TRC20"
  }' | python3 -m json.tool 2>/dev/null || echo "(raw response above)"
echo ""

echo "============================================="
echo "  ✅ Done! Verifying stored configs..."
echo "============================================="
echo ""

curl -s -X GET "${GATEWAY_URL}/internal/crypto/wallets/config" \
  -H "X-Internal-Key: ${INTERNAL_KEY}" | python3 -m json.tool 2>/dev/null || echo "(raw response above)"
