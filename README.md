# EvilAgent 🤖

Docker prostředí pro běh **multiagentního systému** podle webináře Petra Ludwiga
*„AI agenti jako budoucnost práce"*. V jednom izolovaném kontejneru jsou
předinstalované nástroje:

| Nástroj | Role | Příkaz |
|---|---|---|
| **Codex** (OpenAI) | meta-agent, správce ostatních | `codex` |
| **Claude Code** (Anthropic) | vývoj / agent | `claude` |
| **Google Antigravity** | agent (na serveru přes API) | `agy` |
| **Hermes Agent** (Nous Research) | agent + gateway | `hermes` |
| **OpenClaw** | ucelené agentní řešení | `openclaw` |
| **Agent2Telegram** | most agent ↔ Telegram | `agent2telegram` |
| **AgentsMonitor** | monitoring + automatická obnova | `agentsmon` |
| **Whisper** (OpenAI / faster-whisper) | hlasové ovládání (Voice2Text) | `voice2text` |

---

## 🔐 Bezpečnostní model – čtěte jako první

Prezentace doporučuje spouštět agenty přímo na serveru s **vypnutými pojistkami**
(`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`,
`sudo NOPASSWD` na `reboot`/`dd`, hlavní agent se správou celého serveru napojený
na Telegram). To je pohodlné, ale na běžném serveru **nebezpečné** – agent s chybou
nebo pod vlivem prompt-injection má plnou kontrolu nad strojem.

**Řešení tohoto projektu: kontejner je bezpečnostní hranice.**
Agenti uvnitř běží klidně „nespoutaně", protože jsou zavření v izolaci:

- ✅ běží jako **neprivilegovaný uživatel `agent`** (ne root),
- ✅ **`no-new-privileges`** + **zahozené všechny Linux capabilities** (kromě nutného minima) → uvnitř nejde eskalovat na root, `sudo` je záměrně zablokované,
- ✅ **žádný přístup k Docker socketu**, **žádný host network**, **žádný `privileged`** → agent se nedostane na hostitele ani k ostatním kontejnerům,
- ✅ **limity CPU / RAM / počtu procesů** → zběsilý nebo fork-bombující agent nepoloží stroj,
- ✅ **tajemství (API klíče, tokeny) jen v `.env`**, nikdy ne v image ani v gitu,
- ✅ vlastní **bridge síť** oddělená od hostitele,
- ✅ binárky nástrojů jsou v image, data v oddělených **volumes** (snadná záloha i audit).

**Co to znamená prakticky:** agenti mohou fungovat plně automatizovaně
(24/7, přes Telegram, s bypassem schvalování), ale nejhorší, co se může stát,
je poškození obsahu kontejneru – ten kdykoli přestavíte a data obnovíte ze zálohy.

> **Doporučení navíc:** kontejner provozujte na samostatném serveru/VM, dávejte
> agentům jen tokeny s minimem oprávnění (ne hlavní účet), a citlivé repozitáře
> připojujte read-only. Odchozí síť lze dále omezit (viz *Zpřísnění sítě* níže).

---

## 🚀 Rychlý start

Předpoklady: **Docker** + **Docker Compose** na hostiteli.

```bash
# 1) Konfigurace
cp .env.example .env        # klíče jsou volitelné – většina nástrojů se přihlašuje interaktivně

# 2) Sestavení image (stáhne a nainstaluje všechny nástroje)
docker compose build        # nebo: make build

# 3) Start (běží na pozadí, restart-policy: unless-stopped)
docker compose up -d        # nebo: make up

# 4) Vstup do kontejneru jako agent
make shell                  # nebo: docker compose exec -u agent evilagent bash -l
```

Po startu kontejner jen „drží linku" (běží prázdný tmux `main`). Agenty
**nakonfigurujete a spustíte ručně** – viz níže.

---

## ⚙️ První konfigurace nástrojů (ručně po startu)

Vstupte dovnitř (`make shell`) a nastavte, co potřebujete. Přihlášení a konfigurace
se ukládají do trvalých volumes, takže **stačí jednou**.

### Codex (meta-agent)
```bash
codex                      # interaktivní přihlášení (device flow / API klíč)
# spuštění jako trvalý agent v tmuxu:
tmux new -s master 'codex --dangerously-bypass-approvals-and-sandbox'
#   odpojení: Ctrl+B, pak D        znovupřipojení: tmux attach -t master
```
> `--dangerously-*` je zde OK – hranicí je kontejner, ne váš stroj.

### Agent2Telegram (napojení Codexu na Telegram)
```bash
# do .env doplňte TELEGRAM_BOT_TOKEN a TELEGRAM_CHAT_ID (od @BotFather), pak:
agent2telegram connect
```

### Claude Code
```bash
claude                     # přihlášení (předplatné) nebo ANTHROPIC_API_KEY v .env
claude --dangerously-skip-permissions
```

### Hermes Agent
```bash
hermes config set API_SERVER_KEY "$(openssl rand -hex 24)"
hermes config set API_SERVER_ENABLED true
nohup hermes gateway run --replace > ~/hermes.log 2>&1 &
```

### OpenClaw
```bash
openclaw onboard           # zkopírujte kód do prohlížeče, URL vložte zpět
nohup openclaw gateway > ~/openclaw.log 2>&1 &
```

### AgentsMonitor (monitoring + automatická obnova)
```bash
agentsmon add              # přidá běžící agenty pod dohled
agentsmon new              # založí nového hlídaného agenta
```

### Google Antigravity
```bash
agy --dangerously-skip-permissions
```
> Na serveru **nejde přes předplatné**. Použijte Google Cloud projekt / `GEMINI_API_KEY`
> v `.env`. Google Cloud dává na start $300 kreditu na 3 měsíce zdarma.

### Hlasové ovládání (Whisper)
Kontejner nemá mikrofon – audio nahrajete do `~/workspace` a přepíšete:
```bash
voice2text ~/workspace/nahravka.m4a small cs
```
Text pak předáte agentovi. Modely se stáhnou jednou do `~/.cache/whisper`.
Pro nejlepší češtinu lze místo Whisperu použít **ElevenLabs Scribe** přes API
(`ELEVENLABS_API_KEY` v `.env`, umí i Text2Voice).

---

## 💾 Perzistence dat

Vše důležité je v pojmenovaných Docker **volumes** a **přežije restart i rebuild image**:

| Volume | Obsah |
|---|---|
| `codex`, `claude`, `hermes`, `openclaw`, `agent2telegram`, `agentsmon` | konfigurace a přihlášení jednotlivých nástrojů |
| `config` | XDG konfigurace, `gcloud` |
| `cache` | mj. stažené Whisper modely |
| `ssh` | SSH klíče agenta |
| `workspace` | pracovní adresář / repozitáře / data agentů |

Binárky nástrojů **naopak nejsou** ve volumes – jsou v image. Díky tomu
`docker compose down` **nesmaže data** a aktualizace nepřepíše konfiguraci.

> Data smažete jen explicitně: `docker compose down -v` (pozor, nevratné).

---

## 🔄 Aktualizace

Nástroje i systém se aktualizují **přestavením image**; data ve volumes zůstávají:

```bash
make update
# = záloha  →  docker compose build --pull  →  up -d  →  refresh nástrojů v kontejneru
```

Ruční varianta:
```bash
docker compose build --pull && docker compose up -d
```

Jednotlivé nástroje jsou definované v [`scripts/install-tools.sh`](scripts/install-tools.sh) –
verze / zdroje upravíte na jednom místě. Aktualizaci nástrojů bez rebuildu:
```bash
make tools     # spustí install-tools.sh uvnitř běžícího kontejneru
```

---

## 🗄️ Zálohování a obnova

```bash
make backup                                   # -> backups/<datum>/agent-data.tar.gz
./scripts/restore.sh backups/2026.../agent-data.tar.gz
```
Zálohuje se veškerá konfigurace, přihlášení i `workspace` do jednoho archivu.

---

## 🧰 Časté příkazy (`make help`)

| Příkaz | Význam |
|---|---|
| `make up` / `make down` | start / stop (data zůstanou) |
| `make shell` | shell jako `agent` |
| `make root-shell` | shell jako `root` (správa) |
| `make attach` | připojení ke sdílenému tmux `main` |
| `make logs` | sledování logů |
| `make health` | přehled dostupnosti nástrojů |
| `make tools` | reinstalace / update nástrojů |
| `make update` | kompletní aktualizace |
| `make backup` | záloha dat |

---

## 🔒 Zpřísnění sítě (volitelné, pokročilé)

Agenti potřebují ven kvůli API modelů, takže síť nelze úplně zavřít. Chcete-li
přesto omezit odchozí provoz jen na povolené domény, nasaďte před kontejner
**egress proxy** (např. Squid s allow-listem) a přesměrujte přes ni `HTTP(S)_PROXY`.
Kompletní uzavření sítě (`networks: internal: true`) je připravené v
`docker-compose.yml` jako komentář – použitelné jen pro agenty bez potřeby internetu.

---

## ❓ Řešení potíží

- **Nástroj chybí (`MISS`) po buildu.** Instalátory Agent2Telegram / Hermes /
  OpenClaw / AgentsMonitor / Antigravity pocházejí z prezentace a jejich URL se
  mohou lišit nebo být dočasně nedostupné. Build je **záměrně nechá selhat
  potichu** (aby prošly ostatní nástroje). Ověřte/aktualizujte URL v
  [`scripts/install-tools.sh`](scripts/install-tools.sh) a spusťte `make tools`.
  Codex a Claude Code se instalují přes npm a měly by být vždy dostupné.
- **`sudo` uvnitř nefunguje.** Správně – je záměrně zablokované
  (`no-new-privileges`). Pro správu použijte `make root-shell`, nebo trvalé
  změny přidejte do `Dockerfile` a přestavte image.
- **Agent nemá přístup k souboru na hostiteli.** Kontejner nemá bind-mounty
  hostitele (bezpečnost). Data dejte do volume `workspace`
  (`docker compose cp soubor evilagent:/home/agent/workspace/`).

---

## 📁 Struktura projektu

```
.
├── Dockerfile                 # image: Ubuntu + Node + Python + nástroje
├── docker-compose.yml         # služba, bezpečnost, volumes, limity
├── .env.example               # šablona tajemství/konfigurace
├── Makefile                   # zkratky
├── README.md
└── scripts/
    ├── install-tools.sh       # instalace/aktualizace CLI nástrojů (build i runtime)
    ├── entrypoint.sh          # init volumes + drop na uživatele agent
    ├── voice2text.sh          # Whisper přepis audio -> text
    ├── update.sh              # záloha + rebuild + refresh
    ├── backup.sh              # záloha dat agentů
    └── restore.sh             # obnova ze zálohy
```
