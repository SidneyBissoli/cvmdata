# Dados pessoais no espelho e nas edições do Zenodo

Decisão do dono em 2026-11-08, depois de duas pesquisas (CPF e nome).
Não é parecer jurídico; a pergunta aberta a advogado, se o dono quiser
fazê-la, é a da seção "O que continua em aberto".

## O que se decidiu

Igual no espelho (GitHub Releases) e nas edições do Zenodo:

| Dado | Tratamento | Por quê |
|---|---|---|
| CPF, onde estiver | Máscara da Receita: `***.456.789-**` | Sobra para a finalidade: a máscara com o nome identifica a pessoa entre tabelas |
| Documento estrangeiro em coluna de CPF | `***` | Mesmo motivo, sem máscara parcial possível |
| `data_nascimento` | Só o ano, na coluna `ano_nascimento` (inteiro) | Nome + CPF + nascimento é o trio de confirmação de identidade; a pesquisa usa idade |
| Nomes | Como a CVM publica | O nome é o conteúdo da divulgação (Res. CVM 80, itens 7.5 e 7.6) |
| Biografias e declarações | Como a CVM publica, salvo o número de CPF citado nelas | Divulgação exigida; editar o texto falsificaria o que ele afirma |
| Contagens de raça, gênero e deficiência | Como a CVM publica | Por órgão, ninguém identificado |

`source = "cvm"` continua lendo tudo da CVM sem tocar em nada. O
tratamento mora só no ETL (`inst/etl/util-privacy.R`).

É a única exceção à regra "se vem da CVM, fica como na CVM", e vale para
o que o pacote **redistribui**: quem lê da CVM recebe da CVM.

## Por quê

O depósito do Zenodo é público e permanente, e o depositante responde
sozinho por ele (Termos do Zenodo). A CVM publica por dever legal, e o
art. 7º, §§ 3º, 4º e 7º da LGPD permite tratar dado tornado público
respeitando a finalidade da publicação; o art. 10, § 1º limita o legítimo
interesse aos dados estritamente necessários. O teste do necessário dá
resultados opostos para o nome e para o CPF:

- **Nome:** tirá-lo desfaz a finalidade (dizer ao mercado quem governa a
  companhia). O padrão federal é nome completo com CPF descaracterizado
  (Parecer 001/2021 e Despacho 093/2022 da CONJUR-CGU/AGU; dados abertos
  do CNPJ da Receita). O STF apoia a publicação de nomes de quem presta
  contas (Tema 483) e rejeita um direito geral ao esquecimento (Tema 786).
- **CPF:** a máscara faz o mesmo serviço. Medido no FRE 2021–2025: 10.687
  CPFs distintos dão 10.561 máscaras; 123 máscaras são compartilhadas, e
  máscara + nome não junta nenhuma pessoa diferente.

## O que a medição acrescentou (2026-11-08)

A varredura de todos os parquets, valor a valor, achou mais do que as "14
colunas" da conta anterior. Valores alterados no `-latest`, histórico incluído:

| Onde | Valores |
|---|---|
| Colunas `cpf*` (13, em 9 tabelas do FCA e do FRE) | 556.858 |
| `documento_pessoa_relacionada`, `documento_parte_relacionada` (nome não diz CPF) | 2.406 |
| Biografias (`experiencia_profissional`) | 2.364 |
| Outros textos livres (21 colunas) | 201 |
| `data_nascimento` (2 tabelas) | 131.129 |

Nas colunas `cpf*` há também passaportes (`AA999999`), e em colunas de
CNPJ, CPFs preenchidos com zeros. Por isso a regra olha o valor, não só o
nome da coluna, e usa o dígito verificador quando o formato não basta:
`999.999.999-99` é CPF mesmo com dígito errado, e 11 dígitos soltos em
texto só contam se o dígito fechar (os do `motivo_reapresentacao` do ITR
não fecham nenhum: não são CPF e ficam).

## Como funciona

- `mirror_apply_privacy()` é idempotente. O estágio 02 aplica antes de
  gravar; o 03 aplica também ao parquet da release anterior **antes de
  comparar**, então a mudança de regra não parece reapresentação e nenhuma
  linha sem máscara chega ao histórico. Prova em dado real: 871 partições
  comparadas, 0 linha falsa de histórico.
- `privacy_rule` no `__source_hash.json`: a primeira publicação sob a
  regra reescreve os ativos de histórico do `-latest`.
- Guardas que param a publicação: `mirror_privacy_counts()` no 02b e no 06
  ("a regra ainda mudaria algo?"). Só nomes de coluna e contagens vão ao
  log.
- `repair-personal-data.R`: as fotos datadas antigas são reescritas no
  lugar (os ponteiros das fotos seguintes dependem delas, então não se
  apagam), seguidas de `repair-snapshot-digests.R`.

## O que continua em aberto

- **Dados de contato** (`cad/*_resp`, `fca/dri`, `fca/departamento_acionistas`,
  `fca/endereco`): e-mail, telefone e endereço do responsável. Em geral são
  corporativos, mas cerca de 1.150 e-mails são de webmail (medido
  2026-11-08). Fora desta decisão.
- **O que não se limpa daqui:** o histórico do git (fixture
  `fca_cia_aberta_2024.zip`, até esta mudança, com 4 CPFs reais), os
  depósitos do sandbox do Zenodo e as cópias que terceiros já baixaram.
- **Documento que não seja CPF em texto livre** (RG, por exemplo): não há
  formato confiável para achar.
- Se o dono consultar advogado, a pergunta é se este desenho basta para o
  depósito permanente, e como responder a um pedido do art. 18 da LGPD
  sobre um registro do Zenodo que não se apaga.
