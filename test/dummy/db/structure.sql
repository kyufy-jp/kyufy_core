SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: kyufy_core_document_chunks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kyufy_core_document_chunks (
    id bigint NOT NULL,
    source_document_id bigint NOT NULL,
    content text NOT NULL,
    embedding public.vector(1536),
    "position" integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: kyufy_core_document_chunks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.kyufy_core_document_chunks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: kyufy_core_document_chunks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.kyufy_core_document_chunks_id_seq OWNED BY public.kyufy_core_document_chunks.id;


--
-- Name: kyufy_core_programs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kyufy_core_programs (
    id bigint NOT NULL,
    name character varying NOT NULL,
    authority character varying,
    jurisdiction character varying NOT NULL,
    prefecture_code character varying,
    municipality_code character varying,
    category character varying NOT NULL,
    target character varying,
    official_url character varying NOT NULL,
    valid_from date,
    valid_until date,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: kyufy_core_programs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.kyufy_core_programs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: kyufy_core_programs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.kyufy_core_programs_id_seq OWNED BY public.kyufy_core_programs.id;


--
-- Name: kyufy_core_requirements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kyufy_core_requirements (
    id bigint NOT NULL,
    program_id bigint NOT NULL,
    source_document_id bigint,
    kind character varying NOT NULL,
    operator character varying NOT NULL,
    value jsonb DEFAULT '{}'::jsonb NOT NULL,
    raw_text text,
    parent_id bigint,
    logic character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: kyufy_core_requirements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.kyufy_core_requirements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: kyufy_core_requirements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.kyufy_core_requirements_id_seq OWNED BY public.kyufy_core_requirements.id;


--
-- Name: kyufy_core_source_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kyufy_core_source_documents (
    id bigint NOT NULL,
    program_id bigint NOT NULL,
    title character varying NOT NULL,
    url character varying,
    fetched_at timestamp(6) without time zone,
    body text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    license character varying
);


--
-- Name: kyufy_core_source_documents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.kyufy_core_source_documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: kyufy_core_source_documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.kyufy_core_source_documents_id_seq OWNED BY public.kyufy_core_source_documents.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: kyufy_core_document_chunks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_document_chunks ALTER COLUMN id SET DEFAULT nextval('public.kyufy_core_document_chunks_id_seq'::regclass);


--
-- Name: kyufy_core_programs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_programs ALTER COLUMN id SET DEFAULT nextval('public.kyufy_core_programs_id_seq'::regclass);


--
-- Name: kyufy_core_requirements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_requirements ALTER COLUMN id SET DEFAULT nextval('public.kyufy_core_requirements_id_seq'::regclass);


--
-- Name: kyufy_core_source_documents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_source_documents ALTER COLUMN id SET DEFAULT nextval('public.kyufy_core_source_documents_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: kyufy_core_document_chunks kyufy_core_document_chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_document_chunks
    ADD CONSTRAINT kyufy_core_document_chunks_pkey PRIMARY KEY (id);


--
-- Name: kyufy_core_programs kyufy_core_programs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_programs
    ADD CONSTRAINT kyufy_core_programs_pkey PRIMARY KEY (id);


--
-- Name: kyufy_core_requirements kyufy_core_requirements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_requirements
    ADD CONSTRAINT kyufy_core_requirements_pkey PRIMARY KEY (id);


--
-- Name: kyufy_core_source_documents kyufy_core_source_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_source_documents
    ADD CONSTRAINT kyufy_core_source_documents_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: idx_kyufy_core_chunks_embedding_hnsw; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kyufy_core_chunks_embedding_hnsw ON public.kyufy_core_document_chunks USING hnsw (embedding public.vector_cosine_ops);


--
-- Name: idx_kyufy_core_programs_geo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kyufy_core_programs_geo ON public.kyufy_core_programs USING btree (jurisdiction, prefecture_code, municipality_code);


--
-- Name: index_kyufy_core_document_chunks_on_source_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_kyufy_core_document_chunks_on_source_document_id ON public.kyufy_core_document_chunks USING btree (source_document_id);


--
-- Name: index_kyufy_core_programs_on_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_kyufy_core_programs_on_category ON public.kyufy_core_programs USING btree (category);


--
-- Name: index_kyufy_core_programs_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_kyufy_core_programs_on_status ON public.kyufy_core_programs USING btree (status);


--
-- Name: index_kyufy_core_requirements_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_kyufy_core_requirements_on_parent_id ON public.kyufy_core_requirements USING btree (parent_id);


--
-- Name: index_kyufy_core_requirements_on_program_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_kyufy_core_requirements_on_program_id ON public.kyufy_core_requirements USING btree (program_id);


--
-- Name: index_kyufy_core_requirements_on_source_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_kyufy_core_requirements_on_source_document_id ON public.kyufy_core_requirements USING btree (source_document_id);


--
-- Name: index_kyufy_core_source_documents_on_program_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_kyufy_core_source_documents_on_program_id ON public.kyufy_core_source_documents USING btree (program_id);


--
-- Name: kyufy_core_source_documents fk_rails_0974af6ebd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_source_documents
    ADD CONSTRAINT fk_rails_0974af6ebd FOREIGN KEY (program_id) REFERENCES public.kyufy_core_programs(id);


--
-- Name: kyufy_core_requirements fk_rails_35b36d428a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_requirements
    ADD CONSTRAINT fk_rails_35b36d428a FOREIGN KEY (source_document_id) REFERENCES public.kyufy_core_source_documents(id);


--
-- Name: kyufy_core_document_chunks fk_rails_58f73d9455; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_document_chunks
    ADD CONSTRAINT fk_rails_58f73d9455 FOREIGN KEY (source_document_id) REFERENCES public.kyufy_core_source_documents(id);


--
-- Name: kyufy_core_requirements fk_rails_84a6ee98c5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_requirements
    ADD CONSTRAINT fk_rails_84a6ee98c5 FOREIGN KEY (parent_id) REFERENCES public.kyufy_core_requirements(id);


--
-- Name: kyufy_core_requirements fk_rails_bac5f6b3b3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyufy_core_requirements
    ADD CONSTRAINT fk_rails_bac5f6b3b3 FOREIGN KEY (program_id) REFERENCES public.kyufy_core_programs(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260720000001'),
('20260718000001');

