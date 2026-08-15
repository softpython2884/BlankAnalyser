# BlankAnalyser

> Un bac à sable **jetable** pour exécuter un logiciel ou un jeu d'origine douteuse
> sans exposer sa machine — avec un rapport comportemental **lisible en une page**
> plutôt que 400 000 lignes de logs.

![Plateforme](https://img.shields.io/badge/plateforme-Windows%2010%20%2F%2011%20Pro-0078D6?logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Licence](https://img.shields.io/badge/licence-GPL--3.0-blue)
![Sans dépendance](https://img.shields.io/badge/hôte-zéro%20runtime%20à%20installer-brightgreen)
![PRs bienvenues](https://img.shields.io/badge/PRs-bienvenues-ff69b4)

Tu télécharges souvent des logiciels libres ou des jeux indé depuis des
plateformes sans curation, et tu n'as **aucune idée** de ce que cache le code ?
BlankAnalyser te donne un espace isolé pour les **lancer**, les **observer**, et
décider — sans risquer tes clés SSH, tes sessions navigateur ou tes disques.

Construit autour de **Windows Sandbox**, la seule option qui coche les trois
cases à la fois :

- 🛡️ **vraie frontière de sécurité** — une VM matérielle (Hyper-V), pas un bridage ;
- 📉 **zéro téléchargement** — réutilise l'image Windows déjà sur le disque
  (~100 Mo, démarre en 10 s), pensé pour une **connexion limitée** ;
- 🪶 **léger** — tourne sur un portable modeste (≈ 8 Go de RAM).

## Sommaire

- [Démarrage en 30 secondes](#utilisation-simple--blankanalysercmd)
- [Le modèle d'isolation](#le-modèle)
- [Installation](#installation-une-fois)
- [Utilisation en ligne de commande](#utilisation-en-ligne-de-commande)
- [Ce que donne le rapport](#ce-que-le-rapport-te-donne)
- [Mode furtif (anti-détection de VM)](#mode-furtif--anti-détection-de-vm)
- [Limites — à lire](#limites--à-lire)
- [Repli quand la sandbox ne suffit pas](#repli-quand-la-sandbox-ne-suffit-pas)
- [Structure du dépôt](#fichiers)
- [Contribuer & licence](#contribuer)

---

## Le modèle

Trois zones, une seule direction de confiance :

```
        HÔTE                          SANDBOX (jetable)
  ┌──────────────────┐           ┌──────────────────────┐
  │ quarantine\      │ ──── RO ──►  C:\BA\in            │
  │   la cible       │           │                      │
  │                  │           │  copiée → C:\Work    │
  │ cache\           │ ──── RO ──►  C:\BA\cache         │
  │   redists+outils │           │  installés au boot   │
  │                  │           │                      │
  │ guest\           │ ──── RO ──►  C:\BA\kit           │
  │   les scripts    │           │                      │
  │                  │           │       ▼ EXÉCUTION    │
  │ reports\         │ ◄─── RW ───  C:\BA\out           │
  │   .md seulement  │           │       rapport        │
  └──────────────────┘           └──────────────────────┘
   Tout le reste de C:\ , les clés SSH, le profil navigateur
   ne sont PAS montés : ils n'existent pas pour la sandbox.
```

**La cible est montée en lecture seule.** Le programme ne peut même pas réécrire
son propre fichier. Le seul canal retour est `reports\`, et il ne reçoit que du
Markdown généré par nos scripts.

---

## Utilisation simple : `BlankAnalyser.cmd`

**Double-clique `BlankAnalyser.cmd`.** C'est tout. Un menu s'ouvre et gère
l'ensemble :

```
  [ OK ] Windows Sandbox                   installé
  [ !! ] Outil d'observation (Sysmon)      MANQUANT  -> option 1
  [ OK ] Fichiers en quarantaine           1
  [ !! ] RAM libre                         1.4 Go

   1. Installer / réparer BlankAnalyser        (une seule fois)
   2. Ajouter un fichier à analyser
   3. Triage rapide                          (sans l'exécuter)
   4. LANCER dans le bac à sable           (exécution observée)
   5. Lire les rapports
   6. Ouvrir le dossier quarantaine
   7. Aide
```

L'état en haut te dit toujours quoi faire ensuite. L'option 1 demande l'élévation
administrateur toute seule.

Tu peux aussi **glisser-déposer** un `.zip` ou un `.exe` directement sur
`BlankAnalyser.cmd` : il part en quarantaine et le menu s'ouvre dessus.

Le reste de ce document décrit le fonctionnement interne et l'usage en ligne de
commande, si tu veux scripter ou comprendre ce qui se passe.

---

## Installation (une fois)

Via le menu : **option 1**. En ligne de commande :

```powershell
# PowerShell EN ADMINISTRATEUR
.\Setup-Host.ps1
```

Active Windows Sandbox (redémarrage requis la première fois) et télécharge
Sysmon + Procmon (~10 Mo, une seule fois pour toujours).

Ensuite, dépose une fois pour toutes tes runtimes dans `cache\redist\` :

| Fichier | URL | Taille |
|---|---|---|
| `vc_redist.x64.exe` | https://aka.ms/vs/17/release/vc_redist.x64.exe | ~25 Mo |
| `vc_redist.x86.exe` | https://aka.ms/vs/17/release/vc_redist.x86.exe | ~14 Mo |
| `dotnet-runtime-*.exe` | https://dotnet.microsoft.com/download | si jeu .NET |

**C'est ça qui règle le problème « faut tout réinstaller à chaque fois ».** Ils
sont réinstallés automatiquement dans chaque sandbox, depuis le disque local,
sans jamais retoucher à ta connexion.

---

## Utilisation en ligne de commande

```powershell
# 1. Télécharge le jeu avec ton navigateur habituel, dans quarantine\
#    (télécharger n'exécute rien — c'est lancer qui est dangereux)

# 2. Triage statique, sans jamais l'exécuter
.\Triage-Host.ps1 -Target .\quarantine\jeu.zip

# 3. Exécution observée
.\New-SandboxRun.ps1 -Target jeu.zip              # réseau coupé (défaut)
.\New-SandboxRun.ps1 -Target jeu.zip -Gpu         # si le jeu a besoin de la 3D
.\New-SandboxRun.ps1 -Target jeu.zip -Gpu -Network
```

Dans la sandbox : le bootstrap installe tout, arme Sysmon, extrait le jeu dans
`C:\Work\target`. Tu joues **quelques minutes en interagissant vraiment**
(menus, sauvegarde, options — beaucoup de charges utiles attendent une action),
puis tu double-cliques `RAPPORT.cmd` sur le bureau.

Le rapport atterrit dans `reports\` sur ton PC et survit à la fermeture.

### Ordre recommandé

1. **Premier passage réseau coupé.** Tu vois ce qu'il fait au disque et au
   registre, sans lui donner de canal de sortie.
2. **Second passage réseau ouvert**, si le premier est propre. Là tu vois qui il
   appelle. Le rapport DNS est la partie la plus parlante.

---

## Ce que le rapport te donne

Au lieu des 400 000 lignes de Procmon, une page :

- **Processus lancés** avec ligne de commande et parent — un jeu qui lance
  `powershell -enc ...` ou `cmd /c`, c'est fini, tu as ta réponse
- **Domaines DNS interrogés** — la lecture la plus directe de « qui il appelle »
- **Fichiers écrits hors du dossier du jeu**, et fichiers supprimés
- **Clés de registre de persistance** (Run, Services, Winlogon, IFEO)
- **Accès disque brut** — c'est *exactement* la signature du truc qui t'a détruit
  un disque : écrire sur le périphérique en contournant le système de fichiers
- **Injection de code, accès à lsass, chargement de driver, process hollowing**
- **Verdict** trié CRITIQUE / HAUTE / MOYENNE

Sysmon plutôt que Procmon parce que Sysmon produit des événements *structurés et
déjà filtrés au niveau du noyau* : quelques centaines d'événements utiles là où
Procmon en produit des centaines de milliers indifférenciés.

---

## Mode furtif — anti-détection de VM

Beaucoup de malwares vérifient s'ils tournent dans une machine d'analyse et
**restent inertes** s'ils en détectent une, pour passer pour inoffensifs. Le mode
furtif applique la contre-mesure classique des bacs à sable professionnels : il
maquille l'environnement pour pousser ces échantillons à se dévoiler.

```powershell
.\New-SandboxRun.ps1 -Target jeu.zip -Stealth
```

Ce qu'il fait, entièrement **depuis l'intérieur** de la sandbox, sans pilote :

- peuple la session de faux documents anti-datés (tue le signal « session vide ») ;
- **renomme le service d'observation** — plus de service ni de processus nommé
  « Sysmon » ; Procmon n'est pas lancé ;
- simule une présence humaine (petits mouvements de souris en tâche de fond) ;
- épaissit la liste des processus utilisateur.

> [!WARNING]
> **Le mode furtif ne rend PAS la VM invisible, et il ne le peut pas.** Le
> processeur virtualisé (bit hyperviseur du `CPUID`) et le compte imposé
> `WDAGUtilityAccount` trahissent toujours Windows Sandbox à un échantillon
> déterminé. Un rapport propre en mode furtif est un indice **un peu** plus
> solide — **jamais une preuve d'innocuité.**
>
> Le détail de ce qui est masquable et de ce qui ne le sera jamais est dans
> **[docs/ANTI-VM.md](docs/ANTI-VM.md)** — lis-le avant de te fier au mode furtif.

---

## Limites — à lire

**Ce que ça protège vraiment.** L'isolation est réelle : Windows Sandbox est une
VM à frontière matérielle, pas un chroot. Un wiper à l'intérieur détruit un
disque virtuel jetable. Tes clés SSH et ton profil navigateur ne sont pas montés.
Ça, c'est solide.

**Ce que l'analyse ne prouve pas.** Un rapport propre ne veut *pas* dire « sain » :

- Beaucoup de malwares **détectent la sandbox** et restent inertes.
- Les charges utiles **retardées** (des jours) ou **conditionnelles** (date,
  présence d'un wallet crypto) ne se déclencheront jamais en 3 minutes.
- Le rapport dit ce qui **s'est passé**, pas ce qui **aurait pu** se passer.

Autrement dit : l'isolation est une garantie, la détection est un indice.

**Ce qui ne marchera pas dans la sandbox :**

- Jeux avec anti-triche noyau (EAC, BattlEye) — refusent de tourner en VM
- Jeux 3D lourds — le vGPU est paravirtualisé, et sur 8 Go de RAM partagée avec
  un iGPU Radeon 610M, tu es limité au 2D / petit Unity / Godot
- DRM lié au matériel

Si le jeu est trop lourd pour la sandbox, **n'abandonne pas l'isolation pour
autant** — utilise le repli ci-dessous plutôt que de le lancer sur ton compte.

---

## Repli quand la sandbox ne suffit pas

Par ordre de solidité décroissante :

1. **Compte Windows local séparé, non-administrateur.** C'est une vraie frontière
   de sécurité Windows : un autre compte ne peut pas lire `C:\Users\<toi>\.ssh`
   ni ton profil navigateur. Perfs natives, GPU natif. Combine avec
   *Accès contrôlé aux dossiers* (protection anti-rançongiciel de Defender).
2. **Sandboxie-Plus** — virtualisation fichiers/registre au niveau utilisateur,
   perfs natives, très bon journal d'accès intégré. **Mais ce n'est pas une
   frontière de sécurité** : un exploit noyau en sort. Bon contre l'accident,
   faible contre l'attaque ciblée.
3. **Rien.** Alors au minimum : une **sauvegarde débranchée physiquement**. C'est
   la seule chose qui répond à « ça a détruit tout le disque ». Aucun sandbox ne
   remplace ça.

---

## Fichiers

| | |
|---|---|
| **`BlankAnalyser.cmd`** | **le lanceur — double-clique celui-ci** |
| `Menu.ps1` | le menu interactif (UTF-8 **avec BOM** obligatoire, sinon PS 5.1 casse les accents) |
| `Setup-Host.ps1` | prépare l'hôte (admin, une fois) |
| `Triage-Host.ps1` | analyse statique sans exécution |
| `New-SandboxRun.ps1` | génère le `.wsb` et lance la sandbox |
| `guest/Guest-Bootstrap.ps1` | démarrage automatique dans la sandbox |
| `guest/Guest-Report.ps1` | génère le rapport lisible |
| `guest/Guest-FallbackMonitor.ps1` | moniteur sans driver, si Sysmon échoue |
| `guest/Guest-Realism.ps1` | couche de camouflage du mode furtif |
| `guest/sysmon-blankanalyser.xml` | config Sysmon (capture large, filtrage à la lecture) |
| `docs/ANTI-VM.md` | ce que le mode furtif masque et ce qu'il ne masquera jamais |
| `SECURITY.md` | garanties, limites, signalement de faille |
| `CONTRIBUTING.md` | comment contribuer |

---

## Contribuer

Les contributions sont bienvenues — le projet peut aider pas mal de monde dans la
même situation. Lis [CONTRIBUTING.md](CONTRIBUTING.md) : les principes sont
**rester léger** (cible : portable 8 Go, connexion limitée) et **rester honnête**
sur ce qui est protégé. Une CI (PSScriptAnalyzer) vérifie chaque script à chaque
push.

Pistes utiles : meilleures heuristiques de rapport, règles Sysmon plus fines,
camouflage furtif réaliste **et documenté**, et surtout une **traduction anglaise**
du README pour élargir l'audience.

## Sécurité

Le rapport de détection est un **indice**, pas une preuve — voir
[SECURITY.md](SECURITY.md) et [docs/ANTI-VM.md](docs/ANTI-VM.md). Pour signaler une
faille dans BlankAnalyser lui-même, passe par un *security advisory* privé plutôt
qu'une issue publique.

## Licence

[GPL-3.0](LICENSE). Tu peux réutiliser, modifier et redistribuer, à condition que
les projets dérivés restent eux aussi libres sous GPL.

---

> ⚠️ **Rappel final.** Aucun bac à sable ne remplace une **sauvegarde débranchée
> physiquement** : c'est la seule vraie réponse au logiciel qui efface un disque.
> BlankAnalyser réduit le risque, il ne le supprime pas.
