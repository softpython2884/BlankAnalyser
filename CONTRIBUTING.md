# Contribuer à BlankAnalyser

Merci de vouloir aider ! Le projet vise à rester **simple, léger et honnête** :
un outil qu'une personne non spécialiste peut lancer sans se mentir sur ce qu'il
protège.

## Principes du projet

1. **Léger d'abord.** La cible est un portable modeste (≈ 8 Go de RAM) avec une
   connexion limitée. Toute dépendance lourde ou tout téléchargement récurrent
   doit être justifié.
2. **Honnête sur les limites.** On ne vend jamais une garantie qu'on n'a pas.
   Si une fonctionnalité a un angle mort (ex. le mode furtif), il est documenté
   noir sur blanc, pas caché.
3. **Zéro dépendance exotique.** PowerShell 5.1 (livré avec Windows) + outils
   Sysinternals. Pas de runtime à installer côté hôte.

## Mettre la main à la pâte

- **Windows / PowerShell 5.1** est l'environnement de référence.
- Après modification d'un script, vérifie qu'il *parse* :
  ```powershell
  [System.Management.Automation.Language.Parser]::ParseFile(
      '.\chemin\script.ps1', [ref]$null, [ref]([ref]$errs).Value)
  ```
  La CI le fait automatiquement avec **PSScriptAnalyzer** à chaque push/PR.
- **`Menu.ps1` doit rester en UTF-8 AVEC BOM.** Sans le BOM, PowerShell 5.1 lit
  les accents en ANSI et l'affichage casse. Vérifie que les 3 premiers octets
  sont `EF BB BF` après édition.
- Les scripts `guest\*` s'exécutent **dans** la sandbox ; les autres sur l'hôte.
  Garde cette frontière nette.

## Style

- Français dans les messages destinés à l'utilisateur (c'est la langue du
  projet), commentaires en français aussi.
- Fonctions en `Verbe-Nom` PowerShell, indentation 4 espaces.
- Un commit = une idée. Message à l'impératif.

## Idées bienvenues

- Un jeu de règles Sysmon plus fin sans exploser le volume d'événements.
- De meilleures heuristiques de rapport (moins de faux positifs).
- Du camouflage furtif **réaliste et documenté** — sans jamais sur-promettre.
- Traductions du README (en priorité anglais) pour élargir l'audience.

Avant un gros changement, ouvre une *issue* pour en discuter. Ça évite de coder
dans le vide.
