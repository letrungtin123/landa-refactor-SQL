-- Demo QR login configuration
-- Apply manually in Supabase SQL editor / psql. Do not run from Codex.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.tenant_demo_login_settings (
  tenant_id uuid PRIMARY KEY REFERENCES public.tenants(id) ON DELETE CASCADE,
  is_enabled boolean NOT NULL DEFAULT false,
  max_demo_accounts integer NOT NULL DEFAULT 3,
  reservation_ttl_seconds integer NOT NULL DEFAULT 300,
  updated_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tenant_demo_login_settings_max_accounts_chk
    CHECK (max_demo_accounts BETWEEN 1 AND 50),
  CONSTRAINT tenant_demo_login_settings_ttl_chk
    CHECK (reservation_ttl_seconds BETWEEN 60 AND 3600)
);

CREATE TABLE IF NOT EXISTS public.tenant_demo_login_accounts (
  public_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  label varchar(120),
  sort_order integer NOT NULL DEFAULT 0,
  reserved_until timestamptz,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tenant_demo_login_accounts_unique_user
    UNIQUE (tenant_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_demo_login_accounts_tenant_order
  ON public.tenant_demo_login_accounts (tenant_id, sort_order, created_at);

CREATE INDEX IF NOT EXISTS idx_demo_login_accounts_user
  ON public.tenant_demo_login_accounts (user_id);

CREATE INDEX IF NOT EXISTS idx_demo_login_accounts_reserved_until
  ON public.tenant_demo_login_accounts (tenant_id, reserved_until);

ALTER TABLE public.tenant_demo_login_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_demo_login_accounts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.set_demo_login_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_demo_login_settings_updated_at ON public.tenant_demo_login_settings;
CREATE TRIGGER trg_demo_login_settings_updated_at
BEFORE UPDATE ON public.tenant_demo_login_settings
FOR EACH ROW
EXECUTE FUNCTION public.set_demo_login_updated_at();

DROP TRIGGER IF EXISTS trg_demo_login_accounts_updated_at ON public.tenant_demo_login_accounts;
CREATE TRIGGER trg_demo_login_accounts_updated_at
BEFORE UPDATE ON public.tenant_demo_login_accounts
FOR EACH ROW
EXECUTE FUNCTION public.set_demo_login_updated_at();

CREATE OR REPLACE FUNCTION public.enforce_demo_login_learner_account()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  demo_user record;
  max_accounts integer;
  current_count integer;
BEGIN
  SELECT id, tenant_id, role, is_active
  INTO demo_user
  FROM public.users
  WHERE id = NEW.user_id;

  IF demo_user.id IS NULL THEN
    RAISE EXCEPTION 'Demo user does not exist';
  END IF;

  IF demo_user.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
    RAISE EXCEPTION 'Demo user must belong to the selected tenant';
  END IF;

  IF demo_user.role <> 'learner'::public.user_role OR demo_user.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Demo user must be an active learner';
  END IF;

  SELECT COALESCE(max_demo_accounts, 3)
  INTO max_accounts
  FROM public.tenant_demo_login_settings
  WHERE tenant_id = NEW.tenant_id;

  max_accounts := COALESCE(max_accounts, 3);

  SELECT COUNT(*)
  INTO current_count
  FROM public.tenant_demo_login_accounts
  WHERE tenant_id = NEW.tenant_id
    AND public_id IS DISTINCT FROM NEW.public_id;

  IF current_count >= max_accounts THEN
    RAISE EXCEPTION 'Demo account limit exceeded for tenant';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_demo_login_accounts_enforce_learner ON public.tenant_demo_login_accounts;
CREATE TRIGGER trg_demo_login_accounts_enforce_learner
BEFORE INSERT OR UPDATE OF tenant_id, user_id ON public.tenant_demo_login_accounts
FOR EACH ROW
EXECUTE FUNCTION public.enforce_demo_login_learner_account();

CREATE OR REPLACE FUNCTION public.cleanup_demo_login_account_on_user_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM public.tenant_demo_login_accounts
  WHERE user_id = NEW.id
    AND (
      NEW.role <> 'learner'::public.user_role
      OR NEW.is_active IS NOT TRUE
      OR tenant_id IS DISTINCT FROM NEW.tenant_id
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cleanup_demo_login_account_on_user_change ON public.users;
CREATE TRIGGER trg_cleanup_demo_login_account_on_user_change
AFTER UPDATE OF role, is_active, tenant_id ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.cleanup_demo_login_account_on_user_change();
