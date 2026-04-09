package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type EmpresaDadosUpsertInput struct {
	EmpresaID        string
	TenantID         string
	MunicipioID      string
	Bairro           string
	CNPJ             string
	CapitalSocial    *float64
	Endereco         string
	Numero           string
	CEP              string
	EmailContato     string
	Telefone         string
	Telefone2        string
	DataAbertura     string
	DataEncerramento string
	Observacao       string
}

type EmpresaDadosRepository struct {
	pool *pgxpool.Pool
}

func NewEmpresaDadosRepository(pool *pgxpool.Pool) *EmpresaDadosRepository {
	return &EmpresaDadosRepository{pool: pool}
}

func textPtr(t pgtype.Text) *string {
	if !t.Valid {
		return nil
	}
	s := strings.TrimSpace(t.String)
	if s == "" {
		return nil
	}
	return &s
}

func datePtr(d pgtype.Date) *string {
	if !d.Valid {
		return nil
	}
	s := time.Date(d.Time.Year(), d.Time.Month(), d.Time.Day(), 0, 0, 0, 0, time.UTC).Format("2006-01-02")
	return &s
}

func strOrNil(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return strings.TrimSpace(s)
}

func parseDateOrNil(s string) (any, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, nil
	}
	t, err := time.Parse("2006-01-02", s)
	if err != nil {
		return nil, fmt.Errorf("data invalida (use AAAA-MM-DD): %w", err)
	}
	return t, nil
}

func (r *EmpresaDadosRepository) GetByEmpresa(ctx context.Context, empresaID, tenantID string) (*domain.EmpresaDadosItem, error) {
	if strings.TrimSpace(empresaID) == "" || strings.TrimSpace(tenantID) == "" {
		return nil, fmt.Errorf("empresa e tenant obrigatorios")
	}

	const q = `
		SELECT e.id,
			ed.cnpj,
			ed.capital_social::float8,
			ed.endereco, ed.numero, ed.cep, ed.email_contato, ed.telefone, ed.telefone2,
			ed.data_abertura, ed.data_encerramento, ed.observacao,
			COALESCE(m.id::text, ''), COALESCE(m.nome, '')
		FROM public.empresa e
		INNER JOIN public.cliente c ON c.id = e.cliente_id
		LEFT JOIN public.clientes_dados ed ON ed.cliente_id = c.id
		LEFT JOIN public.municipio m ON m.id = COALESCE(c.municipio_id, ed.municipio_id)
		WHERE e.id = $1 AND e.tenant_id = $2 AND e.ativo = true`

	row := r.pool.QueryRow(ctx, q, empresaID, tenantID)

	var (
		id                                             string
		cnpj, endereco, numero, cep, email, tel1, tel2 pgtype.Text
		capitalSocial                                  sql.NullFloat64
		dataAber, dataEnc                              pgtype.Date
		obs                                            pgtype.Text
		mID, mNome                                     string
	)
	if err := row.Scan(&id, &cnpj, &capitalSocial, &endereco, &numero, &cep, &email, &tel1, &tel2, &dataAber, &dataEnc, &obs, &mID, &mNome); err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("empresa nao encontrada")
		}
		return nil, fmt.Errorf("buscar dados complementares: %w", err)
	}

	out := &domain.EmpresaDadosItem{
		EmpresaID:        id,
		CNPJ:             textPtr(cnpj),
		Endereco:         textPtr(endereco),
		Numero:           textPtr(numero),
		CEP:              textPtr(cep),
		EmailContato:     textPtr(email),
		Telefone:         textPtr(tel1),
		Telefone2:        textPtr(tel2),
		DataAbertura:     datePtr(dataAber),
		DataEncerramento: datePtr(dataEnc),
		Observacao:       textPtr(obs),
		Municipio: domain.EmpresaRef{
			ID:   mID,
			Nome: mNome,
		},
	}
	if capitalSocial.Valid {
		v := capitalSocial.Float64
		out.CapitalSocial = &v
	}
	return out, nil
}

func (r *EmpresaDadosRepository) Upsert(ctx context.Context, in EmpresaDadosUpsertInput) error {
	if strings.TrimSpace(in.EmpresaID) == "" || strings.TrimSpace(in.TenantID) == "" {
		return fmt.Errorf("empresa e tenant obrigatorios")
	}

	dAb, err := parseDateOrNil(in.DataAbertura)
	if err != nil {
		return err
	}
	dEnc, err := parseDateOrNil(in.DataEncerramento)
	if err != nil {
		return err
	}

	var mid any
	if s := strings.TrimSpace(in.MunicipioID); s != "" {
		mid = s
	} else {
		mid = nil
	}
	var cap any
	if in.CapitalSocial != nil {
		cap = *in.CapitalSocial
	} else {
		cap = nil
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("iniciar transacao dados complementares: %w", err)
	}
	defer tx.Rollback(ctx)

	const q = `
		INSERT INTO public.clientes_dados (
			cliente_id, municipio_id, cnpj, capital_social, endereco, numero, cep, email_contato, telefone, telefone2,
			data_abertura, data_encerramento, observacao, atualizado_em
		)
		SELECT e.cliente_id, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::date, $12::date, $13, NOW()
		FROM public.empresa e
		WHERE e.id = $1 AND e.tenant_id = $14 AND e.ativo = true
		ON CONFLICT (cliente_id) DO UPDATE SET
			municipio_id = EXCLUDED.municipio_id,
			cnpj = EXCLUDED.cnpj,
			capital_social = EXCLUDED.capital_social,
			endereco = EXCLUDED.endereco,
			numero = EXCLUDED.numero,
			cep = EXCLUDED.cep,
			email_contato = EXCLUDED.email_contato,
			telefone = EXCLUDED.telefone,
			telefone2 = EXCLUDED.telefone2,
			data_abertura = EXCLUDED.data_abertura,
			data_encerramento = EXCLUDED.data_encerramento,
			observacao = EXCLUDED.observacao,
			atualizado_em = NOW()`

	tag, err := tx.Exec(ctx, q,
		in.EmpresaID,
		mid,
		strOrNil(in.CNPJ),
		cap,
		strOrNil(in.Endereco),
		strOrNil(in.Numero),
		strOrNil(in.CEP),
		strOrNil(in.EmailContato),
		strOrNil(in.Telefone),
		strOrNil(in.Telefone2),
		dAb,
		dEnc,
		strOrNil(in.Observacao),
		in.TenantID,
	)
	if err != nil {
		return fmt.Errorf("gravar dados complementares: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("empresa nao encontrada ou sem permissao")
	}

	if _, err := tx.Exec(ctx, `
		UPDATE public.cliente c
		SET municipio_id = $2,
		    bairro = NULLIF(TRIM($4), ''),
		    atualizado_em = NOW()
		FROM public.empresa e
		WHERE c.id = e.cliente_id AND e.id = $1 AND e.tenant_id = $3 AND e.ativo = true`,
		in.EmpresaID, mid, in.TenantID, in.Bairro,
	); err != nil {
		return fmt.Errorf("espelhar municipio e bairro no cliente: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("confirmar dados complementares: %w", err)
	}
	return nil
}
