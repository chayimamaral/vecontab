package repository

import (
	"testing"
	"time"
)

// TestAjustarVencimento_RN2 cobre a regra de postergar vencimentos em sábado,
// domingo e feriados ([RN2]). A lógica vive no repositório (não no AgendaService
// de calendário); testes aqui não exigem banco de dados.
func TestAjustarVencimento_RN2(t *testing.T) {
	loc := time.Local

	tests := []struct {
		name     string
		in       time.Time
		feriados map[string]bool
		want     time.Time
	}{
		{
			name:     "sábado isolado vai para segunda",
			in:       time.Date(2026, 3, 14, 0, 0, 0, 0, loc), // sábado
			feriados: nil,
			want:     time.Date(2026, 3, 16, 0, 0, 0, 0, loc),
		},
		{
			name:     "domingo isolado vai para segunda",
			in:       time.Date(2026, 3, 15, 0, 0, 0, 0, loc),
			feriados: nil,
			want:     time.Date(2026, 3, 16, 0, 0, 0, 0, loc),
		},
		{
			name:     "dia útil sem feriado permanece",
			in:       time.Date(2026, 3, 17, 0, 0, 0, 0, loc), // terça
			feriados: map[string]bool{},
			want:     time.Date(2026, 3, 17, 0, 0, 0, 0, loc),
		},
		{
			name: "feriado nacional em dia útil posterga um dia",
			in:   time.Date(2026, 1, 1, 0, 0, 0, 0, loc), // quinta
			feriados: map[string]bool{
				"2026-01-01": true,
			},
			want: time.Date(2026, 1, 2, 0, 0, 0, 0, loc), // sexta
		},
		{
			name: "cadeia feriado em sexta e sábado termina em segunda",
			in:   time.Date(2026, 4, 3, 0, 0, 0, 0, loc), // sexta santa 2026
			feriados: map[string]bool{
				"2026-04-03": true,
				"2026-04-04": true,
			},
			want: time.Date(2026, 4, 6, 0, 0, 0, 0, loc), // segunda
		},
		{
			name: "após pular fim de semana cai em feriado e avança",
			in:   time.Date(2026, 5, 30, 0, 0, 0, 0, loc), // sábado
			feriados: map[string]bool{
				"2026-06-01": true, // segunda Corpus Christi (exemplo municipal/variável)
			},
			want: time.Date(2026, 6, 2, 0, 0, 0, 0, loc),
		},
		{
			name: "dois feriados em dias úteis consecutivos após fim de semana",
			in:   time.Date(2026, 11, 20, 0, 0, 0, 0, loc), // sexta
			feriados: map[string]bool{
				"2026-11-20": true,
				"2026-11-23": true, // segunda também feriado (cenário fictício encadeado)
			},
			want: time.Date(2026, 11, 24, 0, 0, 0, 0, loc),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ajustarVencimento(tt.in, tt.feriados)
			if !got.Equal(tt.want) {
				t.Fatalf("ajustarVencimento(%s) = %s, want %s",
					tt.in.Format("2006-01-02 Mon"),
					got.Format("2006-01-02 Mon"),
					tt.want.Format("2006-01-02 Mon"))
			}
		})
	}
}
