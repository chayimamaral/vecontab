package repository

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var nonDigit = regexp.MustCompile(`\D`)

type CnaeListParams struct {
	First       int
	Rows        int
	SortField   string
	SortOrder   int
	Denominacao string
	Subclasse   string
}

type CnaeRecord struct {
	ID          string `json:"id"`
	Secao       string `json:"secao"`
	Divisao     string `json:"divisao"`
	Grupo       string `json:"grupo"`
	Classe      string `json:"classe"`
	Subclasse   string `json:"subclasse"`
	Denominacao string `json:"denominacao"`
	Ativo       bool   `json:"ativo"`
}

type CnaeLiteItem struct {
	ID          string `json:"id"`
	Denominacao string `json:"denominacao"`
	Subclasse   string `json:"subclasse"`
}

type CnaeValidateItem struct {
	ID string `json:"id"`
}

// CnaeIbgeResolve descreve uma subclasse encontrada nas tabelas ibge_cnae_* (catálogo oficial).
type CnaeIbgeResolve struct {
	Found       bool   `json:"found"`
	Secao       string `json:"secao"`
	Divisao     string `json:"divisao"`
	Grupo       string `json:"grupo"`
	Classe      string `json:"classe"`
	Denominacao string `json:"denominacao"`
	Subclasse   string `json:"subclasse"`
}

type CnaeRepository struct {
	pool *pgxpool.Pool
}

func NewCnaeRepository(pool *pgxpool.Pool) *CnaeRepository {
	return &CnaeRepository{pool: pool}
}

// SubclasseSomenteDigitos normaliza código CNAE (com ou sem máscara) para 7 dígitos.
func SubclasseSomenteDigitos(s string) string {
	return nonDigit.ReplaceAllString(strings.TrimSpace(s), "")
}

// cnaeHierarquiaListada: descrições da listagem — public.cnae, depois cnae_ibge_hierarquia, depois
// modelo relacional ibge_cnae_* (015). Assim linhas antigas só com subclasse+denominação exibem a hierarquia.
func cnaeHierarquiaListada(col, ibgeCol string) string {
	return fmt.Sprintf(
		`COALESCE(NULLIF(BTRIM(c.%s), ''), NULLIF(BTRIM(h.%s), ''), NULLIF(BTRIM(ibge.%s), ''), '')`,
		col, col, ibgeCol,
	)
}

const cnaeListFrom = `public.cnae c
LEFT JOIN public.cnae_ibge_hierarquia h ON BTRIM(h.subclasse) = BTRIM(c.subclasse)
LEFT JOIN LATERAL (
	SELECT
		s.nome AS ib_secao,
		d.nome AS ib_divisao,
		g.nome AS ib_grupo,
		ccl.nome AS ib_classe
	FROM public.ibge_cnae_subclasse sc
	JOIN public.ibge_cnae_classe ccl ON ccl.id = sc.classe_id
	JOIN public.ibge_cnae_grupo g ON g.id = ccl.grupo_id
	JOIN public.ibge_cnae_divisao d ON d.id = g.divisao_id
	JOIN public.ibge_cnae_secao s ON s.id = d.secao_id
	WHERE RTRIM(sc.codigo::text, ' ') = BTRIM(c.subclasse)
	LIMIT 1
) ibge ON true`

func (r *CnaeRepository) List(ctx context.Context, params CnaeListParams) ([]CnaeRecord, int64, error) {
	whereParts := []string{"c.ativo = true"}
	args := []any{}
	argIndex := 1

	if strings.TrimSpace(params.Denominacao) != "" {
		pat := "%" + strings.TrimSpace(params.Denominacao) + "%"
		i := argIndex
		whereParts = append(whereParts, fmt.Sprintf(
			`(%s ILIKE $%d OR %s ILIKE $%d OR %s ILIKE $%d OR %s ILIKE $%d OR c.denominacao ILIKE $%d OR c.subclasse ILIKE $%d)`,
			cnaeHierarquiaListada("secao", "ib_secao"), i,
			cnaeHierarquiaListada("divisao", "ib_divisao"), i,
			cnaeHierarquiaListada("grupo", "ib_grupo"), i,
			cnaeHierarquiaListada("classe", "ib_classe"), i,
			i, i,
		))
		args = append(args, pat)
		argIndex++
	} else if strings.TrimSpace(params.Subclasse) != "" {
		d := SubclasseSomenteDigitos(params.Subclasse)
		if d != "" {
			whereParts = append(whereParts, fmt.Sprintf("c.subclasse LIKE $%d", argIndex))
			args = append(args, d+"%")
			argIndex++
		}
	}

	dir := "DESC"
	if params.SortOrder == -1 {
		dir = "ASC"
	}
	orderBy := "c.subclasse ASC"
	switch params.SortField {
	case "secao":
		orderBy = cnaeHierarquiaListada("secao", "ib_secao") + " " + dir
	case "divisao":
		orderBy = cnaeHierarquiaListada("divisao", "ib_divisao") + " " + dir
	case "grupo":
		orderBy = cnaeHierarquiaListada("grupo", "ib_grupo") + " " + dir
	case "classe":
		orderBy = cnaeHierarquiaListada("classe", "ib_classe") + " " + dir
	case "denominacao":
		orderBy = "c.denominacao " + dir
	case "subclasse":
		orderBy = "c.subclasse " + dir
	}

	selectCols := fmt.Sprintf(`c.id,
		%s AS secao,
		%s AS divisao,
		%s AS grupo,
		%s AS classe,
		c.subclasse, c.denominacao, c.ativo`,
		cnaeHierarquiaListada("secao", "ib_secao"),
		cnaeHierarquiaListada("divisao", "ib_divisao"),
		cnaeHierarquiaListada("grupo", "ib_grupo"),
		cnaeHierarquiaListada("classe", "ib_classe"))

	whereClause := strings.Join(whereParts, " AND ")
	query := fmt.Sprintf(
		`SELECT %s FROM %s WHERE %s ORDER BY %s LIMIT $%d OFFSET $%d`,
		selectCols,
		cnaeListFrom,
		whereClause,
		orderBy,
		argIndex,
		argIndex+1,
	)
	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list cnae: %w", err)
	}
	defer rows.Close()

	cnaes := make([]CnaeRecord, 0)
	for rows.Next() {
		var rec CnaeRecord
		if err := rows.Scan(&rec.ID, &rec.Secao, &rec.Divisao, &rec.Grupo, &rec.Classe, &rec.Subclasse, &rec.Denominacao, &rec.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan cnae: %w", err)
		}
		cnaes = append(cnaes, rec)
	}

	countQuery := fmt.Sprintf("SELECT count(*) FROM %s WHERE %s", cnaeListFrom, whereClause)
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count cnae: %w", err)
	}

	return cnaes, total, nil
}

func (r *CnaeRepository) lookupIbgeHierarchy(ctx context.Context, sub7 string) (secao, divisao, grupo, classe, denominacao string, ok bool, err error) {
	const q = `
		SELECT s.nome, d.nome, g.nome, c.nome, sc.nome
		FROM public.ibge_cnae_subclasse sc
		JOIN public.ibge_cnae_classe c ON c.id = sc.classe_id
		JOIN public.ibge_cnae_grupo g ON g.id = c.grupo_id
		JOIN public.ibge_cnae_divisao d ON d.id = g.divisao_id
		JOIN public.ibge_cnae_secao s ON s.id = d.secao_id
		WHERE sc.codigo = $1::bpchar`
	err = r.pool.QueryRow(ctx, q, sub7).Scan(&secao, &divisao, &grupo, &classe, &denominacao)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", "", "", "", false, nil
	}
	if err != nil {
		return "", "", "", "", "", false, err
	}
	return secao, divisao, grupo, classe, denominacao, true, nil
}

// mergeComCatalogoIbge: se a subclasse existir no catálogo IBGE, usa hierarquia e denominação oficiais (mesmo JOIN da migração 015).
func (r *CnaeRepository) mergeComCatalogoIbge(ctx context.Context, secao, divisao, grupo, classe, denominacao, subclasse string) (s, d, g, c, den, sub string, err error) {
	sub = SubclasseSomenteDigitos(subclasse)
	if len(sub) != 7 {
		return "", "", "", "", "", "", fmt.Errorf("subclasse deve ter 7 digitos")
	}
	if ibSec, ibDiv, ibGrp, ibCls, ibDen, ok, err := r.lookupIbgeHierarchy(ctx, sub); err != nil {
		return "", "", "", "", "", "", err
	} else if ok {
		return ibSec, ibDiv, ibGrp, ibCls, ibDen, sub, nil
	}
	if strings.TrimSpace(denominacao) == "" {
		return "", "", "", "", "", "", fmt.Errorf("denominacao e obrigatoria para codigo fora do catalogo IBGE")
	}
	return strings.TrimSpace(secao), strings.TrimSpace(divisao), strings.TrimSpace(grupo), strings.TrimSpace(classe), strings.TrimSpace(denominacao), sub, nil
}

func (r *CnaeRepository) upsertCnaeIbgeHierarquia(ctx context.Context, sub, secao, divisao, grupo, classe string) error {
	if strings.TrimSpace(secao) == "" || strings.TrimSpace(divisao) == "" || strings.TrimSpace(grupo) == "" || strings.TrimSpace(classe) == "" {
		return nil
	}
	const q = `
		INSERT INTO public.cnae_ibge_hierarquia (subclasse, secao, divisao, grupo, classe)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (subclasse) DO UPDATE SET
			secao = EXCLUDED.secao,
			divisao = EXCLUDED.divisao,
			grupo = EXCLUDED.grupo,
			classe = EXCLUDED.classe`
	_, err := r.pool.Exec(ctx, q, sub, secao, divisao, grupo, classe)
	return err
}

// ResolveIbge retorna dados oficiais para a subclasse ou found=false.
func (r *CnaeRepository) ResolveIbge(ctx context.Context, subclasse string) (CnaeIbgeResolve, error) {
	sub := SubclasseSomenteDigitos(subclasse)
	out := CnaeIbgeResolve{Subclasse: sub}
	if len(sub) != 7 {
		return out, nil
	}
	sec, div, grp, cls, den, ok, err := r.lookupIbgeHierarchy(ctx, sub)
	if err != nil || !ok {
		return out, err
	}
	out.Found = true
	out.Secao, out.Divisao, out.Grupo, out.Classe, out.Denominacao = sec, div, grp, cls, den
	return out, nil
}

func (r *CnaeRepository) Create(ctx context.Context, secao, divisao, grupo, classe, denominacao, subclasse string) ([]CnaeRecord, int64, error) {
	sec, div, grp, cls, den, sub, err := r.mergeComCatalogoIbge(ctx, secao, divisao, grupo, classe, denominacao, subclasse)
	if err != nil {
		return nil, 0, err
	}
	const query = `
		INSERT INTO public.cnae (secao, divisao, grupo, classe, subclasse, denominacao)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, secao, divisao, grupo, classe, subclasse, denominacao, ativo`

	rows, err := r.pool.Query(ctx, query, sec, div, grp, cls, sub, den)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return nil, 0, fmt.Errorf("esta subclasse ja esta cadastrada")
		}
		return nil, 0, fmt.Errorf("create cnae: %w", err)
	}
	defer rows.Close()

	cnaes := make([]CnaeRecord, 0)
	for rows.Next() {
		var rec CnaeRecord
		if err := rows.Scan(&rec.ID, &rec.Secao, &rec.Divisao, &rec.Grupo, &rec.Classe, &rec.Subclasse, &rec.Denominacao, &rec.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan created cnae: %w", err)
		}
		cnaes = append(cnaes, rec)
	}

	if err := rows.Err(); err != nil {
		return nil, 0, err
	}

	if len(cnaes) == 1 {
		rec := cnaes[0]
		if err := r.upsertCnaeIbgeHierarquia(ctx, rec.Subclasse, rec.Secao, rec.Divisao, rec.Grupo, rec.Classe); err != nil {
			return nil, 0, fmt.Errorf("sync cnae_ibge_hierarquia: %w", err)
		}
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.cnae WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count cnae: %w", err)
	}

	return cnaes, total, nil
}

func (r *CnaeRepository) Update(ctx context.Context, id, secao, divisao, grupo, classe, denominacao, subclasse string) ([]CnaeRecord, int64, error) {
	sec, div, grp, cls, den, sub, err := r.mergeComCatalogoIbge(ctx, secao, divisao, grupo, classe, denominacao, subclasse)
	if err != nil {
		return nil, 0, err
	}
	const query = `
		UPDATE public.cnae
		SET secao = $1, divisao = $2, grupo = $3, classe = $4, subclasse = $5, denominacao = $6
		WHERE id = $7
		RETURNING id, secao, divisao, grupo, classe, subclasse, denominacao, ativo`

	rows, err := r.pool.Query(ctx, query, sec, div, grp, cls, sub, den, id)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return nil, 0, fmt.Errorf("esta subclasse ja esta cadastrada em outro registro")
		}
		return nil, 0, fmt.Errorf("update cnae: %w", err)
	}
	defer rows.Close()

	cnaes := make([]CnaeRecord, 0)
	for rows.Next() {
		var rec CnaeRecord
		if err := rows.Scan(&rec.ID, &rec.Secao, &rec.Divisao, &rec.Grupo, &rec.Classe, &rec.Subclasse, &rec.Denominacao, &rec.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan updated cnae: %w", err)
		}
		cnaes = append(cnaes, rec)
	}

	if err := rows.Err(); err != nil {
		return nil, 0, err
	}

	if len(cnaes) == 1 {
		rec := cnaes[0]
		if err := r.upsertCnaeIbgeHierarquia(ctx, rec.Subclasse, rec.Secao, rec.Divisao, rec.Grupo, rec.Classe); err != nil {
			return nil, 0, fmt.Errorf("sync cnae_ibge_hierarquia: %w", err)
		}
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.cnae WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count cnae: %w", err)
	}

	return cnaes, total, nil
}

func (r *CnaeRepository) Delete(ctx context.Context, id string) ([]CnaeRecord, int64, error) {
	const query = `
		UPDATE public.cnae
		SET ativo = false
		WHERE id = $1
		RETURNING id, secao, divisao, grupo, classe, subclasse, denominacao, ativo`

	rows, err := r.pool.Query(ctx, query, id)
	if err != nil {
		return nil, 0, fmt.Errorf("delete cnae: %w", err)
	}
	defer rows.Close()

	cnaes := make([]CnaeRecord, 0)
	for rows.Next() {
		var rec CnaeRecord
		if err := rows.Scan(&rec.ID, &rec.Secao, &rec.Divisao, &rec.Grupo, &rec.Classe, &rec.Subclasse, &rec.Denominacao, &rec.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan deleted cnae: %w", err)
		}
		cnaes = append(cnaes, rec)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.cnae WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count cnae: %w", err)
	}

	return cnaes, total, nil
}

func (r *CnaeRepository) Lite(ctx context.Context) ([]CnaeLiteItem, error) {
	rows, err := r.pool.Query(ctx, `SELECT id, denominacao, subclasse FROM public.cnae WHERE ativo = true ORDER BY denominacao ASC`)
	if err != nil {
		return nil, fmt.Errorf("lite cnae: %w", err)
	}
	defer rows.Close()

	cnaes := make([]CnaeLiteItem, 0)
	for rows.Next() {
		var id, d, s string
		if err := rows.Scan(&id, &d, &s); err != nil {
			return nil, fmt.Errorf("scan lite cnae: %w", err)
		}
		cnaes = append(cnaes, CnaeLiteItem{ID: id, Denominacao: d, Subclasse: s})
	}

	return cnaes, nil
}

func (r *CnaeRepository) Validate(ctx context.Context, cnae string) ([]CnaeValidateItem, error) {
	sub := SubclasseSomenteDigitos(cnae)
	if sub == "" {
		return nil, nil
	}
	rows, err := r.pool.Query(ctx, `SELECT id FROM public.cnae WHERE ativo = true AND subclasse = $1`, sub)
	if err != nil {
		return nil, fmt.Errorf("validate cnae: %w", err)
	}
	defer rows.Close()

	result := make([]CnaeValidateItem, 0)
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("scan validate cnae: %w", err)
		}
		result = append(result, CnaeValidateItem{ID: id})
	}

	if len(result) > 0 {
		return result, nil
	}

	var ibgeExists bool
	if err := r.pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM public.ibge_cnae_subclasse WHERE codigo = $1::bpchar)`,
		sub,
	).Scan(&ibgeExists); err != nil {
		return nil, fmt.Errorf("validate cnae ibge: %w", err)
	}
	if ibgeExists {
		result = append(result, CnaeValidateItem{ID: ""})
	}

	return result, nil
}
