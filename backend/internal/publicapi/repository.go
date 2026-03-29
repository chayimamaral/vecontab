package publicapi

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Repository acessa dados expostos pela Public API (somente leitura).
type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

// ListRotinasJSON retorna todas as rotinas ativas do município e tipo de empresa em uma única query,
// com passos aninhados via json_agg / json_build_object (Postgres).
//
// tipoEmpresaID: UUID válido ou, para rotinas sem tipo (NULL no banco), os literais "null" ou "none" (case insensitive).
func (r *Repository) ListRotinasJSON(ctx context.Context, municipioID, tipoEmpresaID string) (json.RawMessage, error) {
	tipo := strings.TrimSpace(tipoEmpresaID)

	const q = `
SELECT COALESCE(
	(
		SELECT json_agg(doc ORDER BY doc->>'descricao')
		FROM (
			SELECT json_build_object(
				'id', r.id,
				'descricao', r.descricao,
				'municipio_id', r.municipio_id,
				'tipo_empresa_id', r.tipo_empresa_id,
				'rotinaitens', COALESCE(
					(
						SELECT json_agg(
							json_build_object(
								'id', p.id,
								'descricao', p.descricao,
								'tempoestimado', p.tempoestimado,
								'ordem', ri.ordem,
								'link', COALESCE(l.link, '')
							)
							ORDER BY ri.ordem ASC NULLS LAST
						)
						FROM public.rotinaitens ri
						INNER JOIN public.passos p ON p.id = ri.passo_id
						LEFT JOIN public.linkpassos l ON l.passo_id = p.id
						WHERE ri.rotina_id = r.id
					),
					'[]'::json
				)
			) AS doc
			FROM public.rotinas r
			WHERE r.ativo = true
				AND r.municipio_id = $1
				AND (
					CASE
						WHEN lower($2::text) IN ('null', 'none') THEN r.tipo_empresa_id IS NULL
						ELSE r.tipo_empresa_id = $2::uuid
					END
				)
		) sub
	),
	'[]'::json
)
`

	var raw []byte
	if err := r.pool.QueryRow(ctx, q, municipioID, tipo).Scan(&raw); err != nil {
		return nil, fmt.Errorf("public list rotinas json: %w", err)
	}
	return json.RawMessage(raw), nil
}
