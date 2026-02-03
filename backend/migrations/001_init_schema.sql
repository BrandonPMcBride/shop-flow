-- 001_init_schema.sql
-- Postgres schema for products, carts, cart_items, orders, order_items

BEGIN;

-- =========================
-- UUID generation
-- =========================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =========================
-- Generic updated_at trigger
-- =========================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =========================
-- products
-- =========================
CREATE TABLE IF NOT EXISTS products (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name           text NOT NULL,
  description    text,
  price_cents    integer NOT NULL CHECK (price_cents >= 0),
  inventory_qty  integer NOT NULL CHECK (inventory_qty >= 0),
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_products_updated_at
BEFORE UPDATE ON products
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_products_is_active ON products (is_active);
CREATE INDEX IF NOT EXISTS idx_products_name ON products (name);

-- =========================
-- carts
-- =========================
CREATE TABLE IF NOT EXISTS carts (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NULL,
  session_id text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Enforce: a cart belongs to either a user OR a guest session
  CONSTRAINT carts_owner_check
    CHECK ( (user_id IS NOT NULL) <> (session_id IS NOT NULL) ),

  -- Avoid empty / whitespace session ids
  CONSTRAINT carts_session_nonempty
    CHECK (session_id IS NULL OR length(btrim(session_id)) > 0)
);

CREATE TRIGGER trg_carts_updated_at
BEFORE UPDATE ON carts
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- One cart per user
CREATE UNIQUE INDEX IF NOT EXISTS uq_carts_user_id
ON carts (user_id)
WHERE user_id IS NOT NULL;

-- One cart per session
CREATE UNIQUE INDEX IF NOT EXISTS uq_carts_session_id
ON carts (session_id)
WHERE session_id IS NOT NULL;

-- =========================
-- cart_items
-- =========================
CREATE TABLE IF NOT EXISTS cart_items (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_id    uuid NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  quantity   integer NOT NULL CHECK (quantity > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Prevent duplicate products per cart
  CONSTRAINT uq_cart_items_cart_product UNIQUE (cart_id, product_id)
);

CREATE TRIGGER trg_cart_items_updated_at
BEFORE UPDATE ON cart_items
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_cart_items_cart_id ON cart_items (cart_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_product_id ON cart_items (product_id);

-- =========================
-- orders
-- =========================
CREATE TABLE IF NOT EXISTS orders (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NULL,
  session_id     text NULL,

  -- status: pending, paid, cancelled
  status         text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'paid', 'cancelled')),

  -- Totals stored server-side
  subtotal_cents integer NOT NULL CHECK (subtotal_cents >= 0),
  total_cents    integer NOT NULL CHECK (total_cents >= 0),

  -- Email REQUIRED for all orders
  email          text NOT NULL CHECK (length(btrim(email)) > 0),

  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),

  -- Must be user OR guest session (not both)
  CONSTRAINT orders_owner_check
    CHECK ( (user_id IS NOT NULL) <> (session_id IS NOT NULL) )
);

CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_session_id ON orders (session_id);

-- =========================
-- order_items
-- =========================
CREATE TABLE IF NOT EXISTS order_items (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id         uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id       uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  quantity         integer NOT NULL CHECK (quantity > 0),

  -- Price snapshot at purchase time
  unit_price_cents integer NOT NULL CHECK (unit_price_cents >= 0),

  -- Stored line total
  line_total_cents integer NOT NULL CHECK (line_total_cents >= 0),

  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),

  -- Prevent duplicate product rows per order
  CONSTRAINT uq_order_items_order_product UNIQUE (order_id, product_id),

  -- Ensure line_total is correct
  CONSTRAINT order_items_line_total_check
    CHECK (line_total_cents = unit_price_cents * quantity)
);

CREATE TRIGGER trg_order_items_updated_at
BEFORE UPDATE ON order_items
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items (product_id);

COMMIT;
