// Gera 015_cnae_ibge_seed.sql a partir do export Kelvin (flattened JOIN),
// populando o modelo relacional PostgreSQL (018) e public.cnae via o mesmo JOIN lógico.
//
// Fonte padrão: cnae_classificacao_kelvin.sql (tuplas = resultado de
//   cs.descricao, cd.descricao, cg.descricao, cc.descricao, subclasse, cs2.descricao
// com o CASE do padding de subclasse já aplicado nos VALUES).
//
// Uso (no diretório backend):
//   go run ./cmd/gen-cnae-seed
//   go run ./cmd/gen-cnae-seed -in cnae_classificacao_kelvin.sql -out migrations/015_cnae_ibge_seed.sql
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"strings"
)

type flatRow struct {
	Secao, Divisao, Grupo, Classe, Subcodigo, Denominacao string
}

func writeIBGEDDL(w *bufio.Writer) {
	fmt.Fprintln(w, `CREATE TABLE IF NOT EXISTS public.ibge_cnae_secao (`)
	fmt.Fprintln(w, `    id        smallserial PRIMARY KEY,`)
	fmt.Fprintln(w, `    nome      text NOT NULL UNIQUE`)
	fmt.Fprintln(w, `);`)
	fmt.Fprintln(w)
	fmt.Fprintln(w, `CREATE TABLE IF NOT EXISTS public.ibge_cnae_divisao (`)
	fmt.Fprintln(w, `    id        serial PRIMARY KEY,`)
	fmt.Fprintln(w, `    secao_id  smallint NOT NULL REFERENCES public.ibge_cnae_secao (id) ON DELETE CASCADE,`)
	fmt.Fprintln(w, `    nome      text NOT NULL,`)
	fmt.Fprintln(w, `    UNIQUE (secao_id, nome)`)
	fmt.Fprintln(w, `);`)
	fmt.Fprintln(w)
	fmt.Fprintln(w, `CREATE TABLE IF NOT EXISTS public.ibge_cnae_grupo (`)
	fmt.Fprintln(w, `    id           serial PRIMARY KEY,`)
	fmt.Fprintln(w, `    divisao_id   int NOT NULL REFERENCES public.ibge_cnae_divisao (id) ON DELETE CASCADE,`)
	fmt.Fprintln(w, `    nome         text NOT NULL,`)
	fmt.Fprintln(w, `    UNIQUE (divisao_id, nome)`)
	fmt.Fprintln(w, `);`)
	fmt.Fprintln(w)
	fmt.Fprintln(w, `CREATE TABLE IF NOT EXISTS public.ibge_cnae_classe (`)
	fmt.Fprintln(w, `    id         serial PRIMARY KEY,`)
	fmt.Fprintln(w, `    grupo_id   int NOT NULL REFERENCES public.ibge_cnae_grupo (id) ON DELETE CASCADE,`)
	fmt.Fprintln(w, `    nome       text NOT NULL,`)
	fmt.Fprintln(w, `    UNIQUE (grupo_id, nome)`)
	fmt.Fprintln(w, `);`)
	fmt.Fprintln(w)
	fmt.Fprintln(w, `CREATE TABLE IF NOT EXISTS public.ibge_cnae_subclasse (`)
	fmt.Fprintln(w, `    id          serial PRIMARY KEY,`)
	fmt.Fprintln(w, `    classe_id   int NOT NULL REFERENCES public.ibge_cnae_classe (id) ON DELETE CASCADE,`)
	fmt.Fprintln(w, `    codigo      char(7) NOT NULL UNIQUE,`)
	fmt.Fprintln(w, `    nome        text NOT NULL`)
	fmt.Fprintln(w, `);`)
	fmt.Fprintln(w)
}

func main() {
	inPath := flag.String("in", "cnae_classificacao_kelvin.sql", "export Kelvin (INSERT... VALUES)")
	outPath := flag.String("out", "migrations/015_cnae_ibge_seed.sql", "migração 015")
	flag.Parse()

	f, err := os.Open(*inPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer f.Close()

	const max = 1024 * 1024
	sc := bufio.NewScanner(f)
	buf := make([]byte, max)
	sc.Buffer(buf, max)

	var flats []flatRow
	bySub := map[string]flatRow{}
	lineNum := 0
	for sc.Scan() {
		lineNum++
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "INSERT INTO") {
			continue
		}
		if !strings.HasPrefix(line, "(") {
			continue
		}
		fields, err := parseTuple(line)
		if err != nil || len(fields) != 6 {
			continue
		}
		sub := normalizeCodigo(fields[4])
		if len(sub) != 7 {
			fmt.Fprintf(os.Stderr, "ignorada linha %d: codigo invalido %q\n", lineNum, fields[4])
			continue
		}
		r := flatRow{
			Secao: strings.TrimSpace(fields[0]), Divisao: strings.TrimSpace(fields[1]),
			Grupo: strings.TrimSpace(fields[2]), Classe: strings.TrimSpace(fields[3]),
			Subcodigo: sub, Denominacao: strings.TrimSpace(fields[5]),
		}
		if prev, ok := bySub[sub]; ok {
			if prev != r {
				fmt.Fprintf(os.Stderr, "conflito subclasse %s: %+v vs %+v\n", sub, prev, r)
				os.Exit(1)
			}
			continue
		}
		bySub[sub] = r
		flats = append(flats, r)
	}
	if err := sc.Err(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	secID := map[string]int{}
	divID := map[string]int{}
	grpID := map[string]int{}
	clsID := map[string]int{}
	nextSec, nextDiv, nextGrp, nextCls := 1, 1, 1, 1

	var secOrder []string
	var divOrder []string
	var grpOrder []string
	var clsOrder []string

	for _, r := range flats {
		if _, ok := secID[r.Secao]; !ok {
			secID[r.Secao] = nextSec
			nextSec++
			secOrder = append(secOrder, r.Secao)
		}
		divK := r.Secao + "\x00" + r.Divisao
		if _, ok := divID[divK]; !ok {
			divID[divK] = nextDiv
			nextDiv++
			divOrder = append(divOrder, divK)
		}
		grpK := divK + "\x00" + r.Grupo
		if _, ok := grpID[grpK]; !ok {
			grpID[grpK] = nextGrp
			nextGrp++
			grpOrder = append(grpOrder, grpK)
		}
		clsK := grpK + "\x00" + r.Classe
		if _, ok := clsID[clsK]; !ok {
			clsID[clsK] = nextCls
			nextCls++
			clsOrder = append(clsOrder, clsK)
		}
	}

	out, err := os.Create(*outPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer out.Close()
	w := bufio.NewWriter(out)

	fmt.Fprintln(w, "-- CNAE 2.3 IBGE — gerado por cmd/gen-cnae-seed")
	fmt.Fprintln(w, "-- Equivale ao JOIN Kelvin: secoes → divisoes → grupos → classes → subclasses")
	fmt.Fprintln(w, "-- IF NOT EXISTS: seguro em bases que já tiveram só 014 (sem estas tabelas).")
	fmt.Fprintln(w)
	writeIBGEDDL(w)
	fmt.Fprintln(w, "BEGIN;")
	fmt.Fprintln(w, "TRUNCATE public.ibge_cnae_secao RESTART IDENTITY CASCADE;")
	fmt.Fprintln(w, "DELETE FROM public.cnae;")
	fmt.Fprintln(w)

	const batch = 40

	writeBatch := func(header string, rows []string) {
		for i := 0; i < len(rows); i += batch {
			j := i + batch
			if j > len(rows) {
				j = len(rows)
			}
			fmt.Fprintf(w, "%s\n%s;\n\n", header, strings.Join(rows[i:j], ",\n"))
		}
	}

	var vsec []string
	for _, nome := range secOrder {
		vsec = append(vsec, fmt.Sprintf("(%d,%s)", secID[nome], pgQuote(nome)))
	}
	writeBatch("INSERT INTO public.ibge_cnae_secao (id, nome) VALUES", vsec)

	var vdiv []string
	for _, k := range divOrder {
		parts := strings.SplitN(k, "\x00", 2)
		sid := secID[parts[0]]
		vdiv = append(vdiv, fmt.Sprintf("(%d,%d,%s)", divID[k], sid, pgQuote(parts[1])))
	}
	writeBatch("INSERT INTO public.ibge_cnae_divisao (id, secao_id, nome) VALUES", vdiv)

	var vgrp []string
	for _, k := range grpOrder {
		parts := strings.SplitN(k, "\x00", 3)
		divK := parts[0] + "\x00" + parts[1]
		gid := grpID[k]
		vgrp = append(vgrp, fmt.Sprintf("(%d,%d,%s)", gid, divID[divK], pgQuote(parts[2])))
	}
	writeBatch("INSERT INTO public.ibge_cnae_grupo (id, divisao_id, nome) VALUES", vgrp)

	var vcls []string
	for _, k := range clsOrder {
		parts := strings.SplitN(k, "\x00", 4)
		divK := parts[0] + "\x00" + parts[1]
		grpK := divK + "\x00" + parts[2]
		cid := clsID[k]
		vcls = append(vcls, fmt.Sprintf("(%d,%d,%s)", cid, grpID[grpK], pgQuote(parts[3])))
	}
	writeBatch("INSERT INTO public.ibge_cnae_classe (id, grupo_id, nome) VALUES", vcls)

	var vsub []string
	for _, r := range flats {
		divK := r.Secao + "\x00" + r.Divisao
		grpK := divK + "\x00" + r.Grupo
		clsK := grpK + "\x00" + r.Classe
		cid := clsID[clsK]
		vsub = append(vsub, fmt.Sprintf("(%d,%s,%s)", cid, pgQuote(r.Subcodigo), pgQuote(r.Denominacao)))
	}
	writeBatch("INSERT INTO public.ibge_cnae_subclasse (classe_id, codigo, nome) VALUES", vsub)

	fmt.Fprintln(w, `-- public.cnae = mesmo resultado do SELECT aninhado do Kelvin`)
	fmt.Fprintln(w, `INSERT INTO public.cnae (secao, divisao, grupo, classe, subclasse, denominacao, ativo)`)
	fmt.Fprintln(w, `SELECT s.nome, d.nome, g.nome, c.nome, sc.codigo::text, sc.nome, true`)
	fmt.Fprintln(w, `FROM public.ibge_cnae_subclasse sc`)
	fmt.Fprintln(w, `JOIN public.ibge_cnae_classe c ON c.id = sc.classe_id`)
	fmt.Fprintln(w, `JOIN public.ibge_cnae_grupo g ON g.id = c.grupo_id`)
	fmt.Fprintln(w, `JOIN public.ibge_cnae_divisao d ON d.id = g.divisao_id`)
	fmt.Fprintln(w, `JOIN public.ibge_cnae_secao s ON s.id = d.secao_id`)
	fmt.Fprintln(w, `ORDER BY sc.codigo;`)
	fmt.Fprintln(w)

	fmt.Fprintln(w, `SELECT setval(pg_get_serial_sequence('public.ibge_cnae_secao', 'id'), COALESCE((SELECT MAX(id) FROM public.ibge_cnae_secao), 1));`)
	fmt.Fprintln(w, `SELECT setval(pg_get_serial_sequence('public.ibge_cnae_divisao', 'id'), COALESCE((SELECT MAX(id) FROM public.ibge_cnae_divisao), 1));`)
	fmt.Fprintln(w, `SELECT setval(pg_get_serial_sequence('public.ibge_cnae_grupo', 'id'), COALESCE((SELECT MAX(id) FROM public.ibge_cnae_grupo), 1));`)
	fmt.Fprintln(w, `SELECT setval(pg_get_serial_sequence('public.ibge_cnae_classe', 'id'), COALESCE((SELECT MAX(id) FROM public.ibge_cnae_classe), 1));`)
	fmt.Fprintln(w, `SELECT setval(pg_get_serial_sequence('public.ibge_cnae_subclasse', 'id'), COALESCE((SELECT MAX(id) FROM public.ibge_cnae_subclasse), 1));`)
	fmt.Fprintln(w)

	fmt.Fprintln(w, "CREATE UNIQUE INDEX IF NOT EXISTS uq_cnae_subclasse ON public.cnae (subclasse);")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "TRUNCATE public.cnae_ibge_hierarquia;")
	fmt.Fprintln(w, "INSERT INTO public.cnae_ibge_hierarquia (subclasse, secao, divisao, grupo, classe)")
	fmt.Fprintln(w, "SELECT subclasse, secao, divisao, grupo, classe FROM public.cnae;")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "COMMIT;")

	_ = w.Flush()
	fmt.Fprintf(os.Stderr, "subclasses (tuplas Kelvin): %d | secoes: %d divisoes: %d grupos: %d classes: %d\n",
		len(flats), len(secOrder), len(divOrder), len(grpOrder), len(clsOrder))
}

func normalizeCodigo(s string) string {
	var b strings.Builder
	for _, ch := range strings.TrimSpace(s) {
		if ch >= '0' && ch <= '9' {
			b.WriteRune(ch)
		}
	}
	x := b.String()
	for len(x) < 7 {
		x = "0" + x
	}
	if len(x) > 7 {
		x = x[len(x)-7:]
	}
	return x
}

func pgQuote(s string) string {
	s = strings.ReplaceAll(s, "'", "''")
	return "'" + s + "'"
}

func parseTuple(line string) ([]string, error) {
	line = strings.TrimRight(line, ",")
	line = strings.TrimRight(line, ";")
	line = strings.TrimSpace(line)
	if !strings.HasPrefix(line, "(") || !strings.HasSuffix(line, ")") {
		return nil, fmt.Errorf("tuple")
	}
	line = line[1 : len(line)-1]

	var fields []string
	var b strings.Builder
	inQuote := false
	for i := 0; i < len(line); i++ {
		c := line[i]
		if c == '\'' {
			if inQuote && i+1 < len(line) && line[i+1] == '\'' {
				b.WriteByte('\'')
				i++
				continue
			}
			inQuote = !inQuote
			continue
		}
		if !inQuote && c == ',' {
			fields = append(fields, strings.TrimSpace(b.String()))
			b.Reset()
			continue
		}
		b.WriteByte(c)
	}
	fields = append(fields, strings.TrimSpace(b.String()))
	return fields, nil
}
