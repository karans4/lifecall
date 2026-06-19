-- Add a conversation summary and structured fact-find payload to leads.
ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS summary text;
ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS fact_find jsonb;
