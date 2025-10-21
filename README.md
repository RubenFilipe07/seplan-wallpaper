# Como rodar 
Este repositório contém scripts PowerShell que geram um papel de parede com as notícias. Aqui está o mínimo para executar:

## Pré-requisitos

- Windows PowerShell
- Ter `fundo.png` no diretório 
- Conexão com a internet para baixar notícias miniaturas
- Permissão para executar scripts (use `-ExecutionPolicy Bypass` se necessário)

Como executar:

Abra um PowerShell na pasta do projeto e execute:

```powershell
# Exemplo: versão simples
.\a5.ps1

# Caso o código acima não funcione
powershell -NoProfile -ExecutionPolicy Bypass -File .\a5.ps1
```

Saída

- O arquivo de saída será criado na pasta atual (por exemplo `wallpaper.png` ou `wallpaper_melhorado.png`).
- Os downloads temporários ficam em `thumbs/` e são removidos automaticamente pelos scripts

# Notícias
Exibindo notícias de: https://www.seplan.rn.gov.br/wp-json/wp/v2/materia?per_page=20&page=1&_embed=1

São exibidos os 3 itens mais recentes.



