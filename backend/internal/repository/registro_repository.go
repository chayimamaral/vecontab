package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type RegistroUpdateInput struct {
	CNPJ        string
	CEP         string
	Endereco    string
	Bairro      string
	Cidade      string
	Estado      string
	Telefone    string
	Email       string
	IE          string
	IM          string
	RazaoSocial string
	Fantasia    string
	Observacoes string
}

type RegistroCreateInput struct {
	Nome     string
	Email    string
	Password string
}

type RegistroRepository struct {
	pool *pgxpool.Pool
}

func NewRegistroRepository(pool *pgxpool.Pool) *RegistroRepository {
	return &RegistroRepository{pool: pool}
}

func nullStringPtr(ns sql.NullString) *string {
	if !ns.Valid {
		return nil
	}
	s := ns.String
	return &s
}

func scanDadosComplementares(
	tenantid string,
	scan func(dest ...any) error,
) (domain.DadosComplementaresRecord, error) {
	var cnpj, cep, endereco, bairro, cidade, estado, telefone, email, ie, im, razaosocial, fantasia, observacoes sql.NullString
	if err := scan(
		&tenantid,
		&cnpj,
		&cep,
		&endereco,
		&bairro,
		&cidade,
		&estado,
		&telefone,
		&email,
		&ie,
		&im,
		&razaosocial,
		&fantasia,
		&observacoes,
	); err != nil {
		return domain.DadosComplementaresRecord{}, err
	}
	return domain.DadosComplementaresRecord{
		Tenantid:    tenantid,
		CNPJ:        nullStringPtr(cnpj),
		CEP:         nullStringPtr(cep),
		Endereco:    nullStringPtr(endereco),
		Bairro:      nullStringPtr(bairro),
		Cidade:      nullStringPtr(cidade),
		Estado:      nullStringPtr(estado),
		Telefone:    nullStringPtr(telefone),
		Email:       nullStringPtr(email),
		IE:          nullStringPtr(ie),
		IM:          nullStringPtr(im),
		RazaoSocial: nullStringPtr(razaosocial),
		Fantasia:    nullStringPtr(fantasia),
		Observacoes: nullStringPtr(observacoes),
	}, nil
}

func (r *RegistroRepository) DetailByTenant(ctx context.Context, tenantID string) (domain.DadosComplementaresRecord, error) {
	if tenantID == "" {
		return domain.DadosComplementaresRecord{}, nil
	}

	const query = `SELECT tenantid, cnpj, cep, endereco, bairro, cidade, estado, telefone, email, ie, im, razaosocial, fantasia, observacoes FROM public.tenant_dados WHERE tenantid::text = $1 LIMIT 1`

	record, err := scanDadosComplementares("", func(dest ...any) error {
		return r.pool.QueryRow(ctx, query, tenantID).Scan(dest...)
	})
	if err != nil {
		if err == pgx.ErrNoRows {
			return domain.DadosComplementaresRecord{Tenantid: tenantID}, nil
		}
		return domain.DadosComplementaresRecord{}, fmt.Errorf("detail registro: %w", err)
	}
	return record, nil
}

func (r *RegistroRepository) UpdateByUser(ctx context.Context, userID string, input RegistroUpdateInput) (domain.DadosComplementaresRecord, error) {
	const tenantQuery = `SELECT tenantid FROM public.usuario WHERE id = $1`
	var tenantID string
	if err := r.pool.QueryRow(ctx, tenantQuery, userID).Scan(&tenantID); err != nil {
		return domain.DadosComplementaresRecord{}, fmt.Errorf("find tenant by user: %w", err)
	}

	const query = `
		UPDATE public.tenant_dados
		SET cnpj = $1,
			cep = $2,
			endereco = $3,
			bairro = $4,
			cidade = $5,
			estado = $6,
			telefone = $7,
			email = $8,
			ie = $9,
			im = $10,
			razaosocial = $11,
			fantasia = $12,
			observacoes = $13
		WHERE tenantid = $14
		RETURNING tenantid, cnpj, cep, endereco, bairro, cidade, estado, telefone, email, ie, im, razaosocial, fantasia, observacoes`

	record, err := scanDadosComplementares(tenantID, func(dest ...any) error {
		return r.pool.QueryRow(
			ctx,
			query,
			input.CNPJ,
			input.CEP,
			input.Endereco,
			input.Bairro,
			input.Cidade,
			input.Estado,
			input.Telefone,
			input.Email,
			input.IE,
			input.IM,
			input.RazaoSocial,
			input.Fantasia,
			input.Observacoes,
			tenantID,
		).Scan(dest...)
	})
	if err != nil {
		return domain.DadosComplementaresRecord{}, fmt.Errorf("update registro: %w", err)
	}
	return record, nil
}

func (r *RegistroRepository) UpdateByTenantID(ctx context.Context, tenantID string, input RegistroUpdateInput) (domain.DadosComplementaresRecord, error) {
	tenantID = strings.TrimSpace(tenantID)
	if tenantID == "" {
		return domain.DadosComplementaresRecord{}, fmt.Errorf("tenant id obrigatorio")
	}

	const ensureRow = `
		INSERT INTO public.tenant_dados (tenantid)
		SELECT $1::uuid
		WHERE NOT EXISTS (SELECT 1 FROM public.tenant_dados td WHERE td.tenantid = $2::uuid)`

	if _, err := r.pool.Exec(ctx, ensureRow, tenantID, tenantID); err != nil {
		return domain.DadosComplementaresRecord{}, fmt.Errorf("ensure tenant_dados: %w", err)
	}

	const query = `
		UPDATE public.tenant_dados
		SET cnpj = $1,
			cep = $2,
			endereco = $3,
			bairro = $4,
			cidade = $5,
			estado = $6,
			telefone = $7,
			email = $8,
			ie = $9,
			im = $10,
			razaosocial = $11,
			fantasia = $12,
			observacoes = $13
		WHERE tenantid::text = $14
		RETURNING tenantid, cnpj, cep, endereco, bairro, cidade, estado, telefone, email, ie, im, razaosocial, fantasia, observacoes`

	record, err := scanDadosComplementares(tenantID, func(dest ...any) error {
		return r.pool.QueryRow(
			ctx,
			query,
			input.CNPJ,
			input.CEP,
			input.Endereco,
			input.Bairro,
			input.Cidade,
			input.Estado,
			input.Telefone,
			input.Email,
			input.IE,
			input.IM,
			input.RazaoSocial,
			input.Fantasia,
			input.Observacoes,
			tenantID,
		).Scan(dest...)
	})
	if err != nil {
		return domain.DadosComplementaresRecord{}, fmt.Errorf("update tenant_dados: %w", err)
	}
	return record, nil
}

func (r *RegistroRepository) Create(ctx context.Context, input RegistroCreateInput) (domain.RegistroUserRecord, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return domain.RegistroUserRecord{}, fmt.Errorf("begin tx registro create: %w", err)
	}
	defer tx.Rollback(ctx)

	const existsQuery = `SELECT EXISTS(SELECT 1 FROM public.usuario WHERE email = $1)`
	var exists bool
	if err := tx.QueryRow(ctx, existsQuery, input.Email).Scan(&exists); err != nil {
		return domain.RegistroUserRecord{}, fmt.Errorf("check user exists: %w", err)
	}
	if exists {
		return domain.RegistroUserRecord{}, fmt.Errorf("Usuario ja cadastrado")
	}

	const tenantQuery = `
		INSERT INTO public.tenant (nome, active, plano, contato)
		VALUES ($1, $2, $3, $4)
		RETURNING id`
	var tenantID string
	if err := tx.QueryRow(ctx, tenantQuery, input.Nome, true, "DEMO", input.Nome).Scan(&tenantID); err != nil {
		return domain.RegistroUserRecord{}, fmt.Errorf("create tenant: %w", err)
	}

	const dadosQuery = `
		INSERT INTO public.tenant_dados (tenantid)
		VALUES ($1)`
	if _, err := tx.Exec(ctx, dadosQuery, tenantID); err != nil {
		return domain.RegistroUserRecord{}, fmt.Errorf("create tenant_dados: %w", err)
	}

	const userQuery = `
		INSERT INTO public.usuario (nome, email, password, role, tenantid, active)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, nome, email, role, tenantid, active`

	var record domain.RegistroUserRecord
	if err := tx.QueryRow(ctx, userQuery, input.Nome, input.Email, input.Password, "ADMIN", tenantID, true).Scan(
		&record.ID,
		&record.Nome,
		&record.Email,
		&record.Role,
		&record.TenantID,
		&record.Active,
	); err != nil {
		return domain.RegistroUserRecord{}, fmt.Errorf("create user: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return domain.RegistroUserRecord{}, fmt.Errorf("commit registro create: %w", err)
	}

	return record, nil
}
