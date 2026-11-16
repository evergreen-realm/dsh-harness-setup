# DeepSeek Harness Setup & Starter Kit

One-command setup repository to configure **DeepSeek Harness** with the **Evergreen Memory Plugin**, multi-model fallback routing, and cost-optimized defaults.

## Features

- **Zero-Dependency Memory Plugin**: Bundles EverOS + GBrain graph retrieval with local context injection.
- **Cost-Optimized Model Lineup**: Configured for DeepSeek Flash with high prompt-cache hit rates + Ollama Cloud fallback routing.
- **Update-Proof Persistence**: Keeps plugins, session indexes, and configurations inside permanent user paths (`~/.dsh/`) that survive automatic client updates.
- **Automated Anti-Corruption Tool**: Includes `dsh-session-sanitizer.py` to prevent and repair mid-session format discrepancies.
- **No Leaked Credentials**: Safe to share — contains zero credentials or private session histories.

---

## Quick Start (Single Command)

Open **PowerShell** on Windows and run:

```powershell
git clone --recurse-submodules https://github.com/evergreen-realm/dsh-harness-setup.git
cd dsh-harness-setup
.\setup.ps1
```

### What `setup.ps1` Does:
1. Validates Node.js (>= 22.6.0) and Git.
2. Checks for or assists in downloading the official DeepSeek Harness app.
3. Compiles the memory plugin using Node's native type stripper (no `npm install` needed).
4. Creates and configures `~/.dsh/profiles/desktop/` with `cordis.patch.yml`.
5. Symlinks the plugin into the Harness runtime bundle.
6. Prompts optionally for `OLLAMA_API_KEY` (if using fallback models).
7. Launches DeepSeek Harness ready to code!

---

## Repository Structure

```
dsh-harness-setup/
├── plugins/
│   └── dsh-memory-plugin/     # Git Submodule -> evergreen-realm/dsh-memory-plugin
├── profile-templates/
│   ├── package.json.template  # Profile dependencies template
│   ├── cordis.yml             # Base empty profile specification
│   ├── cordis.patch.yml       # Model providers, fallbacks & UI configurations
│   └── pnpm-workspace.yaml    # Profile workspace configuration
├── setup.ps1                  # Primary Windows setup script
├── .env.example               # Example environment variables
├── COSTS.md                   # Model pricing & cost-optimization breakdown
└── README.md
```

---

## Prerequisites

- **Windows 10 / 11 (x64)**
- **Node.js >= 22.6.0** (check with `node -v`)
- **Git** (check with `git --version`)
- A **DeepSeek Account** (sign in via app UI on first launch)

---

## Troubleshooting

### Session History Error ("system/message requires a protected first surface head")
If a session encounters a format violation due to a network drop or rapid turn interrupt, run the bundled sanitizer:

```powershell
python ~/.dsh/scripts/dsh-session-sanitizer.py
```
Then restart DeepSeek Harness.

---

## License

MIT License — Copyright (c) 2026 Evergreen Realm
