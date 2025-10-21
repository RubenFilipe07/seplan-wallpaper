# Como rodar 
Este repositório contém scripts PowerShell que geram um papel de parede com as notícias. Aqui está o mínimo para executar:

## Pré-requisitos

- Windows PowerShell
- Ter `fundo.png` no diretório 
- Conexão com a internet para baixar notícias e miniaturas
- Permissão para executar scripts (use `-ExecutionPolicy Bypass` se necessário)

Como executar:

Abra um PowerShell na pasta do projeto e execute:

```powershell
# Exemplo: versão simples
.\wallpaper-gerador.ps1

# Caso o código acima não funcione
powershell -NoProfile -ExecutionPolicy Bypass -File .\wallpaper-gerador.ps1
```

Saída

- O arquivo de saída será criado na pasta atual (por exemplo `wallpaper.png` ou `wallpaper_melhorado.png`).
- Os downloads temporários ficam em `thumbs/` e são removidos automaticamente pelos scripts

# Notícias
Exibindo notícias de: https://www.seplan.rn.gov.br/wp-json/wp/v2/materia?per_page=20&page=1&_embed=1

São exibidos os 3 itens mais recentes.

# Imagem

Os exemplos abaixo mostram o arquivo de fundo (`fundo.png`) que você deve manter na pasta do projeto e um exemplo do papel de parede gerado (`wallpaper.png`).

Imagem de exemplo do arquivo de fundo (fundo.png):

![Fundo de exemplo](./fundo.png)

Imagem de exemplo do papel de parede gerado (wallpaper.png):

![Papel de parede gerado](./wallpaper.png)

Explicação rápida:

- `fundo.png`: imagem base que será usada como plano de fundo para compor o papel de parede. Deve estar no mesmo diretório do script antes de rodar.
- `wallpaper.png`: saída gerada pelo script. O nome exato depende de qual versão do script foi executada.
- `thumbs/`: pasta temporária onde são baixadas as miniaturas das notícias; os arquivos são removidos automaticamente pelo script.
- Permissões: se o PowerShell bloquear a execução, rode com `-ExecutionPolicy Bypass` ou ajuste a política de execução.

