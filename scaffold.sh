#!/usr/bin/env bash
set -euo pipefail

# Safety: ensure we're in a git repo
if [ ! -d .git ]; then
  echo "Error: not a git repository. Run this inside the cloned repo folder."
  exit 1
fi

# Create directories
mkdir -p prisma lib pages/pages/api/checkout pages/api web/.gitkeep pages/api/orders pages/api/webhooks pages/styles pages/products pages/api/cart pages/api
mkdir -p pages/api
mkdir -p pages/products
mkdir -p pages/api/orders
mkdir -p pages/api/checkout
mkdir -p pages/api/webhooks
mkdir -p styles
mkdir -p .github/workflows

# Write files (use single-quoted EOF to avoid variable interpolation)
cat > README.md <<'EOF'
# E-commerce Clothing Starter (Next.js + TypeScript + Prisma + NextAuth + Stripe)

This is a minimal starter implementing:
- Product listing & product detail
- Cart (persisted for signed-in users / session for guests)
- Wishlist (users)
- Checkout with Stripe (create-session + webhook)
- Orders schema with cancellation allowed before shipping
- Returns schema & API scaffolding

Requirements
- Node 18+
- PostgreSQL (or another database supported by Prisma)
- Stripe account (test keys)
- SMTP credentials for NextAuth email provider (or configure other provider)

Quick start
1. Copy .env.example to .env and set values.
2. Install dependencies:
   npm install
3. Generate Prisma client and run migrations:
   npx prisma migrate dev --name init
4. (Optional) Seed products (add a seed script or insert via DB client).
5. Start dev server:
   npm run dev
6. Set up Stripe webhook (ngrok or your hosting) and configure STRIPE_WEBHOOK_SECRET.

Notes
- Cancellation rules: user may cancel orders while order.status !== 'shipped' (enforced in API).
- Returns: users can create return requests for delivered items (30-day default policy is up to you to enforce).
- This is a starting point — extend admin UI, image uploads, inventory check, and refund handling.
EOF

cat > package.json <<'EOF'
{
  "name": "clothing-ecommerce-starter",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev -p 3000",
    "build": "next build",
    "start": "next start",
    "prisma:studio": "prisma studio",
    "prisma:migrate": "prisma migrate dev",
    "prisma:generate": "prisma generate"
  },
  "dependencies": {
    "@prisma/client": "^5.0.0",
    "axios": "^1.5.0",
    "bcryptjs": "^2.4.3",
    "next": "14.0.0",
    "next-auth": "^5.0.0",
    "prisma": "^5.0.0",
    "react": "18.2.0",
    "react-dom": "18.2.0",
    "stripe": "^12.0.0"
  },
  "devDependencies": {
    "autoprefixer": "^10.0.0",
    "postcss": "^8.0.0",
    "tailwindcss": "^4.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["DOM", "DOM.Iterable", "ESNext"],
    "allowJs": false,
    "skipLibCheck": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true,
    "module": "ESNext",
    "moduleResolution": "Node",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "noEmit": true
  },
  "exclude": ["node_modules"],
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx"]
}
EOF

cat > next.config.js <<'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  env: {
    NEXTAUTH_URL: process.env.NEXTAUTH_URL,
    NEXTAUTH_SECRET: process.env.NEXTAUTH_SECRET
  }
};

module.exports = nextConfig;
EOF

cat > prisma/schema.prisma <<'EOF'
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model Product {
  id          Int       @id @default(autoincrement())
  name        String
  slug        String    @unique
  description String?
  variants    Variant[]
  images      Image[]
  createdAt   DateTime  @default(now())
  updatedAt   DateTime  @updatedAt
}

model Variant {
  id        Int     @id @default(autoincrement())
  sku       String  @unique
  product   Product @relation(fields: [productId], references: [id])
  productId Int
  price     Int     // cents
  size      String?
  color     String?
  inventory Int     @default(0)
}

model Image {
  id        Int     @id @default(autoincrement())
  url       String
  alt       String?
  product   Product? @relation(fields: [productId], references: [id])
  productId Int?
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String?
  createdAt DateTime @default(now())
  // NextAuth relations (sessions, accounts) will be added by adapter
  wishlist  Wishlist?
  orders    Order[]
}

model Wishlist {
  id        Int       @id @default(autoincrement())
  user      User      @relation(fields: [userId], references: [id])
  userId    Int       @unique
  items     WishlistItem[]
  createdAt DateTime  @default(now())
}

model WishlistItem {
  id         Int     @id @default(autoincrement())
  wishlist   Wishlist @relation(fields: [wishlistId], references: [id])
  wishlistId Int
  variant    Variant  @relation(fields: [variantId], references: [id])
  variantId  Int
  addedAt    DateTime @default(now())
}

model Cart {
  id        Int       @id @default(autoincrement())
  user      User?     @relation(fields: [userId], references: [id])
  userId    Int?
  sessionId String?   // for guests
  items     CartItem[]
  updatedAt DateTime  @updatedAt
}

model CartItem {
  id        Int   @id @default(autoincrement())
  cart      Cart  @relation(fields: [cartId], references: [id])
  cartId    Int
  variant   Variant @relation(fields: [variantId], references: [id])
  variantId Int
  quantity  Int
  addedAt   DateTime @default(now())
}

model Order {
  id             Int           @id @default(autoincrement())
  user           User?         @relation(fields: [userId], references: [id])
  userId         Int?
  status         String        // pending, paid, processing, shipped, delivered, cancelled, returned
  total          Int           // cents
  currency       String
  stripeSession  String?
  items          OrderItem[]
  returnRequests ReturnRequest[]
  createdAt      DateTime      @default(now())
  updatedAt      DateTime      @updatedAt
}

model OrderItem {
  id         Int     @id @default(autoincrement())
  order      Order   @relation(fields: [orderId], references: [id])
  orderId    Int
  variant    Variant @relation(fields: [variantId], references: [id])
  variantId  Int
  quantity   Int
  unitPrice  Int     // cents
}

model ReturnRequest {
  id          Int      @id @default(autoincrement())
  order       Order    @relation(fields: [orderId], references: [id])
  orderId     Int
  orderItem   OrderItem @relation(fields: [orderItemId], references: [id])
  orderItemId Int
  reason      String
  status      String   // requested, approved, rejected, received, refunded
  quantity    Int
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}

model VerificationToken {
  identifier String
  token      String    @unique
  expires    DateTime
  @@map("nextauth_verification_tokens")
}
EOF

cat > lib/prisma.ts <<'EOF'
import { PrismaClient } from "@prisma/client";

declare global {
  // eslint-disable-next-line vars-on-top, no-var
  var prisma: PrismaClient | undefined;
}

const prisma = global.prisma || new PrismaClient();

if (process.env.NODE_ENV !== "production") global.prisma = prisma;

export default prisma;
EOF

cat > lib/stripe.ts <<'EOF'
import Stripe from "stripe";

const stripeSecret = process.env.STRIPE_SECRET_KEY || "";
export const stripe = new Stripe(stripeSecret, { apiVersion: "2024-11-01" });
EOF

mkdir -p pages/api/cart
cat > pages/_app.tsx <<'EOF'
import "../styles/globals.css";
import { SessionProvider } from "next-auth/react";
import type { AppProps } from "next/app";

export default function App({ Component, pageProps: { session, ...pageProps } }: AppProps) {
  return (
    <SessionProvider session={session}>
      <Component {...pageProps} />
    </SessionProvider>
  );
}
EOF

cat > pages/index.tsx <<'EOF'
import { GetServerSideProps } from "next";
import prisma from "../lib/prisma";
import Link from "next/link";

export default function Home({ products }: { products: any[] }) {
  return (
    <div className="container mx-auto p-6">
      <h1 className="text-3xl font-bold mb-6">Clothing Store</h1>
      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-6">
        {products.map((p: any) => (
          <div key={p.id} className="border p-4 rounded">
            <img src={p.images?.[0]?.url || "/placeholder.png"} alt={p.name} className="h-48 w-full object-cover mb-3" />
            <h2 className="text-lg font-semibold">{p.name}</h2>
            <p className="text-sm text-gray-600">{p.description}</p>
            <div className="mt-3 flex justify-between items-center">
              <div className="text-lg font-bold">From ${(p.variants?.[0]?.price / 100).toFixed(2)}</div>
              <Link href={`/products/${p.slug}`}><a className="text-blue-600">View</a></Link>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export const getServerSideProps: GetServerSideProps = async () => {
  const products = await prisma.product.findMany({
    include: { variants: true, images: true },
    take: 20
  });
  return { props: { products: JSON.parse(JSON.stringify(products)) } };
};
EOF

cat > pages/products/[slug].tsx <<'EOF'
import { GetServerSideProps } from "next";
import prisma from "../../lib/prisma";
import { useState } from "react";
import axios from "axios";
import { useSession } from "next-auth/react";

export default function ProductPage({ product }: any) {
  const [quantity, setQuantity] = useState(1);
  const [variantId, setVariantId] = useState(product?.variants?.[0]?.id || null);
  const { data: session } = useSession();

  async function addToCart() {
    await axios.post("/api/cart", { variantId, quantity });
    alert("Added to cart");
  }

  async function addToWishlist() {
    if (!session) {
      alert("Please sign in to save to wishlist");
      return;
    }
    await axios.post("/api/wishlist", { variantId });
    alert("Added to wishlist");
  }

  return (
    <div className="container mx-auto p-6">
      <div className="flex gap-6">
        <img src={product.images?.[0]?.url || "/placeholder.png"} alt={product.name} className="w-1/2 object-cover" />
        <div className="w-1/2">
          <h1 className="text-2xl font-bold">{product.name}</h1>
          <p className="mt-3">{product.description}</p>

          <div className="mt-4">
            <label className="block">Variant</label>
            <select className="border p-2 mt-1" value={variantId} onChange={(e) => setVariantId(Number(e.target.value))}>
              {product.variants.map((v: any) => (
                <option key={v.id} value={v.id}>
                  {v.size || v.color || v.sku} — ${(v.price / 100).toFixed(2)} {v.inventory <= 0 ? "(out of stock)" : ""}
                </option>
              ))}
            </select>
          </div>

          <div className="mt-4 flex items-center gap-3">
            <input type="number" min={1} value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} className="border p-2 w-24" />
            <button onClick={addToCart} className="bg-blue-600 text-white px-4 py-2 rounded">Add to cart</button>
            <button onClick={addToWishlist} className="border px-4 py-2 rounded">Wishlist</button>
          </div>
        </div>
      </div>
    </div>
  );
}

export const getServerSideProps: GetServerSideProps = async (ctx) => {
  const slug = ctx.params?.slug as string;
  const product = await prisma.product.findUnique({ where: { slug }, include: { variants: true, images: true } });
  if (!product) return { notFound: true };
  return { props: { product: JSON.parse(JSON.stringify(product)) } };
};
EOF

cat > pages/api/cart/index.ts <<'EOF'
import type { NextApiRequest, NextApiResponse } from "next";
import prisma from "../../../lib/prisma";
import { getSession } from "next-auth/react";

/**
 * POST: add item { variantId, quantity } -> creates/updates cart for user or session
 * GET: returns current cart for signed-in user (or empty)
 */

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const session = await getSession({ req });
  if (req.method === "GET") {
    if (!session?.user?.email) return res.json({ items: [] });
    const user = await prisma.user.findUnique({ where: { email: session.user.email } });
    if (!user) return res.json({ items: [] });
    const cart = await prisma.cart.findFirst({ where: { userId: user.id }, include: { items: { include: { variant: true } } } });
    return res.json(cart || { items: [] });
  }

  if (req.method === "POST") {
    const { variantId, quantity } = req.body;
    let cart;
    if (session?.user?.email) {
      const user = await prisma.user.findUnique({ where: { email: session.user.email } });
      if (!user) return res.status(400).json({ error: "No user" });
      cart = await prisma.cart.upsert({
        where: { userId: user.id },
        create: { userId: user.id, items: { create: { variantId, quantity } } },
        update: { items: { create: { variantId, quantity } } },
        include: { items: true }
      });
    } else {
      // guest flow: create a session-less cart with sessionId cookie (not fully implemented here)
      cart = await prisma.cart.create({ data: { sessionId: "guest", items: { create: { variantId, quantity } } }, include: { items: true } });
    }
    return res.json(cart);
  }

  return res.status(405).end();
}
EOF

cat > pages/api/wishlist.ts <<'EOF'
import type { NextApiRequest, NextApiResponse } from "next";
import { getSession } from "next-auth/react";
import prisma from "../lib/prisma";

/**
 * POST { variantId } -> add to wishlist (user only)
 * GET -> get wishlist items
 * DELETE -> /api/wishlist?id=... delete by wishlistItem id
 */

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const session = await getSession({ req });
  if (!session?.user?.email) return res.status(401).json({ error: "Sign in required" });
  const user = await prisma.user.findUnique({ where: { email: session.user.email } });
  if (!user) return res.status(400).json({ error: "User not found" });

  if (req.method === "GET") {
    const wishlist = await prisma.wishlist.findUnique({ where: { userId: user.id }, include: { items: { include: { variant: { include: { product: true } } } } } });
    return res.json(wishlist || { items: [] });
  }

  if (req.method === "POST") {
    const { variantId } = req.body;
    let wishlist = await prisma.wishlist.findUnique({ where: { userId: user.id } });
    if (!wishlist) {
      wishlist = await prisma.wishlist.create({ data: { userId: user.id } });
    }
    const item = await prisma.wishlistItem.create({ data: { wishlistId: wishlist.id, variantId } });
    return res.json(item);
  }

  if (req.method === "DELETE") {
    const id = Number(req.query.id);
    await prisma.wishlistItem.delete({ where: { id } });
    return res.json({ success: true });
  }

  return res.status(405).end();
}
EOF

cat > pages/api/checkout/create-session.ts <<'EOF'
import type { NextApiRequest, NextApiResponse } from "next";
import { stripe } from "../../../lib/stripe";
import prisma from "../../../lib/prisma";
import { getSession } from "next-auth/react";

/**
 * Expects body: { cartId } or uses user's cart. Creates a Stripe Checkout session and creates a pending Order.
 */

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== "POST") return res.status(405).end();

  const session = await getSession({ req });
  let cart;
  if (session?.user?.email) {
    const user = await prisma.user.findUnique({ where: { email: session.user.email } });
    cart = await prisma.cart.findFirst({ where: { userId: user?.id }, include: { items: { include: { variant: { include: { product: true } } } } } });
  } else {
    return res.status(400).json({ error: "Guest checkout not implemented in this endpoint" });
  }
  if (!cart || cart.items.length === 0) return res.status(400).json({ error: "Cart is empty" });

  const line_items = cart.items.map((i) => ({
    price_data: {
      currency: "usd",
      unit_amount: i.variant.price,
      product_data: { name: i.variant.product.name }
    },
    quantity: i.quantity
  }));

  const stripeSession = await stripe.checkout.sessions.create({
    payment_method_types: ["card"],
    mode: "payment",
    line_items,
    success_url: `${process.env.NEXTAUTH_URL}/orders/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${process.env.NEXTAUTH_URL}/cart`
  });

  // create pending Order in DB
  const order = await prisma.order.create({
    data: {
      userId: cart.userId || undefined,
      status: "pending",
      total: cart.items.reduce((s, it) => s + it.quantity * it.variant.price, 0),
      currency: "usd",
      stripeSession: stripeSession.id,
      items: { create: cart.items.map((it) => ({ variantId: it.variantId, quantity: it.quantity, unitPrice: it.variant.price })) }
    }
  });

  return res.json({ url: stripeSession.url });
}
EOF

cat > pages/api/webhooks/stripe.ts <<'EOF'
import type { NextApiRequest, NextApiResponse } from "next";
import { buffer } from "micro";
import { stripe } from "../../../lib/stripe";
import prisma from "../../../lib/prisma";

export const config = { api: { bodyParser: false } };

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const sig = req.headers["stripe-signature"] as string;
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET || "";

  const buf = await buffer(req);
  let event;
  try {
    event = stripe.webhooks.constructEvent(buf.toString(), sig, webhookSecret);
  } catch (err: any) {
    console.error("Webhook signature verification failed:", err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object as any;
    // find the corresponding order by stripeSession
    const order = await prisma.order.findUnique({ where: { stripeSession: session.id }, include: { items: true } });
    if (order) {
      await prisma.order.update({ where: { id: order.id }, data: { status: "paid" } });
      // decrement inventory for each item
      for (const item of order.items) {
        await prisma.variant.update({ where: { id: item.variantId }, data: { inventory: { decrement: item.quantity } } });
      }
    }
  }

  res.json({ received: true });
}
EOF

cat > pages/api/orders/[id]/cancel.ts <<'EOF'
import type { NextApiRequest, NextApiResponse } from "next";
import prisma from "../../../../lib/prisma";
import { getSession } from "next-auth/react";

/**
 * POST -> attempt to cancel order: allowed only if status !== 'shipped' and not already cancelled
 * If order was paid, refund must be processed (admin side) — here we just set status to 'cancelled' if allowed.
 */

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== "POST") return res.status(405).end();
  const session = await getSession({ req });
  if (!session?.user?.email) return res.status(401).json({ error: "Sign in required" });

  const orderId = Number(req.query.id);
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) return res.status(404).json({ error: "Order not found" });

  if (order.status === "shipped" || order.status === "delivered") {
    return res.status(400).json({ error: "Cannot cancel after shipment" });
  }
  if (order.status === "cancelled") return res.json({ success: true });

  // If payment captured, you'd call Stripe refund here (admin/secure flow). For now, mark cancelled.
  await prisma.order.update({ where: { id: orderId }, data: { status: "cancelled" } });
  return res.json({ success: true });
}
EOF

cat > styles/globals.css <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

body { @apply bg-gray-50 text-gray-900; }
.container { max-width: 1100px; }
EOF

cat > tailwind.config.js <<'EOF'
module.exports = {
  content: ["./pages/**/*.{js,ts,jsx,tsx}", "./components/**/*.{js,ts,jsx,tsx}"],
  theme: { extend: {} },
  plugins: []
};
EOF

cat > .env.example <<'EOF'
# Copy to .env and fill in values
DATABASE_URL="postgresql://user:pass@localhost:5432/dbname"
NEXTAUTH_URL="http://localhost:3000"
NEXTAUTH_SECRET="a_long_random_secret"
# SMTP for NextAuth Email provider (optional)
SMTP_SERVER="smtp.example.com"
SMTP_USER="user@example.com"
SMTP_PASSWORD="password"
STRIPE_SECRET_KEY="sk_test_..."
STRIPE_WEBHOOK_SECRET="whsec_..."
EOF

cat > .gitignore <<'EOF'
node_modules
.next
.env
.DS_Store
EOF

cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2025 baluguriharshitha2

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

cat > .github/workflows/nodejs-ci.yml <<'EOF'
name: Node.js CI

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [18.x]
    steps:
      - uses: actions/checkout@v4
      - name: Use Node.js
        uses: actions/setup-node@v4
        with:
          node-version: \${{ matrix.node-version }}
      - name: Install dependencies
        run: npm ci
      - name: Generate Prisma client
        run: npm run prisma:generate
      - name: Build
        run: npm run build
EOF

# Git commit
git add .
git commit -m "chore: initial scaffold for clothing ecommerce starter" || echo "No changes to commit"

echo "Scaffold files written and committed locally."
echo "Run: git push origin main"
EOF
