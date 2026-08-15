# Mode furtif et détection de VM — ce qui est possible, ce qui ne l'est pas

> **En une phrase :** le mode furtif rend le bac à sable moins évident pour un
> malware *paresseux*, mais il ne le rend **pas** invisible, et il ne le peut
> pas. Un rapport propre en mode furtif reste un **indice**, jamais une preuve.

Ce document explique pourquoi, en détail, pour que tu ne te fasses pas une
fausse confiance.

---

## Le problème

Beaucoup de malwares modernes savent qu'ils sont souvent exécutés dans des bacs
à sable d'analyse (automatiques ou manuels). Alors ils regardent autour d'eux
et, s'ils pensent être observés, ils **ne font rien** — pas d'activité
malveillante, le temps que l'analyse se termine et les classe « inoffensifs ».
C'est ce qu'on appelle l'**évasion de sandbox** (*sandbox evasion*).

Contre-mesure côté défenseur : rendre l'environnement d'analyse le plus proche
possible d'un vrai poste, pour que le malware « baisse la garde » et se dévoile.
C'est exactement ce que font les bacs à sable professionnels (Joe Sandbox,
Any.run, VMRay, CAPE…). Le mode furtif de BlankAnalyser applique une version
modeste de la même idée.

---

## Comment un programme devine qu'il est dans une VM

Par ordre croissant de difficulté à contrer :

| Niveau | Signal observé | Exemple concret |
|---|---|---|
| **Trivial** | La session est vide | 0 document, 0 historique, 0 fichier récent |
| **Trivial** | Outils d'analyse visibles | un service ou processus nommé `Sysmon`, `Procmon`, `Wireshark` |
| **Facile** | Pas d'interaction humaine | la souris n'a jamais bougé, aucune frappe clavier |
| **Facile** | Peu de processus | une vraie session en a des dizaines |
| **Moyen** | Nom d'utilisateur révélateur | `WDAGUtilityAccount` (spécifique à Windows Sandbox !) |
| **Moyen** | Peu de cœurs / peu de RAM | 1 cœur, 1 Go = machine d'analyse |
| **Difficile** | Périphériques Hyper-V | carte réseau `00:15:5D…`, disque « Msft Virtual Disk », bus `vmbus` |
| **Difficile** | Chaînes firmware / BIOS | SMBIOS contient « Virtual Machine » / « Hyper-V » |
| **Très difficile** | **Bit hyperviseur du CPU** | `CPUID.1:ECX[31]` = 1 → « je tourne sous un hyperviseur » |
| **Très difficile** | Sécurité basée virtualisation | VBS/HVCI actifs, mesurables |

---

## Ce que le mode furtif de BlankAnalyser FAIT

Tout ce qui est réalisable **depuis l'intérieur** de Windows Sandbox, en espace
utilisateur, sans pilote noyau (impossible ici) et sans contrôle de
l'hyperviseur (idem). Concrètement, il s'attaque aux niveaux *trivial* et
*facile* du tableau :

- **Peuple la session** : crée de faux documents, images et téléchargements dans
  le profil, **anti-datés** de plusieurs mois, pour tuer le signal « session
  neuve et vide ».
- **Masque l'observateur** : le service et le processus Sysmon sont renommés
  (ex. `WinHostSvc`) — un malware qui cherche précisément un service « Sysmon »
  ne le trouve pas. Procmon n'est jamais lancé en mode furtif.
- **Simule une présence humaine** : un processus de fond bouge légèrement la
  souris à intervalles réguliers, pour passer les tests « la souris a-t-elle
  bougé ? ».
- **Épaissit la liste des processus** : lance quelques processus utilisateur
  bénins et durables (explorateur, éditeur) pour ne pas paraître désert.

C'est suffisant pour démasquer une bonne partie des malwares « grand public »
qui se contentent d'un test facile. Ce n'est pas rien.

---

## Ce que le mode furtif NE PEUT PAS faire (et pourquoi)

C'est la partie importante. Ces signaux-là restent visibles **quoi qu'on
fasse**, parce que les contrer demanderait soit un pilote noyau (interdit dans
Windows Sandbox), soit le contrôle de l'hyperviseur (que Windows Sandbox
n'expose pas) :

### 1. Le bit hyperviseur du processeur — infranchissable

L'instruction `CPUID` renvoie un bit qui dit « un hyperviseur est présent ».
Ce bit est posé par l'hyperviseur lui-même, **sous** le système invité. Depuis
l'intérieur de la VM, aucun programme utilisateur ne peut le remettre à zéro.
Un malware qui fait ce seul test — trois instructions assembleur — sait qu'il
est virtualisé, point final. **C'est le mur principal.**

### 2. Le compte `WDAGUtilityAccount` — infranchissable ici

Windows Sandbox exécute toujours la session sous ce compte au nom très
reconnaissable. On ne peut pas renommer le compte de la session en cours. Sa
seule présence est une signature quasi certaine de Windows Sandbox
spécifiquement.

### 3. Le matériel Hyper-V — quasi infranchissable sans noyau

Nom du disque (« Msft Virtual Disk »), carte vidéo « Microsoft Hyper-V Video »,
bus `vmbus`, préfixe MAC `00:15:5D`, chaînes SMBIOS… Ces valeurs viennent des
pilotes et du firmware virtuel. Les masquer proprement suppose de s'insérer dans
le noyau, ce que la sandbox verrouille (pas de pilote non signé, pas de test
signing).

### 4. Le driver `SysmonDrv` — partiellement visible

On renomme le binaire Sysmon (donc son service et son processus), mais son
**pilote** reste enregistré sous `SysmonDrv`. Un malware qui énumère les pilotes
chargés — plus rare qu'un simple `sc query` — peut encore le repérer.

---

## Pourquoi Windows Sandbox précisément est difficile à cacher

C'est le compromis assumé du projet. Windows Sandbox a d'énormes avantages
(jetable, zéro téléchargement, frontière matérielle réelle) **parce que** c'est
un conteneur verrouillé bâti sur Hyper-V. Ce verrouillage — pas de pilote noyau,
pas d'accès à l'hyperviseur, compte imposé — est exactement ce qui **empêche**
un camouflage profond. Un outil qui masquerait tout supposerait une VM que tu
contrôles au niveau hyperviseur (KVM patché, VMware avec réglages anti-détection,
etc.), au prix de tout ce qui rend Windows Sandbox pratique ici : plusieurs Go
d'ISO, installation, configuration, et bien plus de RAM que ton portable n'en a.

---

## Comment lire un résultat

- **Rapport sale** (mode furtif ou non) → information fiable et forte : le
  programme a *effectivement* fait quelque chose de malveillant. À prendre au
  sérieux immédiatement.
- **Rapport propre SANS mode furtif** → le programme n'a rien fait de visible…
  ou il a détecté la VM au premier test facile. Peu concluant.
- **Rapport propre AVEC mode furtif** → un peu plus rassurant : il n'a pas été
  arrêté par les pièges faciles. Mais un échantillon qui teste le CPU ou le nom
  d'utilisateur a quand même pu se taire. **Toujours pas une preuve d'innocuité.**

La règle ne change jamais : **l'isolation est une garantie, la détection est un
indice.** Le mode furtif améliore l'indice ; il ne le transforme pas en preuve.

---

## Envie d'aller plus loin ?

Si ton besoin réel est d'analyser des échantillons *conçus pour résister à
l'analyse*, il faut sortir de Windows Sandbox et passer à un hyperviseur que tu
contrôles, avec durcissement anti-détection — au prix des ressources et de la
simplicité :

- **VirtualBox + script anti-détection** (ex. *VBoxHardenedLoader*) : masque une
  grande partie des tells VirtualBox. Lourd, demande un ISO et du disque.
- **VMware Workstation** avec les options `.vmx` anti-détection.
- **KVM/QEMU** avec masquage du bit hyperviseur (`kvm.hidden`, CPU `host-passthrough`)
  et SMBIOS personnalisé — le plus puissant, mais Linux et technique.

Ces pistes dépassent le cadre de BlankAnalyser, dont le but est d'être **léger,
jetable et sans téléchargement**. Elles sont mentionnées ici pour que tu saches
où regarder si un jour ce compromis ne te suffit plus.
