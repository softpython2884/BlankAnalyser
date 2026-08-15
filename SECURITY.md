# Politique de sécurité

## Ce que BlankAnalyser garantit — et ce qu'il ne garantit pas

Lis ceci avant de te fier au résultat d'une analyse.

**Ce qui est une garantie solide : l'isolation.** Windows Sandbox est une machine
virtuelle à frontière matérielle (Hyper-V). Un programme exécuté à l'intérieur
n'a pas accès à l'hôte : ni tes clés SSH, ni ton profil navigateur, ni tes
disques. À la fermeture, tout est détruit.

**Ce qui n'est qu'un indice : la détection.** Le rapport comportemental dit ce
que le programme *a fait* pendant l'observation, pas ce qu'il *aurait pu* faire.
Un rapport propre ne prouve pas l'innocuité :

- un malware peut détecter la VM et rester inerte (voir [docs/ANTI-VM.md](docs/ANTI-VM.md)) ;
- une charge utile peut être retardée (jours) ou conditionnelle (date, présence
  d'un portefeuille crypto, réseau d'entreprise) ;
- le mode dégradé (sans Sysmon) ne voit ni le registre ni les accès disque brut.

**BlankAnalyser réduit le risque, il ne le supprime pas.** Il ne remplace ni un
antivirus à jour, ni — surtout — une **sauvegarde débranchée physiquement**, qui
reste la seule vraie réponse à un logiciel destructeur.

## Signaler une vulnérabilité dans BlankAnalyser lui-même

Si tu penses qu'un des scripts de ce dépôt présente une faille (par exemple une
fuite hors du bac à sable, un montage trop permissif, une commande injectable) :

1. **N'ouvre pas d'issue publique** pour un problème exploitable.
2. Ouvre un *security advisory* privé via l'onglet **Security** du dépôt GitHub,
   ou contacte le mainteneur en privé.
3. Décris le scénario, l'impact, et si possible une reproduction.

Les rapports sur la documentation, l'ergonomie ou les faux positifs de détection
peuvent, eux, passer par des issues publiques normales.

## Bon usage

- Ne commite jamais un échantillon suspect dans un dépôt (le `.gitignore` bloque
  déjà `quarantine/`, mais reste vigilant).
- Fais toujours le premier passage **réseau coupé**.
- Considère chaque binaire non signé comme inconnu tant que tu ne l'as pas
  observé — et même après, avec les réserves ci-dessus.
